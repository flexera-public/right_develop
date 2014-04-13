#
# Copyright (c) 2014 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require ::File.expand_path('../../config/init', __FILE__)

require 'rack/chunked'
require 'stringio'
require 'uri'

module RightDevelop::Testing::Servers::MightApi
  module App
    class Base

      MAX_REDIRECTS = 10  # 500 after so many redirects

      # exceptions
      class MightError < StandardError; end
      class MissingRoute < MightError; end

      attr_reader :config, :env, :logger, :request, :state_file_path

      def initialize(state_file_name)
        @config = ::RightDevelop::Testing::Servers::MightApi::Config
        @logger = ::RightDevelop::Testing::Servers::MightApi.logger

        @state_file_path = state_file_name ? ::File.join(@config.fixtures_dir, state_file_name) : nil
      end

      def call(env)
        @env = env
        @env['rack.logger'] ||= @logger

        # read body from stream.
        @request = ::Rack::Request.new(env)
        body = request.body.read

        # proxy any headers from env starting with HTTP_
        headers = env.inject({}) do |r, (k,v)|
          # note that HTTP_HOST refers to this proxy server instead of the
          # proxied target server. in the case of AWS authentication, it is
          # necessary to pass the value through unmodified or else AWS auth
          # fails.
          if k.start_with?('HTTP_')
            r[k[5..-1]] = v
          end
          r
        end

        # special cases.
        ['ACCEPT', 'CONTENT_TYPE', 'CONTENT_LENGTH', 'USER_AGENT'].each do |key|
          headers[key] = env[key] unless env[key].to_s.empty?
        end

        # log
        verb = @request.request_method
        uri = ::URI.parse(@request.url)
        if @logger.debug?
          @logger.debug(<<EOF
request verb = #{verb.inspect}
request uri = #{uri}
request headers = #{headers.inspect}
request body = #{body.inspect}
EOF
)
        end

        # handler
        result = handle_request(verb, uri, headers, body)

        # log
        if @logger.debug?
          debug_io = StringIO.new
          debug_io.puts(<<EOF
response code = #{result[0].inspect}
response headers = #{result[1].inspect}
response body:
EOF
          )
          result[2].each { |body| debug_io.puts(body) }
          @logger.debug(debug_io.string)
        end
        result
      rescue MissingRoute => e
        message = "#{e.class} #{e.message}"
        logger.debug(message)
        if config.routes.empty?
          logger.debug("No routes configured.")
        else
          logger.debug("The following routes are configured:")
          config.routes.keys.each do |prefix|
            logger.debug("  #{prefix}...")
          end
        end

        # not a 404 because this is a proxy/stub service and 40x might appear to
        # have come from a proxied request/response whereas 500 is never an
        # expected response.
        internal_server_error(message)
      rescue ::RightDevelop::Testing::Client::Rest::Request::Playback::PlaybackError => e
        # response has not been recorded.
        message = e.message
        logger.debug(message)
        internal_server_error(message)
      rescue ::Exception => e
        message = "Unhandled exception: #{e.class} #{e.message}"
        debug_message = ([message] + (e.backtrace || [])).join("\n")
        if @logger
          logger.error(debug_message)
        else
          env['rack.errors'].puts(debug_message)
        end
        internal_server_error(message)
      end

      # Handler.
      #
      # @param [String] verb as one of ['GET', 'POST', etc.]
      # @param [URI] uri parsed from full url
      # @param [Hash] headers for proxy call with any non-proxy data omitted
      # @param [String] body streamed from payload or empty
      #
      # @return [TrueClass] always true
      def handle_request(verb, uri, headers, body)
        raise ::NotImplementedError, 'Must be overridden'
      end

      # Makes a proxied API request using the given request class.
      #
      # @param [Class] request_class for API call
      # @param [String] verb as one of ['GET', 'POST', etc.]
      # @param [URI] uri parsed from full url
      # @param [Hash] headers for proxy call with any non-proxy data omitted
      # @param [String] body streamed from payload or empty
      # @param [Integer] throttle for playback or nil
      #
      # @return [Array] rack-style tuple of [code, headers, [body]]
      def proxy(request_class, verb, uri, headers, body, throttle = nil)

        # check routes.
        unless route = find_route
          raise MissingRoute, "No route configured for #{uri.path.inspect}"
        end
        route_data = route.last
        response = nil
        max_redirects = MAX_REDIRECTS
        loop do
          begin
            proxied_url = ::File.join(route_data[:url], uri.path)
            if uri.query.to_s.empty?
              proxied_url.chomp!('/')
            else
              proxied_url << '?' << uri.query
            end
            proxied_headers = proxy_headers(headers, route_data)

            logger.debug("proxied_url = #{proxied_url.inspect}")
            logger.debug("proxied_headers = #{proxied_headers.inspect}")
            request_options = {
              fixtures_dir:     config.fixtures_dir,
              logger:           logger,
              route_record_dir: route_data[:record_dir],
              state_file_path:  state_file_path,
              method:           verb.downcase.to_sym,
              url:              proxied_url,
              headers:          proxied_headers,
              payload:          body
            }
            request_options[:throttle] = throttle if throttle
            request_proxy = request_class.new(request_options)

            request_proxy.execute do |rest_response, rest_request, net_http_response, &block|

              # rack has a convention of newline-delimited header multi-values.
              #
              # HACK: change underscore to dash to defeat
              # RestClient::AbstractResponse line 27 (on client side) from failing
              # to parse cookies array; it incorrectly calls .inject on the
              # stringized form instead of using the raw array form or parsing the
              # cookies into a hash, but only if the raw name is 'set_cookie'
              # ('set-cookie' is okay).
              #
              # even wierder, on line 78 it assumes the raw name is 'set-cookie'
              # and that works out for us here.
              response_headers = net_http_response.to_hash.inject({}) do |h, (k, v)|
                h[k.to_s.gsub('_', '-').downcase] = v.join("\n")
                h
              end
              ['connection', 'status'].each { |key| response_headers.delete(key) }

              case code = Integer(rest_response.code)
              when 301, 302, 307
                raise RestClient::Exceptions::EXCEPTIONS_MAP[code].new(rest_response, code)
              else
                # special handling for chunked body.
                if response_headers['transfer-encoding'] == 'chunked'
                  reponse_body = ::Rack::Chunked::Body.new([rest_response.body])
                else
                  reponse_body = [rest_response.body]
                end
                response = [code, response_headers, reponse_body]
              end
            end
            break
          rescue RestClient::Exception => e
            max_redirects -= 1
            if max_redirects >= 0
              case e.http_code
              when 301, 302, 307
                if location = e.response.headers[:location]
                  redirect_uri = ::URI.parse(location)
                  redirect_uri.path = ''
                  redirect_uri.query = nil
                  logger.debug("#{e.message} from #{route_data[:url]} to #{redirect_uri}")
                  route_data[:url] = redirect_uri.to_s
                else
                  logger.debug("#{e.message} was missing expected location header.")
                  raise
                end
              else
                raise
              end
            else
              raise MightError.new('Exceeded max redirects')
            end
          end
        end
        raise MightError.new('Unexpected missing response') unless response
        response
      end

      # @return [Array] pair of [prefix, data] or nil
      def find_route
        config.routes.find { |prefix, data| request.path.start_with?(prefix) }
      end

      # Sets the header style using configuration of the proxied service.
      #
      # @param [Hash] headers for proxy
      # @param [Hash] route_data containing header configuration, if any
      #
      # @return [Mash] proxied headers
      def proxy_headers(headers, route_data)
        if header_data = route_data[:headers]
          to_separator = (header_data[:separator] == :underscore) ? '_' : '-'
          from_separator = (to_separator == '-') ? '_' : '-'
          proxied = headers.inject(::Mash.new) do |h, (k, v)|
            k = k.to_s
            case header_data[:case]
            when nil
              k = k.gsub(from_separator, to_separator)
            when :lower
              k = k.downcase.gsub(from_separator, to_separator)
            when :upper
              k = k.upcase.gsub(from_separator, to_separator)
            when :capitalize
              k = k.split(/-|_/).map { |word| word.capitalize }.join(to_separator)
            else
              raise ::ArgumentError,
                    "Unexpected header case: #{route_data.inspect}"
            end
            h[k] = v
            h
          end
        else
          proxied = ::Mash.new(headers)
        end
        proxied
      end

      # @return [Array] rack-style response for 500
      def internal_server_error(message)
        formal = <<EOF
MightAPI internal error

Problem:
  #{message}
EOF

        [
          500,
          {
            'Content-Type'   => 'text/plain',
            'Content-Length' => ::Rack::Utils.bytesize(formal).to_s
          },
          [formal]
        ]
      end

    end
  end
end

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

require 'stringio'
require 'uri'

module RightDevelop::Testing::Servers::MightApi
  module App
    class Base

      # exceptions
      class MightError < StandardError; end
      class MissingRoute < MightError; end

      attr_reader :config, :env, :logger, :request

      def call(env)
        @config = ::RightDevelop::Testing::Servers::MightApi::Config
        @env = env
        @logger = ::RightDevelop::Testing::Servers::MightApi.logger
        @env['rack.logger'] ||= @logger

        # read body from stream.
        @request = ::Rack::Request.new(env)
        body = request.body.read

        # proxy any headers from env starting with HTTP_
        headers = env.inject({}) do |r, (k,v)|
          if k.start_with?('HTTP_')
            unless ['HTTP_HOST'].include?(k)
              r[k[5..-1]] = v
            end
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
          logger.debug("No routes configured in #{config.config_file_path.inspect}.")
        else
          logger.debug("The following routes are configured in #{config.config_file_path.inspect}.:")
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
      #
      # @return [Array] rack-style tuple of [code, headers, [body]]
      def proxy(request_class, verb, uri, headers, body)

        # check routes.
        unless route = find_route
          raise MissingRoute, "No route configured for #{uri.path.inspect}"
        end
        route_data = route.last
        proxied_url = ::File.join(route_data[:url], uri.path)
        unless uri.query.to_s.empty?
          proxied_url << '?' << uri.query
        end
        record_dir = route_data[:record_dir]

        request_proxy = request_class.new(
          record_dir: record_dir,
          logger:     logger,
          method:     verb.downcase.to_sym,
          url:        proxied_url,
          headers:    headers,
          payload:    body)
        response = nil
        request_proxy.execute do |rest_response, rest_request, net_http_response, &block|
          response_headers = rest_response.headers.inject({}) do |h, (k, v)|
            h[k.to_s.gsub('-', '_').upcase] = v.to_s
            h
          end
          ['CONNECTION', 'STATUS'].each { |key| response_headers.delete(key) }
          response = [
            Integer(rest_response.code),
            response_headers,
            [rest_response.body]
          ]
        end
        raise MightError.new('Unexpected missing response') unless response
        response
      end

      # @return [Array] pair of [prefix, data] or nil
      def find_route
        config.routes.find { |prefix, data| request.path.start_with?(prefix) }
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

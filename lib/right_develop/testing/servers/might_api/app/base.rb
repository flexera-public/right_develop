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

module RightDevelop::Testing::Server::MightApi
  module App
    class Base

      MAX_REDIRECTS = 10  # 500 after so many redirects

      # Rack (and Skeletor) apps and some known AWS apps only accept dash and
      # not underscore so ensure the default settings reflect the 80-20 rule.
      DEFAULT_PROXY_SETTINGS = RightSupport::Data::Mash.new(
        header: RightSupport::Data::Mash.new(
          case:      :capitalize,
          separator: :dash
        ).freeze
      ).freeze

      # exceptions
      class MightError < StandardError; end
      class MissingRoute < MightError; end

      attr_reader :config, :logger, :state_file_path

      # @param [Hash] options for initializer
      # @option options [String] :config for sevice
      #   (default = MightAPI Config singleton)
      # @option options [String] :logger for sevice
      #   (default = MightAPI logger singleton)
      # @option options [String] :state_file_name relative to fixtures
      #   directory or nil for no perisisted state.
      def initialize(options = {})
        @config = options[:config] || ::RightDevelop::Testing::Server::MightApi::Config
        @logger = options[:logger] || ::RightDevelop::Testing::Server::MightApi.logger

        @state_file_path = options[:state_file_name] ?
          ::File.join(@config.fixtures_dir, options[:state_file_name]) :
          nil
      end

      def call(env)
        # HACK: chain trap interrupt on first call to app because the trap chain
        # does not exist, in rack terms, until just before app is run.
        # unforunately due to poor design of rack, this object gets no
        # calls from rack other than calls to handle requests (i.e. a call to
        # do run/shutdown would be nice).
        #
        # the downside here is that if the server never receives any request
        # then the trap chain is never setup so temporary files cannot be
        # cleaned-up on shutdown, etc. admin mode has a workaround whereby it is
        # able to clean-up any temporary files immediately after reading its
        # config and whenever the administered configuration changes.
        entrapment unless Base.trapped?

        env['rack.logger'] ||= logger

        # read body from stream.
        request = ::Rack::Request.new(env)
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

        # prepare and call handler
        #
        # note that verb supposed to already be .to_s.upcase but we want to
        # ensure that we agree on that.
        verb = request.request_method.to_s.upcase
        uri = ::URI.parse(request.url)
        logger.info("#{verb} #{uri}")
        result = handle_request(env, verb, uri, headers, body)
        logger.info(result.first.to_s)
        result
      rescue MissingRoute => e
        message = "#{e.class} #{e.message}"
        logger.error(message)
        if config.routes.empty?
          logger.error("No routes configured.")
        else
          logger.error("The following routes are configured:")
          config.routes.keys.each do |prefix|
            logger.error("  #{prefix}...")
          end
        end

        # not a 404 because this is a proxy/stub service and 40x might appear to
        # have come from a proxied request/response whereas 500 is never an
        # expected response.
        internal_server_error(message)
      rescue ::RightDevelop::Testing::Client::Rest::Request::Playback::PeerResetConnectionError => e
        # FIX: have only implemented socket close for webrick; not sure if this
        # is needed for other rack implementations.
        if socket = ::Thread.current[:WEBrickSocket]
          # closing the socket causes 'peer reset connection' on client side and
          # also prevents any response coming back on connection.
          socket.close
        end
        message = e.message
        trace = [e.class.name] + (e.backtrace || [])
        logger.info(message)
        internal_server_error(message)
      rescue ::RightDevelop::Testing::Recording::Metadata::PlaybackError => e
        # response has not been recorded, etc.
        message = e.message
        trace = [e.class.name] + (e.backtrace || [])
        logger.error(message)
        logger.debug(trace.join("\n"))
        internal_server_error(message)
      rescue ::Exception => e
        message = "Unhandled exception: #{e.class} #{e.message}"
        trace = e.backtrace || []
        if logger
          logger.error(message)
          logger.debug(trace.join("\n"))
        else
          env['rack.errors'].puts(message)
          env['rack.errors'].puts(trace.join("\n"))
        end
        internal_server_error(message)
      end

      # Handler.
      #
      # @param [Hash] env from rack
      # @param [String] verb as one of ['GET', 'POST', etc.]
      # @param [URI] uri parsed from full url
      # @param [Hash] headers for proxy call with any non-proxy data omitted
      # @param [String] body streamed from payload or empty
      #
      # @return [TrueClass] always true
      def handle_request(env, verb, uri, headers, body)
        raise ::NotImplementedError, 'Must be overridden'
      end

      # Removes state and/or fixtures for current mode (overridable).
      def cleanup
        # the state file, if any, is always temporary.
        if @state_file_path && ::File.file?(@state_file_path)
          ::File.unlink(@state_file_path)
        end

        # remove any directories listed as temporary by config.
        (config.cleanup_dirs || []).each do |dir|
          ::FileUtils.rm_rf(dir) if ::File.directory?(dir)
        end
        true
      end

      protected

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
        unless route = find_route(uri)
          raise MissingRoute, "No route configured for #{uri.path.inspect}"
        end
        route_path, route_data = route
        response = nil
        max_redirects = MAX_REDIRECTS
        while response.nil? do
          request_proxy = nil
          begin
            proxied_url = ::File.join(route_data[:url], uri.path)
            unless uri.query.to_s.empty?
              proxied_url << '?' << uri.query
            end
            proxied_headers = proxy_headers(headers, route_data)

            request_options = {
              fixtures_dir:    config.fixtures_dir,
              logger:          logger,
              route_path:      route_path,
              route_data:      route_data,
              state_file_path: state_file_path,
              method:          verb.downcase.to_sym,
              url:             proxied_url,
              headers:         proxied_headers,
              payload:         body
            }
            request_options[:throttle] = throttle if throttle
            request_proxy = request_class.new(request_options)

            # log normalized data for obfuscation.
            logger.debug("normalized request headers = #{request_proxy.request_metadata.headers.inspect}")
            logger.debug("normalized request body:\n" << request_proxy.request_metadata.body)

            request_proxy.execute do |rest_response, rest_request, net_http_response, &block|

              # headers.
              response_headers = normalize_rack_response_headers(net_http_response.to_hash)

              # eliminate headers that interfere with response via proxy.
              %w(
                status content-encoding
              ).each { |key| response_headers.delete(key) }

              case response_code = Integer(rest_response.code)
              when 301, 302, 307
                raise RestClient::Exceptions::EXCEPTIONS_MAP[response_code].new(rest_response, response_code)
              else
                # special handling for chunked body.
                if response_headers['transfer-encoding'] == 'chunked'
                  response_body = ::Rack::Chunked::Body.new([rest_response.body])
                else
                  response_body = [rest_response.body]
                end
                response = [response_code, response_headers, response_body]
              end
            end

            # log normalized data for obfuscation.
            logger.debug("normalized response headers = #{request_proxy.response_metadata.headers.inspect}")
            logger.debug("normalized response body:\n" << request_proxy.response_metadata.body.to_s)
          rescue RestClient::RequestTimeout
            net_http_response = request_proxy.handle_timeout
            response_code = Integer(net_http_response.code)
            response_headers = normalize_rack_response_headers(net_http_response.to_hash)
            response_body = [net_http_response.body]
            response = [response_code, response_headers, response_body]
          rescue RestClient::Exception => e
            case e.http_code
            when 301, 302, 307
              max_redirects -= 1
              raise MightError.new('Exceeded max redirects') if max_redirects < 0
              if location = e.response.headers[:location]
                redirect_uri = ::URI.parse(location)
                redirect_uri.path = ''
                redirect_uri.query = nil
                logger.debug("#{e.message} from #{route_data[:url]} to #{redirect_uri}")
                route_data[:url] = redirect_uri.to_s

                # move to end of FIFO queue for retry.
                request_proxy.forget_outstanding_request
              else
                logger.debug("#{e.message} was missing expected location header.")
                raise
              end
            else
              raise
            end
          ensure
            # remove from FIFO queue in case of any unhandled error.
            request_proxy.forget_outstanding_request if request_proxy
          end
        end
        response
      end

      # @param [URI] uri path to find
      #
      # @return [Array] pair of [prefix, data] or nil
      def find_route(uri)
        # ensure path is slash-terminated only for matching purposes.
        find_path = uri.path
        find_path += '/' unless find_path.end_with?('/')
        logger.debug "Route URI path to match = #{find_path.inspect}"
        config.routes.find do |prefix, data|
          matched = find_path.start_with?(prefix)
          logger.debug "Tried = #{prefix.inspect}, matched = #{matched}"
          matched
        end
      end

      # Sets the header style using configuration of the proxied service.
      #
      # @param [Hash] headers for proxy
      # @param [Hash] route_data containing header configuration, if any
      #
      # @return [Mash] proxied headers
      def proxy_headers(headers, route_data)
        proxied = nil
        if proxy_data = route_data[:proxy] || DEFAULT_PROXY_SETTINGS
          if header_data = proxy_data[:header]
            to_separator = (header_data[:separator] == :underscore) ? '_' : '-'
            from_separator = (to_separator == '-') ? '_' : '-'
            proxied = headers.inject(RightSupport::Data::Mash.new) do |h, (k, v)|
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
          end
        end
        proxied || RightSupport::Data::Mash.new(headers)
      end

      # rack has a convention of newline-delimited header multi-values.
      #
      # HACK: changes underscore to dash to defeat RestClient::AbstractResponse
      # line 27 (on client side) from failing to parse cookies array; it
      # incorrectly calls .inject on the stringized form instead of using the
      # raw array form or parsing the cookies into a hash, but only if the raw
      # name is 'set_cookie' ('set-cookie' is okay).
      #
      # even wierder, on line 78 it assumes the raw name is 'set-cookie' and
      # that works out for us here.
      #
      # @param [Hash] headers to normalize
      #
      # @return [Hash] normalized headers
      def normalize_rack_response_headers(headers)
        result = headers.inject({}) do |h, (k, v)|
          h[k.to_s.gsub('_', '-').downcase] = v.join("\n")
          h
        end

        # a proxy server must always instruct the client close the connection by
        # specification because a live socket cannot be proxied from client to
        # the real server. this also works around a lame warning in ruby 1.9.3
        # webbrick code (fixed in 2.1.0+) saying:
        #   Could not determine content-length of response body.
        #   Set content-length of the response or set Response#chunked = true
        # in the case of 204 empty response, which is incorrect.
        result['connection'] = 'close'
        result
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

      # @return [Trueclass|FalseClass] true if trap chain has been setup
      def self.trapped?; !!@trapped; end

      # @param [Trueclass|FalseClass] value of trapped
      # @return [Trueclass|FalseClass] true if trap chain has been setup
      def self.trapped=(value); @trapped = value; end

      # sets-up the trap chain, overriding the trap handler that rack setup just
      # before running the server. the rack trap is called after our own trap
      # handler is invoked.
      def entrapment
        # setup trap chain once.
        Base.trapped = true
        app = self

        # 'get' previous trap by replacing any existing trap with 'IGNORE'
        previous_trap = trap(:INT, 'IGNORE')

        # substitute our trap and chain it to previous by explicitly invoking
        # the previous trap. ruby makes this somewhat difficult and rack then
        # makes it even harder.
        trap(:INT) do
          begin
            # loggers may have closed file handles in a trap so disconnect any
            # loggers from multiplexer before continuing. even when they do not
            # raise exceptions they still appear to log nothing at this point
            # (not sure about syslog, definitely not file or console).
            if app.logger.respond_to?(:targets)
              # HACK: it is bad that Multiplexer#targets exposes its internal
              # array in a manner that allows us to clear it. it would be better
              # if to have a Multiplexer#reset method we could call instead.
              # to ensure that cleaning continues to work, check the result
              # afterward. note that we tried iterating targets and calling the
              # Multiplexer#remove method but that had no effect.
              app.logger.targets.clear
              fail 'Unexpected targets' unless app.logger.targets.empty?
              app.logger.warn('cannot log traps')  # no exception raised
            end

            # cleanup fixtures, if requested.
            app.cleanup
            if previous_trap && previous_trap.respond_to?(:call)
              previous_trap.call
            else
              exit
            end
          rescue ::Exception => e
            # loggers are unreliable so write any rescued error home.
            msg = ([e.class, e.message] + (e.backtrace || [])).join("\n")
            dir = ::ENV['HOME'] || ::Dir.pwd
            path = ::File.join(dir, 'might_api_rescued_error.txt')
            ::File.open(path, 'w') { |f| f.puts msg }
            exit 1
          end
        end
        true
      end

    end
  end
end

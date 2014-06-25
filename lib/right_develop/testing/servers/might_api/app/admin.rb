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

require 'yaml'

module RightDevelop::Testing::Server::MightApi::App
  class Admin < ::RightDevelop::Testing::Server::MightApi::App::Base

    # convenince
    CONFIG_CLASS = ::RightDevelop::Testing::Recording::Config

    # exceptions
    class MightAdminError < MightError; end

    # @see RightDevelop::Testing::Server::MightApi::App::Base#initialize
    def initialize(options = {})
      super
      fail "Unexpected mode: #{config.mode}" unless config.mode == :admin

      # admin has no state to preserve and no fixtures of its own so it can
      # immediately cleanup after reading the configuration file.
      cleanup
    end

    # @see RightDevelop::Testing::Server::MightApi::App::Base#handle_request
    def handle_request(env, verb, uri, headers, body)
      # check routes.
      unless admin_route = find_admin_route(uri)
        raise MissingRoute, "No route configured for #{uri.path.inspect}"
      end
      route_path, route_data = admin_route
      case route_data
      when Base
        return route_data.handle_request(env, verb, uri, headers, body)
      when :configure
        case verb
        when 'GET'
          if @route_handlers
            return [
              200,
              { 'connection' => 'close', 'content-type' => 'application/x-yaml' },
              (@route_handlers || []).map { |h| ::YAML.dump(h.config.to_hash) }
            ]
          else
            return [204, { 'connection' => 'close' }, ['']]
          end
        when 'POST', 'PUT'
          return configure_known_routes(CONFIG_CLASS.new(::YAML.load(body)))
        else
          raise MightAdminError, "Wrong verb: #{verb}"
        end
      else
        raise MissingRoute,
              "No handler for configured administrator route: #{route_path}"
      end
    end

    # @see RightDevelop::Testing::Server::MightApi::App::Base#cleanup
    def cleanup
      # cleanup handlers, if any.
      (@route_handlers || []).each { |handler| handler.cleanup }
      super
    end

    protected

    # @param [URI] uri path to find
    #
    # @return [Array] pair of [prefix, data] or nil
    def find_admin_route(uri)
      # ensure path is slash-terminated only for matching purposes.
      find_path = uri.path
      find_path += '/' unless find_path.end_with?('/')

      # try admin route first (highest precedence). it is for this reason that
      # the route is configured and not hardcoded; it should be chosen so as to
      # never be confused with a proxied route.
      logger.debug "Admin route URI path to match = #{find_path.inspect}"
      if admin_action = (config.admin[:routes] || {})[find_path]
        return [find_path, admin_action]
      else
        logger.debug("Tried admin routes = #{config.admin[:routes].inspect}")
      end

      # try known routes, if any. result is a pair or nil.
      (@known_routes || {}).find do |prefix, data|
        find_path.start_with?(prefix)
      end
    end

    # @param [RightDevelop::Testing::Recording::Config] config for new routes
    def configure_known_routes(config)
      # its possible, but there is currently no need to change the running admin
      # service configuration.
      if config.mode == :admin
        raise MightAdminError,
              'Not allowed to reconfigure a running admin service.'
      end
      route_paths = config.routes.keys
      if route_paths.empty?
        raise MightAdminError,
              'Missing at least one required route in configuration.'
      end

      # create handler by inferring class name from mode.
      handler = ::RightDevelop::Testing::Server::MightApi::App.
        const_get(config.mode.capitalize).
        new(config: config, logger: logger)

      # cleanup and drop any existing routes.
      #
      # note that we could permit multiple configuration calls to accumulate
      # multiple route handlers but it seems simpler at this time for each
      # configuration call to reset all known routes. different fixtures can
      # instead be served by different admin services on other ports, etc.
      #
      # that being said, for bookkeeping purposes, keep a list of handlers as if
      # there could be more than one.
      cleanup
      @known_routes = nil
      @route_handlers = nil

      # explicitly garbage collect since ruby gc is unreliable and we expect the
      # admin service to keep running indefinitely.
      ::GC.start

      # new handler
      @known_routes = route_paths.inject({}) { |h, k| h[k] = handler; h }
      @route_handlers = [handler]

      # empty result.
      [204, { 'connection' => 'close' }, ['']]
    end

  end
end

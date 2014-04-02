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

if ::ENV['RACK_ENV'].to_s.empty?
  ::ENV['RACK_ENV'] = 'development'
end

require 'extlib'
require 'logger'
require 'uri'
require 'yaml'

# define the module hierarchy once so that it can be on a single line hereafter.
module RightDevelop
  module Testing
    module Servers
      module MightApi
        # if only ruby could consume a single line module declaration...
      end
    end
  end
end

module RightDevelop::Testing::Servers::MightApi
  class Config

    DEBUG_ENV_VAR    = 'DEBUG'
    ROOT_DIR_ENV_VAR = 'RS_MIGHT_API_ROOT_DIR'
    MODE_ENV_VAR     = 'RS_MIGHT_API_MODE'

    RELATIVE_CONFIG_PATH = 'config/might_deploy.yml'

    FIXTURES_DIR_NAME = 'fixtures'

    VALID_MODES = ::Mash.new(
      :echo     => 'Echoes request back as response and validates route.',
      :playback => 'Playback a session for one or more stubbed web services.',
      :record   => 'Record a session for one or more proxied web services.'
    ).freeze

    # Setup configuration. Defaults to using environment variables for setup due
    # to rackup not allowing custom arguments to be passed on command line.
    #
    # @param [String] root_to_set as base directory containing configuration and fixtures or nil for env var or working directory
    # @param [String] mode_to_set as server mode or nil for env var
    #
    # @return [Config] self
    def self.setup(root_to_set = nil, mode_to_set = nil)
      # rack doesn't allow for custom command line arguments so we are limited
      # to loading a config by env var or relative to working directory.
      root_to_set ||= ::ENV[ROOT_DIR_ENV_VAR] || ::Dir.pwd
      config_file_path(::File.expand_path(RELATIVE_CONFIG_PATH, root_to_set))
      config = ::Mash.new(::YAML.load_file(config_file_path))
      root_dir(config['root_dir'] || root_to_set)
      mode(mode_to_set || ::ENV[MODE_ENV_VAR].to_s)
      routes(config['routes'] || {})
      log_level(::ENV[DEBUG_ENV_VAR] ? :debug : (config['log_level'] || :info))
      @config = config
      self
    end

    def self.config_file_path(value = nil)
      if value
        unless ::File.file?(value)
          raise ::ArgumentError,
                "Missing required configuration file (or invalid #{ROOT_DIR_ENV_VAR}): #{value.inspect}"
        end
        @config_file_path = value
      end
      @config_file_path
    end

    def self.root_dir(value = nil)
      if value
        unless ::File.directory?(value)
          raise ::ArgumentError, 'root_dir must be an existing directory.'
        end
        @root_dir = ::File.expand_path(value)
      end
      @root_dir
    end

    def self.fixtures_dir
      @fixtures_dir ||= ::File.join(root_dir, FIXTURES_DIR_NAME)
    end

    def self.environment
      @environment ||= ::ENV['RACK_ENV']
    end

    def self.mode(value = nil)
      if value
        value = value.to_s
        if value.empty?
          raise ::ArgumentError, "#{MODE_ENV_VAR} must be set"
        elsif VALID_MODES.has_key?(value)
          @mode = value.to_sym
        else
          raise ::ArgumentError, "mode must be one of #{VALID_MODES.keys.sort.inspect}: #{value.inspect}"
        end
      end
      @mode
    end

    def self.routes(value = nil)
      if value
        case value
        when Hash
          @routes = value.inject({}) do |r, (k, v)|
            r[normalize_route_prefix(k)] = normalize_route_data(v)
            r
          end
        else
          raise ::ArgumentError, 'routes must be a hash'
        end
      end
      @routes
    end

    def self.normalize_route_prefix(prefix)
      prefix = prefix.to_s
      unless prefix.end_with?('/')
        prefix += '/'
      end
      prefix
    end

    def self.normalize_route_data(data)
      data = ::Mash.new(data)
      case data
      when Hash
        case mode
        when :record
          uri = nil
          begin
            uri = ::URI.parse(data['url'])
          rescue URI::InvalidURIError
            # defer handling
          end
          unless uri && uri.scheme && uri.host
            raise ::ArgumentError, "route[url] must be a valid HTTP(S) URL: #{data.inspect}"
          end
          unless uri.path.to_s.empty? && uri.query.to_s.empty?
            raise ::ArgumentError, "route[url] has unexpected path or query string: #{data.inspect}"
          end
        end
        record_dir = data['record_dir']
        if record_dir.nil? || record_dir.empty?
          raise ::ArgumentError, "route[record_dir] is required: #{data.inspect}"
        end
        data['record_dir'] = ::File.expand_path(::File.join('fixtures', record_dir), @root_dir)  # no-op if already an absolute path
      else
        raise ::ArgumentError, "route must be a hash: #{data.class}"
      end
      data
    end

    def self.log_level(value = nil)
      if value
        case value
        when Integer
          if value < ::Logger::DEBUG || value >= ::Logger::UNKNOWN
            raise ::ArgumentError, "log_level is out of range: #{value}"
          end
          @log_level = value
        when String, Symbol
          @log_level = ::Logger.const_get(value.to_s.upcase)
        else
          raise ::ArgumentError, "log_level is unexpected type: #{log_level}"
        end
      end
      @log_level
    end

  end # Config
end # RightDevelop::Testing::Servers::MightApi

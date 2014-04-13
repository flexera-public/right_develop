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
require 'json'
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

    CONFIG_DIR_NAME   = 'config'
    FIXTURES_DIR_NAME = 'fixtures'
    LOG_DIR_NAME      = 'log'

    RELATIVE_CONFIG_PATH = ::File.join(CONFIG_DIR_NAME, 'might_deploy.yml')

    VALID_MODES = ::Mash.new(
      :echo     => 'Echoes request back as response and validates route.',
      :playback => 'Playback a session for one or more stubbed web services.',
      :record   => 'Record a session for one or more proxied web services.'
    ).freeze

    # Loads the config hash from given path or a relative location.
    #
    # @param [String] path to configuration or nil for relative path
    #
    # @return [Hash] configuration hash
    #
    # @raise [ArgumentError] on failure to load
    def self.load_config_hash(path = nil)
      path ||= ::File.expand_path(RELATIVE_CONFIG_PATH, ::Dir.pwd)
      unless ::File.file?(path)
        raise ::ArgumentError,
              "Missing expected configuration file: #{path.inspect}"
      end
      ::YAML.load_file(path)
    end

    # Setup configuration. Defaults to using environment variables for setup due
    # to rackup not allowing custom arguments to be passed on command line.
    #
    # @param [Hash] config as raw configuration data or nil to load relative path
    #
    # @return [Config] self
    #
    # @raise [ArgumentError] on failure to load
    def self.setup(config_hash = nil)
      config_hash = load_config_hash unless config_hash
      current_dir = ::Dir.pwd
      config_hash = ::Mash.new(
        'mode'         => :playback,
        'routes'       => {},
        'fixtures_dir' => ::File.expand_path(FIXTURES_DIR_NAME, current_dir),
        'log_level'    => :info,
        'log_dir'      => ::File.expand_path(LOG_DIR_NAME, current_dir),
        'throttle'     => 0,
      ).merge(config_hash)

      @config_hash = ::Mash.new
      mode(config_hash['mode'])
      routes(config_hash['routes'])
      log_dir(config_hash['log_dir'])
      log_level(config_hash['log_level'])
      fixtures_dir(config_hash['fixtures_dir'])
      throttle(config_hash['throttle'])

      # ensure fixture dir exists as result of configuration for better
      # synchronization of any state file locking.
      ::FileUtils.mkdir_p(fixtures_dir)
      self
    end

    def self.to_hash
      # unmash to hash
      JSON.load(@config_hash.to_json)
    end

    def self.fixtures_dir(value = nil)
      @config_hash['fixtures_dir'] = value if value
      @config_hash['fixtures_dir']
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
          @config_hash['mode'] = value.to_sym
        else
          raise ::ArgumentError, "mode must be one of #{VALID_MODES.keys.sort.inspect}: #{value.inspect}"
        end
      end
      @config_hash['mode']
    end

    def self.routes(value = nil)
      if value
        case value
        when Hash
          @config_hash['routes'] = value.inject({}) do |r, (k, v)|
            r[normalize_route_prefix(k)] = normalize_route_data(v)
            r
          end
        else
          raise ::ArgumentError, 'routes must be a hash'
        end
      end
      @config_hash['routes']
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
            uri = ::URI.parse(data[:url])
          rescue URI::InvalidURIError
            # defer handling
          end
          unless uri && uri.scheme && uri.host
            raise ::ArgumentError, "route[url] must be a valid HTTP(S) URL: #{data.inspect}"
          end
          unless uri.path.to_s.empty? && uri.query.to_s.empty?
            raise ::ArgumentError, "route[url] has unexpected path or query string: #{data.inspect}"
          end

          if header_data = data[:headers]
            if case_value = header_data[:case]
              case case_value = case_value.to_s.to_sym
              when :lower, :upper, :capitalize
                header_data[:case] = case_value
              else
                raise ::ArgumentError,
                      "Unexpected header case: #{data.inspect}"
              end
            end
            if separator_value = header_data[:separator]
              case separator_value = separator_value.to_s.to_sym
              when :dash, :underscore
                header_data[:separator] = separator_value
              else
                raise ::ArgumentError,
                      "Unexpected header separator: #{data.inspect}"
              end
            end
          end
        end
        record_dir = data[:record_dir]
        if record_dir.nil? || record_dir.empty?
          raise ::ArgumentError, "route[record_dir] is required: #{data.inspect}"
        end
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
          @config_hash['log_level'] = value
        when String, Symbol
          @config_hash['log_level'] = ::Logger.const_get(value.to_s.upcase)
        else
          raise ::ArgumentError, "log_level is unexpected type: #{log_level}"
        end
      end
      @config_hash['log_level']
    end

    def self.log_dir(value = nil)
      @config_hash['log_dir'] = value if value
      @config_hash['log_dir']
    end

    def self.throttle(value = nil)
      if value
        value = Integer(value)
        if value < 0 || value > 100
          raise ::ArgumentError, "throttle is out of range: #{value}"
        end
        @config_hash['throttle'] = value
      end
      @config_hash['throttle']
    end

  end # Config
end # RightDevelop::Testing::Servers::MightApi

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

# ancestor
require 'right_develop/testing/recording'
require 'right_support'
require 'json'
require 'logger'
require 'rack/utils'
require 'uri'
require 'yaml'

module RightDevelop::Testing::Recording

  # Config file format.
  class Config

    # default relative directories.
    FIXTURES_DIR_NAME = 'fixtures'.freeze
    LOG_DIR_NAME      = 'log'.freeze
    PID_DIR_NAME      = 'pid'.freeze

    # the empty key is used as a stop traversal signal because any literal
    # value would be ambiguous.
    STOP_TRAVERSAL_KEY = ''.freeze

    VALID_MODES = RightSupport::Data::Mash.new(
      :admin    => 'Administrative for changing mode, fixtures, etc. while running.',
      :echo     => 'Echoes request back as response and validates route.',
      :playback => 'Playback a session for one or more stubbed web services.',
      :record   => 'Record a session for one or more proxied web services.'
    ).freeze

    # keys allowed under the deep route configuration.
    ALLOWED_KINDS          = %w(request response)
    ALLOWED_CONFIG_ACTIONS = %w(delay_seconds significant timeouts transform variables)
    ALLOWED_TIMEOUTS       = %w(open_timeout read_timeout)
    ALLOWED_VARIABLE_TYPES = %w(body header query)

    # metadata.
    METADATA_CLASS = ::RightDevelop::Testing::Recording::Metadata

    # patterns for fixture files.
    FIXTURE_FILE_NAME_REGEX = /^([0-9A-Fa-f]{32}).yml$/

    # typename to value expression for significant/requests/responses configurations.
    TYPE_NAME_VALUE_REGEX = /^(body|header|query|verb)(?:[:#]([^=]+))?=(.*)$/

    # exceptions.
    class ConfigError < StandardError; end

    def initialize(config_hash, options = nil)
      # defaults.
      current_dir = ::Dir.pwd
      defaults = RightSupport::Data::Mash.new(
        'fixtures_dir' => ::File.expand_path(FIXTURES_DIR_NAME, current_dir),
        'log_level'    => :info,
        'log_dir'      => ::File.expand_path(LOG_DIR_NAME, current_dir),
        'pid_dir'      => ::File.expand_path(PID_DIR_NAME, current_dir),
        'throttle'     => 1,
      )
      unless config_hash.kind_of?(::Hash)
        raise ConfigError, 'config_hash must be a hash'
      end

      # shallow merge of hash because the defaults are a shallow hash. deep mash
      # of caller's config to deep clone and normalize keys.
      config_hash = defaults.merge(deep_mash(config_hash))
      if options
        # another deep merge of any additional options.
        ::RightSupport::Data::HashTools.deep_merge!(config_hash, options)
      end
      @config_hash = RightSupport::Data::Mash.new
      mode(config_hash['mode'])
      admin(config_hash['admin'])
      routes(config_hash['routes'])
      log_dir(config_hash['log_dir'])
      pid_dir(config_hash['pid_dir'])
      log_level(config_hash['log_level'])
      fixtures_dir(config_hash['fixtures_dir'])
      cleanup_dirs(config_hash['cleanup_dirs'])
      throttle(config_hash['throttle'])
    end

    # @return [String] raw hash representing complete configuration
    def to_hash
      # unmash to hash
      ::JSON.load(@config_hash.to_json)
    end

    # @return [String] location of fixtures used for record/playback
    def fixtures_dir(value = nil)
      @config_hash['fixtures_dir'] = value if value
      @config_hash['fixtures_dir']
    end

    # @return [TrueClass|FalseClass] true if cleaning-up fixtures directory on
    #   interrupt or configuration change.
    def cleanup_dirs(value = nil)
      @config_hash['cleanup_dirs'] = Array(value) if value
      @config_hash['cleanup_dirs']
    end

    def mode(value = nil)
      if value
        value = value.to_s
        if VALID_MODES.has_key?(value)
          @config_hash['mode'] = value.to_sym
        else
          raise ConfigError,
                "mode must be one of #{VALID_MODES.keys.sort.inspect}: #{value.inspect}"
        end
      end
      @config_hash['mode']
    end

    # @return [Hash] admin route configuration
    def admin(value = nil)
      if value
        if mode == :admin
          case value
          when ::Hash
            admin_routes = (value['routes'] || {}).inject({}) do |r, (k, v)|
              case v
              when ::String, ::Symbol
                r[normalize_route_prefix(k)] = v.to_s.to_sym
              else
                raise ConfigError, "Invalid admin route target: #{v.inspect}"
              end
              r
            end
            if admin_routes.empty?
              raise ConfigError, "Invalid admin routes: #{value['routes'].inspect}"
            else
              @config_hash['admin'] = deep_mash(routes: admin_routes)
            end
          else
            raise ConfigError,
                  "Unexpected type for admin configuration: #{value.class}"
          end
        else
          raise ConfigError,
                "Unexpected admin settings configured for non-admin mode: #{mode}"
        end
      end
      @config_hash['admin'] || {}
    end

    def routes(value = nil)
      if value
        case value
        when Hash
          # admin mode requires any playback/record config to be sent as a
          # PUT/POST request to the configured admin route.
          if mode == :admin
            raise ConfigError, 'Preconfigured routes are not allowed in admin mode.'
          end

          # normalize routes for efficient usage but keep them separate from
          # user's config so that .to_hash returns something understandable and
          # JSONizable/YAMLable.
          mutable_routes = value.inject(RightSupport::Data::Mash.new) do |r, (k, v)|
            r[normalize_route_prefix(k)] = normalize_route_data(k, v)
            r
          end

          # deep freeze routes to detect any case where code is unintentionally
          # modifying the route hash.
          @normalized_routes = ::RightSupport::Data::HashTools.deep_freeze!(mutable_routes)
          @config_hash['routes'] = ::RightSupport::Data::HashTools.deep_clone2(value)
        else
          raise ConfigError, 'routes must be a hash'
        end
      end
      @normalized_routes || {}
    end

    def log_level(value = nil)
      if value
        case value
        when Integer
          if value < ::Logger::DEBUG || value >= ::Logger::UNKNOWN
            raise ConfigError, "log_level is out of range: #{value}"
          end
          @config_hash['log_level'] = value
        when String, Symbol
          @config_hash['log_level'] = ::Logger.const_get(value.to_s.upcase)
        else
          raise ConfigError, "log_level is unexpected type: #{log_level}"
        end
      end
      @config_hash['log_level']
    end

    def log_dir(value = nil)
      @config_hash['log_dir'] = value if value
      @config_hash['log_dir']
    end

    def pid_dir(value = nil)
      @config_hash['pid_dir'] = value if value
      @config_hash['pid_dir']
    end

    def throttle(value = nil)
      if value
        value = Integer(value)
        if value < 0 || value > 100
          raise ConfigError, "throttle is out of range: #{value}"
        end
        @config_hash['throttle'] = value
      end
      @config_hash['throttle']
    end

    # Loads the config from given path or a relative location.
    #
    # @param [String] path to configuration
    # @param [Hash] options to merge after loading config hash
    #
    # @return [Config] configuration object
    #
    # @raise [ArgumentError] on failure to load
    def self.from_file(path, options = nil)
      # load
      unless ::File.file?(path)
        raise ConfigError, "Missing expected configuration file: #{path.inspect}"
      end
      config_hash = deep_mash(::YAML.load_file(path))

      # enumerate routes looking for any route-specific config data to load
      # into the config hash from .yml files in subdirectories. this allows
      # the user to spread configuration of specific requests/responses out in
      # the file system instead of having a single monster config .yml
      extension = '.yml'
      (config_hash[:routes] || {}).each do |route_path, route_data|
        if subdir = route_data[:subdir]
          route_subdir = ::File.expand_path(::File.join(path, '..', subdir))
          ::Dir[::File.join(route_subdir, "**/*#{extension}")].each do |route_config_path|
            route_config_data = RightSupport::Data::Mash.new(::YAML.load_file(route_config_path))
            filename = ::File.basename(route_config_path)[0..-(extension.length + 1)]
            hash_path = ::File.dirname(route_config_path)[(route_subdir.length + 1)..-1].split('/')
            unless current_route_data = ::RightSupport::Data::HashTools.deep_get(route_data, hash_path)
              current_route_data = RightSupport::Data::Mash.new
              ::RightSupport::Data::HashTools.deep_set!(route_data, hash_path, current_route_data)
            end

            # inject a 'stop' at the point where the sub-config file data was
            # inserted into the big hash. the 'stop' basically distingishes the
            # 'directory' from the 'file' information because the hash doesn't
            # use classes to distinguish the data it contains; it only uses
            # simple types. use of simple types makes it easy to YAMLize or
            # JSONize or otherwise serialize in round-trip fashion.
            merge_data = { filename => { STOP_TRAVERSAL_KEY => route_config_data } }
            ::RightSupport::Data::HashTools.deep_merge!(current_route_data, merge_data)
          end
        end
      end

      # config
      self.new(config_hash, options)
    end

    # Deeply mashes and duplicates (clones) a hash containing other hashes or
    # arrays of hashes but not other types.
    #
    # Note that Mash.new(my_mash) will convert child hashes to mashes but not
    # with the guarantee of cloning and detaching the deep mash. In other words.
    # if any part of the hash is already a mash then it is not cloned by
    # invoking Mash.new()
    #
    # now delegates to RightSupport::Data::HashTools
    #
    # @return [Object] depends on input type
    def self.deep_mash(any)
      ::RightSupport::Data::HashTools.deep_mash(any)
    end

    protected

    # @see RightDevelop::Testing::Client::RecordMetadata.normalize_header_key
    def normalize_header_key(key)
      METADATA_CLASS.normalize_header_key(key)
    end

    # @see Config.deep_mash
    def deep_mash(any)
      ::RightSupport::Data::HashTools.deep_mash(any)
    end

    def normalize_route_prefix(prefix)
      prefix = prefix.to_s
      unless prefix.end_with?('/')
        prefix += '/'
      end
      prefix
    end

    def normalize_route_data(route_path, route_data)
      position = ['routes', "#{route_path} (#{route_data[:subdir].inspect})"]
      case route_data
      when Hash
        route_data = deep_mash(route_data)  # deep clone and mash
        case mode
        when :record
          uri = nil
          begin
            uri = ::URI.parse(route_data[:url])
          rescue URI::InvalidURIError
            # defer handling
          end
          unless uri && uri.scheme && uri.host
            raise ConfigError, "#{position_string(position, 'url')} must be a valid HTTP(S) URL: #{route_data.inspect}"
          end
          unless uri.path.to_s.empty? && uri.query.to_s.empty?
            raise ConfigError, "#{position_string(position, 'url')} has unexpected path or query string: #{route_data.inspect}"
          end
        end
        subdir = route_data[:subdir]
        if subdir.nil? || subdir.empty?
          raise ConfigError, "#{position_string(position, 'subdir')} is required: #{route_data.inspect}"
        end
        if proxy_data = route_data[:proxy]
          if header_data = proxy_data[:header]
            if case_value = header_data[:case]
              case case_value = case_value.to_s.to_sym
              when :lower, :upper, :capitalize
                header_data[:case] = case_value
              else
                raise ConfigError, "#{position_string(position, 'proxy/headers/case')} must be one of [lower, upper, capitalize]: #{route_data.inspect}"
              end
            end
            if separator_value = header_data[:separator]
              case separator_value = separator_value.to_s.to_sym
              when :dash, :underscore
                header_data[:separator] = separator_value
              else
                raise ConfigError, "#{position_string(position, 'proxy/headers/separator')} must be one of [dash, underscore]: #{route_data.inspect}"
              end
            end
          end
        end
        matchers_key = METADATA_CLASS::MATCHERS_KEY
        if matchers_data = route_data[matchers_key]
          route_data[matchers_key] = normalize_route_configuration(
            route_path,
            position + [matchers_key],
            matchers_data)
        end
      else
        raise ConfigError, "route must be a hash: #{route_data.class}"
      end
      route_data
    end

    # Formats a displayable position string.
    #
    # @param [String] position as base
    # @param [String|Array] subpath to join or nil
    #
    # @return [String] displayable config-root relative position string
    def position_string(position, subpath = nil)
      "might_config[#{(position + Array(subpath).join('/').split('/')).join('][')}]"
    end

    # Converts hierarchical hash of URI path fragments to sub-configurations to
    # a flat hash of regular expressions matching URI to sub-configuration.
    # Additional matchers such as verb or header are not included in the regex.
    # this is intended to reduce how much searching is needed to find the
    # configuration for a particular request/response. Ruby has no direct
    # support for hashing by matching a regular expression to a value but the
    # hash idiom is still useful here.
    def normalize_route_configuration(uri_path, position, configuration_data)
      uri_path = uri_path[1..-1] if uri_path.start_with?('/')
      uri_path = uri_path.chomp('/').split('/')
      recursive_traverse_uri(regex_to_data = {}, position, uri_path, configuration_data)
    end

    # Builds regular expressions from URI paths by recursively looking for
    # either the 'stop' key or the start of matcher information. When the path
    # for the URI is complete the wildcard 'file' path is converted to a regular
    # expression and inserted into the regex_to_data hash. The data has a regex
    # on the left-hand and a matcher data hash on the right-hand. The matcher
    # data may have empty criteria if no matching beyond the URI path is needed.
    def recursive_traverse_uri(regex_to_data, position, uri_path, data)
      unless data.respond_to?(:has_key?)
        message = "Expected a hash at #{position_string(position, uri_path)}; " +
                  "use the #{STOP_TRAVERSAL_KEY.inspect} key to stop traversal."
        raise ConfigError, message
      end

      data.each do |k, v|
        # stop key or 'type:name=value' qualifier stops URI path traversal.
        k = k.to_s
        if k == STOP_TRAVERSAL_KEY || k.index('=')
          # create regular expression from uri_path elements up to this point.
          # include a leading forward-slash (/) because uri.path will generally
          # have it.
          regex_string = '^/' + uri_path.map do |path_element|
            case path_element
            when '**'
              '.*'  # example: 'api/**'
            else
              # element may contain single wildcard character (*)
              ::Regexp.escape(path_element).gsub("\\*", '[^/]*')
            end
          end.join('/') + '$'
          regex = ::Regexp.compile(regex_string)

          # URI path is the outermost qualifier, but there can be literal verb,
          # header, query qualifiers as well. create another interesting map of
          # (qualifier name to value) to (configuration data). the qualifiers
          # can be hierarchical, of course, so we must traverse and flatten
          # those also.
          #
          # examples of resulting uri regex to matcher data:
          #   request:
          #     /^api\/create$/ => { { 'verb' => 'POST', 'header' => { 'x_foo' => 'foo' } } => { 'body' => { 'name' => 'foo_name_variable' } } }
          #   response:
          #     { { 'verb' => 'GET', 'query' => { 'view' => 'full' } } => { 'body' => { 'name' => 'foo_name_variable' } } }
          #
          # FIX: don't think there is a need for wildcard qualifiers beyond URI
          # path (i.e. wildcard matchers) so they are not currently supported.
          qualifiers_to_data = regex_to_data[regex] ||= {}
          current_qualifiers = RightSupport::Data::Mash.new
          if k == STOP_TRAVERSAL_KEY
            # no qualifiers; stopped after URI path
            qualifiers_to_data[current_qualifiers] = normalize_route_stop_configuration(position, uri_path + [k], v)
          else
            recursive_traverse_qualifiers(qualifiers_to_data, current_qualifiers, position, uri_path + [k], v)
          end
        else
          # recursion
          recursive_traverse_uri(regex_to_data, position, uri_path + [k], v)
        end
      end
      regex_to_data
    end

    # Recursively builds one of more hash of qualifiers cumulatively with the
    # parent qualifiers being included in child qualifier hashes. The completed
    # qualifier hash is then inserted into the qualifiers_to_data hash.
    def recursive_traverse_qualifiers(qualifiers_to_data, current_qualifiers, position, subpath, data)
      unless data.kind_of?(::Hash)
        message = "Expected a hash at #{position_string(position, subpath)}; " +
                  "use the #{STOP_TRAVERSAL_KEY.inspect} key to stop traversal."
        raise ConfigError, message
      end

      # could be multiple qualifiers in a CGI-style string.
      current_qualifiers = RightSupport::Data::Mash.new(current_qualifiers)
      more_qualifiers = RightSupport::Data::Mash.new
      ::CGI.unescape(subpath.last).split('&').each do |q|
        if matched = TYPE_NAME_VALUE_REGEX.match(q)
          case qualifier_type = matched[1]
          when 'verb'
            if matched[2]
              message = "Verb qualifiers cannot have a name: " +
                        position_string(position, subpath)
              raise ConfigError, message
            end
            verb = matched[3].upcase
            unless METADATA_CLASS::VERBS.include?(verb)
              message = "Unknown verb = #{verb}: " +
                        position_string(position, subpath + [k])
              raise ConfigError, message
            end
            more_qualifiers[qualifier_type] = verb
          else
            unless matched[2]
              message = "#{qualifier_type} qualifiers must have a name: " +
                        position_string(position, subpath)
              raise ConfigError, message
            end

            # qualifier may be nested (for query string or body).
            qualifier = ::Rack::Utils.parse_nested_query("#{matched[2]}=#{matched[3]}")

            # names and values are case sensitive but header keys are usually
            # not case-sensitive so convert the header keys to snake_case to
            # match normalized headers from request.
            if qualifier_type == 'header'
              qualifier = qualifier.inject(RightSupport::Data::Mash.new) do |h, (k, v)|
                h[normalize_header_key(k)] = v
                h
              end
            end
            ::RightSupport::Data::HashTools.deep_merge!(
              more_qualifiers[qualifier_type] ||= RightSupport::Data::Mash.new,
              qualifier)
          end
        else
          message = "Qualifier does not match expected pattern: " +
                    position_string(position, subpath)
          raise ConfigError, message
        end
      end
      ::RightSupport::Data::HashTools.deep_merge!(current_qualifiers, more_qualifiers)

      data.each do |k, v|
        # only the 'stop' key stops traversal now.
        k = k.to_s
        if k == STOP_TRAVERSAL_KEY
          qualifiers_to_data[current_qualifiers] = normalize_route_stop_configuration(position, subpath, v)
        else
          # recursion
          recursive_traverse_qualifiers(qualifiers_to_data, current_qualifiers, position, subpath + [k], v)
        end
      end
      qualifiers_to_data
    end

    # Ensures that any header keys are normalized in deep stop configuration.
    # Only header keys are normalized; other fields are case-sensitive and
    # otherwise adhere to a standard specific to the API for field names.
    def normalize_route_stop_configuration(position, subpath, route_stop_config)

      # sanity check.
      unwanted_keys = route_stop_config.keys.map(&:to_s) - ALLOWED_KINDS
      unless unwanted_keys.empty?
        message = 'The route configuration for route configuration at ' +
                  "#{position_string(position, subpath)} " +
                  "contained illegal kind specifiers = " +
                  "#{unwanted_keys.inspect}. Only #{ALLOWED_KINDS} are allowed."
        raise ConfigError, message
      end

      route_stop_config.inject(RightSupport::Data::Mash.new) do |rst, (rst_k, rst_v)|

        # sanity check.
        unwanted_keys = rst_v.keys.map(&:to_s) - ALLOWED_CONFIG_ACTIONS
        unless unwanted_keys.empty?
          message = 'The route configuration for route configuration at ' +
                    "#{position_string(position, subpath + [rst_k])} " +
                    "contained illegal action specifiers = " +
                    "#{unwanted_keys.inspect}. Only #{ALLOWED_CONFIG_ACTIONS} are allowed."
          raise ConfigError, message
        end

        rst[rst_k] = rst_v.inject(RightSupport::Data::Mash.new) do |kc, (kc_k, kc_v)|
          case kc_k
          when METADATA_CLASS::DELAY_SECONDS_KEY
            begin
              kc_v = Float(kc_v)
            rescue ::ArgumentError
              location = position_string(position, subpath + [rst_k, kc_k])
              message = 'Invalid route configuration delay_seconds value at ' +
                        "#{location}: #{kc_v.inspect}"
              raise ConfigError, message
            end
          when METADATA_CLASS::TIMEOUTS_KEY
            # sanity check.
            kc_v = kc_v.inject(RightSupport::Data::Mash.new) do |h, (k, v)|
              h[k] = Integer(v)
              h
            end
            unwanted_keys = kc_v.keys - ALLOWED_TIMEOUTS
            unless unwanted_keys.empty?
              message = 'The route configuration for timeouts at ' +
                        "#{position_string(position, subpath + [rst_k, kc_k])} " +
                        "contained illegal timeout specifiers = " +
                        "#{unwanted_keys.inspect}. Only #{ALLOWED_TIMEOUTS} are allowed."
              raise ConfigError, message
            end
          else
            # sanity check.
            kc_v = deep_mash(kc_v)
            unwanted_keys = kc_v.keys - ALLOWED_VARIABLE_TYPES
            unless unwanted_keys.empty?
              message = 'The route configuration for variables at ' +
                        "#{position_string(position, subpath + [rst_k, kc_k])} " +
                        "contained illegal variable specifiers = " +
                        "#{unwanted_keys.inspect}. Only #{ALLOWED_VARIABLE_TYPES} are allowed."
              raise ConfigError, message
            end

            if headers = kc_v[:header]
              case headers
              when ::Array
                # significant
                kc_v[:header] = headers.inject([]) do |a, k|
                  a << normalize_header_key(k)
                end
              when ::Hash
                # transform, variables
                kc_v[:header] = headers.inject(RightSupport::Data::Mash.new) do |h, (k, v)|
                  h[normalize_header_key(k)] = v
                  h
                end
              else
                message = "Expected an array at #{position_string(position, subpath + [rst_k, kc_k, :header])}; " +
                          "use the #{STOP_TRAVERSAL_KEY.inspect} key to stop traversal."
                raise ConfigError, message
              end
            end
          end
          kc[kc_k] = kc_v
          kc
        end
        rst
      end
    end

  end # Config
end # RightDevelop::Testing::Recording

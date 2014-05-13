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
require 'digest/md5'
require 'uri'

module RightDevelop::Testing::Recording

  # Metadata for record and playback.
  class Metadata

    # value used for obfuscation.
    HIDDEN_CREDENTIAL_VALUE = 'HIDDEN_CREDENTIAL'.freeze

    # common API verbs.
    VERBS = %w(DELETE GET HEAD PATCH POST PUT).freeze

    # valid modes, determines how variables are substituted, etc.
    MODES = %w(echo record playback validate)

    # valid kinds, also keys under matchers.
    KINDS = %w(request response)

    # route-relative config keys.
    MATCHERS_KEY    = 'matchers'.freeze
    SIGNIFICANT_KEY = 'significant'.freeze
    TIMEOUTS_KEY    = 'timeouts'.freeze
    TRANSFORM_KEY   = 'transform'.freeze
    VARIABLES_KEY   = 'variables'.freeze

    # finds the value index for a recorded variable, if any.
    VARIABLE_INDEX_REGEX = /\[(\d+)\]$/

    # throw/catch signals.
    HALT = :halt_recording_metadata_generator

    # retry-able failures.
    class RetryableFailure; end

    class MissingVariableFailure < RetryableFailure
      attr_reader :path, :variable, :variable_array_index, :variable_array_size

      def initialize(options)
        @path = options[:path] or raise ::ArgumentError, 'options[:path] is required'
        @variable = options[:variable] or raise ::ArgumentError, 'options[:variable] is required'
        @variable_array_index = options[:variable_array_index] || 0
        @variable_array_size = options[:variable_array_size] || 0
      end

      def message
        if (0 == variable_array_size)
          result = 'A variable was never defined by request '
        else
          result =
            'A variable index is past the range of values defined by request ' <<
            "(#{variable_array_index} >= #{variable_array_size}) "
        end
        result <<
          "while replacing variable = #{variable.inspect} at " <<
          path.join('/').inspect
      end
    end

    # exceptions.
    class RecordingError < StandardError; end

    attr_reader :uri, :verb, :http_status, :headers, :body
    attr_reader :mode, :logger, :effective_route_config, :variables
    attr_reader :typenames_to_values

    # Computes the metadata used to identify where the request/response should
    # be stored-to/retrieved-from. Recording the full request is not strictly
    # necessary (because the request maps to a MD5 used for response-only) but
    # it adds human-readability and the ability to manually customize some or
    # all responses.
    def initialize(options)
      unless (@logger = options[:logger])
        raise ::ArgumentError, "options[:logger] is required: #{@logger.inspect}"
      end
      unless (@mode = options[:mode].to_s) && MODES.include?(@mode)
        raise ::ArgumentError, "options[:mode] must be one of #{MODES.inspect}: #{@mode.inspect}"
      end
      unless (@kind = options[:kind].to_s) && KINDS.include?(@kind)
        raise ::ArgumentError, "options[:kind] must be one of #{KINDS.inspect}: #{@kind.inspect}"
      end
      unless (@uri = options[:uri]) && @uri.respond_to?(:path)
        raise ::ArgumentError, "options[:uri] must be a valid parsed URI: #{@uri.inspect}"
      end
      unless (@verb = options[:verb]) && VERBS.include?(@verb)
        raise ::ArgumentError, "options[:verb] must be one of #{VERBS.inspect}: #{@verb.inspect}"
      end
      unless (@headers = options[:headers]).kind_of?(::Hash)
        raise ::ArgumentError, "options[:headers] must be a hash: #{@headers.inspect}"
      end
      unless (@route_data = options[:route_data]).kind_of?(::Hash)
        raise ::ArgumentError, "options[:route_data] must be a hash: #{@route_data.inspect}"
      end
      @http_status = options[:http_status]
      if @kind == 'response'
        @http_status = Integer(@http_status)
      elsif !@http_status.nil?
        raise ::ArgumentError, "options[:http_status] is unexpected for #{@kind}."
      end
      unless (@variables = options[:variables]).kind_of?(::Hash)
        raise ::ArgumentError, "options[:variables] must be a hash: #{@variables.inspect}"
      end
      if (@effective_route_config = options[:effective_route_config]) && !@effective_route_config.kind_of?(::Hash)
        raise ::ArgumentError, "options[:effective_route_config] is not a hash: #{@effective_route_config.inspect}"
      end
      @body = options[:body]  # not required

      # merge one or more wildcard configurations matching the current uri and
      # parameters.
      @headers = normalize_headers(@headers)
      @typenames_to_values = compute_typenames_to_values

      # effective route config may already have been computed for request
      # (on record) or not (on playback).
      @effective_route_config ||= compute_effective_route_config

      # apply the configuration by substituting for variables in the request and
      # by obfuscating wherever a variable name is nil.
      case @mode
      when 'validate'
        # do nothing; used to validate the fixtures before playback, etc.
      else
        erck = @effective_route_config[@kind]
        if effective_variables = erck && erck[VARIABLES_KEY]
          recursive_replace_variables(
            [@kind, VARIABLES_KEY],
            @typenames_to_values,
            effective_variables,
            erck[TRANSFORM_KEY])
        end
        if logger.debug?
          logger.debug("#{@kind} effective_route_config = #{@effective_route_config[@kind].inspect}")
          logger.debug("#{@kind} typenames_to_values = #{@typenames_to_values.inspect}")
        end
      end

      # recreate headers and body from data using variable substitutions and
      # obfuscations.
      @headers = @typenames_to_values[:header]
      @body = normalize_body(@headers, @typenames_to_values[:body] || @body)
    end

    # @return [String] normalized query string
    def query
      q = @typenames_to_values[:query]
      if q && !q.empty?
        build_query_string(q)
      else
        nil
      end
    end

    # @return [String] computed checksum for normalized 'significant' data
    def checksum
      @checksum ||= compute_checksum
    end

    # @return [Hash] timeouts from effective configuration or empty
    def timeouts
      (@effective_route_config[@kind] || {})[TIMEOUTS_KEY] || {}
    end

    # Establishes a normal header key form for agreement between configuration
    # and metadata pieces.
    #
    # @param [String|Symbol] key to normalize
    #
    # @return [String] normalized key
    def self.normalize_header_key(key)
      key.to_s.downcase.gsub('-', '_')
    end

    # @param [String] url to normalize
    #
    # @return [URI] uri with scheme inserted if necessary
    def self.normalize_uri(url)
      # the following logic is borrowed from RestClient::Request#parse_url
      url = "http://#{url}" unless url.match(/^http/)
      uri = ::URI.parse(url)

      # need at least a (leading) forward-slash in path for any subsequent route
      # matching.
      uri.path = '/' if uri.path.empty?

      # strip proxied server details not needed for playback.
      # strip any basic authentication, which is never recorded.
      uri = ::URI.parse(url)
      uri.scheme = nil
      uri.host = nil
      uri.port = nil
      uri.user = nil
      uri.password = nil
      uri
    end

    # Sorts data for a consistent appearance in JSON.
    #
    # HACK: replacement for ::RightSupport::Data::HashTools.deep_sorted_json
    # method that can underflow the @state.depth field as -1 probably due to
    # some (1.9.3+?) logic that resets the depth to zero when JSON data gets too
    # deep or else @state.depth doesn't mean what it used to mean in Ruby 1.8.
    # need to fix the utility...
    #
    # @param [Hash|Array] data to JSONize
    #
    # @return [String] sorted JSON
    def self.deep_sorted_json(data, pretty = false)
      data = deep_sorted_data(data)
      pretty ? ::JSON.pretty_generate(data) : ::JSON.dump(data)
    end

    # Duplicates and sorts hash keys for a consistent appearance (in JSON).
    # Traverses arrays to sort hash elements. Note this only works for Ruby 1.9+
    # due to hashes now preserving insertion order.
    #
    # @param [Hash|Array] data to deep-sort
    #
    # @return [String] sorted data
    def self.deep_sorted_data(data)
      case data
      when ::Hash
        data = data.map { |k, v| [k.to_s, v] }.sort.inject({}) do |h, (k, v)|
          h[k] = deep_sorted_data(v)
          h
        end
      when Array
        data.map { |e| deep_sorted_data(e) }
      else
        if data.respond_to?(:to_hash)
          deep_sorted_data(data.to_hash)
        else
          data
        end
      end
    end

    protected

    # @see RightDevelop::Testing::Client::RecordMetadata.normalize_header_key
    def normalize_header_key(key)
      self.class.normalize_header_key(key)
    end

    # Transforms all relevant request fields to data that can be matched by
    # qualifiers or substituted with variables.
    #
    # @param [URI] uri for query string, etc.
    # @param [Hash] normalized_headers for header information
    # @param [String] body to parse
    #
    # @return [Mash] types to names to values
    def compute_typenames_to_values
      ::Mash.new(
        verb:   @verb,
        query:  parse_query_string(@uri.query.to_s),
        header: @headers,
        body:   parse_body(@headers, @body)
      )
    end

    # Parses a query string (from URI or payload) to a mapping of parameter name
    # to a mapping of parameter name to value(s). Parses nested queries using
    # the "hash_name[key][subkey][]" notation (FIX: which is called what?).
    #
    # @param [String] query_string to parse
    #
    # @return [Hash] parsed query
    def parse_query_string(query_string)
      ::Rack::Utils.parse_nested_query(query_string)
    end

    # @param [Hash] hash for query string
    #
    # @return [String] query string
    def build_query_string(hash)
      ::Rack::Utils.build_nested_query(hash)
    end

    # Content-Type header can have other information (such as encoding) so look
    # specifically for the 'application/blah' information.
    #
    # @param [Hash] normalized_headers for lookup
    #
    # @return [String] content type or nil
    def compute_content_type(normalized_headers)
      # content type may be an array or an array of strings needing to be split.
      #
      # example: ["application/json; charset=utf-8"]
      content_type = normalized_headers['content_type']
      content_type = Array(content_type).join(';').split(';').map { |ct| ct.strip }
      last_seen = nil
      content_type.each do |ct|
        ct = ct.strip
        return ct if ct.start_with?('application/')
      end
      nil
    end

    # Parses the body using content type.
    #
    # @param [Hash] normalized_headers for content type, etc.
    #
    # @return [Hash] body as a hash of name/value pairs or empty if not parsable
    def parse_body(normalized_headers, body)
      body = body.to_s
      unless body.empty?
        case compute_content_type(normalized_headers)
        when nil
          # do nothing
        when 'application/x-www-form-urlencoded'
          return parse_query_string(body)
        when 'application/json'
          return ::JSON.load(body)
        else
          # try-parse for other application/* content types to avoid having to
          # specify anything more here. modern formats are JSONish and we
          # currently don't care about XMLish formats.
          begin
            return ::JSON.load(body)
          rescue ::JSON::ParserError
            # ignored
          end
        end
      end
      nil
    end

    # Reformats body data in a normal form that involves sorted query-string or
    # JSON format. The idea is that the same payload can appear many times with
    # slightly different ordering of body elements and yet represent the same
    # request or response.
    #
    # @return [String] normalized body
    def normalize_body(normalized_headers, body)
      case body
      when nil
        return body
      when ::Hash, ::Array
        body_hash = body
      when ::String
        body_hash = parse_body(normalized_headers, body)
        return body unless body_hash
      else
        return body
      end
      case ct = compute_content_type(normalized_headers)
      when 'application/x-www-form-urlencoded'
        result = build_query_string(body_hash)
        normalize_content_length(normalized_headers, result)
      else
        result = ::JSON.dump(body_hash)
        normalize_content_length(normalized_headers, result)
      end
      result
    end

    # Updates content-length header for normalized body, if necessary.
    def normalize_content_length(normalized_headers, normalized_body)
      if normalized_headers['content_length']
        normalized_headers['content_length'] = ::Rack::Utils.bytesize(normalized_body)
      end
      true
    end

    # Computes the effective route configuration for the current request, which
    # may be an amalgam of several configurations found by URI wildcard.
    #
    # @param [URI] uri for request with some details omitted
    # @param [Hash] typenames_to_values in form of { type => name [=> subkey]* => value }
    #
    # @return [Hash] effective route configuration
    def compute_effective_route_config
      result = ::Mash.new
      if configuration_data = @route_data[MATCHERS_KEY]
        # the top-level keys are expected to be regular expressions used to
        # match only the URI path.
        uri_qualified_data = []
        configuration_data.each do |uri_regex, qualified_data|
          if uri_regex.match(uri.path)
            uri_qualified_data << qualified_data
          end
        end

        # the next level attempts to match qualifiers, which could be empty.
        # if all known qualifiers match then the configuration is applied.
        uri_qualified_data.each do |qualified_data|
          # the same URI can map to multiple sets of qualified configurations.
          # the left-hand is a mapping of (typenames to required values) and
          # the right-hand is the configuration to use when matched.
          #
          # note that .all? == true when .empty? == true
          qualified_data.each do |qualifier_hash, configuration|
            all_matched = qualifier_hash.all? do |qualifier_type, qualifier_name_to_value|
              match_deep(@typenames_to_values[qualifier_type], qualifier_name_to_value)
            end
            if all_matched
              # the final data is the union of all configurations matching
              # this request path and qualifiers. the uri regex and other
              # data used to match the request parameters is eliminated from
              # the final configuration.
              ::RightSupport::Data::HashTools.deep_merge!(result, configuration)
            end
          end
        end
      end
      result
    end

    # Partially matches the real data against a subset of known values.
    #
    # @param [Hash] target to match
    # @param [Hash] source for lookup in real data
    #
    # @return [TrueClass|FalseClass] true if all matched, false if any differed
    def match_deep(target, source)
      case source
      when ::Hash
        source.all? do |k, v|
          target_value = target[k]
          if target_value.kind_of?(::Hash) && v.kind_of?(::Hash)
            match_deep(target_value, v)
          else
            target_value.to_s == v.to_s
          end
        end
      else
        target == source
      end
    end

    # Deep substitutes variables while capturing/substituting real data and/or
    # obfuscates sensitive data.
    #
    # note that @variables is a flat hash of variable names (chosen by the user
    # configuration) to literal values; the user is required to make unique or
    # reuse these effectively 'global' variable names where appropriate. the are
    # not constrained in any way so a convention such as
    # 'my::namespace::variable_name' could be used.
    #
    # the literal values can be any JSON type, etc. the type of the value does
    # not have to be string (even though we will record a placeholder string)
    # because the value will be changed back to the original before playback
    # responds.
    #
    # the value can change over time without a problem. we will keep all of the
    # values by the same variable name in an array. the value that we insert
    # into the recorded data will be the variable name plus the value array
    # index in brackets ([]) if the index is non-zero. if the value keeps being
    # changed to distinct values in an unbounded fashion then that would be an
    # issue for recording because we have no bounds check here.
    #
    # example: {someFieldInBody:"my_variable_name[42]"}
    #
    # this allows
    #
    # @param [Hash] variables from current state
    # @param [Hash] target to receive substituted names
    # @param [Hash] source for variables to substitute
    # @param [Hash] transform for data structure elements or nil
    #
    # @return [Hash] data with any replacements
    def recursive_replace_variables(path, target, source, transform)
      source.each do |k, variable|
        unless (target_value = target[k]).nil?

          # apply transform, if any, before attempting to replace variables.
          case current_transform = transform && transform[k]
          when ::String
            case current_transform
            when 'JSON'
              target_value = ::JSON.parse(target_value)
            else
              raise RecordingError, "Unknown transform: #{current_transform}"
            end
          end

          # variable replacement.
          case variable
          when nil
            # non-captured hidden credential. same for request or response.
            target_value = HIDDEN_CREDENTIAL_VALUE
          when ::Array
            # array should have a single element which should be a hash with
            # futher variable declarations for
            #   "one ore more objects of the same type in an array."
            # the array is only an indicator that an array is expected here.
            variables_for_elements = variable.first
            if variable.size != 1 || !variables_for_elements.kind_of?(::Hash)
              message = 'Invalid variable specification has an array but does '+
                        'not have exactly one element that is a hash at ' +
                        "#{(path + [k]).join('/').inspect}"
              raise RecordingError, message
            end

            transform_for_elements = nil
            if current_transform
              if current_transform.kind_of?(::Array) &&
                 current_transform.size == 1 &&
                 current_transform.first.kind_of?(::Hash)
                transform_for_elements = current_transform.first
              else
                message = 'Invalid transform specification does not match ' +
                          'array variable specification at ' +
                          (path + [k]).join('/').inspect
                raise RecordingError, message
              end
            end
            if target_value.kind_of?(::Array)
              target_value.each_with_index do |item, index|
                recursive_replace_variables(
                  path + [k, index],
                  item,
                  variables_for_elements,
                  transform_for_elements)
              end
            end
          when ::Hash
            # ignore if target is not a hash; allow a root config to try and
            # replace variables without knowing exact schema for each request.
            if target_value.kind_of?(::Hash)
              transform_for_subhash = current_transform.kind_of?(::Hash) ? current_transform : nil
              recursive_replace_variables(
                path + [k],
                target_value,
                variable,
                transform_for_subhash)
            end
          when ::String
            case @kind
            when 'request'
              # record request changes real data to variable name after
              # caching the real value.
              # playback request is parsed only in order to cache the variable
              # value; variable name will not appear anywhere in playback.
              target_value = variable_to_cache(variable, target_value)
            when 'response'
              case @mode
              when 'record'
                # value must exist (from some previous request) for the response
                # to be able to reference it.
                target_value = variable_in_cache(path, variable, target_value)
              when 'playback'
                # playback response uses cached variable value from some
                # previous request.
                target_value = variable_from_cache(path, variable, target_value)
              else
                fail "Unexpected mode: #{@mode.inspect}"
              end
            else
              fail "Unexpected kind: #{@kind.inspect}"
            end
          else
            # a nil target_value would mean the data did not have a placeholder
            # for the value to subtitute, which is ignorable.
            # what is not ignorable, however, is having an unexpected type here.
            message = 'Unexpected variable entry at ' +
                      "#{(path + [k]).join('/').inspect}"
            raise RecordingError, message
          end

          # reverse transform, if any, before reassignment.
          case current_transform
          when 'JSON'
            target_value = ::JSON.dump(target_value)
          end
          target[k] = target_value
        end
      end
      target
    end

    # Inserts (or reuses) a real value into cached array by variable name.
    def variable_to_cache(variable, real_value)
      result = nil
      if values = @variables[variable]
        # quick out for same as initial value; don't show array index.
        if values.first == real_value
          result = variable
        else
          # show zero-based array index beyond the zero index.
          unless value_index = values.index(real_value)
            value_index = values.size
            values << real_value
          end
          result = "#{variable}[#{value_index}]"
        end
      else
        # new variable, quick out.
        @variables[variable] = [real_value]
        result = variable
      end
      result
    end

    # Requires a real value to already exist in cache by variable name.
    def variable_in_cache(path, variable, real_value)
      result = nil
      values = @variables[variable]
      case value_index = values && values.index(real_value)
      when nil
        message = 'A variable referenced by a response has not yet been ' +
                  "defined by a request while replacing variable = " +
                  "#{variable.inspect} at #{path.join('/').inspect}"
        raise RecordingError, message
      when 0
        variable
      else
        "#{variable}[#{value_index}]"
      end
    end

    # Attempts to get cached variable value by index from recorded string.
    def variable_from_cache(path, variable, target_value)
      result = nil
      if variable_array = @variables[variable]
        if matched = VARIABLE_INDEX_REGEX.match(target_value)
          variable_array_index = Integer(matched[1])
        else
          variable_array_index = 0
        end
        if variable_array_index >= variable_array.size
          # see below.
          throw(
            HALT,
            MissingVariableFailure.new(
              path:                 path,
              variable:             variable,
              variable_array_index: variable_array_index,
              variable_array_size:  variable_array.size))
        end
        result = variable_array[variable_array_index]
      else
        # this might be caused by a race condition where the request that
        # expects the variable to be set is made on a thread that runs faster
        # than the thread making the API call that defines the variable. if so
        # then the race should resolve itself after a few retries. if the
        # variable is never defined then that can be handled later.
        # unfortunately, all of the metadata has to be recreated after the state
        # has changed and there is no way to determine this condition exists
        # without performing that work.
        throw(
          HALT,
          MissingVariableFailure.new(
            path:                 path,
            variable:             variable))
      end
      result
    end

    # normalizes header keys, removes some unwanted headers and obfuscates any
    # cookies.
    def normalize_headers(headers)
      result = headers.inject({}) do |h, (k, v)|
        # value is in raw form as array of sequential header values
        h[normalize_header_key(k)] = v
        h
      end

      # eliminate headers that interfere with playback or don't make sense to
      # record.
      %w(
        connection status host user_agent content_encoding
      ).each { |key| result.delete(key) }

      # always obfuscate cookie headers as they won't be needed for playback and
      # would be non-trivial to configure for each service.
      %w(cookie set_cookie).each do |k|
        if cookies = result[k]
          if cookies.is_a?(::String)
            cookies = cookies.split(';').map { |c| c.strip }
          end
          result[k] = cookies.map do |cookie|
            if offset = cookie.index('=')
              cookie_name = cookie[0..(offset-1)]
              "#{cookie_name}=#{HIDDEN_CREDENTIAL_VALUE}"
            else
              cookie
            end
          end
        end
      end
      result
    end

    # determines which values are significant to checksum. by default the verb
    # query and body are significant but not headers. if the caller specifies
    # any of them (except verb and http_status) then that overrides default.
    def compute_checksum
      # some things are significant by default but can be overridden by config.
      significant =
        (@effective_route_config[@kind] &&
         @effective_route_config[@kind][SIGNIFICANT_KEY]) ||
        {}

      # verb and (response-only) http_status are always significant.
      significant_data = ::Mash.new(verb: @verb)
      significant_data[:http_status] = @http_status if @http_status

      # headers
      copy_if_significant(:header, significant, significant_data)

      # query
      unless copy_if_significant(:query, significant, significant_data)
        # entire query string is significant by default.
        significant_data[:query] = @typenames_to_values[:query]
      end

      # body
      unless copy_if_significant(:body, significant, significant_data)
        case body_value = @typenames_to_values[:body]
        when nil
          # body is either nil, empty or was not parsable; insert the checksum
          # of the original body.
          case @body
          when nil, '', ' '
            significant_data[:body_checksum] = 'empty'
          else
            significant_data[:body_checksum] = ::Digest::MD5.hexdigest(@body)
          end
        else
          # body was parsed but no single element was considered significant.
          # use the parsed body so that it can be 'normalized' in sorted order.
          significant_data[:body] = body_value
        end
      end

      # use deep-sorted JSON to prevent random ordering changing the checksum.
      checksum_data = self.class.deep_sorted_json(significant_data)
      if logger.debug? && @mode != 'validate'
        logger.debug("#{@kind} checksum_data = #{checksum_data.inspect}")
      end
      ::Digest::MD5.hexdigest(checksum_data)
    end

    # Performs a selective copy of any significant fields (recursively) or else
    # does nothing. Significance does not require the field to exist in the
    # known fields; a missing field is still significant (value = nil).
    #
    # @param [String|Symbol] type of significance
    # @param [Hash] significant selectors
    # @param [Hash] significant_data to populate
    #
    # @return [TrueClass|FalseClass] true if any were significant
    def copy_if_significant(type, significant, significant_data)
      if significant_type = significant[type]
        significant_data[type] = recursive_selective_hash_copy(
          ::Mash.new, @typenames_to_values[type], significant_type)
        true
      else
        false
      end
    end

    # Recursively selects and copies values from source to target.
    def recursive_selective_hash_copy(target, source, selections, path = [])
      selections.each do |k, v|
        case v
        when nil
          # hash to nil; user configured by using flat hashes instead of arrays.
          # it's a style thing that makes the YAML look prettier.
          copy_hash_value(target, source, path + [k])
        when ::Array
          # also supporting arrays of names at top level or under a hash.
          v.each { |item| copy_hash_value(target, source, path + [item]) }
        when ::Hash
          # recursion.
          recursive_selective_hash_copy(target, source, v, path + [k])
        end
      end
      target
    end

    # copies a single value between hashes by path.
    def copy_hash_value(target, source, path)
      value = ::RightSupport::Data::HashTools.deep_get(source, path)
      ::RightSupport::Data::HashTools.deep_set!(target, path, value)
      true
    end

  end # Metadata
end # RightDevelop::Testing::Recording

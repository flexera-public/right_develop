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
require 'right_develop/testing/clients/rest'

require 'digest/md5'
require 'rest_client'
require 'right_support'
require 'yaml'

module RightDevelop::Testing::Client::Rest::Request

  # Base class for record/playback request implementations.
  class Base < ::RestClient::Request

    HIDDEN_CREDENTIAL_NAMES = %w(email password user username)
    HIDDEN_CREDENTIAL_VALUE = 'hidden_credential'

    attr_reader :fixtures_dir, :logger, :route_record_dir, :state_file_path
    attr_reader :request_timestamp, :response_timestamp

    def initialize(args)
      args = args.dup
      unless @fixtures_dir = args.delete(:fixtures_dir)
        raise ::ArgumentError, 'fixtures_dir is required'
      end
      unless @logger = args.delete(:logger)
        raise ::ArgumentError, 'logger is required'
      end
      unless @route_record_dir = args.delete(:route_record_dir)
        raise ::ArgumentError, 'route_record_dir is required'
      end
      unless @state_file_path = args.delete(:state_file_path)
        raise ::ArgumentError, 'state_file_path is required'
      end

      super(args)

      if @block_response
        raise ::NotImplementedError,
              'block_response not supported for record/playback'
      end
      if @raw_response
        raise ::ArgumentError, 'raw_response not supported for record/playback'
      end
    end

    # Overrides log_request to capture start-time for network request.
    #
    # @return [Object] undefined
    def log_request
      result = super
      @request_timestamp = ::Time.now.to_i
      result
    end

    # Overrides log_response to capture end-time for network request.
    #
    # @param [RestClient::Response] to capture
    #
    # @return [Object] undefined
    def log_response(response)
      @response_timestamp = ::Time.now.to_i
      super
    end

    protected

    # @return [Hash] current state
    def state
      @state ||= initialize_state
    end

    # Initializes the state used to keep track of the current epoch (in seconds
    # since start of run, etc.) for record/playback.
    #
    # @return [Hash] initialized state
    def initialize_state
      if ::File.file?(state_file_path)
        ::YAML.load_file(state_file_path)
      else
        { epoch: 0 }
      end
    end

    # Saves the state file.
    #
    # @return [TrueClass] always true
    def save_state
      ::File.open(state_file_path, 'w') { |f| f.puts(::YAML.dump(state)) }
      true
    end

    # @return [String] checksum for given value or 'empty'
    def checksum(value)
      value = value.to_s
      value.empty? ? 'empty' : ::Digest::MD5.hexdigest(value)
    end

    # Computes the metadata used to identify where the request/response should
    # be stored-to/retrieved-from. Recording the request is not strictly
    # necessary (because the request maps to a MD5 used for response-only) but
    # it adds human-readability and the ability to manually customize some or
    # all responses.
    #
    # @return [Hash] metadata for storing/retrieving request and response
    def compute_record_metadata
      # use rest-client method to parse URL (again).
      uri = parse_url(@url)
      query_file_name = self.method.to_s.upcase
      unless (query_string = uri.query.to_s).empty?
        # try to keep it human-readable by CGI-escaping the only illegal *nix
        # file character = '/'.
        query_string = normalize_query_string(query_string).gsub('/', '%2F')
        query_file_name << '_' << query_string
      end

      # payload is an I/O object but we can quickly get body from .string if it
      # is a StringIO object. assume it always is a string unless streaming a
      # large file, in which case we don't support it currently.
      stream = @payload.instance_variable_get(:@stream)
      if stream && stream.respond_to?(:string)
        body = stream.string
      else
        # assume payload is too large to buffer or else it would be StringIO.
        # we could compute the MD5 by streaming if we really wanted to, but...
        raise ::NotImplementedError,
              'Non-string payload streams are not currently supported.'
      end

      # JSON data may be hash-ordered inconsistently between invocations.
      # attempt to sort JSON data before creating a key.
      case headers['CONTENT_TYPE']
      when 'application/x-www-form-urlencoded'
        normalized_body = normalize_query_string(body)
      when 'application/json'
        normalized_body = normalize_json(body)
      else
        normalized_body = body
      end
      normalized_body_token = body.empty? ? 'empty' : ::Digest::MD5.hexdigest(body)
      query_file_name = "#{normalized_body_token}_#{query_file_name}"
      relative_request_dir = ::File.join('requests', uri.path)
      relative_response_dir = ::File.join('responses', uri.path)

      # make URI relative to target server (eliminate proxy server detail).
      uri.scheme = nil
      uri.host = nil
      uri.port = nil
      uri.user = nil
      uri.password = nil

      # result
      {
        uri:                   uri,
        normalized_body:       normalized_body,
        normalized_body_token: normalized_body_token,
        query_file_name:       query_file_name,
        relative_request_dir:  relative_request_dir,
        relative_response_dir: relative_response_dir,
      }
    end

    # Sort the given query string fields because order of parameters should not
    # matter but multiple invocations might shuffle the parameter order.
    # Also attempts to obfuscate any user credentials.
    #
    # @param [String] query_string to normalize
    #
    # @return [String] normalized query string
    def normalize_query_string(query_string)
      query = []
      ::CGI.parse(query_string).sort.each do |k, v|
        # right-hand-side of CGI.parse hash is always an array
        normalized_key = normalized_parameter_name(k)
        v.sort.each do |item|
          # top-level obfuscation (FIX: deeper?)
          if HIDDEN_CREDENTIAL_NAMES.include?(normalized_key)
            item = HIDDEN_CREDENTIAL_VALUE if item.is_a?(::String)
          end
          query << "#{k}=#{item}"
        end
      end
      query.join('&')
    end

    # Deep-sorts the given JSON string and attempts to obfuscate any user
    # credentails.
    #
    # Note that if the payload contains arrays that contain hashes then those
    # hashes are not sorted due to a limitation of deep_sorted_json.
    #
    # FIX: deep_sorted_json could traverse arrays and sort sub-hashes if
    # necessary.
    #
    # @param [String] json to normalize
    #
    # @return [String] normalized JSON string
    def normalize_json(json)
      # top-level obfuscation (FIX: deeper?)
      hash = ::JSON.load(json).inject({}) do |h, (k, v)|
        normalized_key = normalized_parameter_name(k)
        if HIDDEN_CREDENTIAL_NAMES.include?(normalized_key)
          v = HIDDEN_CREDENTIAL_VALUE if item.is_a?(::String)
        end
        h[k] = v
      end
      ::RightSupport::Data::HashTools.deep_sorted_json(hash, pretty = true)
    end

    # Converts header/payload keys to a form consistent with parameter passing
    # logic. The various layers of Net::HTTP, RestClient and Rack all seem to
    # have different conventions for header/parameter names.
    def normalized_parameter_name(key)
      key.to_s.gsub('-', '').gsub('_', '').downcase
    end

    def request_file_path(record_metadata)
      ::File.join(
        @fixtures_dir,
        state[:epoch].to_s,
        @route_record_dir,
        record_metadata[:relative_request_dir],
        record_metadata[:query_file_name] + '.txt')
    end

    def response_file_path(record_metadata)
      ::File.join(
        @fixtures_dir,
        state[:epoch].to_s,
        @route_record_dir,
        record_metadata[:relative_response_dir],
        record_metadata[:query_file_name] + '.yml')
    end

  end # Base

end # RightDevelop::Testing::Client::Rest

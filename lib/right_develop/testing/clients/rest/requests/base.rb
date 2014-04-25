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
require 'right_develop/testing/recording/metadata'

require 'rack/utils'
require 'rest_client'
require 'right_support'
require 'yaml'

module RightDevelop::Testing::Client::Rest::Request

  # Base class for record/playback request implementations.
  class Base < ::RestClient::Request

    # metadata.
    METADATA_CLASS = ::RightDevelop::Testing::Recording::Metadata

    attr_reader :fixtures_dir, :logger, :route_path, :route_data
    attr_reader :state_file_path, :request_timestamp, :response_timestamp
    attr_reader :request_metadata

    def initialize(args)
      args = args.dup
      unless @fixtures_dir = args.delete(:fixtures_dir)
        raise ::ArgumentError, 'fixtures_dir is required'
      end
      unless @logger = args.delete(:logger)
        raise ::ArgumentError, 'logger is required'
      end
      unless @route_path = args.delete(:route_path)
        raise ::ArgumentError, 'route_path is required'
      end
      unless @route_data = args.delete(:route_data)
        raise ::ArgumentError, 'route_data is required'
      end
      unless @route_data[:subdir]
        raise ::ArgumentError, "route_data is invalid: #{route_data.inspect}"
      end
      unless @state_file_path = args.delete(:state_file_path)
        raise ::ArgumentError, 'state_file_path is required'
      end

      # resolve request metadata before initializing base class in order to set
      # any timeout values.
      request_verb = args[:method] or raise ::ArgumentError, "must pass :method"
      request_verb = request_verb.to_s.upcase
      request_headers = (args[:headers] || {}).dup
      request_url = args[:url] or raise ::ArgumentError, "must pass :url"
      request_url = process_url_params(request_url, request_headers)
      if request_body = args[:payload]
        # currently only supporting string payload or nil.
        unless request_body.kind_of?(::String)
          raise ::ArgumentError, 'args[:payload] must be a string'
        end
      end

      rm = nil
      with_state_lock do |state|
        rm = METADATA_CLASS.new(
          mode:       recording_mode,
          kind:       :request,
          logger:     @logger,
          route_data: @route_data,
          uri:        METADATA_CLASS.normalize_uri(request_url),
          verb:       request_verb,
          headers:    request_headers,
          body:       request_body,
          variables:  state[:variables])
      end
      @request_metadata = rm
      unless rm.timeouts.empty?
        args = args.dup
        if rm.timeouts[:open_timeout]
          args[:open_timeout] = Integer(rm.timeouts[:open_timeout])
        end
        if rm.timeouts[:read_timeout]
          args[:timeout] = Integer(rm.timeouts[:read_timeout])
        end
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

    # Handles a timeout raised by a Net::HTTP call.
    #
    # @return [Net::HTTPResponse] response
    def handle_timeout
      raise NotImplementedError, 'Must be overridden'
    end

    protected

    # @return [Symbol] recording mode as one of [:record, :playback]
    def recording_mode
      raise NotImplementedError, 'Must be overridden'
    end

    # Holds the state file lock for block.
    #
    # @yield [state] gives exclusive state access to block
    # @yieldparam [Hash] state
    # @yieldreturn [Object] anything
    #
    # @return [Object] block result
    def with_state_lock
      result = nil
      state_dir = ::File.dirname(state_file_path)
      ::FileUtils.mkdir_p(state_dir) unless ::File.directory?(state_dir)
      ::File.open(state_file_path, ::File::RDWR | File::CREAT, 0644) do |f|
        f.flock(::File::LOCK_EX)
        state_yaml = f.read
        if state_yaml.empty?
          state = { epoch: 0, variables: {} }
        else
          state = ::YAML.load(state_yaml)
        end
        result = yield(state)
        f.seek(0)
        f.truncate(0)
        f.puts(::YAML.dump(state))
      end
      result
    end

    # @return [RightDevelop::Testing::Client::RecordMetdata] metadata for response
    def response_metadata(state, response_code, response_headers, response_body)
      METADATA_CLASS.new(
        mode:                   recording_mode,
        kind:                   :response,
        logger:                 logger,
        route_data:             @route_data,
        effective_route_config: request_metadata.effective_route_config,
        uri:                    request_metadata.uri,
        verb:                   request_metadata.verb,
        http_status:            response_code,
        headers:                response_headers,
        body:                   response_body,
        variables:              state[:variables])
    end

    # Directory common to all fixtures of the given kind.
    def fixtures_route_dir(kind, state)
      ::File.join(
        @fixtures_dir,
        state[:epoch].to_s,
        @route_data[:subdir],
        kind.to_s)
    end

    # Expands path to fixture file given kind, state, etc.
    def fixture_file_path(kind, state)
      # remove API root from path because we are already under an API-specific
      # subdirectory and the route base path may be redundant.
      unless request_metadata.uri.path.start_with?(@route_path)
        raise ::ArgumentError,
              "Request URI = #{request_metadata.uri.path.inspect} did not start with #{@route_path.inspect}."
      end
      route_relative_path = request_metadata.uri.path[@route_path.length..-1]
      ::File.join(
        fixtures_route_dir(kind, state),
        route_relative_path,
        request_metadata.checksum + '.yml')
    end

    def request_file_path(state)
      fixture_file_path(:request, state)
    end

    def response_file_path(state)
      fixture_file_path(:response, state)
    end

  end # Base

end # RightDevelop::Testing::Client::Rest

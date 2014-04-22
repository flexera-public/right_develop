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

    attr_reader :fixtures_dir, :logger, :route_data, :state_file_path
    attr_reader :request_timestamp, :response_timestamp

    def initialize(args)
      args = args.dup
      unless @fixtures_dir = args.delete(:fixtures_dir)
        raise ::ArgumentError, 'fixtures_dir is required'
      end
      unless @logger = args.delete(:logger)
        raise ::ArgumentError, 'logger is required'
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

    # @return [String] verb for current request
    def request_verb
      # Q: does it seem weird that RestClient::Request overrides the core
      #    Object#method function?
      # A: it is very weird; try getting any .method(name) metadata from one of
      #    these objects.
      method.to_s.upcase
    end

    # @return [String] body from request payload object
    def request_body
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
      body
    end

    # @return [RightDevelop::Testing::Client::RecordMetdata] metadata for request
    def request_metadata(state)
      METADATA_CLASS.new(
        mode:       recording_mode,
        kind:       :request,
        logger:     logger,
        route_data: @route_data,
        uri:        METADATA_CLASS.normalize_uri(@url),
        verb:       request_verb,
        headers:    headers,
        body:       request_body,
        variables:  state[:variables])
    end

    # @return [RightDevelop::Testing::Client::RecordMetdata] metadata for response
    def response_metadata(state, request_metadata, response_code, response_headers, response_body)
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

    def request_file_path(state, request_metadata)
      ::File.join(
        @fixtures_dir,
        state[:epoch].to_s,
        @route_data[:subdir],
        'requests',
        request_metadata.uri.path,
        request_metadata.checksum + '.yml')
    end

    def response_file_path(state, request_metadata)
      ::File.join(
        @fixtures_dir,
        state[:epoch].to_s,
        @route_data[:subdir],
        'responses',
        request_metadata.uri.path,
        request_metadata.checksum + '.yml')
    end

  end # Base

end # RightDevelop::Testing::Client::Rest

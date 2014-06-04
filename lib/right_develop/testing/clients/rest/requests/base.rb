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

require 'digest/md5'
require 'rack/utils'
require 'rest_client'
require 'right_support'
require 'thread'
require 'yaml'

module RightDevelop::Testing::Client::Rest::Request

  # Base class for record/playback request implementations.
  class Base < ::RestClient::Request

    # metadata.
    METADATA_CLASS = ::RightDevelop::Testing::Recording::Metadata

    # semaphore
    MUTEX = ::Mutex.new

    attr_reader :fixtures_dir, :logger, :route_path, :route_data
    attr_reader :state_file_path, :request_timestamp, :response_timestamp
    attr_reader :request_metadata, :response_metadata

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
      @response_metadata = nil

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
      push_outstanding_request
      result
    end

    # Overrides log_response to capture end-time for network request.
    #
    # @param [RestClient::Response] to capture
    #
    # @return [Object] undefined
    def log_response(response)
      pop_outstanding_request
      super
    end

    # Handles a timeout raised by a Net::HTTP call.
    #
    # @return [Net::HTTPResponse] response or nil if subclass responsibility
    def handle_timeout
      pop_outstanding_request
      nil
    end

    # Removes the current request from the FIFO queue of outstanding requests in
    # case of error, redirect, etc.
    def forget_outstanding_request
      ruid = request_uid
      ork = outstanding_request_key
      with_state_lock do |state|
        outstanding = state[:outstanding]
        if outstanding_requests = outstanding[ork]
          if outstanding_requests.delete(ruid)
            logger.debug("Forgot outstanding request uid=#{ruid.inspect} at #{ork.inspect}")
          end
          outstanding.delete(ork) if outstanding_requests.empty?
        end
      end
    end

    protected

    # @return [Symbol] recording mode as one of [:record, :playback]
    def recording_mode
      raise NotImplementedError, 'Must be overridden'
    end

    # @return [String] unique identifier for this request (for this process)
    def request_uid
      @request_uid ||= ::Digest::MD5.hexdigest("#{::Process.pid}, #{self.object_id}")
    end

    # @return [String] path to current outstanding request, if any
    def outstanding_request_key
      ::File.join(request_metadata.uri.path, request_metadata.checksum)
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
      MUTEX.synchronize do  # mutex for thread sync
        state_dir = ::File.dirname(state_file_path)
        ::FileUtils.mkdir_p(state_dir) unless ::File.directory?(state_dir)
        ::File.open(state_file_path, ::File::RDWR | File::CREAT, 0644) do |f|
          f.flock(::File::LOCK_EX)  # file lock for process sync
          state_yaml = f.read
          if state_yaml.empty?
            state = { epoch: 0, variables: {}, outstanding: {} }
          else
            state = ::YAML.load(state_yaml)
          end
          result = yield(state)
          f.seek(0)
          f.truncate(0)
          f.puts(::YAML.dump(state))
        end
      end
      result
    end

    # Keeps a FIFO queue of outstanding requests using request object id in
    # state to ensure responses are synchronous. This is important for record/
    # playback of long polling with many threads/processes doing the polling. We
    # do not want a younger long polling request to steal responses from an
    # older request because we cannot maintain asynchronous state for playback.
    #
    # To make this blocking behavior more reasonable for testing, configure
    # shorter timeouts for API calls that you know are long polling; the default
    # read timeout value is 60 seconds. The timeout only effects playback time
    # if you use throttle > 0.
    def push_outstanding_request
      ruid = request_uid
      ork = outstanding_request_key
      with_state_lock do |state|
        outstanding = state[:outstanding]
        outstanding_requests = outstanding[ork] ||= []
        outstanding_requests << ruid
        logger.debug("Pushed outstanding request uid=#{ruid.inspect} at #{ork.inspect}.")
      end
      @request_timestamp = ::Time.now.to_i
      true
    end

    # Blocks until all similar previous requests have been popped from the
    # queue. This is simple if there is a single producer/consumer of
    # request/response but more complex as threads are introduced.
    def pop_outstanding_request
      @response_timestamp = ::Time.now.to_i
      ruid = request_uid
      ork = outstanding_request_key
      while ruid do
        with_state_lock do |state|
          outstanding = state[:outstanding]
          outstanding_requests = outstanding[ork]
          if outstanding_requests.first == ruid
            outstanding_requests.shift
            outstanding.delete(ork) if outstanding_requests.empty?
            logger.debug("Popped outstanding request uid=#{ruid.inspect} at #{ork.inspect}.")
            ruid = nil
          end
        end
        sleep 0.1 if ruid
      end
      true
    end

    # @return [RightDevelop::Testing::Client::RecordMetdata] metadata for response
    def create_response_metadata(state, response_code, response_headers, response_body)
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
    def fixtures_route_dir(kind, epoch)
      ::File.join(
        @fixtures_dir,
        epoch.to_s,
        @route_data[:subdir],
        kind.to_s)
    end

    # Expands path to fixture file given kind, state, etc.
    def fixture_file_path(kind, epoch)
      # remove API root from path because we are already under an API-specific
      # subdirectory and the route base path may be redundant.
      uri_path = request_metadata.uri.path
      uri_path += '/' unless uri_path.end_with?('/')
      unless uri_path.start_with?(@route_path)
        raise ::ArgumentError,
              "Request URI = #{request_metadata.uri.path.inspect} did not start with #{@route_path.inspect}."
      end
      route_relative_path = uri_path[@route_path.length..-1]
      ::File.join(
        fixtures_route_dir(kind, epoch),
        route_relative_path,
        request_metadata.checksum + '.yml')
    end

    def request_file_path(epoch)
      fixture_file_path(:request, epoch)
    end

    def response_file_path(epoch)
      fixture_file_path(:response, epoch)
    end

  end # Base

end # RightDevelop::Testing::Client::Rest

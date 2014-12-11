#
# Copyright (c) 2013 RightScale Inc
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

require 'fileutils'
require 'rest_client'

module RightDevelop::Testing::Client::Rest::Request

  # Provides a middle-ware layer that intercepts response by overriding the
  # logging mechanism built into rest-client Request. Request supports 'before'
  # hooks (for request) but not 'after' hooks (for response) so logging is all
  # we have.
  class Record < ::RightDevelop::Testing::Client::Rest::Request::Base

    # simulated 504 Net::HTTPResponse
    class TimeoutNetHttpResponse
      attr_reader :code, :body

      def initialize
        message = 'Timeout'
        @code = 504
        @headers = {
          'content-type'   => 'text/plain',
          'content-length' => ::Rack::Utils.bytesize(message).to_s,
          'connection'     => 'close',
        }.inject({}) do |h, (k, v)|
          h[k] = Array(v)  # expected to be an array
          h
        end
        @body = message
      end

      def [](key)
        if header = @headers[key.downcase]
          header.join(', ')
        else
          nil
        end
      end

      def to_hash; @headers; end
    end

    # Overrides transmit to catch halt thrown by log_request.
    #
    # @param [URI[ uri of some kind
    # @param [Net::HTTP] req of some kind
    # @param [RestClient::Payload] of some kind
    #
    # @return
    def transmit(uri, req, payload, &block)
      super
    rescue ::Interrupt
      if @request_timestamp
        logger.warn('Interrupted with at least one request outstanding; will record a timeout response.')
        handle_timeout
      end
      raise
    end

    # Overrides log_request for basic logging.
    #
    # @param [RestClient::Response] to capture
    #
    # @return [Object] undefined
    def log_request
      logger.debug("proxied_url = #{@url.inspect}")
      super
    end

    # Overrides log_response to capture both request and response.
    #
    # @param [RestClient::Response] to capture
    #
    # @return [Object] undefined
    def log_response(response)
      result = super
      with_state_lock { |state| record_response(state, response) }
      result
    end

    # @see RightDevelop::Testing::Client::Rest::Request::Base.handle_timeout
    def handle_timeout
      super
      response = TimeoutNetHttpResponse.new
      with_state_lock { |state| record_response(state, response) }
      response
    end

    protected

    # @see RightDevelop::Testing::Client::Rest::Request::Base#recording_mode
    def recording_mode
      :record
    end

    def record_response(state, response)
      # never record redirects because a redirect cannot be proxied back to the
      # client (i.e. the client cannot update it's request url when proxied).
      code = response.code
      http_status = Integer(code)
      if http_status >= 300 && http_status < 400
        return true
      end

      # use raw headers for response instead of the usual RestClient behavior of
      # converting arrays to comma-delimited strings.
      @response_metadata = create_response_metadata(
        state, http_status, response.to_hash, response.body)

      # record elapsed time in (integral) seconds. not intended to be a precise
      # measure of time but rather used to throttle server if client is time-
      # sensitive for some reason.
      elapsed_seconds = @response_timestamp - @request_timestamp
      response_hash = {
        elapsed_seconds: elapsed_seconds,
        http_status:     response_metadata.http_status,
        headers:         response_metadata.headers.to_hash,
        body:            response_metadata.body,
      }

      # detect collision, if any, to determine if we have entered a new epoch.
      ork = outstanding_request_key
      call_count = 0
      next_checksum = response_metadata.checksum
      if response_data = (state[:response_data] ||= {})[ork]
        last_checksum = response_data[:checksum]
        if last_checksum != next_checksum
          # note that variables never reset due to epoch change but they can be
          # updated by a subsequent client request.
          state[:epoch] += 100        # leave room to insert custom epochs
          state[:response_data] = {}  # reset checksums for next epoch
          logger.debug("A new epoch = #{state[:epoch]} begins due to #{request_metadata.verb} \"#{request_metadata.uri}\"")
        else
          call_count = response_data[:call_count]
        end
      end
      call_count += 1
      state[:response_data][ork] = {
        checksum:   next_checksum,
        call_count: call_count,
      }
      response_hash[:call_count] = call_count

      # write request unless already written.
      file_path = request_file_path(state[:epoch])
      unless ::File.file?(file_path)
        # note that variables are not recorded because they must always be
        # supplied by the client's request.
        request_hash = {
          verb:    request_metadata.verb,
          query:   request_metadata.query,
          headers: request_metadata.headers.to_hash,
          body:    request_metadata.body
        }
        ::FileUtils.mkdir_p(::File.dirname(file_path))
        ::File.open(file_path, 'w') { |f| f.puts(::YAML.dump(request_hash)) }
      end
      logger.debug("Recorded request at #{file_path.inspect}.")

      # response always written for incremented call count.
      file_path = response_file_path(state[:epoch])
      ::FileUtils.mkdir_p(::File.dirname(file_path))
      ::File.open(file_path, 'w') { |f| f.puts(::YAML.dump(response_hash)) }
      logger.debug("Recorded response at #{file_path.inspect}.")
      true
    end

  end # Base
end # RightDevelop::Testing::Client::Rest

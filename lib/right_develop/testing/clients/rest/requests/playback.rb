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

require 'rest_client'

module RightDevelop::Testing::Client::Rest::Request

  # Provides a middle-ware layer that intercepts transmition of the request and
  # escapes out of the execute call with a stubbed response using throw/catch.
  class Playback < ::RightDevelop::Testing::Client::Rest::Request::Base

    HALT_TRANSMIT = :halt_transmit

    # exceptions
    class PlaybackError < StandardError; end

    # fake Net::HTTPResponse
    class FakeNetHttpResponse
      attr_reader :code, :headers, :body

      def initialize(file_path)
        response_hash = ::YAML.load_file(file_path)
        @code = response_hash[:code]
        @headers = response_hash[:headers].inject({}) do |h, (k, v)|
          h[k] = [v]  # expected to be an array
          h
        end
        @body = response_hash[:body]
        unless @code && @headers && @body
          raise PlaybackError, "Invalid response file: #{file_path.inspect}"
        end
      end

      def [](key)
        (headers[key.downcase] || []).first
      end

      def to_hash; headers; end
    end

    # Overrides log_request to interrupt transmit before any connection is made.
    #
    # @raise [Symbol] always throws HALT_TRANSMIT
    def log_request
      super
      throw(HALT_TRANSMIT, HALT_TRANSMIT)
    end

    # Overrides transmit to catch halt thrown by log_request.
    #
    # @param [URI[ uri of some kind
    # @param [Net::HTTP] req of some kind
    # @param [RestClient::Payload] of some kind
    #
    # @return
    def transmit(uri, req, payload, &block)
      caught = catch(HALT_TRANSMIT) { super }
      if caught == HALT_TRANSMIT
        response = fetch_response
        log_response(response)
        process_result(response, &block)
      else
        raise PlaybackError,
              'Unexpected RestClient::Request#transmit returned without calling RestClient::Request#log_request'
      end
    end

    protected

    def fetch_response
      record_metadata = compute_record_metadata
      file_path = response_file_path(record_metadata)

      # TODO update timestamp looking for a 'current' response to provide
      # statefulness.

      if ::File.file?(file_path)
        logger.debug("Played back reponse from #{file_path.inspect}.")
        FakeNetHttpResponse.new(file_path)
      else
        raise PlaybackError, "Unable to locate response: #{file_path.inspect}"
      end
    end

  end # Base
end # RightDevelop::Testing::Client::Rest

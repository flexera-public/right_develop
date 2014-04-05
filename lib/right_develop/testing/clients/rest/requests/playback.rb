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
      attr_reader :code, :body, :elapsed_seconds

      def initialize(file_path)
        response_hash = ::YAML.load_file(file_path)
        @elapsed_seconds = Integer(response_hash[:elapsed_seconds] || 0)
        @code = response_hash[:code].to_s
        @headers = response_hash[:headers].inject({}) do |h, (k, v)|
          h[k] = Array(v)  # expected to be an array
          h
        end
        @body = response_hash[:body]  # optional
        unless @code && @headers
          raise PlaybackError, "Invalid response file: #{file_path.inspect}"
        end
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

    attr_reader :throttle

    def initialize(args)
      if args[:throttle]
        args = args.dup
        @throttle = Integer(args.delete(:throttle))
        if @throttle < 0 || @throttle > 100
          raise ::ArgumentError, 'throttle must be a percentage between 0 and 100'
        end
      else
        @throttle = 0
      end
      super(args)
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

        # delay, if throttled, to simulate server response time.
        if @throttle > 0 && response.elapsed_seconds > 0
          delay = (Float(response.elapsed_seconds) * @throttle) / 100.0
          logger.debug("throttle delay = #{delay}")
          sleep delay
        end
        log_response(response)
        process_result(response, &block)
      else
        raise PlaybackError,
              'Unexpected RestClient::Request#transmit returned without calling RestClient::Request#log_request'
      end
    end

    protected

    def fetch_response
      # response must exist in the current epoch (i.e. can only enter next epoch
      # after a valid response is found).
      record_metadata = compute_record_metadata
      file_path = response_file_path(record_metadata)
      if ::File.file?(file_path)
        logger.debug("Played back response from #{file_path.inspect}.")
        result = FakeNetHttpResponse.new(file_path)
      else
        raise PlaybackError, "Unable to locate response: #{file_path.inspect}"
      end

      # determine if epoch is done, which it is if every known request has been
      # responded to for the current epoch. there is a steady state at the end
      # of time when all responses are given but there is no next epoch.
      dirty = false
      logger.debug("BEGIN playback state = #{state.inspect}")
      unless state[:end_of_time]
        # state usually changes except for a specific case.
        dirty = true

        # list epochs once.
        unless epochs = state[:epochs]
          epochs = []
          ::Dir[::File.join(fixtures_dir, '*')].each do |path|
            if ::File.directory?(path)
              name = ::File.basename(path)
              epochs << Integer(name) if name =~ /^\d+$/
            end
          end
          state[:epochs] = epochs = epochs.sort
        end

        # current epoch must be listed.
        current_epoch = state[:epoch]
        unless index = epochs.index(current_epoch)
          raise PlaybackError,
                "Unable to locate current epoch directory: #{::File.join(fixtures_dir, current_epoch.to_s).inspect}"
        end

        # sorted epochs reveal the future.
        if next_epoch = epochs[index + 1]
          # list all responses in current epoch once.
          unless state[:remaining_responses]
            search_path = response_file_path(relative_response_dir: '**', query_file_name: '*')
            state[:remaining_responses] = ::Dir[search_path]
          end

          # may have been reponded before in same epoch; only care if this is
          # the first time response was used.
          if state[:remaining_responses].delete(file_path)
            if state[:remaining_responses].empty?
              # time marches on.
              state[:epoch] = next_epoch
              state.delete(:remaining_responses)
              logger.debug("A new epoch=#{state[:epoch]} begins due to #{method.to_s.upcase} \"#{record_metadata[:uri]}\"")
            end
          else
            dirty = false
          end
        else
          # the future is now.
          state.delete(:remaining_responses)
          state.delete(:epochs)
          state[:end_of_time] = true
        end

        # state didn't necesessarily change.
        save_state if dirty
      end
      logger.debug("END playback state (dirty = #{dirty}) = #{state.inspect}")
      result
    end

  end # Base
end # RightDevelop::Testing::Client::Rest

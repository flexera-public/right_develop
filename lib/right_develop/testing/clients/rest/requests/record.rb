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

    protected

    def record_response(state, response)
      # never record redirects because a redirect cannot be proxied back to the
      # client (i.e. the client cannot update it's request url when proxied).
      code = response.code
      http_status = Integer(code)
      if http_status >= 300 && http_status < 400
        return true
      end

      # use raw headers instead of the usual RestClient behavior of converting
      # arrays to comma-delimited strings.
      normalized_headers = normalize_headers(response.to_hash)
      normalized_body = normalize_body(normalized_headers, response.body)

      # record elapsed time in (integral) seconds. not intended to be a precise
      # measure of time but rather used to throttle server if client is time-
      # sensitive for some reason.
      elapsed_seconds = @response_timestamp - @request_timestamp
      response_hash = {
        elapsed_seconds: elapsed_seconds,
        code:            Integer(code),
        headers:         normalized_headers,
        body:            normalized_body,
      }

      # detect collision, if any, to determine if we have entered a new epoch.
      record_metadata = compute_record_metadata
      data_key = response_data_key(record_metadata)
      call_count = 0
      next_checksum_value = response_checksum_value(response_hash)
      if response_data = (state[:response_data] ||= {})[data_key]
        last_checksum_value = response_data[:checksum_value]
        if last_checksum_value != next_checksum_value
          state[:epoch] += 100        # leave room to insert custom epochs
          state[:response_data] = {}  # reset checksums for next epoch
          logger.debug("A new epoch=#{state[:epoch]} begins due to #{method.to_s.upcase} \"#{record_metadata[:uri]}\"")
        else
          call_count = response_data[:call_count]
        end
      end
      call_count += 1
      state[:response_data][data_key] = {
        checksum_value: next_checksum_value,
        call_count:     call_count,
      }
      response_hash[:call_count] = call_count

      # write request unless already written.
      file_path = request_file_path(state, record_metadata)
      unless ::File.file?(file_path)
        ::FileUtils.mkdir_p(::File.dirname(file_path))
        ::File.open(file_path, 'w') do |f|
          request_hash = {
            headers: record_metadata[:normalized_headers],
            body:    record_metadata[:normalized_body]
          }
          f.puts(::YAML.dump(request_hash))
        end
      end
      logger.debug("Recorded request at #{file_path.inspect}.")

      # response always written for incremented call count.
      file_path = response_file_path(state, record_metadata)
      ::FileUtils.mkdir_p(::File.dirname(file_path))
      ::File.open(file_path, 'w') do |f|
        f.puts(::YAML.dump(response_hash))
      end
      logger.debug("Recorded response at #{file_path.inspect}.")
      true
    end

    # @return [String] key for quick lookup of responses in current epoch
    def response_data_key(record_metadata)
      ::File.join(
        relative_response_dir(record_metadata),
        record_metadata[:query_file_name])
    end

    # Computes the checksum for response code and body. Response headers are
    # ignored because they represent metadata that can vary for similar
    # responses (DATE, etc.).
    #
    # @param [Hash] response_hash to encode
    #
    # @return [String] encoded code and body
    def response_checksum_value(response_hash)
      "#{response_hash[:code]}-#{checksum(response_hash[:body])}"
    end

  end # Base
end # RightDevelop::Testing::Client::Rest

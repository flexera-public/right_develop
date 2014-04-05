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
      record_response(response)
      result
    end

    protected

    def record_response(response)
      # never record redirects because a redirect cannot be proxied back to the
      # client (i.e. the client cannot update it's request url when proxied).
      code = response.code
      http_status = Integer(code)
      if http_status >= 300 && http_status < 400
        return true
      end

      # use raw headers instead of converting arrays to comma-delimited strings.
      headers = response.to_hash.inject({}) do |r, (k, v)|
        # value is in raw form as array of sequential header values
        r[k.to_s.gsub('-', '_').upcase] = v
        r
      end
      body = response.body

      # record elapsed time in (integral) seconds. not intended to be a precise
      # measure of time but rather used to throttle server if client is time-
      # sensitive for some reason.
      elapsed_seconds = @response_timestamp - @request_timestamp

      # obfuscate any cookies as they won't be needed for playback.
      if cookies = headers['SET_COOKIE']
        headers['SET_COOKIE'] = cookies.map do |cookie|
          if offset = cookie.index('=')
            cookie_name = cookie[0..(offset-1)]
            "#{cookie_name}=#{HIDDEN_CREDENTIAL_VALUE}"
          else
            cookie
          end
        end
      end
      ['CONNECTION', 'STATUS'].each { |key| headers.delete(key) }

      response_hash = {
        elapsed_seconds: elapsed_seconds,
        code:            Integer(code),
        headers:         headers,
        body:            body
      }

      # detect collision, if any, to determine if we have entered a new epoch.
      record_metadata = compute_record_metadata
      checksum_key = response_checksum_key(record_metadata)
      last_checksum_value = (state[:response_checksums] ||= {})[checksum_key]
      next_checksum_value = response_checksum_value(response_hash)
      if last_checksum_value && last_checksum_value != next_checksum_value
        state[:epoch] += 100             # leave room to insert custom epochs
        state[:response_checksums] = {}  # reset checksums for next epoch
        logger.debug("A new epoch=#{state[:epoch]} begins due to #{method.to_s.upcase} \"#{record_metadata[:uri]}\"")
      end
      state[:response_checksums][checksum_key] = next_checksum_value

      # request
      request_file_path = request_file_path(record_metadata)
      ::FileUtils.mkdir_p(::File.dirname(request_file_path))
      ::File.open(request_file_path, 'w') do |f|
        f.write(record_metadata[:normalized_body])
      end
      logger.debug("Recorded request at #{request_file_path.inspect}.")

      # response
      response_file_path = response_file_path(record_metadata)
      ::FileUtils.mkdir_p(::File.dirname(response_file_path))
      ::File.open(response_file_path, 'w') do |f|
        f.puts(::YAML.dump(response_hash))
      end

      # persist state for every successful recording.
      save_state
      logger.debug("Recorded response at #{response_file_path.inspect}.")
      true
    end

    # @return [String] key for quick lookup of responses in current epoch
    def response_checksum_key(record_metadata)
      ::File.join(
        record_metadata[:relative_response_dir],
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

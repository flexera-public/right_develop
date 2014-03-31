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
      result = super(response)
      record_response(response)
      result
    end

    protected

    def record_response(response)
      code = response.code
      headers = response.to_hash.inject({}) do |r, (k, v)|
        # value is in raw form as array of sequential header values
        r[k.to_s.gsub('-', '_').upcase] = v
        r
      end
      #response.each_key { |k| headers[k.to_s.gsub('-', '_').upcase] = response[k] }
      body = response.body

      # obfuscate any cookies as they won't be needed for playback.
      if cookies = headers['SET_COOKIE']
        headers['SET_COOKIE'] = cookies.map do |cookie|
          if offset = cookie.index('=')
            cookie_name = cookie[0..(offset-1)]
            "#{cookie_name}=hidden_credential"
          else
            cookie
          end
        end
      end
      ['CONNECTION', 'STATUS'].each { |key| headers.delete(key) }

      response_hash = {
        code:    code,
        headers: headers,
        body:    body
      }

      # TODO update timestamp whenever a recording collision is detected to
      # provide statefulness. until then, it's clobberin' time!

      # request
      record_metadata = compute_record_metadata
      file_path = request_file_path(record_metadata)
      ::FileUtils.mkdir_p(::File.dirname(file_path))
      ::File.open(file_path, 'w') do |f|
        f.write(record_metadata[:normalized_body])
      end
      logger.debug("Recorded request at #{file_path.inspect}.")

      # response
      file_path = response_file_path(record_metadata)
      ::FileUtils.mkdir_p(::File.dirname(file_path))
      ::File.open(file_path, 'w') do |f|
        f.puts(::YAML.dump(response_hash))
      end
      logger.debug("Recorded response at #{file_path.inspect}.")
      true
    end

  end # Base
end # RightDevelop::Testing::Client::Rest

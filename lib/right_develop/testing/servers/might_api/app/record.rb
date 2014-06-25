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

module RightDevelop::Testing::Server::MightApi::App
  class Record < ::RightDevelop::Testing::Server::MightApi::App::Base

    STATE_FILE_NAME = 'record_state.yml'

    # @see RightDevelop::Testing::Server::MightApi::App::Base#initialize
    def initialize(options = {})
      options = { state_file_name: STATE_FILE_NAME }.merge(options)
      super(options)
      fail "Unexpected mode: #{config.mode}" unless config.mode == :record
    end

    # @see RightDevelop::Testing::Server::MightApi::App::Base#handle_request
    def handle_request(env, verb, uri, headers, body)
      proxy(
        ::RightDevelop::Testing::Client::Rest::Request::Record,
        verb,
        uri,
        headers,
        body)
    end

  end
end

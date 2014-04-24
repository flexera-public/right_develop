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

require ::File.expand_path('../base', __FILE__)

require 'right_support'

module RightDevelop::Testing::Server::MightApi::App

  # Implements an echo service.
  class Echo < ::RightDevelop::Testing::Server::MightApi::App::Base

    # metadata
    METADATA_CLASS = ::RightDevelop::Testing::Recording::Metadata

    def initialize
      super(nil)
    end

    # @see RightDevelop::Testing::Server::MightApi::App::Base#handle_request
    def handle_request(verb, uri, headers, body)

      # check routes.
      response = ::Rack::Response.new
      if route = find_route
        response.write "URL matched #{route.last[:name].inspect}\n"
      else
        response.write "Failed to match any route. The following routes are valid:\n"
        config.routes.keys.each do |prefix|
          response.write "Prefix = #{prefix.inspect}\n\n"
        end
      end

      # echo request back as response.
      response.write "\nruby %sp%s\n\n" % [RUBY_VERSION, RUBY_PATCHLEVEL]
      response.write "Raw configuration = #{::JSON.pretty_generate(config.to_hash)}\n\n"  # hash order is significant in config
      config.routes.each do |route_path, route_config|
        response.write "=== Compiled route matchers begin for root = #{route_path.inspect}:\nmatchers = {\n"
        (route_config[METADATA_CLASS::MATCHERS_KEY] || {}).each do |regex, route_data|
          response.write "  #{regex.inspect} =>\n    #{route_data.inspect},\n"
        end
        response.write "}\n=== Compiled route matchers end.\n\n"
      end
      response.write "env = #{::RightSupport::Data::HashTools.deep_sorted_json(env, true)}\n\n"
      response.write "ENV = #{::RightSupport::Data::HashTools.deep_sorted_json(::ENV, true)}\n\n"
      response.write "verb = #{verb.inspect}\n\n"
      response.write "uri = #{uri}\n\n"
      response.write "headers = #{::RightSupport::Data::HashTools.deep_sorted_json(headers, true)}\n\n"
      response.write "body = #{body.inspect}\n\n"
      response.finish
    end

  end
end
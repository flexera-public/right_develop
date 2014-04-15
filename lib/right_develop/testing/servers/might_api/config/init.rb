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

# fixup RACK_ENV
require 'right_develop'

require ::File.expand_path('../../lib/config', __FILE__)
require ::File.expand_path('../../lib/logger', __FILE__)

module RightDevelop::Testing::Server::MightApi

  # attempt to read stdin for configuration or else expect relative file path.
  # note the following .fcntl call returns zero when data is available on $stdin
  config_yaml = ($stdin.tty? || 0 != $stdin.fcntl(::Fcntl::F_GETFL, 0)) ? '' : $stdin.read
  config_hash = config_yaml.empty? ? nil : ::YAML.load(config_yaml)
  Config.setup(config_hash)

  # ready.
  logger.info("MightApi initialized in #{Config.mode} mode.")
end

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

require 'logger'
require 'right_support'

module RightDevelop::Testing::Servers::MightApi

  def self.logger
    @logger ||= lambda do
      l = nil
      case Config.environment
      when 'development'
        log_dir = ::File.join(Config.root_dir, 'log')
        log_file_path = ::File.join(log_dir, 'development.log')
        ::FileUtils.mkdir_p(log_dir)
        file_logger = ::Logger.new(log_file_path)
        STDOUT.sync = true
        console_logger = ::Logger.new(STDOUT)
        l = ::RightSupport::Log::Multiplexer.new(file_logger, console_logger)
      when 'test'
        # any tests should mock logger to verify output.
        l = ::RightSupport::Log::NullLogger.new
      else
        l = ::RightSupport::Log::SystemLogger.new('might_api', facility: 'local0')
      end
      l.formatter = DateTimeLoggerFormatter.new
      l.level = Config.log_level
      l
    end.call
  end

  class DateTimeLoggerFormatter < ::Logger::Formatter
    def call(severity, time, progname, msg)
      sprintf("%s: %s\n", ::Time.now, msg2str(msg))
    end
  end
end

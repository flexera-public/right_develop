#
# Copyright (c) 2009-2011 RightScale Inc
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

# Cucumber naïvely requires JUST this file without necessarily requiring
# RightDevelop's main file. Make up for Cucumber's shortcomings.

# Cucumber sometimes avoids loading us; not sure why!
require 'right_develop'

require 'cucumber'
require 'cucumber/formatter/junit'

module RightDevelop::CI
  class JavaCucumberFormatter < Cucumber::Formatter::Junit
    private

    def build_testcase(duration, status, exception = nil, suffix = "")
      @time += duration
      # Use "cucumber" as a pseudo-package, and the feature name as a pseudo-class
      classname = "cucumber.#{RightDevelop::CI::Util.pseudo_java_class_name(@feature_name)}"
      name = "#{@scenario}#{suffix}"
      pending = [:pending, :undefined].include?(status)
      passed = (status == :passed || (pending && !@options[:strict]))

      @builder.testcase(:classname => classname, :name => name, :time => "%.6f" % duration) do
        unless passed
          @builder.failure(:message => "#{status.to_s} #{name}", :type => status.to_s) do
            @builder.cdata! @output
            @builder.cdata!(format_exception(exception)) if exception
          end
          @failures += 1
        end
        if passed and (status == :skipped || pending)
          @builder.skipped
          @skipped += 1
        end
      end
      @tests += 1
    end
  end
end

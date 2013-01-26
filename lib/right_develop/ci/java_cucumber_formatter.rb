# Copyright (c) 2012- RightScale, Inc, All Rights Reserved Worldwide.
#
# THIS PROGRAM IS CONFIDENTIAL AND PROPRIETARY TO RIGHTSCALE
# AND CONSTITUTES A VALUABLE TRADE SECRET.  Any unauthorized use,
# reproduction, modification, or disclosure of this program is
# strictly prohibited.  Any use of this program by an authorized
# licensee is strictly subject to the terms and conditions,
# including confidentiality obligations, set forth in the applicable
# License Agreement between RightScale.com, Inc. and the licensee.

# Cucumber naïvely requires JUST this file without necessarily requiring
# RightDevelop's main file. Make up for Cucumber's shortcomings.

# Cucumber sometimes avoids loading us; not sure why!
require 'right_develop'

require 'cucumber'

module RightDevelop::CI
  class JavaCucumberFormatter < Cucumber::Formatter::Junit
    private

    def build_testcase(duration, status, exception = nil, suffix = "")
      @time += duration
      # Use "cucumber" as a pseudo-package, and the feature name as a pseudo-class
      classname = "cucumber.#{@feature_name}"
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

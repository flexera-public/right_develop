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


['cucumber', 'cucumber/formatter/junit', 'cucumber/formatter/progress'].each do |f|
  begin
    require f
  rescue LoadError
    # no-op, we will raise later
  end
end

module RightDevelop::CI
  if defined?(Cucumber)
    class JavaCucumberFormatter < Cucumber::Formatter::Junit
      def initialize(runtime, io, options)
        super

        @progress = Cucumber::Formatter::Progress.new(runtime, STDOUT, options)
      end

      def before_features(features)
        @progress.before_features(features) if @progress.respond_to?(:before_features)
      end

      def after_features(features)
        @progress.after_features(features) if @progress.respond_to?(:after_features)
      end

      def before_feature_element(*args)
        @progress.before_feature_element(*args) if @progress.respond_to?(:before_feature_element)
        super
      end

      def after_feature_element(*args)
        @progress.after_feature_element(*args) if @progress.respond_to?(:after_feature_element)
      end

      def before_steps(*args)
        @progress.before_steps(*args) if @progress.respond_to?(:before_steps)
        super
      end

      def after_steps(*args)
        @progress.after_steps(*args)if @progress.respond_to?(:after_steps)
        super
      end

      def after_step_result(*args)
        @progress.after_step_result(*args) if @progress.respond_to?(:after_step_result)
      end

      def exception(*args)
        @progress.exception(*args) if @progress.respond_to?(:exception)
      end

      private

      def build_testcase(duration, status, exception = nil, suffix = "")
        @time += duration
        # Use "cucumber" as a pseudo-package, and the feature name as a pseudo-class
        classname = "cucumber.#{RightDevelop::CI::Util.pseudo_java_class_name(@feature_name)}"
        name = "#{@scenario}#{suffix}"
        pending = [:pending, :undefined].include?(status)
        passed = (status == :passed || (pending && !@options[:strict]))

        @builder.testcase(:classname => classname.to_sym, :name => name, :time => "%.6f" % duration) do
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
  else
    JavaCucumberFormatter = Object
  end
end

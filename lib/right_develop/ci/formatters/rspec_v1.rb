module RightDevelop::CI::Formatters
  # JUnit XML output formatter for RSpec 1.x
  class RSpecV1 < Spec::Runner::Formatter::BaseTextFormatter
    def initialize(*args)
      super(*args)
      @current_example_group = nil
      @test_times = {}
      @test_groups = {}
      @test_results = {}
      @test_failures = {}
    end

    def example_group_started(example)
      @current_example_group = example
    end

    def example_started(example)
      @test_groups[example] ||= @current_example_group
      @example_started_at = Time.now
    end

    def example_passed(example)
      @test_groups[example] ||= @current_example_group
      @test_times[example] = Time.now - @example_started_at
      @test_results[example] = 'passed'
    end

    def example_failed(example, counter, failure)
      @test_groups[example] ||= @current_example_group
      @test_times[example] = Time.now - @example_started_at
      @test_results[example] = 'failed'
      @test_failures[example] = failure
    end

    def example_pending(example, message, deprecated_pending_location=nil)
      @test_groups[example] ||= @current_example_group
      @test_times[example] = Time.now - @example_started_at
      @test_results[example] = 'pending'
    end

    def dump_summary(duration, example_count, failure_count, pending_count)
      builder = Builder::XmlMarkup.new :indent => 2
      builder.instruct! :xml, :version => "1.0", :encoding => "UTF-8"
      builder.testsuite :errors => 0, :failures => failure_count, :skipped => pending_count, :tests => example_count, :time => duration, :timestamp => Time.now.iso8601 do
        builder.properties
        @test_results.each_pair do |test, result|
          classname        = purify(classname_for(test))
          full_description = purify(test.description)

          # The full description always begins with the classname, but this is useless info when
          # generating the XML report.
          if full_description.start_with?(classname)
            full_description = full_description[classname.length..-1].strip
          end

          builder.testcase(:classname => classname.to_sym, :name => full_description, :time => @test_times[test]) do
            case result
            when "failed"
              builder.failure :message => "failed #{full_description}", :type => "failed" do
                builder.cdata! purify(failure_details_for(test))
              end
            when "pending" then
              builder.skipped
            end
          end
        end
      end
      output.puts builder.target!
    end

    def dump_failure(counter, failure)
      # no-op; our summary contains everything
    end

    def dump_pending()
      # no-op; our summary contains everything
    end

    private

    def failure_details_for(example)
      exception = @test_failures[example].exception
      exception.nil? ? "" : "#{exception.message}\n#{format_backtrace(exception.backtrace)}"
    end

    def classname_for(example)
      # Take our best guess, by looking at the description of the example group
      # and assuming the first word is a class name
      group = @test_groups[example]
      klass = group.description.split(/\s+/).first
      klass = RightDevelop::CI::Util.pseudo_java_class_name(klass)
      "rspec.#{klass}"
    end

    def purify(untrusted)
      RightDevelop::CI::Util.purify(untrusted)
    end
  end
end
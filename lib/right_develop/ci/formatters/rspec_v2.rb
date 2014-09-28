require 'rspec/core/formatters/progress_formatter'

# Hack: enable colour output to non-TTY
module RSpec
  module Core
    class Configuration
      def output_to_tty?(*args)
        true
      end
    end
  end
end

module RightDevelop::CI::Formatters
  # JUnit XML output formatter for RSpec 2.x
  class RSpecV2 < RSpec::Core::Formatters::BaseFormatter
    def initialize(*args)
      super(*args)
      @test_results = []
      @progress = RSpec::Core::Formatters::ProgressFormatter.new(STDOUT)
      @summary = RSpec::Core::Formatters::BaseTextFormatter.new(STDOUT)
      @failures = 0
    end

    def example_passed(example)
      @test_results << example

      @progress.example_passed(example)
      @summary.example_passed(example)
    end

    def example_failed(example)
      @test_results << example

      @progress.example_failed(example)
      @summary.example_failed(example)

      puts
      failures = @failures
      @summary.instance_eval { dump_failure(example, failures) }
      @failures += 1
    end

    def example_pending(example)
      @test_results << example

      @progress.example_pending(example)
      @summary.example_pending(example)
    end

    def dump_summary(duration, example_count, failure_count, pending_count)
      builder = Builder::XmlMarkup.new :indent => 2
      builder.instruct! :xml, :version => "1.0", :encoding => "UTF-8"
      builder.testsuite :errors => 0, :failures => failure_count, :skipped => pending_count, :tests => example_count, :time => duration, :timestamp => Time.now.iso8601 do
        builder.properties
        @test_results.each do |test|
          classname        = purify(classname_for(test))
          full_description = purify(test.full_description)
          time             = test.metadata[:execution_result][:run_time]

          # The full description always begins with the classname, but this is useless info when
          # generating the XML report.
          if full_description.start_with?(classname)
            full_description = full_description[classname.length..-1].strip
          end

          builder.testcase(:classname => classname.to_sym, :name => full_description, :time => time) do
            case test.metadata[:execution_result][:status]
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

      puts
      @summary.dump_summary(duration, example_count, failure_count, pending_count)
    end

    def dump_pending
      @summary.dump_pending if @failures == 0
    end

    protected

    def failure_details_for(example)
      exception = example.exception
      exception.nil? ? "" : "#{exception.message}\n#{format_backtrace(exception.backtrace, example).join("\n")}"
    end

    def classname_for(example)
      klass = example.example_group.top_level_description || example.example_group.described_class
      klass = RightDevelop::CI::Util.pseudo_java_class_name(klass.to_s)
      "rspec.#{klass}"
    end

    def purify(untrusted)
      RightDevelop::CI::Util.purify(untrusted)
    end
  end
end
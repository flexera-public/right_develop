require 'rspec/core/formatters/progress_formatter'
require 'rspec/core/formatters/base_text_formatter'

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
  # JUnit XML output formatter for RSpec 3.x
  class RSpecV3 < RSpec::Core::Formatters::BaseFormatter
    RSpec::Core::Formatters.register self,
      :start, :example_group_started, :start_dump,
      :example_started, :example_passed, :example_failed,
      :example_pending, :dump_summary, :dump_pending

    def initialize(output)
      super(output)
      @failed_examples = []
      @example_group_number = 0
      @example_number = 0
      @test_results = []
      @progress = RSpec::Core::Formatters::ProgressFormatter.new(STDOUT)
      @summary = RSpec::Core::Formatters::BaseTextFormatter.new(STDOUT)
      @failures = 0
    end

    def start(notification)

    end

    def example_group_started(notification)

    end

    def start_dump(notification)

    end

    def example_started(notification)

    end

    def example_passed(passed)
      @test_results << passed

      @progress.example_passed(passed)
    end

    def example_failed(failed)
      @test_results << failed

      @progress.example_failed(failed)

      puts
      failures = @failures
      puts failed.fully_formatted(failures)
      @failures += 1
    end

    def example_pending(pending)
      @test_results << pending

      @progress.example_pending(pending)
    end

    def dump_summary(summary)
      builder = Builder::XmlMarkup.new :indent => 2
      builder.instruct! :xml, :version => "1.0", :encoding => "UTF-8"
      builder.testsuite :errors => 0,
                        :failures => summary.failure_count,
                        :skipped => summary.pending_count,
                        :tests => summary.example_count,
                        :time => summary.duration,
                        :timestamp => Time.now.iso8601 do
        builder.properties
        @test_results.each do |test|
          classname        = purify(classname_for(test.example))
          full_description = purify(test.example.full_description)
          time             = test.example.metadata[:execution_result][:run_time]

          # The full description always begins with the classname, but this is useless info when
          # generating the XML report.
          if full_description.start_with?(classname)
            full_description = full_description[classname.length..-1].strip
          end

          builder.testcase(:classname => classname.to_sym, :name => full_description, :time => time) do
            case test.example.metadata[:execution_result][:status]
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
      @summary.dump_summary(summary)
    end

    def dump_pending(summary)
      @summary.dump_pending(summary) if @failures == 0
    end

    protected

    def failure_details_for(failure)
      example   = failure.example
      exception = failure.example.exception
      formatter = RSpec.configuration.backtrace_formatter
      backtrace = formatter.format_backtrace(exception.backtrace, example.metadata)
      exception.nil? ? "" : "#{exception.message}\n#{backtrace.join("\n")}"
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
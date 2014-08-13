module RightDevelop::CI::Formatters
  # JUnit XML output formatter for RSpec 3.x
  class RSpecV3 < RSpec::Core::Formatters::BaseFormatter
    RSpec::Core::Formatters.register self,
      :start, :example_group_started, :start_dump,
      :example_started, :example_passed, :example_failed,
      :example_pending, :dump_summary

    def initialize(output)
      super(output)
      @failed_examples = []
      @example_group_number = 0
      @example_number = 0

      @test_results = []
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
    end

    def example_failed(failure)
      @test_results << failure
    end

    def example_pending(pending)
      @test_results << pending
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
    end

    protected

    def failure_details_for(failure)
      exception = failure.example.exception
      exception.nil? ? "" : "#{exception.message}\n#{failure.formatted_backtrace.join("\n")}"
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
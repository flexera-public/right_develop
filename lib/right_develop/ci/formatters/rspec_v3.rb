module RightDevelop::CI::Formatters
  # JUnit XML output formatter for RSpec 3.x
  class RSpecV3 < RSpec::Core::Formatters::BaseFormatter
    def initialize(*args)
      raise NotImplementedError, "Tony is lazy"
    end
  end
end
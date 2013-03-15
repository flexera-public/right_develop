module RightDevelop
  module Git
    # A Git command failed unexpectedly.
    class CommandError < StandardError
      attr_reader :output

      def initialize(message)
        @output = message
        lines = message.split("\n").map { |l| l.strip }.reject { |l| l.empty? }
        super(lines.last || @output)
      end
    end

    # A Git command's output did not match with expected output.
    class FormatError < StandardError; end
  end

  require "right_develop/git/branch"
  require "right_develop/git/branch_collection"
  require "right_develop/git/commit"
  require "right_develop/git/repository"
end
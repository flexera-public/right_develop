module RightDevelop::Git
  # A commit within a Git repository.
  class Commit
    COMMIT_INFO     = /([0-9A-Fa-f]+) ([0-9]+) (.*)/

    def initialize(repo, line)
      @repo = repo
      match = COMMIT_INFO.match(line)
      raise FormatError, "Unrecognized commit summary '#{line}'" unless match && match.length >= 3
      @info = [ match[1], match[2], match[3] ]
    end

    def to_s
      @info.join(' ')
    end

    def hash
      # This overrides String#hash on purpose
      @info[0]
    end

    def timestamp
      Time.at(@info[1].to_i)
    end

    def author
      @info[2]
    end
  end
end
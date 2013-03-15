module RightDevelop::Git
  # A branch in a Git repository. Has some proxy methods that make it act a bit like
  # a string, whose value is the name of the branch. This allows branches to be sorted,
  # matched against Regexp, and certain other string-y operations.
  class Branch
    BRANCH_NAME     = '[#A-Za-z0-9._\/-]+'
    BRANCH_INFO     = /(\* |  )?(#{BRANCH_NAME})( -> )?(#{BRANCH_NAME})?/
    BRANCH_FULLNAME = /(remotes\/)?(#{BRANCH_NAME})/

    def initialize(repo, line)
      match = BRANCH_INFO.match(line)
      if match && (fullname = match[2])
        match = BRANCH_FULLNAME.match(fullname)
        if match
          @fullname = match[2]
          @remote = !!match[1]
          @repo = repo
        else
          raise FormatError, "Unrecognized branch name '#{line}'"
        end
      else
        raise FormatError, "Unrecognized branch info '#{line}'"
      end
    end

    def to_s
      @fullname
    end
    alias inspect to_s

    def =~(other)
      @fullname =~ other
    end

    def ==(other)
      self.to_s == other.to_s
    end

    def <=>(other)
      self.to_s <=> other.to_s
    end

    def remote?
      @remote
    end

    def name
      if remote?
        #remove the initial remote-name in the branch (origin/master --> master)
        bits = @fullname.split('/')
        bits.shift
        bits.join('/')
      else
        @fullname
      end
    end

    def display(width=40)
      if @fullname.length >= width
        (@fullname[0..(width-5)] + "...").ljust(width)
      else
        @fullname.ljust(width)
      end
    end

    def delete
      if self.remote?
        @repo.shell("git push origin :#{self.name}")
      else
        @repo.shell("git branch -D #{@fullname}")
      end
    end
  end
end
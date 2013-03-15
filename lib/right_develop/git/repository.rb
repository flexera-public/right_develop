module RightDevelop::Git
  # An entire Git repository. Mostly acts as a factory for Branch,
  # BranchCollection and Commit objects.
  class Repository
    DEFAULT_LOG_OPTIONS = {
      :tail=>1_000
    }

    def initialize(dir)
      @dir = dir
    end

    def fetch
      shell('git fetch -q')
    end

    def branches()
      lines = shell('git branch -a')
      branches = BranchCollection.new(self)
      lines.each do |line|
        branch = Branch.new(self, line)
        branches << branch if branch
      end
      branches
    end

    def log(branch_spec='master', options={})
      options = DEFAULT_LOG_OPTIONS.merge(options)

      args = [
        "-n#{options[:tail]}",
        "--format='%h %at %aE'"
      ]
      if options[:no_merges]
        args << "--no-merges"
      end

      lines = shell("git log #{args.join(' ')} #{branch_spec}")
      lines.map do |line|
        Commit.new(self, line)
      end.compact
    end

    def shell(cmd, *args)
      Dir.chdir(@dir) do

        full_cmd="#{cmd} #{args.join ' '}"
        output = `#{full_cmd}`
        if $?.success?
          return output.split("\n").map { |l| l.strip }
        else
          raise CommandError, "#{full_cmd} --> #{output}"
        end
      end
    end
  end
end
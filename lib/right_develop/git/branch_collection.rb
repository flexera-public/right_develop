module RightDevelop::Git
  # A collection of Git branches. Acts a bit like an Array, allowing it to be mapped,
  # sorted and compared as such.
  class BranchCollection
    def initialize(repo, *args)
      @repo = repo
      @branches = args
    end

    def to_s
      @branches.inspect
    end
    alias inspect to_s

    def local
      local = BranchCollection.new(@repo)
      @branches.each do |branch|
        local << branch unless branch.remote?
      end
      local
    end

    def remote
      remote = BranchCollection.new(@repo)
      @branches.each do |branch|
        remote << branch if branch.remote?
      end
      remote
    end

    def merged(target)
      merged = BranchCollection.new(@repo)

      all_merged = shell("git branch -r --merged #{target}").map do |line|
        Branch.new(@repo, line)
      end

      @branches.each do |candidate|
        # For some reason Set#include? does not play nice with our overridden comparison operators
        # for branches, so we need to do this the hard way :(
        merged << candidate if all_merged.detect { |b| candidate == b }
      end

      merged
    end

    # Accessor that acts like either a Hash or Array accessor
    def [](argument)
      case argument
      when String
        target = Branch.new(@repo, argument)
        @branches.detect { |b| b == target }
      else
        @branches.__send__(:[], argument)
      end
    end

    def method_missing(meth, *args, &block)
      result = @branches.__send__(meth, *args, &block)

      if result.is_a?(Array)
        BranchCollection.new(@repo, *result)
      else
        result
      end
    end

    def shell(cmd, *args)
      @repo.shell(cmd, *args)
    end
  end
end
require "action_view"

module RightDevelop::Commands
  class Git
    include ActionView::Helpers::DateHelper

    NAME_SPLIT_CHARS = /-|_|\//
    YES              = /(ye?s?)/i
    NO               = /(no?)/i

    DEFAULT_OPTIONS  = {
      :except=>"release|v?[0-9.]+"
    }

    TASKS = %w(prune)

    # Parse command-line options and create a Command object
    def self.create
      task_list = TASKS.map { |c| "       * #{c}" }.join("\n")

      options = Trollop.options do
        banner <<-EOS
The 'git' command automates various repository management tasks. All tasks
accept the same options, although not every option applies to every command.

Usage:
       right_develop git <task> [options]

Where <task> is one of:
#{task_list}
EOS
        opt :age, "Minimum age to consider", :default => '3.months.ago'
        opt :only, "Limit to branches matching this prefix", :type=>:string
        opt :except, "Ignore branches matching this prefix", :type=>:string
        opt :local, "Limit to local branches"
        opt :remote, "Limit to remote branches"
        opt :merged, "Limit to branches that are fully merged into the named branch", :type=>:string
        stop_on TASKS
      end

      options = DEFAULT_OPTIONS.merge(options)
      task = ARGV.shift

      case task
      when "prune"
        git = RightDevelop::Git::Repository.new(Dir.pwd)
        self.new(git, :prune, options)
      else
        Trollop.die "unknown task #{task}"
      end

    end

    def initialize(repo, subcommand, options)
      @git        = repo
      @subcommand = subcommand
      @options    = options

      # Post-process the "age" option
      max_age = options[:age]
      if max_age =~ /^[0-9]+\.?(hours|days|weeks|months|years)?\.?(ago)?$/
        max_age = eval(options[:age])
      elsif max_age =~ /^[0-9]+$/
        max_age = max_age.to_i.months.ago
      else
        raise ArgumentError, "Can't parse max_age of '#{max_age}'"
      end
      @max_age = max_age
    end

    # Run this command.
    def run
      case @subcommand
      when :prune
        prune(@options)
      else
        raise StateError, "Invalid @subcommand; check Git.create!"
      end
    end

    protected

    # Prune dead branches from the repository.
    #
    # @param [Time] max_age Ignore any branch with commits more recently than this timestamp.
    # @param [Hash] options
    # @option options [Regexp] :except Ignore branches matching this pattern
    # @option options [Regexp] :only Consider only branches matching this pattern
    # @option options [true|false] :local Consider local branches
    # @option options [true|false] :remote Consider remote branches
    # @option options [String] :merged Consider only branches that are fully merged into this branch (e.g. master)
    def prune(options={})
      branches = @git.branches

      #Filter by name prefix
      except   = Regexp.new("^(origin/)?(#{Regexp.escape(options[:except])})") if options[:except]
      only     = Regexp.new("^(origin/)?(#{Regexp.escape(options[:only])})") if options[:only]
      branches = branches.select { |x| x =~ only } if only
      branches = branches.reject { |x| x =~ except } if except

      #Filter by location (local/remote)
      if options[:local] && !options[:remote]
        branches = branches.local
      elsif options[:remote] && !options[:local]
        branches = branches.remote
      elsif options[:remote] && options[:local]
        raise ArgumentError, "Cannot specify both --local and --remote!"
      end

      #Filter by merge status
      if options[:merged]
        branches = branches.merged(options[:merged])
      end

      old = {}
      branches.each do |branch|
        next if except && (except === branch)

        latest = @git.log(branch, :tail=>1).first
        timestamp = latest.timestamp
        if timestamp < @max_age &&
          old[branch] = timestamp
        end
      end

      if old.empty?
        STDERR.puts "No branches older than #{time_ago_in_words(max_age)} found; do you need to specify --remote?"
        exit -2
      end

      all_by_prefix = branches.group_by { |b| b.name.split(NAME_SPLIT_CHARS).first }

      all_by_prefix.each_pair do |prefix, branches|
        old_in_group = branches.select { |b| old.key?(b) }
        next if old_in_group.empty?
        old_in_group = old_in_group.sort { |a, b| old[a] <=> old[b] }
        puts prefix
        puts '-' * prefix.length
        old_in_group.each do |b|
          puts "\t" + b.display(40) + "\t" + time_ago_in_words(old[b])
        end
        puts
      end

      unless options[:force]
        return unless prompt("Delete all #{old.size} branches above?", true)
      end

      old.each do |branch, timestamp|
        branch.delete
      end
    end

    private

    def prompt(p, yes_no=false)
      puts #newline for newline's sake!

      loop do
        print p, ' '
        line = STDIN.readline.strip
        if yes_no
          return true if line =~ YES
          return false if line =~ NO
        else
          return line
        end
      end
    end
  end
end
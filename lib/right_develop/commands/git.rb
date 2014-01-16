#
# Copyright (c) 2013 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'set'
require 'uri'

require 'right_git'
require 'right_support'

require 'right_develop'

module RightDevelop::Commands
  class Git
    include RightSupport::Log::Mixin

    NAME_SPLIT_CHARS = /-|_|\//
    YES              = /(ye?s?)/i
    NO               = /(no?)/i
    TASKS            = %w(prune tickets)
    MERGE_COMMENT    = /^Merge (?:remote[- ])?(?:tracking )?(?:branch|pull request #[0-9]+ from) ['"]?(.*)['"]?$/i
    WORD_BOUNDARY    = %r{[_ /-]+}

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

And [options] are selected from:
        EOS
        opt :age, "Minimum age to consider",
            :default => "3.months"
        opt :only, "Limit to branches matching this prefix",
            :type => :string
        opt :except, "Ignore branches matching this prefix",
            :type    => :string,
            :default => "(release|ve?r?)?[0-9.]+"
        opt :local, "Limit to local branches"
        opt :remote, "Limit to remote branches"
        opt :merged, "Limit to branches that are merged into this branch",
            :type    => :string,
            :default => "master"
        opt :since, "Base branch or tag to compare against for determining 'new' commits",
            :default => "origin/master"
        opt :link, "Word prefix indicating a link to an external ticketing system",
            :default => "(?:[#A-Za-z]+)([0-9]+)$"
        opt :link_to, "URL pattern to generate ticket links, don't forget trailing slash!",
            :type => :string
        opt :debug, "Enable verbose debug output",
            :default => false
      end

      task = ARGV.shift

      repo = ::RightGit::Git::Repository.new(
        ::Dir.pwd,
        ::RightDevelop::Utility::Git::DEFAULT_REPO_OPTIONS)

      case task
      when "prune"
        self.new(repo, :prune, options)
      when "tickets"
        self.new(repo, :tickets, options)
      else
        Trollop.die "unknown task #{task}"
      end
    end

    # @param [RightGit::Git::Repository] repo the Git repository to operate on
    # @param [Symbol] task one of :prune or :tickets
    # @option options [String] :age Ignore branches newer than this time-ago-in-words e.g. "3 months"; default unit is months
    # @option options [String] :except Ignore branches matching this regular expression
    # @option options [String] :only Consider only branches matching this regular expression
    # @option options [Boolean] :local Consider only local branches
    # @option options [Boolean] :remote Consider only remote branches
    # @option options [String] :merged Consider only branches that are fully merged into this branch (e.g. master)
    # @option options [String] :since the name of a "base branch" representing the previous release
    # @option options [String] :link word prefix connoting a link to an external ticketing system
    # @option options [String] :link_to URL prefix to use when generating ticket links
    def initialize(repo, task, options)
      logger                                  = Logger.new(STDERR)
      logger.level                            = options[:debug] ? Logger::DEBUG : Logger::WARN
      RightSupport::Log::Mixin.default_logger = logger

      # Post-process "age" option; transform from natural-language expression into a timestamp.
      if (age = options.delete(:age))
        age           = parse_age(age)
        options[:age] = age
      end

      # Post-process "except" option; transform into a Regexp.
      if (except = options.delete(:except))
        except           = Regexp.new("^(origin/)?(#{except})")
        options[:except] = except
      end

      # Post-process "only" option; transform into a Regexp.
      if (only = options.delete(:only))
        only           = Regexp.new("^(origin/)?(#{only})")
        options[:only] = only
      end

      # Post-process "since" option; transform into a Regexp.
      if (link = options.delete(:link))
        link           = Regexp.new("^#{link}")
        options[:link] = link
      end

      @git     = repo
      @task    = task
      @options = options
    end

    # Run the task that was specified when this object was instantiated. This
    # method does no work; it just delegates to a task method.
    def run
      case @task
      when :prune
        prune(@options)
      when :tickets
        tickets(@options)
      else
        raise StateError, "Invalid @task; check Git.create!"
      end
    end

    protected

    # Prune dead branches from the repository.
    #
    # @option options [Time] :age Ignore branches whose HEAD commit is newer than this timestamp
    # @option options [Regexp] :except Ignore branches matching this pattern
    # @option options [Regexp] :only Consider only branches matching this pattern
    # @option options [Boolean] :local Consider only local branches
    # @option options [Boolean] :remote Consider only remote branches
    # @option options [String] :merged Consider only branches that are fully merged into this branch (e.g. master)
    def prune(options={})
      puts describe_prune(options)

      puts "Fetching latest branches and tags from remotes"
      @git.fetch_all(:prune => true)

      branches = @git.branches(:all => true)

      #Filter by name prefix
      branches = branches.select { |x| x =~ options[:only] } if options[:only]
      branches = branches.reject { |x| x =~ options[:except] } if options[:except]

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
        puts "Checking merge status of #{branches.size} branches; please be patient"
        branches = branches.merged(options[:merged])
      end

      old = {}
      branches.each do |branch|
        latest    = @git.log(branch, :tail => 1).first
        timestamp = latest.timestamp
        if timestamp < options[:age] &&
          old[branch] = timestamp
        end
      end

      if old.empty?
        STDERR.puts "No branches found; try different options"
        exit -2
      end

      puts

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
        puts "  deleted #{branch}"
      end
    end

    # Produce a report of all the tickets that have been merged into the named branch. This works
    # by scanning merge commit comments, recognizing words that look like a ticket reference, and
    # extracting a matched segment as the ticket ID. The user must specify a matching Regexp using
    # the :link option.
    #
    # @example Match Acunote stories
    #   git.tickets(:link=>/acu([0-9]+)/)
    #
    # @option options [String] :since the name of a "base branch" representing the previous release
    # @option options [Regexp] :merged the name of a branch (e.g. master) representing the next release
    # @option options [Regexp] :link a word prefix that connotes links to an external ticketing system
    # @option options [Boolean] :local Consider only local branches
    # @option options [Boolean] :remote Consider only remote branches
    def tickets(options={})
      since  = options[:since]
      merged = options[:merged]

      tickets = Set.new
      link    = options[:link]

      @git.log("#{since}..#{merged}", :merges => true).each do |commit|
        if (match = MERGE_COMMENT.match(commit.comment))
          words = match[1].split(WORD_BOUNDARY)
        else
          words = commit.comment.split(WORD_BOUNDARY)
        end

        got = words.detect do |w|
          if match = link.match(w)
            if match[1]
              tickets << match[1]
            else
              raise ArgumentError, "Regexp '#{link}' lacks capture groups; please use a () somewhere"
            end
          else
            nil
          end
        end
        unless got
          logger.warn "Couldn't infer a ticket link from '#{commit.comment}'"
        end
      end

      if (link_to = options[:link_to])
        link_to = link_to + '/' unless link_to =~ %r{/$}
        tickets.each { |t| puts link_to + t }
      else
        tickets.each { |t| puts t }
      end
    end

    private

    # Build a plain-English description of a prune command based on the
    # options given.
    # @param [Hash] options
    def describe_prune(options)
      statement = ['Pruning']

      if options[:remote]
        statement << 'remote'
      elsif options[:local]
        statement << 'local'
      end

      statement << 'branches'

      if options[:age]
        statement << "older than #{time_ago_in_words(options[:age])}"
      end

      if options[:merged]
        statement << "that are fully merged into #{options[:merged]}"
      end

      if options[:only]
        naming = "with a name containing '#{options[:only]}'"
        if options[:except]
          naming << " (but not '#{options[:except]}')"
        end
        statement << naming
      end

      statement.join(' ')
    end

    # Ask the user a yes-or-no question
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

    # An ordered list of time intervals of decreasing magnitude. Stored as Array and not Hash in
    # order to ensure consistent traversal order between Ruby 1.8 and 1.9+.
    TIME_INTERVALS = [
      [31_557_600, 'year'],
      [2_592_000, 'month'],
      [604_800, 'week'],
      [86_400, 'day'],
      [3_600, 'hour'],
      [60, 'minute'],
      [1, 'second'],
    ]

    # Workalike for ActiveSupport date-helper method. Given a Time in the past, return
    # a natural-language English string that describes the duration separating that time from
    # the present. The duration is very approximate, and will be rounded down to the nearest
    # appropriate interval (e.g. 2.5 hours becomes 2 hours).
    #
    # @example about three days ago
    #    time_ago_in_words(Time.now - 86400*3.1) # => "3 days"  
    #
    # @param [Time] once_upon_a the long-ago time to compare to Time.now
    # @return [String] an English time duration
    def time_ago_in_words(once_upon_a)
      dt = Time.now.to_f - once_upon_a.to_f

      words = nil

      TIME_INTERVALS.each do |pair|
        mag, term = pair.first, pair.last
        if dt >= mag
          units = Integer(dt / mag)
          words = "%d %s%s" % [units, term, units > 1 ? 's' : '']
          break
        end
      end

      if words
        words
      else
        once_upon_a.strftime("%Y-%m-%d")
      end
    end

    # Given a natural-language English description of a time duration, return a Time in the past,
    # that is the same duration from Time.now that is expressed in the string. 
    #
    # @param [String] str an English time duration
    # @return [Time] a Time object in the past, as described relative to now by str
    def parse_age(str)
      ord, word = str.split(/[. ]+/, 2)
      ord       = Integer(ord)
      word.gsub!(/s$/, '')

      ago = nil

      TIME_INTERVALS.each do |pair|
        mag, term = pair.first, pair.last

        if term == word
          ago = Time.at(Time.now.to_i - ord * mag)
          break
        end
      end

      if ago
        ago
      else
        raise ArgumentError, "Cannot parse '#{str}' as an age"
      end
    end
  end
end

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

require 'right_git'
require 'right_develop'
require "action_view"

module RightDevelop::Commands
  class Git
    NAME_SPLIT_CHARS = /-|_|\//
    YES              = /(ye?s?)/i
    NO               = /(no?)/i

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

And [options] are selected from:
EOS
        opt :age, "Minimum age to consider",
              :default => "3.months"
        opt :only, "Limit to branches matching this prefix", 
              :type=>:string
        opt :except, "Ignore branches matching this prefix",
              :type=>:string,
              :default => "^(release|v?[0-9.]+|)"
        opt :local, "Limit to local branches"
        opt :remote, "Limit to remote branches"
        opt :merged, "Limit to branches that are fully merged into the named branch",
              :type=>:string,
              :default => "master"
        stop_on TASKS
      end

      task = ARGV.shift

      case task
      when "prune"
        repo = ::RightGit::Git::Repository.new(
          ::Dir.pwd,
          ::RightDevelop::Utility::Git::DEFAULT_REPO_OPTIONS)
        self.new(repo, :prune, options)
      else
        Trollop.die "unknown task #{task}"
      end
    end

    # @option options [String] :age Ignore branches newer than this time-ago-in-words e.g. "3 months"; default unit is months
    # @option options [String] :except Ignore branches matching this regular expression
    # @option options [String] :only Consider only branches matching this regular expression
    # @option options [true|false] :local Consider local branches
    # @option options [true|false] :remote Consider remote branches
    # @option options [String] :merged Consider only branches that are fully merged into this branch (e.g. master)
    def initialize(repo, task, options)
      # Post-process "age" option; transform from natural-language expression into a timestamp.
      if (age = options.delete(:age))
        age = parse_age(age)
        options[:age] = age
      end

      # Post-process "except" option; transform into a Regexp.
      if (except = options.delete(:except))
        except = Regexp.new("^(origin/)?(#{except})")
        options[:except] = except
      end

      # Post-process "only" option; transform into a Regexp.
      if (only = options.delete(:only))
        only = Regexp.new("^(origin/)?(#{only})")
        options[:only] = only
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
    # @option options [true|false] :local Consider local branches
    # @option options [true|false] :remote Consider remote branches
    # @option options [String] :merged Consider only branches that are fully merged into this branch (e.g. master)
    def prune(options={})
      branches = @git.branches

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
        branches = branches.merged(options[:merged])
      end

      old = {}
      branches.each do |branch|
        latest = @git.log(branch, :tail=>1).first
        timestamp = latest.timestamp
        if timestamp < options[:age] &&
          old[branch] = timestamp
        end
      end

      if old.empty?
        STDERR.puts "No branches older than #{time_ago_in_words(options[:age])} found; do you need to specify --remote?"
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
          units = dt / mag
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
      ord = Integer(ord)
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

#
# Copyright (c) 2014 RightScale Inc
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

require 'right_develop'
require 'shellwords'

module RightDevelop::Commands
  class Server
    include RightSupport::Log::Mixin

    TASKS = %w(echo playback record)

    class PlainFormatter < ::Logger::Formatter
      def call(severity, time, progname, msg)
        sprintf("%s\n", msg2str(msg))
      end
    end

     # Parse command-line options and create a Command object
    def self.create
      task_list = TASKS.map { |c| "       * #{c}" }.join("\n")

      options = Trollop.options do
        banner <<-EOS
The 'server' command starts a server in the foreground to assist in testing. The
behavior of the server depends on the type specified.

Usage:
       right_develop git <task> [options]

Where <task> is one of:
#{task_list}

And [options] are selected from:
        EOS
        opt :test_dir, 'Root directory for config and fixtures.',
            :type => :string,
            :default => ::Dir.pwd
        opt :ruby_version, 'Ruby version to select with rbenv when running server. Requires a minimum of ruby v1.9.3',
            :type => :string,
            :default => '2.1.0'
        opt :force, 'Force overwrite of any existing recording',
            :default => false
        opt :debug, 'Enable verbose debug output',
            :default => false
      end

      task = ARGV.shift.to_s.to_sym
      case task
      when :echo, :playback, :record
        self.new(task, options)
      else
        Trollop.die "unknown task #{task}"
      end
    end

    # @param [Symbol] task one of :prune or :tickets
    # @option options [String] :root_dir for config and fixtures.
    # @option options [String] :ruby_version to select with rbenv when running server
    # @option options [String] :debug is true for debug-level logging
    def initialize(task, options)
      logger = ::Logger.new(STDOUT)
      logger.level = options[:debug] ? ::Logger::DEBUG : ::Logger::WARN
      logger.formatter = PlainFormatter.new
      RightSupport::Log::Mixin.default_logger = logger

      @task = task
      @options = options
    end

    # Run the task that was specified when this object was instantiated. This
    # method does no work; it just delegates to a task method.
    def run
      case @task
      when :echo, :playback, :record
        run_might_api(@task, @options)
      else
        raise ::ArgumentError, 'Unexpected task'
      end
    end

    protected

    def shell
      ::RightDevelop::Utility::Shell
    end

    def run_might_api(mode, options)
      if shell.is_windows?
        raise ::NotImplementedError, 'Not supported under Windows'
      end
      server_root_dir = ::File.expand_path('../../testing/servers/might_api', __FILE__)
      test_root_dir = ::File.expand_path(options[:test_dir])
      [server_root_dir, test_root_dir].each do |dir|
        unless ::File.directory?(dir)
          ::Trollop.die "Missing expected directory: #{dir.inspect}"
        end
      end

      # sanity checks.
      config_file_path = ::File.join(test_root_dir, 'config', 'might_deploy.yml')
      unless ::File.file?(config_file_path)
        ::Trollop.die "Missing expected configuration file: #{config_file_path.inspect}"
      end
      fixtures_dir = ::File.join(test_root_dir, 'fixtures')
      case mode
      when :record
        if ::File.directory?(fixtures_dir)
          if options[:force]
            logger.warn("Overwriting existing #{fixtures_dir.inspect} due to force=true")
            ::FileUtils.rm_rf(fixtures_dir)
          else
            ::Trollop.die "Cannot record over existing directory: #{fixtures_dir.inspect}"
          end
        end
      when :playback
        unless ::File.directory?(fixtures_dir)
          ::Trollop.die "Missing expected directory: #{fixtures_dir.inspect}"
        end
      end

      ::Dir.chdir(server_root_dir) do
        logger.warn("in #{server_root_dir.inspect}")
        logger.warn('Preparing to run server...')
        if `which rbenv`.strip.empty?
          logger.warn('Unable to invoke rbenv to ensure ruby version.')
        else
          shell.execute("rbenv local #{options[:ruby_version]}")
        end
        shell.execute('bundle check || bundle install')
        logger.level = options[:debug] ? ::Logger::DEBUG : ::Logger::INFO
        begin
          cmd = options[:debug] ? 'DEBUG=true ' : ''
          cmd << "RS_MIGHT_API_ROOT_DIR=#{::Shellwords.escape(test_root_dir).inspect} "
          cmd << "RS_MIGHT_API_MODE=#{mode} "
          cmd << 'bundle exec rackup'
          shell.execute(cmd)
        rescue ::Interrupt
          # server runs in foreground so interrupt is normal
        end
      end
    end

  end
end

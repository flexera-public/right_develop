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
require 'right_develop/testing/servers/might_api/lib/config'
require 'tmpdir'

module RightDevelop::Commands
  class Server
    include RightSupport::Log::Mixin

    CONFIG_CLASS = ::RightDevelop::Testing::Server::MightApi::Config

    TASKS = CONFIG_CLASS::VALID_MODES

    class PlainFormatter < ::Logger::Formatter
      def call(severity, time, progname, msg)
        sprintf("%s\n", msg2str(msg))
      end
    end

     # Parse command-line options and create a Command object
    def self.create
      task_list = TASKS.sort.inject([]) do |a, (k, v)|
        a << ' * %s%s' % [k.to_s.ljust(10), v]
      end.join("\n")

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
        opt :root_dir, 'Root directory for config and fixtures',
            :default => ::Dir.pwd
        opt :port, 'Port on which server will listen',
            :default => 9292
        opt :force, 'Force overwrite of any existing recording',
            :default => false
        opt :throttle, 'Playback delay as a percentage of recorded response time',
            :default => 0
        opt :debug, 'Enable verbose debug output',
            :default => false
      end

      task = ARGV.shift.to_s
      if TASKS.keys.include?(task)
        self.new(task.to_sym, options)
      else
        ::Trollop.die "unknown task #{task}"
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
      ::RightSupport::Log::Mixin.default_logger = logger

      @task = task
      @options = options
    end

    # Run the task that was specified when this object was instantiated. This
    # method does no work; it just delegates to a task method.
    def run
      run_might_api(@task, @options)
    end

    protected

    def shell
      ::RightDevelop::Utility::Shell
    end

    def run_might_api(mode, options)
      if shell.is_windows?
        ::Trollop.die 'Not supported under Windows'
      end
      if RUBY_VERSION < '1.9.3'
        ::Trollop.die 'Requires a minimum of ruby 1.9.3'
      end
      server_root_dir = ::File.expand_path('../../testing/servers/might_api', __FILE__)
      root_dir = ::File.expand_path(options[:root_dir])
      [server_root_dir, root_dir].each do |dir|
        unless ::File.directory?(dir)
          ::Trollop.die "Missing expected directory: #{dir.inspect}"
        end
      end

      # sanity checks.
      config = nil
      ::Dir.chdir(root_dir) do
        config_hash = CONFIG_CLASS.load_config_hash
        config_hash['mode'] = mode
        config_hash['log_level'] = options[:debug] ? :debug : :info
        config_hash['throttle'] = options[:throttle]
        config = CONFIG_CLASS.setup(config_hash)
      end
      fixtures_dir = config.fixtures_dir
      tmp_root_dir = ::Dir.mktmpdir
      tmp_config_path = ::File.join(tmp_root_dir, CONFIG_CLASS::RELATIVE_CONFIG_PATH)
      case mode
      when :record
        if ::File.directory?(fixtures_dir)
          if options[:force]
            logger.warn("Overwriting existing #{fixtures_dir.inspect} due to force=true")
            ::FileUtils.rm_rf(fixtures_dir)
          else
            ::Trollop.die "Unable to record over existing directory: #{fixtures_dir.inspect}"
          end
        end
      when :playback
        unless ::File.directory?(fixtures_dir)
          ::Trollop.die "Missing expected directory: #{fixtures_dir.inspect}"
        end

        # copy fixtures tmp location so that multiple server instances can
        # playback the same fixture directory but keep their own state (even if
        # original gets re-recorded, etc.).
        tmp_fixtures_dir = ::File.expand_path(CONFIG_CLASS::FIXTURES_DIR_NAME, tmp_root_dir)
        ::FileUtils.mkdir_p(tmp_fixtures_dir)
        ::FileUtils.cp_r(::File.join(fixtures_dir, '.'), tmp_fixtures_dir)
        config.fixtures_dir(tmp_fixtures_dir)
        config.normalize_fixtures_dir(logger)
      end

      # write updated config to tmp location.
      ::FileUtils.mkdir_p(::File.dirname(tmp_config_path))
      ::File.open(tmp_config_path, 'w') { |f| f.puts ::YAML.dump(config.to_hash) }

      ::Dir.chdir(server_root_dir) do
        logger.warn("in #{server_root_dir.inspect}")
        logger.warn('Preparing to run server...')
        shell.execute('bundle check || bundle install')
        logger.level = options[:debug] ? ::Logger::DEBUG : ::Logger::INFO
        begin
          cmd = "cat #{tmp_config_path.inspect} | bundle exec rackup --port #{options[:port]}"
          shell.execute(cmd)
        rescue ::Interrupt
          # server runs in foreground so interrupt is normal
        ensure
          begin
            ::FileUtils.rm_rf(tmp_root_dir)
          rescue ::Exception => e
            logger.error("Unable to remove #{tmp_root_dir.inspect}:\n  #{e.class}: #{e.message}")
          end
        end
      end
    end

  end
end

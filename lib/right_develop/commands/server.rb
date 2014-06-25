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

require 'fileutils'
require 'open3'
require 'tmpdir'

module RightDevelop::Commands
  class Server
    include RightSupport::Log::Mixin

    CONFIG_CLASS = ::RightDevelop::Testing::Server::MightApi::Config

    MODES = CONFIG_CLASS::VALID_MODES

    # for display in help message
    DEFAULT_SEND_TO = 'run a new instance of service from current shell'

    class PlainFormatter < ::Logger::Formatter
      def call(severity, time, progname, msg)
        sprintf("%s\n", msg2str(msg))
      end
    end

     # Parse command-line options and create a Command object
    def self.create
      mode_list = MODES.sort.inject([]) do |a, (k, v)|
        a << ' * %s%s' % [k.to_s.ljust(10), v]
      end.join("\n")

      options = Trollop.options do
        banner <<-EOS
The 'server' command starts a server in the foreground (by default) to assist in testing. The behavior of the server depends on the type specified.

Usage:
  right_develop server <mode> [options]

Where <mode> is one of:
#{mode_list}

And [options] are selected from:
        EOS
        send_to_msg =
          'Configure an already-running admin service at given URL. ' +
          'The URL to PUT is specific to the admin service configuration'
        opt :root_dir, 'Root directory for config and fixtures',
            :default => ::Dir.pwd
        opt :port, 'Port on which server will listen',
            :default => 9292
        opt :force, 'Force overwrite of any existing recording',
            :default => false
        opt :throttle, 'Playback delay as a percentage of recorded response time',
            :default => 1
        opt :debug, 'Enable verbose debug output',
            :default => false
        opt :send_to, send_to_msg,
            :default => DEFAULT_SEND_TO
        opt :start, 'Start the server in the background',
            :default => false
        opt :stop, 'Stop any running server by mode, port and last known PID',
            :default => false
      end

      mode = ARGV.shift.to_s
      if MODES.keys.include?(mode)
        self.new(mode.to_sym, options)
      else
        ::Trollop.die("unknown mode #{mode}")
      end
    end

    # @param [Symbol] mode one of :prune or :tickets
    # @option options [String] :root_dir for config and fixtures.
    # @option options [String] :ruby_version to select with rbenv when running server
    # @option options [String] :debug is true for debug-level logging
    def initialize(mode, options)
      logger = ::Logger.new(STDOUT)
      logger.level = options[:debug] ? ::Logger::DEBUG : ::Logger::WARN
      logger.formatter = PlainFormatter.new
      ::RightSupport::Log::Mixin.default_logger = logger

      @mode = mode
      @options = options
    end

    # Run the mode that was specified when this object was instantiated. This
    # method does no work; it just delegates to a mode method.
    def run
      run_might_api(@mode, @options)
    end

    protected

    def shell
      ::RightDevelop::Utility::Shell
    end

    def run_might_api(mode, options)
      # sanity checks.
      if shell.is_windows?
        ::Trollop.die('Not supported under Windows')
      end
      if RUBY_VERSION < '1.9.3'
        ::Trollop.die('Requires a minimum of ruby 1.9.3')
      end

      # ensure cleanest bundler environment.
      shell.setup_clean_env

      # check and enhance options.
      options = options.dup
      server_root_dir = ::File.expand_path('../../testing/servers/might_api', __FILE__)
      options[:server_root_dir] = server_root_dir
      root_dir = ::File.expand_path(options[:root_dir])
      options[:root_dir] = root_dir
      [server_root_dir, root_dir].each do |dir|
        unless ::File.directory?(dir)
          ::Trollop.die("Missing expected directory: #{dir.inspect}")
        end
      end
      send_to = (options[:send_to] == DEFAULT_SEND_TO) ? nil : options[:send_to]
      options[:send_to] = send_to
      if send_to && (options[:start] || options[:stop])
        ::Trollop.die('Option --send-to cannot be combined with background options')
      elsif options[:start] && options[:stop]
        ::Trollop.die('Option --start cannot be combined with --stop')
      end

      # sanity checks.
      config = nil
      ::Dir.chdir(root_dir) do
        config = CONFIG_CLASS.from_file(
          CONFIG_CLASS::DEFAULT_CONFIG_PATH,
          mode:      mode,
          log_level: options[:debug] ? :debug : :info,
          throttle:  options[:throttle])
      end

      # stop, start, run or send.
      if options[:stop]
        do_stop(config, options)
      else
        do_non_stop(config, options)
      end
      true
    end

    def xid_file_name(config, options, extension)
      ::File.join(
        config.pid_dir,
        "mode-#{config.mode}_port-#{options[:port]}#{extension}")
    end

    def gid_file_path(config, options)
      xid_file_name(config, options, '.gid')
    end

    def pid_file_path(config, options)
      xid_file_name(config, options, '.pid')
    end

    def do_start(cmd, config, options)
      # create PID dir.
      unless ::File.directory?(config.pid_dir)
        ::FileUtils.mkdir_p(config.pid_dir)
      end
      pfp = pid_file_path(config, options)
      gfp = gid_file_path(config, options)
      if ::File.exists?(pfp) || ::File.exists?(gfp)
        msg = 'The service appears to already be running due to PID files ' +
              "found under #{config.pid_dir.inspect}"
        ::Trollop.die(msg)
      else
        executioner = lambda do
          # use open3 to spawn service process.
          cmd = "#{cmd} 1>/dev/null 2>&1"
          stdin, stdout_and_stderr, wait_thread = ::Open3.popen2e(cmd)

          # save PID/GID for stop.
          pid = wait_thread.pid
          gid = ::Process.getpgid(pid)
          logger.info("Started (pid = #{pid}, gid = #{gid}).")
          ::File.open(gfp, 'w') { |f| f.write gid }
          ::File.open(pfp, 'w') { |f| f.write pid }

          # intentionally not closing I/O objects or waiting on thread so that
          # service continues to run while parent goes away.
        end

        # clean all bundler env vars before executing child process (but only
        # if bundler is loaded).
        executioner = shell.wrap_executioner_with_clean_env(executioner)
        executioner.call
      end
      true
    end

    def do_stop(config, options)
      # group identifier
      gfp = gid_file_path(config, options)
      gid = (::File.read(gfp) rescue '').strip

      # process identifier
      pfp = pid_file_path(config, options)
      pid = (::File.read(pfp) rescue '').strip

      unless pid.empty? || gid.empty?
        pid = Integer(pid)
        gid = Integer(gid)
        signals = ['INT', 'TERM', 'KILL']
        signals.each do |signal|
          # use PID (process ID) to detect parent process but use GID
          # (group ID) to kill parent process and any children.
          found = false
          begin
            ::Process.kill(0, pid)
            found = true
          rescue Errno::ESRCH
            found = false
          end
          if found
            begin
              ::Process.kill(signal, -gid)
            rescue
              raise if signal == signals.last
            end
            sleep 2
          else
            break
          end
        end
        puts 'Stopped.'
      end
      ::File.unlink(pfp) rescue nil
      ::File.unlink(gfp) rescue nil
    end

    def do_non_stop(config, options)
      # convenience
      server_root_dir = options[:server_root_dir]
      send_to = options[:send_to]
      fixtures_dir = config.fixtures_dir
      tmp_root_dir = ::Dir.mktmpdir
      tmp_config_path = ::File.join(tmp_root_dir, CONFIG_CLASS::DEFAULT_CONFIG_PATH)

      case config.mode
      when :record
        if ::File.directory?(fixtures_dir)
          if options[:force]
            logger.warn("Overwriting existing #{fixtures_dir.inspect} due to force=true")
            ::FileUtils.rm_rf(fixtures_dir)
          else
            ::Trollop.die("Unable to record over existing directory: #{fixtures_dir.inspect}")
          end
        end
      when :playback
        unless ::File.directory?(fixtures_dir)
          ::Trollop.die("Missing expected directory: #{fixtures_dir.inspect}")
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

      # tell service to cleanup tmp root dir for us if/when it is interrupted or
      # changes configuration. any temporary state files are also removed even
      # if present in a non-temporary directory.
      config.cleanup_dirs(tmp_root_dir)

      # write updated config to tmp location.
      ::FileUtils.mkdir_p(::File.dirname(tmp_config_path))
      ::File.open(tmp_config_path, 'w') { |f| f.puts ::YAML.dump(config.to_hash) }

      ::Dir.chdir(server_root_dir) do
        logger.warn("in #{server_root_dir.inspect}")
        logger.warn('Preparing to run server...')
        shell.execute('bundle check || bundle install')
        logger.level = options[:debug] ? ::Logger::DEBUG : ::Logger::INFO
        cleanup = true
        begin
          # curl the config to running service in admin mode, if requested.
          if send_to
            curl_debug = options[:debug] ? '-i' : '-s'
            cmd = "curl #{curl_debug} -S -f --upload-file #{tmp_config_path} #{send_to}"
          else
            # start service in foreground or background.
            cmd = "cat #{tmp_config_path.inspect} | bundle exec rackup --port #{options[:port]}"
          end
          if options[:start]
            do_start(cmd, config, options)
            cleanup = false
          else
            shell.execute(cmd)
            cleanup = false  # only reachable in case of send-to
          end
        rescue ::Interrupt
          # server runs in foreground so interrupt is normal
        rescue RightGit::Shell::ShellError => e
          logger.error(e.message)
        ensure
          # ensured cleanup in case of failed service run. cannot cleanup in
          # case of sending configuration or starting background service.
          if cleanup
            case config.mode
            when :record
              # remove temporary record state file from root of fixtures directory.
              ::Dir[::File.join(config.fixtures_dir, '*.yml')].each do |path|
                begin
                  ::File.unlink(path)
                rescue ::Exception => e
                  logger.error("Unable to remove #{path.inspect}:\n  #{e.class}: #{e.message}")
                end
              end
            end
            begin
              ::FileUtils.rm_rf(tmp_root_dir)
            rescue ::Exception => e
              logger.error("Unable to remove #{tmp_root_dir.inspect}:\n  #{e.class}: #{e.message}")
            end
          end
        end
      end
      true
    end
  end # Server
end # RightDevelop::Commands

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

# ancestor
require 'right_develop/utility'

require 'right_git'
require 'right_support'

module RightDevelop
  module Utility

    # extends default shell easy-singleton from right_git gem.
    class Shell < ::RightGit::Shell::Default

      class NullLoggerSingleton
        @@logger = nil

        def self.instance
          @@logger ||= ::RightSupport::Log::NullLogger.new
        end
      end

      # bundle exec sets GEM_HOME and GEM_PATH (in Windows?) and these need to
      # be wacked in order to have a pristing rubygems environment since bundler
      # won't clean them. also, if you 'bundle exec rake ...' and then put
      # arguments to the right of the task name, then these args won't appear in
      # Bundler::ORIGINAL_ENV.
      # example: "bundle exec rake build:all DEBUG=true ..."
      def setup_clean_env
        # user may be running gem binary directly without bundler.
        if defined?(::Bundler)
          # a little revisionist history music...
          ::ENV.each do |key, value|
            if key.start_with?('GEM_') || key.start_with?('BUNDLER_')
              ::Bundler::ORIGINAL_ENV[key] = nil
            elsif Bundler::ORIGINAL_ENV[key].nil?
              ::Bundler::ORIGINAL_ENV[key] = value
            end
          end
          ::Bundler.with_clean_env do
            # now the ENV is clean and not missing any right-hand args so replace
            # the ORIGINAL_ENV.
            ::Bundler::ORIGINAL_ENV.replace(ENV)
          end
        end
        true
      end

      # @return [TrueClass|FalseClass] true if running on Windows platform
      def is_windows?
        return !!(RUBY_PLATFORM =~ /mswin|win32|dos|mingw|cygwin/)
      end

      # Creates a null logger.
      #
      # @return [Logger] the null logger
      def null_logger
        NullLoggerSingleton.instance
      end

      # @return [Logger] RightSupport::Log::Mixin.default_logger
      def default_logger
        RightSupport::Log::Mixin.default_logger
      end

      # Overrides ::RightGit::Shell::Default#execute
      #
      # @param [String] cmd the shell command to run
      # @param [Hash] options for execution
      # @option options :directory [String] to use as working directory during command execution or nil
      # @option options :logger [Logger] logger for shell execution (default = STDOUT)
      # @option options :outstream [IO] output stream to receive STDOUT and STDERR from command (default = none)
      # @option options :raise_on_failure [TrueClass|FalseClass] if true, wil raise a RuntimeError if the command does not end successfully (default), false to ignore errors
      # @option options :set_env_vars [Hash] environment variables to set during execution (default = none set)
      # @option options :clear_env_vars [Hash] environment variables to clear during execution (default = none cleared but see :clean_bundler_env)
      # @option options :clean_bundler_env [TrueClass|FalseClass] true to clear all bundler environment variables during execution (default), false to inherit bundler env from parent
      # @option options :sudo [TrueClass|FalseClass] if true, will wrap command in sudo if needed, false to run as current user (default)
      #
      # @return [Integer] exitstatus of the command
      #
      # @raise [ShellError] on failure only if :raise_on_failure is true
      def execute(cmd, options = {})
        options = {
          :clean_bundler_env => true,
          :sudo              => false
        }.merge(options)

        if options[:sudo]
          fail "Not available in Windows" if is_windows?
          cmd = "sudo #{cmd}" unless ::Process.euid == 0
        end

        # super execute.
        super(cmd, options)
      end

      # Overrides ::RightGit::Shell::Default#configure_executioner
      def configure_executioner(executioner, options)
        # super configure early to ensure that any custom env vars are set after
        # restoring the pre-bundler env.
        executioner = super(executioner, options)

        # clean all bundler env vars, if requested.
        if options[:clean_bundler_env]
          executioner = wrap_executioner_with_clean_env(executioner)
        end
        executioner
      end

      # Encapsulates executioner with bundler-defeating logic, but only if
      # bundler has been loaded by current process.
      #
      # @param [Proc] executioner to conditionally wrap
      #
      # @return [Proc] wrapped or original executioner
      def wrap_executioner_with_clean_env(executioner)
        # only if bundler is loaded.
        if defined?(::Bundler)
          # double-lambda, single call freezes the inner call made to previous
          # definition of executioner.
          executioner = lambda do |e|
            lambda { ::Bundler.with_clean_env { e.call } }
          end.call(executioner)
        end
        executioner
      end

    end # Shell
  end # Utility
end # RightDevelop

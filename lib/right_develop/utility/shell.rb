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

module RightDevelop
  module Utility
    module Shell

      class NullLoggerSingleton
        @@logger = nil

        def self.instance
          @@logger ||= ::Logger.new(
            ::RightDevelop::Utility::Shell.is_windows? ? 'nul' : '/dev/null')
        end
      end

      module_function

      # bundle exec sets GEM_HOME and GEM_PATH (in Windows?) and these need to
      # be wacked in order to have a pristing rubygems environment since bundler
      # won't clean them. also, if you 'bundle exec rake ...' and then put
      # arguments to the right of the task name, then these args won't appear in
      # Bundler::ORIGINAL_ENV.
      # example: "bundle exec rake build:all DEBUG=true ..."
      def setup_clean_env
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

      # Run the given command and print the output to stdout.
      #
      # @param [String] cmd the shell command to run
      # @param [Hash] options for execution
      # @option options :outstream [IO] output stream to receive STDOUT and STDERR from command (default = STDOUT)
      # @option options :raise_on_failure [TrueClass|FalseClass] if true, wil raise a RuntimeError if the command does not end successfully (default), false to ignore errors
      # @option options :sudo [TrueClass|FalseClass] if true, will wrap command in sudo if needed, false to run as current user (default)
      # @option options :set_env_vars [Hash] environment variables to set during execution (default = none set)
      # @option options :clear_env_vars [Hash] environment variables to clear during execution (default = none cleared but see :clean_bundler_env)
      # @option options :clean_bundler_env [TrueClass|FalseClass] true to clear all bundler environment variables during execution (default), false to inherit bundler env from parent
      #
      # @return [Integer] exitstatus of the command
      #
      # === Raises
      # RuntimeError:: if command does not complete successfully and option :raise_on_failure is true
      def execute(cmd, options = {})
        options = {
          :outstream         => STDOUT,
          :raise_on_failure  => true,
          :sudo              => false,
          :set_env_vars      => nil,
          :clear_env_vars    => nil,
          :clean_bundler_env => true
        }.merge(options)

        if options[:sudo]
          fail "Not available in Windows" if is_windows?
          cmd = "sudo #{cmd}" unless ::Process.euid == 0
        end

        # build execution block in layers.
        exitstatus = nil
        executioner = lambda do
          puts "+ #{cmd}"
          ::IO.popen("#{cmd} 2>&1", 'r') do |output|
            output.sync = true
            done = false
            while !done
              begin
                options[:outstream] << output.readline
              rescue ::EOFError
                done = true
              end
            end
          end
          exitstatus = $?.exitstatus
          if (!$?.success? && options[:raise_on_failure])
            fail "Execution failed with exitstatus #{exitstatus}"
          end
        end

        # set specific environment variables, if requested.
        sev = options[:set_env_vars]
        if (sev && !sev.empty?)
          executioner = lambda do |e|
            lambda { set_env_vars(sev) { e.call } }
          end.call(executioner)
        end

        # clear specific environment variables, if requested.
        cev = options[:clear_env_vars]
        if (cev && !cev.empty?)
          executioner = lambda do |e|
            lambda { clear_env_vars(cev) { e.call } }
          end.call(executioner)
        end

        # clean all bundler env vars, if requested.
        if options[:clean_bundler_env]
          executioner = lambda do |e|
            lambda { ::Bundler.with_clean_env { e.call } }
          end.call(executioner)
        end

        # invoke.
        executioner.call

        return exitstatus
      end

      # Invoke a shell command and return its output as a string, similar to
      # backtick but defaulting to raising exception on failure.
      #
      # === Parameters
      # @param [String] cmd command to execute
      # @param [Hash] options for execution
      #
      # === Return
      # @return [String] entire output (stdout) of the command
      def output_for(cmd, options = {})
        output = StringIO.new
        execute(cmd, options.merge(:outstream => output))
        output.string
      end

      # Sets the given list of environment variables while
      # executing the given block.
      #
      # === Parameters
      # @param [Hash] variables to set
      #
      # === Yield
      # @yield [] called with environment set
      #
      # === Return
      # @return [TrueClass] always true
      def set_env_vars(variables)
        save_vars = {}
        variables.each { |k, v| save_vars[k] = ENV[k]; ENV[k] = v }
        begin
          yield
        ensure
          variables.each_key { |k| ENV[k] = save_vars[k] }
        end
        true
      end

      # Clears (set-to-nil) the given list of environment variables while
      # executing the given block.
      #
      # @param [Array] names of variables to clear
      #
      # @yield [] called with environment cleared
      #
      # @return [TrueClass] always true
      def clear_env_vars(names, &block)
        save_vars = {}
        names.each { |k| save_vars[k] = ENV[k]; ENV[k] = nil }
        begin
          yield
        ensure
          names.each { |k| ENV[k] = save_vars[k] }
        end
        true
      end

    end # Shell
  end # Utility
end # RightDevelop

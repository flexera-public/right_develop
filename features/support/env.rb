#--
# Copyright: Copyright (c) 2010- RightScale, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# 'Software'), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

require 'tmpdir'

require 'rubygems'
require 'bundler/setup'

lib_dir = File.expand_path('../../../lib', __FILE__)
$: << lib_dir unless $:.include?(lib_dir)
require 'right_develop'

module RubyAppHelper
  def ruby_app_root
    @ruby_app_root ||= Dir.mktmpdir('right_develop_cucumber_ruby')
  end

  def ruby_app_path(*args)
    path = ruby_app_root
    until args.empty?
      item = args.shift
      path = File.join(path, item)
    end
    path
  end

  # Run a shell command in app_dir, e.g. a rake task
  def ruby_app_shell(cmd, options={})
    ignore_errors = options[:ignore_errors] || false
    log = !!(Cucumber.logger)

    all_output = ''
    Dir.chdir(ruby_app_root) do
      Cucumber.logger.debug("bash> #{cmd}\n") if log
      Bundler.with_clean_env do
        IO.popen("#{cmd} 2>&1", 'r') do |output|
          output.sync = true
          done = false
          until done
            begin
              line = output.readline + "\n"
              all_output << line
              Cucumber.logger.debug(line) if log
            rescue EOFError
              done = true
            end
          end
        end
      end
    end

    $?.success?.should(be_true) unless ignore_errors
    all_output
  end
end

module RightDevelopWorld
  include RubyAppHelper
end

# The Cucumber world
World(RightDevelopWorld)

After do
  FileUtils.rm_rf(ruby_app_root) if File.directory?(ruby_app_root)
end

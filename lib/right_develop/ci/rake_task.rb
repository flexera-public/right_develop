#
# Copyright (c) 2009-2011 RightScale Inc
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

# Once this file is required, the Rake DSL is loaded - don't do this except inside Rake!!
require 'rake/tasklib'

# Make sure the rest of RightDevelop & CI is required, since this file can be
# required directly.
require 'right_develop'
require 'right_develop/ci'

# Try to load RSpec 2.x - 1.x Rake tasks
['rspec/core/rake_task', 'spec/rake/spectask'].each do |f|
  begin
    require f
  rescue LoadError
    # no-op, we will raise later
  end
end

require 'cucumber'
require 'cucumber/rake/task'

module RightDevelop::CI
  # A Rake task definition that creates a CI namespace with appropriate
  # tests.
  class RakeTask < ::Rake::TaskLib
    include ::Rake::DSL if defined?(::Rake::DSL)

    # The namespace in which to define the continuous integration tasks.
    #
    # Default :ci
    attr_accessor :ci_namespace

    # File glob to select which specs will be run with the spec task.
    #
    # Default nil (let RSpec choose pattern)
    attr_accessor :rspec_pattern

    # Filename (without directory!) to which RSpec XML results should be written.
    # The CI task will take output_path, append "rspec" as a subdir and finally
    # append this file name, to come up with a relative path for output. For example:
    #
    # Default "rspec.xml"
    #
    #   output_path = "my_cool_ci"
    #   rspec_output = "my_awesome_rspec.xml"
    #
    # Given the options above, the CI harness would write RSpec results to:
    #   my_cool_ci/rspec/my_awesome_rspec.xml
    attr_accessor :rspec_output

    # The base directory for all output files.
    #
    # Default 'measurement'
    attr_accessor :output_path

    # The name for the RSpec task.
    #
    # Default :spec
    attr_accessor :rspec_name

    # The description for the RSpec task.
    #
    # Default "Run RSpec examples"
    attr_accessor :rspec_desc

    # An array of additional options for the RSpec task.
    #
    # Default: []
    #
    # Use like:
    #   rspec_opts = ["-t", "~slow_specs"]
    attr_accessor :rspec_opts

    # The name for the Cucumber task.
    #
    # Default :cucumber
    attr_accessor :cucumber_name

    # The description for the Cucumber task.
    #
    # Default "Run Cucumber examples"
    attr_accessor :cucumber_desc

    def initialize(*args)
      @ci_namespace = args.shift || :ci

      yield self if block_given?

      @output_path ||= 'measurement'
      @rspec_output ||= 'rspec.xml'
      @rspec_name ||= :spec
      @rspec_desc ||= "Run RSpec examples"
      @cucumber_name ||= :cucumber
      @cucumber_desc ||= "Run Cucumber examples"
      @rspec_opts ||= []

      namespace @ci_namespace do
        task :prep do
          FileUtils.mkdir_p(@output_path)
          FileUtils.mkdir_p(File.join(@output_path, 'rspec'))
          FileUtils.mkdir_p(File.join(@output_path, 'cucumber'))
        end

        if defined?(::RSpec::Core::RakeTask)
          default_opts = ['-r', 'right_develop/ci',
                          '-f', JavaSpecFormatter.name,
                          '-o', File.join(@output_path, 'rspec', @rspec_output)]

          # RSpec 2
          desc @rspec_desc
          RSpec::Core::RakeTask.new(@rspec_name => :prep) do |t|
            t.rspec_opts = default_opts + @rspec_opts
            unless self.rspec_pattern.nil?
              t.pattern = self.rspec_pattern
            end
          end
        elsif defined?(::Spec::Rake::SpecTask)
          default_opts = ['-r', 'right_develop/ci',
                          '-f', JavaSpecFormatter.name + ":" + File.join(@output_path, 'rspec', @rspec_output)]

          # RSpec 1
          Spec::Rake::SpecTask.new(@rspec_name => :prep) do |t|
            desc @rspec_desc
            t.spec_opts = default_opts + @rspec_opts
            unless self.rspec_pattern.nil?
              t.spec_files = FileList[self.rspec_pattern]
            end
          end
        else
          raise LoadError, "Cannot define CI rake task: unsupported RSpec version"
        end

        Cucumber::Rake::Task.new(@cucumber_name, @cucumber_desc) do |t|
          t.cucumber_opts = ['--no-color',
                             '--format', JavaCucumberFormatter.name,
                             '--out', File.join(@output_path, 'cucumber')]
        end
        task :cucumber => [:prep]
      end
    end
  end
end

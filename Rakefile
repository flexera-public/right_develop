# -*-ruby-*-
require 'rubygems'
require 'bundler/setup'

require 'rake'

# These dependencies can be omitted using "bundle install --without"; tolerate their absence.
['rdoc/task', 'jeweler', 'coveralls/rake/task'].each do |optional|
  begin
    require optional
  rescue LoadError
    # ignore
  end
end

require 'rubygems/package_task'

require 'rake/clean'
require 'rspec/core/rake_task'
require 'cucumber/rake/task'

# We use RightDevelop's CI harness in its own Rakefile. Hooray dogfood!
lib_dir = File.expand_path('../lib', __FILE__)
$: << lib_dir unless $:.include?(lib_dir)
require 'right_develop'

# But, we have a very special need, because OUR Cucumbers need to run with a pristine
# environment that isn't polluted by RVM or RubyGems or anyone else, in order to validate
# that RightDevelop's CI harness doesn't break your app if those gems are unavailable.
# Thus when our own Rake task runs spec or cucumber as a subprocess, we need to give it
# a pristine non-bundled environment, so it can use Bundler.with_clean_env to launch
# subprocesses.
require File.expand_path('../features/support/file_utils_bundler_mixin', __FILE__)

desc "Run unit tests"
task :default => :spec

desc "Run unit tests"
RSpec::Core::RakeTask.new do |t|
  t.pattern = Dir['**/*_spec.rb']
end

desc "Run functional tests"
Cucumber::Rake::Task.new do |t|
  t.cucumber_opts = %w{--color --format pretty}
end

if defined?(Rake::RDocTask)
  desc 'Generate documentation for the right_develop gem.'
  Rake::RDocTask.new(:rdoc) do |rdoc|
    rdoc.rdoc_dir = 'doc'
    rdoc.title    = 'RightDevelop'
    rdoc.options << '--line-numbers' << '--inline-source'
    rdoc.rdoc_files.include('README.rdoc')
    rdoc.rdoc_files.include('lib/**/*.rb')
    rdoc.rdoc_files.exclude('features/**/*')
    rdoc.rdoc_files.exclude('spec/**/*')
  end
end

if defined?(Jeweler)
  Jeweler::Tasks.new do |gem|
    # gem is a Gem::Specification; see http://docs.rubygems.org/read/chapter/20 for more options
    gem.name = "right_develop"
    gem.homepage = "https://github.com/rightscale/right_develop"
    gem.license = "MIT"
    gem.summary = %Q{Reusable dev & test code.}
    gem.description = %Q{A toolkit of development tools created by RightScale.}
    gem.email = "support@rightscale.com"
    gem.authors = ["Tony Spataro"]
    gem.rubygems_version = "1.3.7"
    gem.files.exclude ".rspec"
    gem.files.exclude "Gemfile*"
    gem.files.exclude "features/**/*"
    gem.files.exclude "spec/**/*"
  end

  Jeweler::RubygemsDotOrgTasks.new

  CLEAN.include('pkg')
end

if defined?(Coveralls::RakeTask)
  Coveralls::RakeTask.new
else
  raise "WTF YO"
end

RightDevelop::CI::RakeTask.new
RightDevelop::Git::RakeTask.new
RightDevelop::S3::RakeTask.new

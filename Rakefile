# -*-ruby-*-
require 'rubygems'
require 'bundler/setup'

require 'rake'
require 'rdoc/task'
require 'rubygems/package_task'

require 'rake/clean'
require 'rspec/core/rake_task'
require 'cucumber/rake/task'

# We use RightDevelop's CI harness in its own Rakefile. Hooray dogfood!
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

desc "Build right_develop gem"
Gem::PackageTask.new(Gem::Specification.load("right_develop.gemspec")) do |package|
  package.need_zip = true
  package.need_tar = true
end

CLEAN.include('pkg')

RightDevelop::CI::RakeTask.new

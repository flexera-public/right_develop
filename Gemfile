# NOTE: do not include right_develop's gemspec in its Gemfile; this is a Jewelerized
# project and gemspec-in-gemfile is not appropriate. It causes a loop in the dependency
# solver and Jeweler ends up generating a needlessly large gemspec.

source 'https://rubygems.org'

# Runtime dependencies of RightDevelop

# Gems used by the CI harness
gem 'right_support', ['>= 2.8.31', '< 3.0.0'] 

# Gems used by reusable spec helpers
gem "builder", "~> 3.0"

# Gems used by the command-line Git tools
gem 'trollop', ['>= 1.0', '< 3.0']
gem 'right_git', '>= 1.0'

# Gems used by S3 tools
gem 'right_aws', '>= 2.1.0'

# testing server and client
gem 'rack'

# Gems used during RightDevelop development that should be called out in the gemspec
group :development do
  gem 'rake', '>= 0.8.7'
  gem 'jeweler', '~> 2.0'
  gem 'rdoc', '>= 2.4.2'

  # debuggers
  gem 'debugger', '>= 1.6.6', :platforms => [:ruby_19, :ruby_20]
  gem 'pry', :platforms => [:ruby_21]
  gem 'pry-byebug', :platforms => [:ruby_21]
end

# Gems that are only used locally by this repo to run tests and should NOT be
# called out in the gemspec.
group :test do
  gem 'rspec', '~> 2.0'
  gem 'cucumber', ['~> 1.0', '< 1.3.3'] # Cuke >= 1.3.3 depends on RubyGems > 2.0 without specifyin that in its gemspec
  gem 'libxml-ruby', '~> 2.7', :platforms => [:mri]
end

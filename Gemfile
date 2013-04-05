source "https://rubygems.org"

# Runtime dependencies of RightDevelop

# Gems used by the CI harness
gem "rake", [">= 0.8.7", "< 0.10"]
gem "right_support", "~> 2.0"
gem "builder", "~> 3.0"
gem "rspec", [">= 1.3", "< 3.0"]
gem "cucumber", "~> 1.0"

# Gems used by the command-line Git tools
gem "trollop", "~> 1.0"
gem "actionpack", [">= 2.3.0", "< 4.0"]

# Gems used during RightDevelop development that should be called out in the gemspec
group :development do
  gem "jeweler", "~> 1.8.3"
  gem "rdoc", ">= 2.4.2"
  gem "syntax", "~> 1.0.0" #rspec will syntax-highlight code snippets if this gem is available
  gem "nokogiri", "~> 1.5"
  gem "flexmock", "~> 0.8.7", :require => nil
  gem "activesupport"
  gem "libxml-ruby", "~> 2.4.0"
end

# Gems that are only used locally by this repo to run tests and should NOT be called out in the gemspec
group :test do
  gemspec
  gem "ruby-debug", ">= 0.10", :platforms => :ruby_18
  gem "ruby-debug19", ">= 0.11.6", :platforms => :ruby_19
end

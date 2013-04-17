# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{right_develop}
  s.version = "1.1.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Tony Spataro"]
  s.date = %q{2013-04-17}
  s.default_executable = %q{right_develop}
  s.description = %q{A toolkit of development tools created by RightScale.}
  s.email = %q{support@rightscale.com}
  s.executables = ["right_develop"]
  s.extra_rdoc_files = [
    "LICENSE",
    "README.rdoc"
  ]
  s.files = [
    ".rspec",
    "CHANGELOG.rdoc",
    "Gemfile",
    "Gemfile.lock",
    "LICENSE",
    "README.rdoc",
    "Rakefile",
    "VERSION",
    "bin/right_develop",
    "features/cucumber.feature",
    "features/rake_integration.feature",
    "features/rspec1.feature",
    "features/rspec2.feature",
    "features/step_definitions/http_client_steps.rb",
    "features/step_definitions/request_balancer_steps.rb",
    "features/step_definitions/ruby_steps.rb",
    "features/step_definitions/serialization_steps.rb",
    "features/step_definitions/server_steps.rb",
    "features/support/env.rb",
    "features/support/file_utils_bundler_mixin.rb",
    "lib/right_develop.rb",
    "lib/right_develop/ci.rb",
    "lib/right_develop/ci/java_cucumber_formatter.rb",
    "lib/right_develop/ci/java_spec_formatter.rb",
    "lib/right_develop/ci/rake_task.rb",
    "lib/right_develop/commands.rb",
    "lib/right_develop/commands/git.rb",
    "lib/right_develop/git.rb",
    "lib/right_develop/git/branch.rb",
    "lib/right_develop/git/branch_collection.rb",
    "lib/right_develop/git/commit.rb",
    "lib/right_develop/git/repository.rb",
    "lib/right_develop/net.rb",
    "lib/right_develop/parsers.rb",
    "lib/right_develop/parsers/sax_parser.rb",
    "lib/right_develop/parsers/xml_post_parser.rb",
    "right_develop.gemspec",
    "right_develop.rconf",
    "spec/right_develop/parsers/sax_parser_spec.rb",
    "spec/spec_helper.rb"
  ]
  s.homepage = %q{https://github.com/rightscale/right_develop}
  s.licenses = ["MIT"]
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.6.2}
  s.summary = %q{Reusable dev & test code.}

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<rake>, ["< 0.10", ">= 0.8.7"])
      s.add_runtime_dependency(%q<right_support>, ["~> 2.0"])
      s.add_runtime_dependency(%q<builder>, ["~> 3.0"])
      s.add_runtime_dependency(%q<rspec>, ["< 3.0", ">= 1.3"])
      s.add_runtime_dependency(%q<cucumber>, ["~> 1.0"])
      s.add_runtime_dependency(%q<trollop>, ["< 3.0", ">= 1.0"])
      s.add_runtime_dependency(%q<actionpack>, ["< 4.0", ">= 2.3.0"])
      s.add_development_dependency(%q<jeweler>, ["~> 1.8.3"])
      s.add_development_dependency(%q<rdoc>, [">= 2.4.2"])
      s.add_development_dependency(%q<syntax>, ["~> 1.0.0"])
      s.add_development_dependency(%q<nokogiri>, ["~> 1.5"])
      s.add_development_dependency(%q<flexmock>, ["~> 0.8.7"])
      s.add_development_dependency(%q<activesupport>, [">= 0"])
      s.add_development_dependency(%q<libxml-ruby>, ["~> 2.4.0"])
      s.add_development_dependency(%q<jeweler>, ["~> 1.8.3"])
      s.add_development_dependency(%q<rdoc>, [">= 2.4.2"])
      s.add_development_dependency(%q<syntax>, ["~> 1.0.0"])
      s.add_development_dependency(%q<nokogiri>, ["~> 1.5"])
      s.add_development_dependency(%q<flexmock>, ["~> 0.8.7"])
      s.add_development_dependency(%q<activesupport>, [">= 0"])
      s.add_development_dependency(%q<libxml-ruby>, ["~> 2.4.0"])
      s.add_development_dependency(%q<jeweler>, ["~> 1.8.3"])
      s.add_development_dependency(%q<rdoc>, [">= 2.4.2"])
      s.add_development_dependency(%q<syntax>, ["~> 1.0.0"])
      s.add_development_dependency(%q<nokogiri>, ["~> 1.5"])
      s.add_development_dependency(%q<flexmock>, ["~> 0.8.7"])
      s.add_development_dependency(%q<activesupport>, [">= 0"])
      s.add_development_dependency(%q<libxml-ruby>, ["~> 2.4.0"])
      s.add_development_dependency(%q<jeweler>, ["~> 1.8.3"])
      s.add_development_dependency(%q<rdoc>, [">= 2.4.2"])
      s.add_development_dependency(%q<syntax>, ["~> 1.0.0"])
      s.add_development_dependency(%q<nokogiri>, ["~> 1.5"])
      s.add_development_dependency(%q<flexmock>, ["~> 0.8.7"])
      s.add_development_dependency(%q<activesupport>, [">= 0"])
      s.add_development_dependency(%q<libxml-ruby>, ["~> 2.4.0"])
      s.add_development_dependency(%q<jeweler>, ["~> 1.8.3"])
      s.add_development_dependency(%q<rdoc>, [">= 2.4.2"])
      s.add_development_dependency(%q<syntax>, ["~> 1.0.0"])
      s.add_development_dependency(%q<nokogiri>, ["~> 1.5"])
      s.add_development_dependency(%q<flexmock>, ["~> 0.8.7"])
      s.add_development_dependency(%q<activesupport>, [">= 0"])
      s.add_development_dependency(%q<libxml-ruby>, ["~> 2.4.0"])
      s.add_development_dependency(%q<jeweler>, ["~> 1.8.3"])
      s.add_development_dependency(%q<rdoc>, [">= 2.4.2"])
      s.add_development_dependency(%q<syntax>, ["~> 1.0.0"])
      s.add_development_dependency(%q<nokogiri>, ["~> 1.5"])
      s.add_development_dependency(%q<flexmock>, ["~> 0.8.7"])
      s.add_development_dependency(%q<activesupport>, [">= 0"])
      s.add_development_dependency(%q<libxml-ruby>, ["~> 2.4.0"])
      s.add_development_dependency(%q<jeweler>, ["~> 1.8.3"])
      s.add_development_dependency(%q<rdoc>, [">= 2.4.2"])
      s.add_development_dependency(%q<syntax>, ["~> 1.0.0"])
      s.add_development_dependency(%q<nokogiri>, ["~> 1.5"])
      s.add_development_dependency(%q<jeweler>, ["~> 1.8.3"])
      s.add_development_dependency(%q<rdoc>, [">= 2.4.2"])
      s.add_development_dependency(%q<syntax>, ["~> 1.0.0"])
      s.add_development_dependency(%q<nokogiri>, ["~> 1.5"])
      s.add_development_dependency(%q<jeweler>, ["~> 1.8.3"])
      s.add_development_dependency(%q<rdoc>, [">= 2.4.2"])
      s.add_development_dependency(%q<syntax>, ["~> 1.0.0"])
      s.add_development_dependency(%q<nokogiri>, ["~> 1.5"])
    else
      s.add_dependency(%q<rake>, ["< 0.10", ">= 0.8.7"])
      s.add_dependency(%q<right_support>, ["~> 2.0"])
      s.add_dependency(%q<builder>, ["~> 3.0"])
      s.add_dependency(%q<rspec>, ["< 3.0", ">= 1.3"])
      s.add_dependency(%q<cucumber>, ["~> 1.0"])
      s.add_dependency(%q<trollop>, ["< 3.0", ">= 1.0"])
      s.add_dependency(%q<actionpack>, ["< 4.0", ">= 2.3.0"])
      s.add_dependency(%q<jeweler>, ["~> 1.8.3"])
      s.add_dependency(%q<rdoc>, [">= 2.4.2"])
      s.add_dependency(%q<syntax>, ["~> 1.0.0"])
      s.add_dependency(%q<nokogiri>, ["~> 1.5"])
      s.add_dependency(%q<flexmock>, ["~> 0.8.7"])
      s.add_dependency(%q<activesupport>, [">= 0"])
      s.add_dependency(%q<libxml-ruby>, ["~> 2.4.0"])
      s.add_dependency(%q<jeweler>, ["~> 1.8.3"])
      s.add_dependency(%q<rdoc>, [">= 2.4.2"])
      s.add_dependency(%q<syntax>, ["~> 1.0.0"])
      s.add_dependency(%q<nokogiri>, ["~> 1.5"])
      s.add_dependency(%q<flexmock>, ["~> 0.8.7"])
      s.add_dependency(%q<activesupport>, [">= 0"])
      s.add_dependency(%q<libxml-ruby>, ["~> 2.4.0"])
      s.add_dependency(%q<jeweler>, ["~> 1.8.3"])
      s.add_dependency(%q<rdoc>, [">= 2.4.2"])
      s.add_dependency(%q<syntax>, ["~> 1.0.0"])
      s.add_dependency(%q<nokogiri>, ["~> 1.5"])
      s.add_dependency(%q<flexmock>, ["~> 0.8.7"])
      s.add_dependency(%q<activesupport>, [">= 0"])
      s.add_dependency(%q<libxml-ruby>, ["~> 2.4.0"])
      s.add_dependency(%q<jeweler>, ["~> 1.8.3"])
      s.add_dependency(%q<rdoc>, [">= 2.4.2"])
      s.add_dependency(%q<syntax>, ["~> 1.0.0"])
      s.add_dependency(%q<nokogiri>, ["~> 1.5"])
      s.add_dependency(%q<flexmock>, ["~> 0.8.7"])
      s.add_dependency(%q<activesupport>, [">= 0"])
      s.add_dependency(%q<libxml-ruby>, ["~> 2.4.0"])
      s.add_dependency(%q<jeweler>, ["~> 1.8.3"])
      s.add_dependency(%q<rdoc>, [">= 2.4.2"])
      s.add_dependency(%q<syntax>, ["~> 1.0.0"])
      s.add_dependency(%q<nokogiri>, ["~> 1.5"])
      s.add_dependency(%q<flexmock>, ["~> 0.8.7"])
      s.add_dependency(%q<activesupport>, [">= 0"])
      s.add_dependency(%q<libxml-ruby>, ["~> 2.4.0"])
      s.add_dependency(%q<jeweler>, ["~> 1.8.3"])
      s.add_dependency(%q<rdoc>, [">= 2.4.2"])
      s.add_dependency(%q<syntax>, ["~> 1.0.0"])
      s.add_dependency(%q<nokogiri>, ["~> 1.5"])
      s.add_dependency(%q<flexmock>, ["~> 0.8.7"])
      s.add_dependency(%q<activesupport>, [">= 0"])
      s.add_dependency(%q<libxml-ruby>, ["~> 2.4.0"])
      s.add_dependency(%q<jeweler>, ["~> 1.8.3"])
      s.add_dependency(%q<rdoc>, [">= 2.4.2"])
      s.add_dependency(%q<syntax>, ["~> 1.0.0"])
      s.add_dependency(%q<nokogiri>, ["~> 1.5"])
      s.add_dependency(%q<jeweler>, ["~> 1.8.3"])
      s.add_dependency(%q<rdoc>, [">= 2.4.2"])
      s.add_dependency(%q<syntax>, ["~> 1.0.0"])
      s.add_dependency(%q<nokogiri>, ["~> 1.5"])
      s.add_dependency(%q<jeweler>, ["~> 1.8.3"])
      s.add_dependency(%q<rdoc>, [">= 2.4.2"])
      s.add_dependency(%q<syntax>, ["~> 1.0.0"])
      s.add_dependency(%q<nokogiri>, ["~> 1.5"])
    end
  else
    s.add_dependency(%q<rake>, ["< 0.10", ">= 0.8.7"])
    s.add_dependency(%q<right_support>, ["~> 2.0"])
    s.add_dependency(%q<builder>, ["~> 3.0"])
    s.add_dependency(%q<rspec>, ["< 3.0", ">= 1.3"])
    s.add_dependency(%q<cucumber>, ["~> 1.0"])
    s.add_dependency(%q<trollop>, ["< 3.0", ">= 1.0"])
    s.add_dependency(%q<actionpack>, ["< 4.0", ">= 2.3.0"])
    s.add_dependency(%q<jeweler>, ["~> 1.8.3"])
    s.add_dependency(%q<rdoc>, [">= 2.4.2"])
    s.add_dependency(%q<syntax>, ["~> 1.0.0"])
    s.add_dependency(%q<nokogiri>, ["~> 1.5"])
    s.add_dependency(%q<flexmock>, ["~> 0.8.7"])
    s.add_dependency(%q<activesupport>, [">= 0"])
    s.add_dependency(%q<libxml-ruby>, ["~> 2.4.0"])
    s.add_dependency(%q<jeweler>, ["~> 1.8.3"])
    s.add_dependency(%q<rdoc>, [">= 2.4.2"])
    s.add_dependency(%q<syntax>, ["~> 1.0.0"])
    s.add_dependency(%q<nokogiri>, ["~> 1.5"])
    s.add_dependency(%q<flexmock>, ["~> 0.8.7"])
    s.add_dependency(%q<activesupport>, [">= 0"])
    s.add_dependency(%q<libxml-ruby>, ["~> 2.4.0"])
    s.add_dependency(%q<jeweler>, ["~> 1.8.3"])
    s.add_dependency(%q<rdoc>, [">= 2.4.2"])
    s.add_dependency(%q<syntax>, ["~> 1.0.0"])
    s.add_dependency(%q<nokogiri>, ["~> 1.5"])
    s.add_dependency(%q<flexmock>, ["~> 0.8.7"])
    s.add_dependency(%q<activesupport>, [">= 0"])
    s.add_dependency(%q<libxml-ruby>, ["~> 2.4.0"])
    s.add_dependency(%q<jeweler>, ["~> 1.8.3"])
    s.add_dependency(%q<rdoc>, [">= 2.4.2"])
    s.add_dependency(%q<syntax>, ["~> 1.0.0"])
    s.add_dependency(%q<nokogiri>, ["~> 1.5"])
    s.add_dependency(%q<flexmock>, ["~> 0.8.7"])
    s.add_dependency(%q<activesupport>, [">= 0"])
    s.add_dependency(%q<libxml-ruby>, ["~> 2.4.0"])
    s.add_dependency(%q<jeweler>, ["~> 1.8.3"])
    s.add_dependency(%q<rdoc>, [">= 2.4.2"])
    s.add_dependency(%q<syntax>, ["~> 1.0.0"])
    s.add_dependency(%q<nokogiri>, ["~> 1.5"])
    s.add_dependency(%q<flexmock>, ["~> 0.8.7"])
    s.add_dependency(%q<activesupport>, [">= 0"])
    s.add_dependency(%q<libxml-ruby>, ["~> 2.4.0"])
    s.add_dependency(%q<jeweler>, ["~> 1.8.3"])
    s.add_dependency(%q<rdoc>, [">= 2.4.2"])
    s.add_dependency(%q<syntax>, ["~> 1.0.0"])
    s.add_dependency(%q<nokogiri>, ["~> 1.5"])
    s.add_dependency(%q<flexmock>, ["~> 0.8.7"])
    s.add_dependency(%q<activesupport>, [">= 0"])
    s.add_dependency(%q<libxml-ruby>, ["~> 2.4.0"])
    s.add_dependency(%q<jeweler>, ["~> 1.8.3"])
    s.add_dependency(%q<rdoc>, [">= 2.4.2"])
    s.add_dependency(%q<syntax>, ["~> 1.0.0"])
    s.add_dependency(%q<nokogiri>, ["~> 1.5"])
    s.add_dependency(%q<jeweler>, ["~> 1.8.3"])
    s.add_dependency(%q<rdoc>, [">= 2.4.2"])
    s.add_dependency(%q<syntax>, ["~> 1.0.0"])
    s.add_dependency(%q<nokogiri>, ["~> 1.5"])
    s.add_dependency(%q<jeweler>, ["~> 1.8.3"])
    s.add_dependency(%q<rdoc>, [">= 2.4.2"])
    s.add_dependency(%q<syntax>, ["~> 1.0.0"])
    s.add_dependency(%q<nokogiri>, ["~> 1.5"])
  end
end


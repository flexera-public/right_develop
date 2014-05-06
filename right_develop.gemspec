# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{right_develop}
  s.version = "2.2.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Tony Spataro"]
  s.date = %q{2014-04-28}
  s.default_executable = %q{right_develop}
  s.description = %q{A toolkit of development tools created by RightScale.}
  s.email = %q{support@rightscale.com}
  s.executables = ["right_develop"]
  s.extra_rdoc_files = [
    "LICENSE",
    "README.rdoc"
  ]
  s.files = [
    "CHANGELOG.rdoc",
    "LICENSE",
    "README.rdoc",
    "Rakefile",
    "VERSION",
    "bin/right_develop",
    "lib/right_develop.rb",
    "lib/right_develop/ci.rb",
    "lib/right_develop/ci/java_cucumber_formatter.rb",
    "lib/right_develop/ci/java_spec_formatter.rb",
    "lib/right_develop/ci/rake_task.rb",
    "lib/right_develop/ci/util.rb",
    "lib/right_develop/commands.rb",
    "lib/right_develop/commands/git.rb",
    "lib/right_develop/commands/server.rb",
    "lib/right_develop/git.rb",
    "lib/right_develop/git/rake_task.rb",
    "lib/right_develop/net.rb",
    "lib/right_develop/parsers.rb",
    "lib/right_develop/parsers/sax_parser.rb",
    "lib/right_develop/parsers/xml_post_parser.rb",
    "lib/right_develop/s3.rb",
    "lib/right_develop/s3/interface.rb",
    "lib/right_develop/s3/rake_task.rb",
    "lib/right_develop/testing.rb",
    "lib/right_develop/testing/clients.rb",
    "lib/right_develop/testing/clients/rest.rb",
    "lib/right_develop/testing/clients/rest/requests.rb",
    "lib/right_develop/testing/clients/rest/requests/base.rb",
    "lib/right_develop/testing/clients/rest/requests/playback.rb",
    "lib/right_develop/testing/clients/rest/requests/record.rb",
    "lib/right_develop/testing/recording.rb",
    "lib/right_develop/testing/recording/config.rb",
    "lib/right_develop/testing/recording/metadata.rb",
    "lib/right_develop/testing/servers/might_api/.gitignore",
    "lib/right_develop/testing/servers/might_api/Gemfile",
    "lib/right_develop/testing/servers/might_api/Gemfile.lock",
    "lib/right_develop/testing/servers/might_api/app/base.rb",
    "lib/right_develop/testing/servers/might_api/app/echo.rb",
    "lib/right_develop/testing/servers/might_api/app/playback.rb",
    "lib/right_develop/testing/servers/might_api/app/record.rb",
    "lib/right_develop/testing/servers/might_api/config.ru",
    "lib/right_develop/testing/servers/might_api/config/init.rb",
    "lib/right_develop/testing/servers/might_api/lib/config.rb",
    "lib/right_develop/testing/servers/might_api/lib/logger.rb",
    "lib/right_develop/utility.rb",
    "lib/right_develop/utility/git.rb",
    "lib/right_develop/utility/shell.rb",
    "lib/right_develop/utility/versioning.rb",
    "right_develop.gemspec",
    "right_develop.rconf"
  ]
  s.homepage = %q{https://github.com/rightscale/right_develop}
  s.licenses = ["MIT"]
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.7}
  s.summary = %q{Reusable dev & test code.}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<rake>, [">= 0.8.7", "< 0.10"])
      s.add_runtime_dependency(%q<right_support>, ["~> 2.0"])
      s.add_runtime_dependency(%q<builder>, ["~> 3.0"])
      s.add_runtime_dependency(%q<rspec>, [">= 1.3", "< 3.0"])
      s.add_runtime_dependency(%q<cucumber>, ["~> 1.0", "< 1.3.3"])
      s.add_runtime_dependency(%q<trollop>, [">= 1.0", "< 3.0"])
      s.add_runtime_dependency(%q<right_git>, ["~> 0.1.0"])
      s.add_runtime_dependency(%q<right_aws>, [">= 2.1.0"])
      s.add_runtime_dependency(%q<extlib>, [">= 0"])
      s.add_runtime_dependency(%q<rack>, [">= 0"])
      s.add_development_dependency(%q<jeweler>, ["~> 1.8.3"])
      s.add_development_dependency(%q<rdoc>, [">= 2.4.2"])
    else
      s.add_dependency(%q<rake>, [">= 0.8.7", "< 0.10"])
      s.add_dependency(%q<right_support>, ["~> 2.0"])
      s.add_dependency(%q<builder>, ["~> 3.0"])
      s.add_dependency(%q<rspec>, [">= 1.3", "< 3.0"])
      s.add_dependency(%q<cucumber>, ["~> 1.0", "< 1.3.3"])
      s.add_dependency(%q<trollop>, [">= 1.0", "< 3.0"])
      s.add_dependency(%q<right_git>, ["~> 0.1.0"])
      s.add_dependency(%q<right_aws>, [">= 2.1.0"])
      s.add_dependency(%q<extlib>, [">= 0"])
      s.add_dependency(%q<rack>, [">= 0"])
      s.add_dependency(%q<jeweler>, ["~> 1.8.3"])
      s.add_dependency(%q<rdoc>, [">= 2.4.2"])
    end
  else
    s.add_dependency(%q<rake>, [">= 0.8.7", "< 0.10"])
    s.add_dependency(%q<right_support>, ["~> 2.0"])
    s.add_dependency(%q<builder>, ["~> 3.0"])
    s.add_dependency(%q<rspec>, [">= 1.3", "< 3.0"])
    s.add_dependency(%q<cucumber>, ["~> 1.0", "< 1.3.3"])
    s.add_dependency(%q<trollop>, [">= 1.0", "< 3.0"])
    s.add_dependency(%q<right_git>, ["~> 0.1.0"])
    s.add_dependency(%q<right_aws>, [">= 2.1.0"])
    s.add_dependency(%q<extlib>, [">= 0"])
    s.add_dependency(%q<rack>, [">= 0"])
    s.add_dependency(%q<jeweler>, ["~> 1.8.3"])
    s.add_dependency(%q<rdoc>, [">= 2.4.2"])
  end
end


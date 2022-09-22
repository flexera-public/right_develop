# encoding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'right_develop/version'

Gem::Specification.new do |spec|
  spec.name = 'right_develop'
  spec.version = ::RightDevelop::VERSION
  spec.authors = ['Tony Spataro', 'Scott Messier']
  spec.description = 'A toolkit of development tools created by RightScale.'
  spec.email = 'support@rightscale.com'
  spec.homepage = 'https://github.com/rightscale/right_develop'
  spec.licenses = ['MIT']
  spec.summary = 'Reusable dev & test code.'

  spec.executables = ['right_develop']
  spec.extra_rdoc_files = [
    'CHANGELOG.md',
    'LICENSE',
    'README.md'
  ]
  spec.files  = `git ls-files -z`.split("\x0").select { |f| f.match(%r{lib/|gemspec}) }
  spec.require_paths = ['lib']

  spec.required_ruby_version = Gem::Requirement.new('~> 2.1')

  spec.add_runtime_dependency(%q<right_support>, ['~> 2.14'])
  spec.add_runtime_dependency(%q<builder>, [">= 2.1.2"])
  spec.add_runtime_dependency(%q<trollop>, ["< 3.0", ">= 1.0"])
  spec.add_runtime_dependency(%q<right_git>, [">= 1.0"])
  spec.add_runtime_dependency(%q<right_aws>, [">= 2.1.0"])
  spec.add_runtime_dependency(%q<rack>, [">= 0"])
end

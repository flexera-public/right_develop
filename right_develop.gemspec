# -*- mode: ruby; encoding: utf-8 -*-

require 'rubygems'

spec = Gem::Specification.new do |s|
  s.required_rubygems_version = nil if s.respond_to? :required_rubygems_version=
  s.required_ruby_version = Gem::Requirement.new(">= 1.8.7")

  s.name    = 'right_develop'
  s.version = '1.0.0'
  s.date    = '2013-01-25'

  s.authors = ['Tony Spataro']
  s.email   = 'support@rightscale.com'
  s.homepage= 'https://github.com/rightscale/right_develop'

  s.summary = %q{Reusable dev & test code.}
  s.description = %q{A toolkit of development tools created by RightScale.}

  basedir = File.dirname(__FILE__)
  candidates = ['right_develop.gemspec', 'LICENSE', 'README.rdoc'] + Dir['lib/**/*']
  s.files = candidates.sort

  s.add_runtime_dependency(%q<right_support>, ["~> 2.0"])
  s.add_runtime_dependency(%q<builder>, ["~> 3.0"])
  s.add_runtime_dependency(%q<rspec>, [">= 1.3", "< 3.0"])
  s.add_runtime_dependency(%q<cucumber>, ["~> 1.0"])
end

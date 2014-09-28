require 'nokogiri'

Given /^a Ruby application$/ do
  ruby_app_root.should_not be_nil
end

Given /^a Gemfile$/ do
  gemfile = ruby_app_path('Gemfile')
  unless File.exist?(gemfile)
    basedir = File.expand_path('../../..', __FILE__)
    File.open(gemfile, 'w') do |file|
      file.puts "source 'https://rubygems.org'"
      file.puts "gem 'right_develop', :path=>'#{basedir}'"
    end
  end
end

Given /^a gem dependency on '(.*)'$/ do |dependency|
  step 'a Gemfile'
  gem, version = dependency.split(/\s+/, 2)
  gemfile = ruby_app_path('Gemfile')
  File.open(gemfile, 'a') do |file|
    file.puts "gem '#{gem}', '#{version}'"
  end
end

Given /^a Rakefile$/ do
  rakefile = ruby_app_path('Rakefile')
  unless File.exist?(rakefile)
    File.open(rakefile, 'w') do |file|
      file.puts "# Auto-generated by #{__FILE__}"
    end
  end
end

Given /^the Rakefile contains a ([A-Za-z0-9:]+)::RakeTask$/ do |mod|
  step 'a Rakefile'
  rakefile = ruby_app_path('Rakefile')
  File.open(rakefile, 'w') do |file|
    file.puts "require 'right_develop'"
    file.puts "#{mod}::RakeTask.new"
  end
end

Given /^the Rakefile contains a ([A-Za-z0-9:]+)::RakeTask with parameter '(.*)'$/ do |mod, ns|
  step 'a Rakefile'
  rakefile = ruby_app_path('Rakefile')
  File.open(rakefile, 'w') do |file|
    file.puts "require 'right_develop'"
    file.puts "#{mod}::RakeTask.new(#{ns})"
  end
end

Given /^the Rakefile contains:$/ do |content|
  step 'a Rakefile'
  rakefile = ruby_app_path('Rakefile')
  File.open(rakefile, 'w') do |file|
    file.puts "require 'right_develop'"
    content.split("\n").each do |line|
      file.puts line
    end
  end
end

Given /^a trivial (failing|pending)? ?RSpec spec$/ do |failing_pending|
  spec_dir = ruby_app_path('spec')
  spec = ruby_app_path('spec', 'trivial_spec.rb')
  FileUtils.mkdir_p(spec_dir)
  File.open(spec, 'w') do |file|
    # always include one passing test case as a baseline
    file.puts "describe String do"
    file.puts "  it 'has a size' do"
    file.puts "    'joe'.size.should == 3"
    file.puts "  end"

    case failing_pending
    when 'failing'
      # include a failing spec
      file.puts
      file.puts "it 'meets an impossible ideal' do"
      file.puts "  raise NotImplementedError, 'inconceivable!'"
      file.puts "end"
    when 'pending'
      # include two pending specs: one implicit and one explicit
      file.puts
      file.puts "it 'supports some awesome new feature' do"
      file.puts "  pending"
      file.puts "  1.should == 2"
      file.puts "end"
      file.puts ""
      file.puts "it 'has some useful behavior'"
    else
      # no further examples
    end

    file.puts "end"
  end
end

Given /^an RSpec spec named '([A-Za-z0-9_.]+)' with content:$/ do |name, content|
  spec_dir = ruby_app_path('spec')
  spec = ruby_app_path('spec', name)
  FileUtils.mkdir_p(spec_dir)
  File.open(spec, 'w') do |file|
    content.split("\n").each do |line|
      file.puts line
    end
  end
end

Given /^a trivial (failing )?Cucumber feature$/ do |failing|
  features_dir = ruby_app_path('features')
  steps_dir    = ruby_app_path('features', 'step_definitions')
  feature      = ruby_app_path('features', 'trivial.feature')
  steps        = ruby_app_path('features', 'step_definitions', 'trivial_steps.rb')
  FileUtils.mkdir_p(features_dir)
  FileUtils.mkdir_p(steps_dir)

  unless File.exist?(steps)
    File.open(steps, 'w') do |file|
      file.puts "When /^the night has come and the land is dark$/ do; end"
      file.puts "When /^the moon is the only light we see$/ do; end"
      file.puts "Then /^I won't be afraid.*$/ do; end"
      file.puts "Then /^as long as you stand.*by me$/ do; end"
      file.puts "Then /^you run away as fast as you can$/ do; raise NotImplementedError; end"
    end
  end
  unless File.exist?(feature)
    File.open(feature, 'w') do |file|
      file.puts "Feature: Song Lyrics from the 1950s"
      file.puts
      file.puts "  Scenario: Stand By Me"
      file.puts "    When the night has come and the land is dark"
      file.puts "    And the moon is the only light we see"
      file.puts "    Then I won't be afraid, oh, I won't be afraid"
      if failing.nil?
        file.puts "    And as long as you stand, stand by me"
      else
        file.puts "    And you run away as fast as you can"
      end
    end
  end
end

When /^I install the bundle$/ do
  ruby_app_shell('bundle check || bundle install --local || bundle install')
end

When /^I rake '(.*)'$/ do |task|
  @ruby_app_output = ruby_app_shell("bundle exec rake #{task} --trace ", :ignore_errors => true)
end

Then /^the command should (succeed|fail)$/ do |success|
  if success == 'succeed'
    $?.exitstatus.should == 0
  elsif success == 'fail'
    $?.exitstatus.should_not == 0
  else
    raise NotImplementedError, "Unknown expectation #{success}"
  end
end
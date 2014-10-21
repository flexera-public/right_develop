When /^I install the bundle$/ do
  ruby_app_shell('bundle check || bundle install --local || bundle install')
end

When /^I bundle exec '(.*)'$/ do |command|
  @ruby_app_output = ruby_app_shell("bundle exec #{command}", :ignore_errors => true)
end

When /^I rake '(.*)'$/ do |task|
  @ruby_app_output = ruby_app_shell("bundle exec rake #{task} --trace", :ignore_errors => true)
end

# Bundler doesn't seem to install binstubs when a gem is declared using the :path option, meaning
# that we need to invoke right_develop's CLI tool using an absolute path. Bit of a hack...
When /^I invoke right_develop with '(.*)'$/ do |args|
  bin = File.expand_path('../../../bin/right_develop', __FILE__)
  step "I bundle exec '#{bin} #{args}'"
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

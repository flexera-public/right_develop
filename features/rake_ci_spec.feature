Feature: Rake CI integration
  In order to promote reuse of development tools
  RightDevelop should expose Continuous Integration tasks via Rake

  Background:
    Given a Ruby application
    And a Gemfile
    And a gem dependency on 'rake ~> 0.9'
    And a gem dependency on 'rspec ~> 3.0'

  Scenario: list CI tasks
    Given the Rakefile contains a RightDevelop::CI::RakeTask
    When I install the bundle
    And I rake '-T'
    And the output should contain 'ci:spec'

  Scenario: override CI namespace
    Given the Rakefile contains:
    """
    RightDevelop::CI::RakeTask.new do |task|
      task.ci_namespace = :funkalicious
    end
    """
    When I install the bundle
    And I rake '-T'
    And the output should contain 'funkalicious:spec'

  Scenario: override CI task names and descriptions
    Given the Rakefile contains:
    """
    RightDevelop::CI::RakeTask.new do |task|
      task.rspec_name    = :rspeck
      task.rspec_desc    = "My RSpec task"
    end
    """
    When I install the bundle
    And I rake '-T'
    And the output should contain 'ci:rspeck'
    And the output should contain 'My RSpec task'

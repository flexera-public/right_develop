Feature: Rake CI integration
  In order to promote reuse of development tools
  RightDevelop should expose Continuous Integration tasks via Rake

  Background:
    Given a Ruby application
    And a Gemfile
    And a gem dependency on 'rake ~> 0.9'
    And a gem dependency on 'cucumber <= 1.3.3'

  Scenario: list CI tasks
    Given the Rakefile contains a RightDevelop::CI::RakeTask
    When I install the bundle
    And I rake '-T'
    Then the output should contain 'ci:cucumber'

  Scenario: override CI namespace
    Given the Rakefile contains:
    """
    RightDevelop::CI::RakeTask.new do |task|
      task.ci_namespace = :funkalicious
    end
    """
    When I install the bundle
    And I rake '-T'
    Then the output should contain 'funkalicious:cucumber'

  Scenario: override CI task names and descriptions
    Given the Rakefile contains:
    """
    RightDevelop::CI::RakeTask.new do |task|
      task.cucumber_name = :cukes
      task.cucumber_desc = "My Cucumber task"
    end
    """
    When I install the bundle
    And I rake '-T'
    Then the output should contain 'ci:cukes'
    And the output should contain 'My Cucumber task'

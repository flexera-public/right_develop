Feature: conditional Rake integration
  In order to facilitate TDD and enhance code quality
  RightDevelop should limit Rake integration to just the frameworks in use
  So developers aren't presented with useless Rake tasks

  Background:
    Given a Ruby application
    And a Gemfile
    And a gem dependency on 'rake ~> 0.9'
    And the Rakefile contains a RightDevelop::CI::RakeTask

  Scenario: conditional Cucumber integration
    Given a gem dependency on 'cucumber ~> 1.0'
    When I install the bundle
    When I rake '-T'
    Then the command should succeed
    And the output should contain 'ci:cucumber'
    And the output should not contain 'ci:spec'

  Scenario: conditional RSpec integration
    Given a gem dependency on 'rspec ~> 3.0'
    When I install the bundle
    When I rake '-T'
    Then the command should succeed
    And the output should contain 'ci:spec'
    And the output should not contain 'ci:cucumber'

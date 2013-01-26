Feature: Rake integration
  In order to promote predictable, reliable Continuous Integration
  RightDevelop should expose a "ci:" Rake namespace

  Background:
    Given a Ruby application
    And a Gemfile
    And a gem dependency on 'rake ~> 0.9'

  Scenario: list Rake tasks
    Given the Rakefile contains a RightDevelop::CI::RakeTask
    When I install the bundle
    And I rake '-T'
    And the output should contain 'ci:cucumber'
    And the output should contain 'ci:spec'

  Scenario: override namespace
    Given the Rakefile contains a RightDevelop::CI::RakeTask with parameter ':funkalicious'
    When I install the bundle
    And I rake '-T'
    Then the output should contain 'funkalicious:cucumber'
    Then the output should contain 'funkalicious:spec'

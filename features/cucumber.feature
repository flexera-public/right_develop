Feature: Cucumber 1.x support
  In order to facilitate TDD and enhance code quality
  RightDevelop should provide CI tasks with Cucumber with JUnit XML output
  So any Ruby project can have a beautiful, info-rich Jenkins project

  Background:
    Given a Ruby application
    And a Gemfile
    And a gem dependency on 'rake ~> 0.9'
    And a gem dependency on 'cucumber ~> 1.0'
    And the Rakefile contains a RightDevelop::CI::RakeTask

  Scenario: passing Cucumber features
    Given a trivial Cucumber feature
    When I install the bundle
    And I rake 'ci:cucumber'
    Then the command should succeed
    And the output should contain '** Execute ci:cucumber'
    And the directory 'measurement/cucumber' should contain files

  Scenario: failing Cucumber features
    Given a trivial failing Cucumber feature
    When I install the bundle
    And I rake 'ci:cucumber'
    Then the command should fail
    And the output should contain '** Execute ci:cucumber'
    And the directory 'measurement/cucumber' should contain files

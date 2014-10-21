Feature: command-line interface
  In order to facilitate TDD and enhance code quality
  RightDevelop should provide CI tasks with Cucumber with JUnit XML output
  So any Ruby project can have a beautiful, info-rich Jenkins project

  Background:
    Given a Ruby application
    And a Gemfile
    When I install the bundle

  Scenario: usage information
    When I invoke right_develop with '--help'
    Then the command should succeed
    And the output should contain 'Usage:'
    And the output should contain 'Where <command> is one of:'
    And the output should contain 'To get help on a command:'

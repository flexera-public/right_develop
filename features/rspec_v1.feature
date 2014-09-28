Feature: RSpec 1.x support
  In order to facilitate TDD and enhance code quality
  RightDevelop should provide a Rake CI harness with JUnit XML output
  So any Ruby project can have a beautiful, info-rich Jenkins project

  Background:
    Given a Ruby application
    And a Gemfile
    And a gem dependency on 'rake ~> 0.9'
    And a gem dependency on 'rspec ~> 1.0'
    And the Rakefile contains a RightDevelop::CI::RakeTask
    When I install the bundle

  Scenario: passing examples
    Given a trivial RSpec spec
    When I rake 'ci:spec'
    Then the command should succeed
    And the file 'measurement/rspec/rspec.xml' should mention 1 passing test case
    And the output should contain 1 '.' progress ticks
    And the output should contain '1 example'

  Scenario: failing examples
    Given a trivial failing RSpec spec
    When I rake 'ci:spec'
    Then the command should fail
    And the file 'measurement/rspec/rspec.xml' should mention 1 failing test case
    And the output should contain 1 'F' progress ticks
    And the output should contain '1 failure'

  Scenario: pending examples
    Given a trivial pending RSpec spec
    When I rake 'ci:spec'
    Then the command should succeed
    And the file 'measurement/rspec/rspec.xml' should mention 2 skipped test case
    And the output should contain 2 '*' progress ticks
    And the output should contain '2 pending'

  Scenario: color console output
    Given a trivial failing RSpec spec
    When I rake 'ci:spec'
    Then the output should have ANSI color

  Scenario: override input file pattern
    Given an RSpec spec named 'passing_spec.rb' with content:
    """
    describe String do
      it 'is cool' do
        'cool'.should == 'cool'
      end
    end
    """
    And an RSpec spec named 'failing_spec.rb' with content:
    """
    describe String do
      it 'is uncool' do
        'cool'.should == 'uncool'
      end
    end
    """
    And the Rakefile contains:
    """
    RightDevelop::CI::RakeTask.new do |task|
      task.rspec_pattern = 'spec/passing_spec.rb'
    end
    """
    When I rake 'ci:spec'
    Then the command should succeed

  Scenario: override output file location
    Given a trivial RSpec spec
    And the Rakefile contains:
    """
    RightDevelop::CI::RakeTask.new do |task|
      task.rspec_output = 'awesome.xml'
    end
    """
    When I rake 'ci:spec'
    Then the command should succeed
    And the file 'measurement/rspec/awesome.xml' should exist

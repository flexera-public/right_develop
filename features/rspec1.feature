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

  Scenario: passing RSpec 1.x examples
    Given a trivial RSpec spec
    When I install the bundle
    And I rake 'ci:spec'
    Then the command should succeed
    And the file 'measurement/rspec/rspec.xml' should mention 2 passing test cases
    And the file 'measurement/rspec/rspec.xml' should mention 0 failing test cases

  Scenario: failing RSpec 1.x examples
    Given a trivial failing RSpec spec
    When I install the bundle
    And I rake 'ci:spec'
    Then the command should fail
    And the file 'measurement/rspec/rspec.xml' should mention 2 passing test cases
    And the file 'measurement/rspec/rspec.xml' should mention 1 failing test case

  Scenario: override spec files
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
    When I install the bundle
    And I rake 'ci:spec'
    Then the command should succeed

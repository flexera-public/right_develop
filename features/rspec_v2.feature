Feature: RSpec 2.x support
  In order to facilitate TDD and enhance code quality
  RightDevelop should provide a Rake CI harness with JUnit XML output
  So any Ruby project can have beautiful, info-rich Jenkins reports

  Background:
    Given a Ruby application
    And a Gemfile
    And a gem dependency on 'rake ~> 0.9'
    And a gem dependency on 'rspec ~> 2.0'
    And the Rakefile contains a RightDevelop::CI::RakeTask
    When I install the bundle

  Scenario: passing examples
    Given a trivial RSpec spec
    When I rake 'ci:spec'
    Then the command should succeed
    And the file 'measurement/rspec/rspec.xml' should mention 1 passing test case
    And the output should contain 1 '.' progress tick
    And the output should contain '1 example'

  Scenario: failing examples
    Given a trivial failing RSpec spec
    When I rake 'ci:spec'
    Then the command should fail
    And the file 'measurement/rspec/rspec.xml' should mention 1 failing test case
    And the output should contain 1 'F' progress tick
    And the output should contain '1 failure'

  Scenario: pending examples
    Given a trivial pending RSpec spec
    When I rake 'ci:spec'
    Then the command should succeed
    And the file 'measurement/rspec/rspec.xml' should mention 2 skipped test cases
    And the output should contain 2 '*' progress ticks
    And the output should contain '2 pending'

  Scenario: color console output
    Given a trivial failing RSpec spec
    When I rake 'ci:spec'
    Then the command should have ANSI color

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

  Scenario: add command-line options
    Given an RSpec spec named 'tagged_spec.rb' with content:
    """
    describe String, :string => true do
      it 'is cool' do
        'cool'.should == 'cool'
      end
    end
    describe Integer do
      it 'is zero' do
        1.should == 0
      end
    end
    """
    And the Rakefile contains:
    """
    RightDevelop::CI::RakeTask.new do |task|
      task.rspec_opts = ['-t', 'string']
    end
    """
    When I rake 'ci:spec'
    Then the command should succeed

  Scenario: with an overriden described_class
    Given an RSpec spec named 'described_class_spec.rb' with content:
    """
    describe String do
      metadata[:example_group][:described_class] = Integer

      it 'is not an integer' do
        "1".should == "1"
      end
    end
    """
    When I rake 'ci:spec'
    Then the command should succeed
    And the file 'measurement/rspec/rspec.xml' should not mention the class Integer
    And the file 'measurement/rspec/rspec.xml' should mention the class String

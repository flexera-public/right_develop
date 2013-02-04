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
    Given the Rakefile contains:
    """
    RightDevelop::CI::RakeTask.new do |task|
      task.ci_namespace = :funkalicious
    end
    """
    When I install the bundle
    And I rake '-T'
    Then the output should contain 'funkalicious:cucumber'
    Then the output should contain 'funkalicious:spec'

  Scenario: override spec files
    Given a gem dependency on 'rspec ~> 2.0'
    And an RSpec spec named 'passing_spec.rb' with content:
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
      task.rspec_files = 'passing_spec.rb'
    end
    """
    When I install the bundle
    And I rake 'ci:spec'
    Then the command should succeed

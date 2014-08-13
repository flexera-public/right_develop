Feature: Rake Git integration
  In order to promote reuse of development tools
  RightDevelop should expose Git tasks via Rake

  Background:
    Given a Ruby application
    And a Gemfile
    And a gem dependency on 'rake ~> 0.9'

  Scenario: list Git tasks
    Given the Rakefile contains a RightDevelop::Git::RakeTask
    When I install the bundle
    And I rake '-T'
    Then the output should contain 'git:setup'
    And the output should contain 'git:checkout[revision,base_dir]'
    And the output should contain 'git:verify[revision,base_dir]'

  Scenario: override Git namespace
    Given the Rakefile contains:
    """
    RightDevelop::Git::RakeTask.new do |task|
      task.git_namespace = :funkalicious
    end
    """
    When I install the bundle
    And I rake '-T'
    Then the output should contain 'funkalicious:setup'

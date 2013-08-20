Feature: basic Rake integration
  In order to promote reuse of development tools
  RightDevelop should expose some of its operations via Rake

  Background:
    Given a Ruby application
    And a Gemfile
    And a gem dependency on 'rake ~> 0.9'

  Scenario: list CI tasks
    Given the Rakefile contains a RightDevelop::CI::RakeTask
    When I install the bundle
    And I rake '-T'
    Then the output should contain 'ci:cucumber'
    And the output should contain 'ci:spec'

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
    And the output should contain 'funkalicious:spec'

  Scenario: list S3 tasks
    Given the Rakefile contains a RightDevelop::S3::RakeTask
    When I install the bundle
    And I rake '-T'
    Then the output should contain 's3:list_files'

  Scenario: override S3 namespace
    Given the Rakefile contains:
    """
    RightDevelop::S3::RakeTask.new do |task|
      task.s3_namespace = :funkalicious
    end
    """
    When I install the bundle
    And I rake '-T'
    Then the output should contain 'funkalicious:list_files'

  Scenario: list Git tasks
    Given the Rakefile contains a RightDevelop::Git::RakeTask
    When I install the bundle
    And I rake '-T'
    Then the output should contain 'git:setup'
    And the output should contain 'git:branch[revision,base_dir]'
    And the output should contain 'git:check[revision,base_dir]'

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

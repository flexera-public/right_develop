Feature: Rake S3 integration
  In order to promote reuse of development tools
  RightDevelop should expose S3 tasks via Rake

  Background:
    Given a Ruby application
    And a Gemfile
    And a gem dependency on 'rake ~> 0.9'

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

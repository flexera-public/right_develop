#
# Copyright (c) 2013 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# ancestor
require 'right_develop/utility'
require 'right_git'

module RightDevelop::Utility::Git

  DEFAULT_REPO_OPTIONS = {
    :shell  => ::RightDevelop::Utility::Shell
  }.freeze

  class VerifyError < StandardError; end

  module_function

  # Factory method for a default repository object from the current working
  # directory. The working directory can change but the repo directory is
  # preserved by the object.
  #
  # @return [RightGit::Git::Repository] new repository
  def default_repository
    ::RightGit::Git::Repository.new('.', DEFAULT_REPO_OPTIONS)
  end

  # Performs setup of the working directory repository for automation or
  # development. Currently this only involves initializing/updating submodules.
  #
  # @return [TrueClass] always true
  def setup
    default_repository.update_submodules(:recursive => true)
    true
  end

  # @return [TrueClass|FalseClass] true if the given revision is a commit SHA
  def is_sha?(revision)
    ::RightGit::Git::Commit.sha?(revision)
  end

  # Determine if the branch given by name exists.
  #
  # @param [String] branch_name to query
  # @param [Hash] options for query
  # @option options [TrueClass|FalseClass] :remote to find remote branches
  # @option options [TrueClass|FalseClass] :local to find local branches
  # @option options [RightGit::Git::Repository] :repo to use or nil
  #
  # @return [TrueClass|FalseClass] true if branch exists
  def branch_exists?(branch_name, options = {})
    options = {
      :remote => true,
      :local  => true,
      :repo   => nil
    }.merge(options)
    remote = options[:remote]
    local = options[:local]
    repo = options[:repo] || default_repository
    unless local || remote
      raise ::ArgumentError, 'Either remote or local must be true'
    end
    both = local && remote
    repo.branches(:all => remote).any? do |branch|
      branch.name == branch_name && (both || remote == branch.remote?)
    end
  end

  # Determine if the tag given by name exists.
  #
  # @param [String] tag_name to query
  # @param [Hash] options for query
  # @option options [RightGit::Git::Repository] :repo to use or nil
  #
  # @return [TrueClass|FalseClass] true if tag exists
  def tag_exists?(tag_name, options = {})
    options = {
      :repo => nil
    }.merge(options)
    repo = options[:repo] || default_repository

    # note that remote tags cannot be queried directly; use git fetch --tags to
    # import them first.
    repo.tags.any? { |tag| tag.name == tag_name }
  end

  # Clones the repo given by URL to the given destination (if any).
  #
  # @param [String] repo URL to clone
  # @param [String] destination path where repo is cloned
  #
  # @return [TrueClass] always true
  def clone_to(repo, destination)
    ::RightGit::Git::Repository.clone_to(repo, destination, DEFAULT_REPO_OPTIONS)
    true
  end

  # Generates a difference from the current workspace to the given commit on the
  # same branch as a sorted list of relative file paths. This is useful for
  # creating a list of files to patch, etc.
  #
  # @param [String] commit to diff from (e.g. 'master')
  # @return [String] list of relative file paths from diff or empty
  def diff_files_from(commit)
    git_args = ['diff', '--stat', '--name-only', commit]
    result = default_repository.git_output(git_args).lines.map { |line| line.strip }.sort
    # not sure if git would ever mention directories in a diff, but ignore them.
    result.delete_if { |item| ::File.directory?(item) }
    return result
  end

  # Checks out the given revision (tag, branch or SHA) and optionally creates a
  # new branch from it.
  #
  # @param [String] revision to checkout
  # @param [Hash] options for checkout
  # @option options [TrueClass|FalseClass] :force to perform hard reset and force checkout
  # @option options [String] :new_branch_name to create after checkout or nil
  # @option options [TrueClass|FalseClass] :recursive to perform a recursive checkout to same branch or tag (but not for SHA)
  #
  # @return [TrueClass] always true
  def checkout_revision(revision, options = {})
    options = {
      :new_branch_name => nil,
      :force           => true,
      :recursive       => true
    }.merge(options)

    # check parameters.
    new_branch_name = options[:new_branch_name]
    if new_branch_name && new_branch_name == revision
      raise ::ArgumentError, "revision cannot be same as new_branch_name: #{revision}"
    end
    unless [TrueClass, FalseClass, NilClass].include?(options[:force].class)
      raise ::ArgumentError, "force must be a boolean"
    end
    force = !!options[:force]

    # hard reset any local changes before attempting checkout, if forced.
    repo = default_repository
    logger = repo.logger
    logger.info("Performing checkout in #{repo.repo_dir.inspect}")
    repo.hard_reset_to(nil) if force

    # fetch to ensure revision is known and most up-to-date.
    repo.fetch_all

    # do full checkout of revision with submodule update before any attempt to
    # create a new branch. this handles some wierd git failures where submodules
    # are changing between major/minor versions of the code.
    repo.checkout_to(revision, :force => true)

    # note that the checkout-to-a-branch will simply switch to a local copy of
    # the branch which may or may not by synchronized with its remote origin. to
    # ensure the branch is synchronized, perform a pull.
    is_sha = is_sha?(revision)
    needs_pull = (
      !is_sha &&
      branch_exists?(revision, :remote => true, :local => false, :repo => repo)
    )
    if needs_pull
      # hard reset to remote origin to overcome any local branch divergence.
      repo.hard_reset_to("origin/#{revision}") if force

      # a pull is not needed at this point if we forced hard reset but it is
      # always nice to see it succeed in the output.
      repo.spit_output('pull', 'origin', revision)
    end

    # perform a localized hard reset to revision just to prove that revision is
    # now known to the local git database.
    repo.hard_reset_to(revision)

    # note that the submodule update is non-recursive for tags and branches in
    # case the submodule needs to checkout to a specific branch before updating
    # its own submodules. it would be strange to recursively update submodules
    # from the parent and then have the recursively checked-out child revision
    # (branch or tag) introduce a different set of submodules.
    repo.update_submodules(:recursive => is_sha && options[:recursive])

    # recursively checkout submodules, if requested and unless we determine the
    # revision is a SHA (in which case recursive+SHA is ignored).
    if !is_sha && options[:recursive]
      repo.submodule_paths(:recursive => false).each do |submodule_path|
        # note that recursion will use the current directory and create a new
        # repo by calling default_repository.
        ::Dir.chdir(submodule_path) do
          checkout_revision(revision, options)
        end
      end
    end

    # create a new branch from fully resolved directory, if requested.
    repo.spit_output('checkout', '-b', new_branch_name) if new_branch_name
    true
  end

  # Verifies that the local repository and all submodules match the expected
  # revision (branch, tag or SHA).
  #
  # @param [String] revision to check or nil to use base directory revision
  #
  # @return [TrueClass] always true
  #
  # @raise [VerifyError] on failure
  def verify_revision(revision = nil)
    repo = default_repository
    logger = repo.logger
    if revision
      # check current directory against revision.
      actual_revision = current_revision(revision, :repo => repo)
      if revision != actual_revision
        message =
          'Base directory is in an inconsistent state' +
          " (#{revision} != #{actual_revision}): #{repo.repo_dir.inspect}"
        raise VerifyError, message
      end
    else
      # determine revision to check from local HEAD state if not given. at best
      # this will be a branch or tag, at worst a SHA.
      logger.info("Resolving the default branch, tag or SHA to use for verification in #{repo.repo_dir.inspect}")
      revision = current_revision(nil, :repo => repo)
    end

    # start verify.
    logger.info("Verifying consistency of revision=#{revision} in #{repo.repo_dir.inspect}")
    if is_sha?(revision)
      revision_type = :sha
    elsif branch_exists?(revision, :remote => false, :local => true, :repo => repo)
      revision_type = :branch
    else
      revision_type = :tag
    end

    # for SHAs and tags, verify that expected submodule commits are checked-out
    # by looking for +,- in the submodule status. any that are out of sync will
    # not have a blank space on the left-hand side.
    if revision_type != :branch
      repo.git_output('submodule status --recursive').lines.each do |line|
        data = line.chomp
        if matched = ::RightGit::Git::Repository::SUBMODULE_STATUS_REGEX.match(data)
          if matched[1] != ' '
            message =
              'At least one submodule is in an inconsistent state:' +
              " #{::File.expand_path(matched[3])}"
            raise VerifyError, message
          end
        else
          raise VerifyError,
                "Unexpected output from submodule status: #{data.inspect}"
        end
      end
    end

    # branches are not required to have up-to-date submodule commits for ad-hoc
    # building purposes but all submodules should be checked-out to the same
    # branch (and that branch must exist for all submodules).
    #
    # for the tag case (i.e. release candidate), we peform a double-check
    # inside each submodule to verify that what the submodule thinks is tagged
    # is the same as the submodule SHA from the parent. the same tag must exist
    # and must be consistent for all submodules.
    if revision_type != :sha
      repo.submodule_paths(:recursive => true).each do |submodule_path|
        sub_repo = ::RightGit::Git::Repository.new(submodule_path, DEFAULT_REPO_OPTIONS)
        logger.info("Inspecting #{sub_repo.repo_dir.inspect}")
        actual_revision = current_revision(revision, :repo => sub_repo)
        if revision != actual_revision
          message =
            'At least one submodule is in an inconsistent state' +
            " (#{revision} != #{actual_revision}): #{sub_repo.repo_dir.inspect}"
          raise VerifyError, message
        end
      end
    end
    true
  end

  # Attempts to determine which branch, tag or SHA to which the current
  # directory is pointing. A directory can be pointing at both a branch and
  # multiple tags at the same time it so uses the hint to pick one or the other,
  # if given. if all else fails, the current SHA is returned.
  #
  # note that current revision is localized and so not directly related to the
  # current state of remote branches or tags. do a fetch to ensure those.
  #
  # @param [String] hint for branch vs. tag or nil
  # @param [Hash] options for query
  # @option options [RightGit::Git::Repository] :repo to use or nil
  #
  # @return [String] current revision
  def current_revision(hint = nil, options = {})
    options = {
      :repo => nil
    }.merge(options)
    repo = options[:repo] || default_repository

    # SHA logic
    actual_sha = repo.sha_for(nil)
    return actual_sha if is_sha?(hint)

    # branch logic
    branch_hint = (
      hint.nil? ||
      branch_exists?(hint, :remote => true, :local => true, :repo => repo)
    )
    if branch_hint
      branch = repo.git_output('rev-parse --abbrev-ref HEAD').strip
      return branch if branch != 'HEAD'
    end

    # tag logic
    if hint && tag_exists?(hint, :repo => repo)
      hint_sha = repo.sha_for(hint)
      return hint if hint_sha == actual_sha
    end

    # lookup tags for actual SHA, if any.
    if first_tag = tags_for_sha(actual_sha, :repo => repo).first
      return first_tag
    end

    # detached HEAD state, no matching branches or tags.
    actual_sha
  end

  # Generates a list of tags pointing to the given SHA, if any.
  # When the revision is a tag, only one tag is returned regardless of
  # whether other tags reference the same SHA.
  #
  # @param [String] sha for tags
  # @param [Hash] options for query
  # @option options [RightGit::Git::Repository] :repo to use or nil
  #
  # @return [Array] tags for the revision or empty
  def tags_for_sha(sha, options = {})
    options = {
      :repo => nil
    }.merge(options)
    repo = options[:repo] || default_repository
    git_args = ['tag', '--contains', sha]
    repo.git_output(git_args).lines.map { |line| line.strip }
  end

end # RightDevelop::Utility::Git

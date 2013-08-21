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

module RightDevelop::Utility::Git

  SHA1_REGEX = /^[0-9a-fA-F]{40}$/

  COMMIT_SHA1_REGEX = /^commit ([0-9a-fA-F]{40})$/

  SUBMODULE_STATUS_REGEX = /^([+\- ])([0-9a-fA-F]{40}) (.*) (.*)$/

  class VerifyError < StandardError; end

  module_function

  # Executes and returns the output for a git command. Raises on failure.
  #
  # @param [String|Array] args to execute
  #
  # @return [String] output
  def git_output(*args)
    cmd = ['git'] + Array(args).flatten
    return ::RightDevelop::Utility::Shell.output_for(cmd.join(' '))
  end

  # Prints the output for a git command.  Raises on failure.
  #
  # @param [String|Array] args to execute
  #
  # @return [TrueClass] always true
  def spit_output(*args)
    cmd = ['git'] + Array(args).flatten
    ::RightDevelop::Utility::Shell.execute(cmd.join(' '))
    true
  end

  # msysgit on Windows exits zero even when checkout|reset|fetch fails so we
  # need to scan the output for error or fatal messages. it does no harm to do
  # the same on Linux even though the exit code works properly there.
  #
  # @param [String|Array] args to execute
  #
  # @return [TrueClass] always true
  def vet_output(*args)
    last_output = git_output(*args).strip
    puts last_output unless last_output.empty?
    if last_output.downcase =~ /error|fatal/
      fail "git exited zero but an error was detected in output."
    end
    true
  end

  # @return [TrueClass|FalseClass] true if the given revision is a commit SHA
  def is_sha?(revision)
    !!SHA1_REGEX.match(revision)
  end

  # Determine if the branch given by name exists.
  #
  # @param [String] branch_name to query
  # @param [Hash] options for query
  # @option options [TrueClass|FalseClass] :remote to find remote branches
  # @option options [TrueClass|FalseClass] :local to find local branches
  #
  # @return [TrueClass|FalseClass] true if branch exists
  def branch_exists?(branch_name, options = {})
    options = {
      :remote => true,
      :local  => true
    }.merge(options)
    remote = options[:remote]
    local = options[:local]
    unless local || remote
      raise ::ArgumentError, 'Either remote or local must be true'
    end
    remote_regex = remote ? /\/#{::Regexp.escape(branch_name)}$/ : nil
    branches(:all => remote).any? do |data|
      (local && data == branch_name) || (remote && remote_regex.match(data))
    end
  end

  # Generates a list of known (checked-out) branches from the current git
  # directory.
  #
  # @param [Hash] options for branches
  # @option options [TrueClass|FalseClass] :all is true to include remote branches, else local only (default)
  #
  # @return [Array] list of branches
  def branches(options = {})
    options = {
      :all => true
    }.merge(options)
    git_args = ['branch']
    git_args << '-a' if options[:all]
    git_output(git_args).lines.map do |line|
      # strip any leading asterisk used to mark current branch, etc.
      line.gsub(/^\*/, '').strip
    end
  end

  # Determine if the tag given by name exists.
  #
  # @param [String] tag_name to query
  #
  # @return [TrueClass|FalseClass] true if tag exists
  def tag_exists?(tag_name)
    # note that remote tags cannot be queried directly; use git fetch --tags to
    # import them first.
    tags.any? { |tag| tag == tag_name }
  end

  # Generates a list of known (fetched) tags from the current git directory.
  #
  # @return [Array] list of tags
  def tags
    git_output('tag').map { |line| line.strip }
  end

  # Queries the recursive list of submodule paths for the current workspace.
  #
  # @param [TrueClass|FalseClass] recursive if true will recursively get paths
  #
  # @return [Array] list of submodule paths or empty
  def submodule_paths(recursive = false)
    git_args = ['submodule', 'status']
    git_args << '--recursive' if recursive
    git_output(git_args).map do |line|
      data = line.chomp
      if matched = SUBMODULE_STATUS_REGEX.match(data)
        matched[3]
      else
        fail "Unexpected output from submodule status: #{data.inspect}"
      end
    end
  end

  # Updates submodules for the current workspace.
  #
  # @param [TrueClass|FalseClass] recursive if true will recursively get paths
  #
  # @return [TrueClass] always true
  def update_submodules(recursive = false)
    git_args = ['submodule', 'update', '--init']
    git_args << '--recursive' if recursive
    spit_output(git_args)
  end

  # Clones the repo given by URL to the given destination (if any).
  #
  # @param [String] repo URL to clone
  # @param [String] destination path where repo is cloned to or nil to clone to subdir of working dir
  #
  # @return [TrueClass] always true
  def clone_to(repo, destination = nil)
    git_args = ['clone', repo]
    git_args << destination if destination
    spit_output(git_args)
  end

  # Performs a hard reset to the given revision, if given, or else the last
  # checked-out SHA.
  def hard_reset_to(revision = nil)
    git_args = ['reset', '--hard']
    git_args << revision if revision
    vet_output(git_args)
    true
  end

  # Fetches branch and tag information from remote origin.
  #
  # @return [TrueClass] always true
  def fetch_all
    vet_output('fetch')
    vet_output('fetch --tags') # need a separate call to fetch tags
    true
  end

  # Generates a difference from the current workspace to the given commit on the
  # same branch as a sorted list of relative file paths. This is useful for
  # creating a list of files to patch, etc.
  #
  # @param [String] commit to diff from (e.g. 'master')
  # @return [String] list of relative file paths from diff or empty
  def diff_files_from(commit)
    result = git_output('diff', '--stat', '--name-only', commit).
      map { |line| line.strip }.sort
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
    puts "Performing checkout in #{::Dir.pwd.inspect}"
    hard_reset_to(nil) if force

    # fetch to ensure revision is known and most up-to-date.
    fetch_all

    # do full checkout of revision with submodule update before any attempt to
    # create a new branch. this handles some wierd git failures where submodules
    # are changing between major/minor versions of the code.
    git_args = ['checkout', revision]
    git_args << '--force' if force
    vet_output(git_args)

    # note that the checkout-to-a-branch will simply switch to a local copy of
    # the branch which may or may not by synchronized with its remote origin. to
    # ensure the branch is synchronized, perform a pull.
    is_sha = is_sha?(revision)
    if !is_sha && branch_exists?(revision, :remote => true, :local => false)
      # hard reset to remote origin to overcome any local branch divergence.
      hard_reset_to("origin/#{revision}") if force

      # a pull is not needed at this point if we forced hard reset but it is
      # always nice to see it succeed in the output.
      spit_output('pull', 'origin', revision)
    end

    # perform a localized hard reset to revision just to prove that revision is
    # now known to the local git database.
    hard_reset_to(revision)

    # note that the submodule update is non-recursive for tags and branches in
    # case the submodule needs to checkout to a specific branch before updating
    # its own submodules. it would be strange to recursively update submodules
    # from the parent and then have the recursively checked-out child revision
    # (branch or tag) introduce a different set of submodules.
    update_submodules(recursive = is_sha && options[:recursive])

    # recursively checkout submodules, if requested and unless we determine the
    # revision is a SHA (in which case recursive+SHA is ignored).
    if !is_sha && options[:recursive]
      submodule_paths(recursive = false).each do |submodule_path|
        ::Dir.chdir(submodule_path) do
          checkout_revision(revision, options)
        end
      end
    end

    # create a new branch from fully resolved directory, if requested.
    spit_output('checkout', '-b', new_branch_name) if new_branch_name
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
    if revision
      # check current directory against revision.
      actual_revision = current_revision(revision)
      if revision != actual_revision
        message =
          'Base directory is in an inconsistent state' +
          " (#{revision} != #{actual_revision}): #{::Dir.pwd.inspect}"
        raise VerifyError, message
      end
    else
      # determine revision to check from local HEAD state if not given. at best
      # this will be a branch or tag, at worst a SHA.
      puts "\nResolving the default branch, tag or SHA to use for verification in #{::Dir.pwd.inspect}"
      revision = current_revision
    end

    # start verify.
    puts "\nVerifying consistency of revision=#{revision} in #{::Dir.pwd.inspect}"
    if is_sha?(revision)
      revision_type = :sha
    elsif branch_exists?(revision, :remote => false, :local => true)
      revision_type = :branch
    else
      revision_type = :tag
    end

    # for SHAs and tags, verify that expected submodule commits are checked-out
    # by looking for +,- in the submodule status. any that are out of sync will
    # not have a blank space on the left-hand side.
    if revision_type != :branch
      git_output('submodule status --recursive').lines.each do |line|
        data = line.chomp
        if matched = SUBMODULE_STATUS_REGEX.match(data)
          if matched[1] != ' '
            message =
              'At least one submodule is in an inconsistent state:' +
              " #{::File.expand_path(matched[3])}"
            raise VerifyError, message
          end
        else
          fail "Unexpected output from submodule status: #{data.inspect}"
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
      submodule_paths(recursive = true).each do |submodule_path|
        ::Dir.chdir(submodule_path) do
          puts "\nInspecting #{::Dir.pwd.inspect}"
          actual_revision = current_revision(revision)
          if revision != actual_revision
            message =
              'At least one submodule is in an inconsistent state' +
              " (#{revision} != #{actual_revision}): #{::Dir.pwd.inspect}"
            raise VerifyError, message
          end
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
  #
  # @return [String] current revision
  def current_revision(hint = nil)
    # SHA logic
    actual_sha = current_sha
    return actual_sha if is_sha?(hint)

    # branch logic
    if hint.nil? || branch_exists?(hint, :remote => true, :local => true)
      branch = git_output('rev-parse --abbrev-ref HEAD').strip
      return branch if branch != 'HEAD'
    end

    # tag logic
    if hint && tag_exists?(hint)
      hint_sha = sha_for(hint)
      return hint if hint_sha == actual_sha
    end

    # lookup tags for actual SHA, if any.
    if first_tag = tags_for_sha(actual_sha).first
      return first_tag
    end

    # detached HEAD state, no matching branches or tags.
    actual_sha
  end

  # Determines the SHA referenced by the current directory.
  #
  # @return [String] current SHA
  def current_sha
    sha_for(revision = nil)
  end

  # Determines the SHA referenced by the given revision. Raises on failure.
  #
  # @param [String] revision or nil for current SHA
  #
  # @return [String] SHA for revision
  def sha_for(revision)
    git_args = ['show', revision].compact
    result = nil
    git_output(git_args).lines.each do |line|
      if matched = COMMIT_SHA1_REGEX.match(line.strip)
        result = matched[1]
        break
      end
    end
    fail 'Unable to locate commit in show output.' unless result
    result
  end

  # Generates a list of tags pointing to the given SHA, if any.
  # When the revision is a tag, only one tag is returned regardless of
  # whether other tags reference the same SHA.
  #
  # @return [Array] tags for the revision or empty
  def tags_for_sha(sha)
    git_args = ['tag', '--contains', sha]
    git_output(git_args).map { |line| line.strip }
  end

end # RightDevelop::Utility::Git

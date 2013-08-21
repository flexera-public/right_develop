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

# Make sure the rest of RightDevelop & Gitis required, since this file can be
# required directly.
require 'right_develop/git'

# Once this file is required, the Rake DSL is loaded - don't do this except inside Rake!!
require 'rake/tasklib'

module RightDevelop::Git

  class RakeTask < ::Rake::TaskLib
    DEFAULT_OPTIONS = {
      :git_namespace => :git
    }

    include ::Rake::DSL if defined?(::Rake::DSL)

    attr_accessor :git_namespace

    def initialize(options = {})
      # Let client provide options object-style, in our initializer
      options = DEFAULT_OPTIONS.merge(options)
      self.git_namespace = options[:git_namespace]

      # Let client provide options DSL-style by calling our writers
      yield(self) if block_given?

      namespace self.git_namespace do

        desc "Perform 'git submodule update --init --recursive'"
        task :setup do
          git.update_submodules(:recursive => true)
        end

        desc "If HEAD is a branch or tag ref, ensure that all submodules are checked out to the same tag or branch or ensure consistency for SHA"
        task :verify, [:revision, :base_dir] do |_, args|
          revision = args[:revision].to_s.strip
          base_dir = args[:base_dir].to_s.strip
          revision = nil if revision.empty?
          base_dir = '.' if base_dir.empty?
          ::Dir.chdir(base_dir) do
            git.verify_revision(revision)
          end
        end

        desc "Checkout supermodule and all submodules to given tag, branch or SHA"
        task :checkout, [:revision, :base_dir] do |_, args|
          revision = args[:revision].to_s.strip
          base_dir = args[:base_dir].to_s.strip
          raise ::ArgumentError, 'revision is required' if revision.empty?
          base_dir = '.' if base_dir.empty?
          ::Dir.chdir(base_dir) do
            git.checkout_revision(revision, :force => true, :recursive => true)
          end
        end

      end # namespace
    end # initialize

    private

    def git
      ::RightDevelop::Utility::Git
    end

  end # RakeTask
end # RightDevelop::Git

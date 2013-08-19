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

# ancestors.
require 'right_develop'
require 'right_develop/buckets'

# localized
require 'tmpdir'

# Try to load RSpec 2.x - 1.x Rake tasks
require 'rake/tasklib' # assumes we are inside a rake process
['rspec/core/rake_task', 'spec/rake/spectask'].each do |f|
  begin
    require f
  rescue LoadError
    # no-op, we will raise later
  end
end

module RightDevelop::Buckets

  class RakeTask < ::Rake::TaskLib
    include ::Rake::DSL if defined?(::Rake::DSL)

    # @return [Class] storage_class
    attr_accessor :storage_class

    def initialize(options = {})
      options = {
        :namespace     => :s3,
        :storage_class => ::RightDevelop::Buckets::Aws::S3
      }.merge(options)

      @storage_class = options[:storage_class]

      namespace options[:namespace] do

        desc 'List files in S3 bucket'
        task :list_files, [:bucket, :subdirectory, :recursive, :filters] do |task, args|
          raise ::ArgumentError.new(":bucket is required") unless bucket = args[:bucket]
          list = storage.list_files(
            bucket,
            :subdirectory => args[:subdirectory],
            :recursive    => args[:recursive] != 'false',
            :filters      => args[:filters])
          puts "Files in S3 bucket \"#{bucket}/#{args[:subdirectory]}\":"
          list.sort.each { |path| puts "  #{path}" }
        end

        desc 'Download files from S3 bucket'
        task :download_files, [:bucket, :to_dir_path, :subdirectory, :recursive, :filters] do |task, args|
          raise ::ArgumentError.new(":bucket is required") unless bucket = args[:bucket]
          raise ::ArgumentError.new(":to_dir_path is required") unless to_dir_path = args[:to_dir_path]
          count = storage.download_files(
            bucket,
            to_dir_path,
            :subdirectory => args[:subdirectory],
            :recursive    => args[:recursive] != 'false',
            :filters      => args[:filters])
          puts "Downloaded #{count} file(s)."
        end

        desc 'Upload files to S3 bucket'
        task :upload_files, [:bucket, :from_dir_path, :subdirectory, :recursive, :access, :filters] do |task, args|
          raise ::ArgumentError.new(":bucket is required") unless bucket = args[:bucket]
          raise ::ArgumentError.new(":from_dir_path is required") unless from_dir_path = args[:from_dir_path]
          count = storage.upload_files(
            bucket,
            from_dir_path,
            :subdirectory => args[:subdirectory],
            :recursive => args[:recursive] != 'false',
            :access => args[:access],
            :filters => args[:filters])
          puts "Uploaded #{count} file(s)."
        end

        desc 'Copy files between S3 buckets'
        task :copy_files, [:from_bucket, :from_subdirectory, :to_bucket, :to_subdirectory, :recursive, :access, :filters] do |task, args|
          raise ::ArgumentError.new(":from_bucket is required") unless from_bucket = args[:from_bucket]
          raise ::ArgumentError.new(":to_bucket is required") unless to_bucket = args[:to_bucket]
          verbose = ::Rake.application.options.trace
          recursive = args[:recursive] != 'false'

          # establish from/to credentials before copying.
          from_storage = storage_class.new(
            :aws_access_key_id     => ENV['FROM_AWS_ACCESS_KEY_ID'],
            :aws_secret_access_key => ENV['FROM_AWS_SECRET_ACCESS_KEY'],
            :logger                => logger)
          to_storage = storage_class.new(
            :aws_access_key_id     => ENV['TO_AWS_ACCESS_KEY_ID'],
            :aws_secret_access_key => ENV['TO_AWS_SECRET_ACCESS_KEY'],
            :logger                => logger)

          # download
          ::Dir.mktmpdir do |temp_dir|
            ::Dir.chdir(temp_dir) do
              download_count = from_storage.download_files(
                from_bucket,
                temp_dir,
                :subdirectory => args[:from_subdirectory],
                :recursive    => recursive,
                :filters      => args[:filters])

              upload_count = to_storage.upload_files(
                to_bucket,
                temp_dir,
                :subdirectory => args[:to_subdirectory],
                :recursive    => recursive,
                :access       => args[:access],
                :filters      => nil)  # already filtered during download

              if upload_count == download_count
                puts "Copied #{upload_count} file(s)."
              else
                fail "Failed to upload all downloaded files (#{upload_count} uploaded != #{download_count} downloaded)."
              end
            end
          end
        end

        desc 'Delete files from S3 bucket'
        task :delete_files, [:bucket, :subdirectory, :recursive, :filters] do |task, args|
          raise ::ArgumentError.new(":bucket is required") unless bucket = args[:bucket]
          count = storage.delete_files(
            bucket,
            :subdirectory => args[:subdirectory],
            :recursive    => args[:recursive] != 'false',
            :filters      => args[:filters])
          puts "Deleted #{count} file(s)."
        end

      end # namespace
    end # initialize

    def logger
      unless @logger
        verbose = Rake.application.options.trace
        @logger = verbose ? Logger.new(STDOUT) : RightDevelop::Utility::Shell.null_logger
      end
      @logger
    end

    def storage
      unless @storage
        @storage = storage_class.new(
          :aws_access_key_id     => ENV['AWS_ACCESS_KEY_ID'],
          :aws_secret_access_key => ENV['AWS_SECRET_ACCESS_KEY'],
          :logger                => logger)
      end
      @storage
    end

  end # RakeTask
end # RightDevelop::Buckets

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
require 'right_develop/buckets/aws'

# localized
require 'fileutils'
require 'logger'
require 'right_aws'

module RightDevelop::Buckets::Aws
  class S3 < RightDevelop::Buckets::StorageBase
    DEFAULT_OPTIONS = {
      :aws_access_key_id => nil,
      :aws_secret_access_key => nil,
      :logger => nil
    }

    # @option options [String] :aws_access_key_id defaults to using env var value
    # @option options [String] :aws_secret_access_key defaults to using env var value
    # @option options [Logger] :logger or nil to log to STDOUT
    def initialize(options={})
      options = DEFAULT_OPTIONS.merge(options)

      aws_access_key_id  = options[:aws_access_key_id]
      aws_secret_access_key = options[:aws_secret_access_key]
      unless aws_access_key_id && aws_secret_access_key
        raise ::ArgumentError,
              'Missing one or both mandatory options - :aws_access_key_id and :aws_secret_access_key'
      end

      @logger = options[:logger] || Logger.new(STDOUT)
      @s3 = ::RightAws::S3Interface.new(aws_access_key_id, aws_secret_access_key, :logger => @logger)
    end

    attr_accessor :logger

    # Lists the files in the given bucket.
    #
    # @param [String] bucket to query
    # @option options [String] :subdirectory to start from or nil
    # @option options [TrueClass|FalseClass] :recursive true if recursive (default)
    # @option options [Array] :filters for returned paths or nil or empty
    # @return [Array] list of relative file paths or empty
    def list_files(bucket, options={})
      options = DEFAULT_OPTIONS.dup.merge(options)
      prefix = normalize_subdirectory_path(options[:subdirectory])
      filters = normalize_filters(options)
      files = []
      trivial_filters = filters.select { |filter| filter.is_a?(String) }
      if trivial_filters.empty?
        @s3.incrementally_list_bucket(bucket, 'prefix' => prefix) do |response|
          incremental_files = response[:contents].map do |details|
            details[:key][(prefix.length)..-1]
          end
          files += filter_files(incremental_files, filters)
        end
      else
        trivial_filters.each do |filename|
          begin
            # use head to query file existence.
            @s3.head(bucket, "#{prefix}#{filename}")
            files << filename
          rescue RightAws::AwsError => e
            # do nothing if file not found
            raise unless '404' == e.http_code
          end
        end
      end
      return files
    end

    # Downloads all files from the given bucket to the given directory.
    #
    # @param [String] bucket for download
    # @param [String] to_dir_path source directory to upload
    # @option options [String] :subdirectory to start from or nil
    # @option options [TrueClass|FalseClass] :recursive true if recursive (default)
    # @option options [Array] :filters for returned paths or nil or empty
    # @return [Fixnum] count of uploaded files
    def download_files(bucket, to_dir_path, options={})
      options = DEFAULT_OPTIONS.dup.merge(options)
      prefix = normalize_subdirectory_path(options[:subdirectory])
      files = list_files(bucket, options)
      if files.empty?
        logger.info("No files found in \"#{bucket}/#{prefix}\"")
      else
        logger.info("Downloading #{files.count} files...")
        prefix = normalize_subdirectory_path(options[:subdirectory])
        downloaded = 0
        files.each do |path|
          key = "#{prefix}#{path}"
          to_file_path = File.join(to_dir_path, path)
          parent_path = File.dirname(to_file_path)
          FileUtils.mkdir_p(parent_path) unless File.directory?(parent_path)

          disk_file = to_file_path
          file_md5 = File.exist?(disk_file) && Digest::MD5.hexdigest(File.read(disk_file))

          if file_md5
            head = @s3.head(bucket, key) rescue nil
            key_md5 = head && head['etag'].gsub(/[^0-9a-fA-F]/, '')
            skip = (key_md5 == file_md5)
          end

          if skip
            logger.info("Skipping #{bucket}/#{key} (identical contents)")
          else
            logger.info("Downloading #{bucket}/#{key}")
            ::File.open(to_file_path, 'wb') do |f|
              @s3.get(bucket, key) { |chunk| f.write(chunk) }
            end
            downloaded += 1
          end

          logger.info("Downloaded to \"#{to_file_path}\"")
        end
      end

      downloaded
    end

    # Uploads all files from the given directory (ignoring any empty
    # directories) to the given bucket.
    #
    # @param [String] bucket for upload
    # @param [String] from_dir_path source directory to upload
    # @option options [String] :subdirectory to start from or nil
    # @option options [TrueClass|FalseClass] :recursive true if recursive (default)
    # @option options [Array] :filters for returned paths or nil or empty
    # @option options [String] :visibility for uploaded files, defaults to 'public-read'
    # @return [Fixnum] count of downloaded files
    def upload_files(bucket, from_dir_path, options={})
      Dir.chdir(from_dir_path) do
        logger.info("Working in #{Dir.pwd.inspect}")
        options = DEFAULT_OPTIONS.dup.merge(options)
        prefix = normalize_subdirectory_path(options[:subdirectory])
        filters = normalize_filters(options)
        pattern = options[:recursive] ? '**/*' : '*'
        files = Dir.glob(pattern).select { |path| File.file?(path) }
        filter_files(files, filters)
        access = normalize_access(options)
        uploaded = 0
        files.each do |path|
          key = "#{prefix}#{path}"
          file_md5 = Digest::MD5.hexdigest(File.read(path))
          File.open(path, 'rb') do |f|
            head = @s3.head(bucket, key) rescue nil
            key_md5 = head && head['etag'].gsub(/[^0-9a-fA-F]/, '')

            if file_md5 == key_md5
              logger.info("Skipping #{bucket}/#{key} (identical contents)")
            else
              logger.info("Uploading to #{bucket}/#{key}")
              @s3.put(bucket, key, f, 'x-amz-acl' => access)
              uploaded += 1
            end
          end
        end

        uploaded
      end
    end

    # Deletes all files from the given bucket.
    #
    # @param [String] bucket for delete
    # @option options [String] :subdirectory to start from or nil
    # @option options [TrueClass|FalseClass] :recursive true if recursive (default)
    # @option options [Regexp] :filter for files to delete or nil
    # @return [Fixnum] count of deleted files
    def delete_files(bucket, options={})
      options = DEFAULT_OPTIONS.dup.merge(options)
      prefix = normalize_subdirectory_path(options[:subdirectory])
      files = list_files(bucket, options)
      if files.empty?
        logger.info("No files found in \"#{bucket}/#{prefix}\"")
      else
        logger.info("Deleting #{files.count} files...")
        files.each do |path|
          @s3.delete(bucket, "#{prefix}#{path}")
          logger.info("Deleted \"#{bucket}/#{prefix}#{path}\"")
        end
      end
      return files.size
    end
  end # S3
end # RightDevelop::Buckets::Aws

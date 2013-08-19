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

# ancestor.
require 'right_develop/buckets'

module RightDevelop
  module Buckets

    # Provides an implementation-independent interface for bucket storage.
    #
    # Note: filters are used as options for multiple storage actions below and
    # refers to an array of Regexp or wildcard-style filter strings
    # (e.g. '*.txt'). they are used to match file paths relative to a given
    # subdirectory or else from the root of the bucket or directory on disk).
    class StorageBase

      NO_SLASHES_REGEXP = /^[^\/]+$/
      DEFAULT_OPTIONS = { :filters => nil, :subdirectory => nil, :recursive => true }.freeze

      # Lists the files in the given bucket.
      #
      # @param [String] bucket to query
      # @option options [String] :subdirectory to start from or nil
      # @option options [TrueClass|FalseClass] :recursive true if recursive (default)
      # @option options [Array] :filters for returned paths or nil or empty
      # @return [Array] list of relative file paths or empty
      def list_files(bucket, options={})
        raise NotImplementedError
      end

      # Downloads all files from the given bucket to the given directory.
      #
      # @param [String] bucket for download
      # @param [String] to_dir_path source directory to upload
      # @option options [String] :subdirectory to start from or nil
      # @option options [TrueClass|FalseClass] :recursive true if recursive (default)
      # @option options [Array] :filters for returned paths or nil or empty
      # @return [Fixnum] count of downloaded files
      def download_files(bucket, to_dir_path, options={})
        raise NotImplementedError
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
      # @return [Fixnum] count of uploaded files
      def upload_files(bucket, from_dir_path, options={})
        raise NotImplementedError
      end

      # Deletes all files from the given bucket.
      #
      # @param [String] bucket for delete
      # @option options [String] :subdirectory to start from or nil
      # @option options [TrueClass|FalseClass] :recursive true if recursive (default)
      # @option options [Array] :filters for returned paths or nil or empty
      # @return [Fixnum] count of deleted files
      def delete_files(bucket, options={})
        raise NotImplementedError
      end

      protected

      # Normalizes a relative file path for use with buckets.
      #
      # @param [String] subdirectory
      def normalize_file_path(path)
        # remove leading and trailing slashes and change any multiple slashes to single.
        return (path || '').gsub("\\", '/').gsub(/^\/+/, '').gsub(/\/+$/, '').gsub(/\/+/, '/')
      end

      # Normalizes subdirectory path for use with buckets.
      #
      # @param [String] path
      # @return [String] normalized path
      def normalize_subdirectory_path(path)
        path = normalize_file_path(path)
        path += '/' unless path.empty?
        return path
      end

      # Normalizes storage filters from options.
      #
      # @option options [Array] :filters for returned paths or nil or empty
      def normalize_filters(options)
        initial_filters = Array(options[:filters])
        normalized_filters = nil

        # support trivial filters as simple string array for direct lookup of
        # one or more S3 object (since listing entire buckets can be slow).
        # recursion always requires a listing so that cannot be trivial.
        if !options[:recursive] && initial_filters.size == 1
          # filter is trivial unless it contains wildcards. more than one
          # non-wildcard filenames delimited by semicolon can be trivial.
          filter = initial_filters.first
          if filter.kind_of?(String) && filter == filter.gsub('*', '').gsub('?', '')
            normalized_filters = filter.split(';').uniq
          end
        end
        unless normalized_filters
          normalized_filters = []
          normalized_filters << NO_SLASHES_REGEXP unless options[:recursive]
          initial_filters.each do |filter|
            if filter.kind_of?(String)
              # split on semicolon (;) and OR the result into one regular expression.
              # example: "*.tar;*.tgz;*.zip" -> /^.*\.tar|.*\.tgz|.*\.zip$/
              #
              # convert wildcard-style filter string (e.g. '*.txt') to Regexp.
              escaped = Regexp.escape(filter).gsub("\\*", '.*').gsub("\\?", '.').gsub(';', '|')
              regexp = Regexp.compile("^#{escaped}$")
              filter = regexp
            end
            normalized_filters << filter unless normalized_filters.index(filter)
          end
        end
        return normalized_filters
      end

      # Normalizes access from options (for uploading files).
      #
      # Note: access strings are AWS S3-style but can easily be mapped to any
      # bucket storage implementation which supports ACLs.
      #
      # @option options [String] :access requested ACL or nil for public-read
      # @return @return [String] normalized access
      def normalize_access(options)
        access = options[:access].to_s.empty? ? nil : options[:access]
        return access || 'public-read'
      end

      # Filters the given list of file paths using the given filters, if any.
      #
      # @param [Array] files to filter
      # @param [Array] filters for matching or empty
      # @return [Array] filtered files
      def filter_files(files, filters)
        return files if filters.empty?

        # select each path only if it matches all filters.
        return files.select { |path| filters.all? { |filter| filter.match(path) } }
      end

    end  # StorageBase
  end  # Buckets
end  # RightDevelop

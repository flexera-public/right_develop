#
# Copyright (c) 2014 RightScale Inc
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

if ::ENV['RACK_ENV'].to_s.empty?
  ::ENV['RACK_ENV'] = 'development'
end

require 'right_develop/testing/recording/config'
require 'uri'

# define the module hierarchy once so that it can be on a single line hereafter.
module RightDevelop
  module Testing
    module Server
      module MightApi
        # if only ruby could consume a single line module declaration...
      end
    end
  end
end

module RightDevelop::Testing::Server::MightApi
  class Config

    # default config path.
    CONFIG_DIR_NAME     = 'config'.freeze
    DEFAULT_CONFIG_PATH = ::File.join(CONFIG_DIR_NAME, 'might_deploy.yml').freeze

    METADATA_CLASS = ::RightDevelop::Testing::Recording::Metadata
    CONFIG_CLASS   = ::RightDevelop::Testing::Recording::Config

    # Loads the config hash from given path or a relative location.
    #
    # @param [String] path to configuration
    #
    # @return [Mash] configuration hash
    #
    # @raise [ArgumentError] on failure to load
    def self.from_file(path, options = nil)
      @config = CONFIG_CLASS.from_file(path, options)
      self
    end

    # Setup configuration. Defaults to using environment variables for setup due
    # to rackup not allowing custom arguments to be passed on command line.
    #
    # @param [Hash] config as raw configuration data
    #
    # @return [Config] self
    #
    # @raise [ArgumentError] on failure to load
    def self.from_hash(config_hash)
      @config = CONFIG_CLASS.new(config_hash)
      self
    end

    # @see Object#method_missing
    def self.method_missing(methud, *args, &block)
      if @config && @config.respond_to?(methud)
        @config.__send__(methud, *args, &block)
      else
        super
      end
    end

    # @see Object#respond_to?
    def self.respond_to?(methud)
      super(methud) || (@config && @config.respond_to?(methud))
    end

    # @see Class.const_missing
    def self.const_missing(konst)
      if CONFIG_CLASS.const_defined?(konst)
        CONFIG_CLASS.const_get(konst)
      else
        super
      end
    end

    # @see Class.const_defined?
    def self.const_defined?(konst)
      super(konst) || CONFIG_CLASS.const_defined?(konst)
    end

    # @return [String] environment configuration string
    def self.environment
      @environment ||= ::ENV['RACK_ENV']
    end

    def self.normalize_fixtures_dir(logger)
      # remove any residual state files at root of fixtures directory.
      logger.info("Normalizing fixtures directory: #{fixtures_dir.inspect} ...")
      ::Dir[::File.join(fixtures_dir, '*.yml')].each do |path|
        ::File.unlink(path) if ::File.file?(path)
      end

      # recursively iterate requests/responses ensuring that both files exist
      # and that they are MD5-named. if not, then supply the MD5 by renaming
      # both files. this allows a user to write custom request/responses without
      # having to supply the MD5 checksum for the significant request parts.
      ::Dir[::File.join(fixtures_dir, '*/*')].sort.each do |epoch_api_dir|
        if ::File.directory?(epoch_api_dir)
          # request/response pairs must be identical whether or not using human-
          # readable file names.
          route_subdir_name = ::File.basename(epoch_api_dir)
          if route = routes.find { |prefix, data| data[:subdir] == route_subdir_name }
            route_path, route_data = route
            requests_dir = epoch_api_dir + '/request/'
            responses_dir = epoch_api_dir + '/response/'
            request_files = ::Dir[requests_dir + '**/*.yml'].sort.map { |path| path[requests_dir.length..-1] }
            response_files = ::Dir[responses_dir + '**/*.yml'].sort.map { |path| path[responses_dir.length..-1] }
            if request_files != response_files
              difference = ((request_files - response_files) | (response_files - request_files)).sort
              message = 'Mismatched request/response file pairs under ' +
                        "#{epoch_api_dir.inspect}: #{difference.inspect}"
              raise ::ArgumentError, message
            end

            # convert filename prefix to MD5 wherever necessary.
            request_files.each do |path|
              # load request/response pair to validate.
              request_file_path = ::File.join(requests_dir, path)
              response_file_path = ::File.join(responses_dir, path)
              request_data = RightSupport::Data::Mash.new(::YAML.load_file(request_file_path))
              response_data = RightSupport::Data::Mash.new(::YAML.load_file(response_file_path))

              # if confing contains unreachable (i.e. no available route) files
              # then that is ignorable.
              query_string = request_data[:query]
              uri = METADATA_CLASS.normalize_uri(
                URI::HTTP.build(
                  host:  'none',
                  path:  (route_path + ::File.dirname(path)),
                  query: request_data[:query]).to_s)

              # compute checksum from recorded request metadata.
              request_metadata = METADATA_CLASS.new(
                mode:       :validate,
                kind:       :request,
                logger:     logger,
                route_data: route_data,
                uri:        uri,
                verb:       request_data[:verb],
                headers:    request_data[:headers],
                body:       request_data[:body],
                variables:  {})

              # rename fixure file prefix only if given custom name by user.
              name = ::File.basename(path)

              if matched = FIXTURE_FILE_NAME_REGEX.match(name)
                # verify correct MD5 for body.
                file_checksum = matched[1]
                if file_checksum.casecmp(request_metadata.checksum) != 0
                  message = "Checksum from fixture file name (#{file_checksum}) " +
                            "does not match the request body checksum " +
                            "(#{request_metadata.checksum}): #{request_file_path.inspect}"
                  raise ::ArgumentError, message
                end
              else
                # compute checksum from loaded request body.
                checksum_file_name = request_metadata.checksum + '.yml'

                # rename file pair.
                to_request_file_path = ::File.join(::File.dirname(request_file_path), checksum_file_name)
                to_response_file_path = ::File.join(::File.dirname(response_file_path), checksum_file_name)
                logger.debug("Renaming #{request_file_path.inspect} to #{to_request_file_path.inspect}.")
                ::File.rename(request_file_path, to_request_file_path)
                logger.debug("Renaming #{response_file_path.inspect} to #{to_response_file_path.inspect}.")
                ::File.rename(response_file_path, to_response_file_path)
              end
            end
          else
            # unknown route fixture directories will cause playback engine to
            # spin forever.
            unrecognized_routes << epoch_api_dir
            message = "Cannot find a route for fixtures directory: #{epoch_api_dir.inspect}"
            raise ::ArgumentError, message
          end
        end
      end
    end

  end # Config
end # RightDevelop::Testing::Server::MightApi

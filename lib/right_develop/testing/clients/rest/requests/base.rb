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

# ancestor
require 'right_develop/testing/clients/rest'

require 'rest_client'
require 'right_support'
require 'digest/md5'

module RightDevelop::Testing::Client::Rest::Request

  # Base class for record/playback request implementations.
  class Base < ::RestClient::Request

    attr_reader :record_dir, :logger

    def initialize(args)
      args = args.dup
      unless @record_dir = args.delete(:record_dir)
        raise ::ArgumentError, 'record_dir is required'
      end
      unless @logger = args.delete(:logger)
        raise ::ArgumentError, 'logger is required'
      end

      super(args)

      if @block_response
        raise ::NotImplementedError,
              'block_response not supported for record/playback'
      end
      if @raw_response
        raise ::ArgumentError, 'raw_response not supported for record/playback'
      end
    end

    protected

    # Computes the metadata used to identify where the request/response should
    # be stored-to/retrieved-from. Recording the request is not strictly
    # necessary (because the request maps to a MD5 used for response-only) but
    # it adds human-readability and the ability to manually customize some or
    # all responses.
    #
    # @return [Hash] metadata for storing/retrieving request and response
    def compute_record_metadata
      # use rest-client method to parse URL (again).
      uri = parse_url(@url)
      query_file_name = self.method.to_s.upcase
      unless (query_string = uri.query.to_s).empty?
        # try to keep it human-readable by CGI-escaping the only illegal *nix
        # file character = '/'.
        query_string = normalize_query_string(query_string).gsub('/', '%2F')
        query_file_name << '_' << query_string
      end

      # payload is an I/O object but we can quickly get body from .string if it
      # is a StringIO object, which it usually is.
      stream = @payload.instance_variable_get(:@stream)
      if stream && stream.respond_to?(:string)
        body = stream.string
      else
        # assume payload is too large to buffer or else it would be StringIO.
        # we could compute the MD5 by streaming if we really wanted to, but...
        raise ::NotImplementedError,
              'Non-string payload streams are not currently supported.'
      end

      # JSON data may be hash-ordered inconsistently between invocations.
      # attempt to sort JSON data before creating a key.
      case headers['CONTENT_TYPE']
      when 'application/x-www-form-urlencoded'
        normalized_body = normalize_query_string(body)
      when 'application/json'
        normalized_body = normalize_json(body)
      else
        normalized_body = body
      end
      normalized_body_token = body.empty? ? 'empty' : ::Digest::MD5.hexdigest(body)
      query_file_name = "#{normalized_body_token}_#{query_file_name}"
      relative_request_dir = ::File.join('requests', uri.path)
      relative_response_dir = ::File.join('responses', uri.path)

      # TODO determine current timestamp to provide statefulness.
      current_timestamp = 0

      # result
      {
        current_timestamp:     current_timestamp,
        normalized_body:       normalized_body,
        normalized_body_token:  normalized_body_token,
        query_file_name:       query_file_name,
        relative_request_dir:  relative_request_dir,
        relative_response_dir: relative_response_dir,
      }
    end

    # Sort the given query string fields because order of parameters should not
    # matter but multiple invocations might shuffle the parameter order.
    #
    # @param [String] query_string to normalize
    #
    # @return [String] normalized query string
    def normalize_query_string(query_string)
      query = []
      ::CGI.parse(query_string).sort.each do |k, v|
        # right-hand-side of CGI.parse hash is always an array
        v.sort.each { |item| query << "#{k}=#{item}" }
      end
      query.join('&')
    end

    # Deep-sorts the given JSON string. If the payload contains arrays that
    # contain hashes then those hashes are not sorted due to a limitation of
    # deep_sorted_json.
    #
    # FIX: deep_sorted_json could traverse arrays and sort sub-hashes if
    # necessary.
    #
    # @param [String] json to normalize
    #
    # @return [String] normalized JSON string
    def normalize_json(json)
      hash = ::JSON.load(json)
      ::RightSupport::Data::HashTools.deep_sorted_json(hash, pretty = true)
    end

    def request_file_path(record_metadata)
      ::File.join(
        @record_dir,
        record_metadata[:current_timestamp].to_s,
        record_metadata[:relative_request_dir],
        record_metadata[:query_file_name] + '.txt')
    end

    def response_file_path(record_metadata)
      ::File.join(
        @record_dir,
        record_metadata[:current_timestamp].to_s,
        record_metadata[:relative_response_dir],
        record_metadata[:query_file_name] + '.yml')
    end

  end # Base

end # RightDevelop::Testing::Client::Rest

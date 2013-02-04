require 'xml/libxml'
require 'active_support/inflector'
require 'right_develop/parsers/xml_post_parser.rb'

module RightDevelop::Parsers
  class SaxParser
    extend XmlPostParser

    # Parses XML into a ruby hash
    #
    # @param [String] text The XML string to convert into a ruby hash
    # @param [Hash] opts
    # @opts [Lambda or Proc] :post_parser A lambda function to run against
    #   the return content of the initial xml parser.
    # @return [Array or Hash] returns rubified XML in Hash and Array format
    def self.parse(text, opts = {})
      # Parse the xml text
      # http://libxml.rubyforge.org/rdoc/
      xml           = ::XML::SaxParser::string(text)
      xml.callbacks = new
      xml.parse

      if opts[:post_parser]
        if opts[:post_parser].kind_of?(Proc)
          return opts[:post_parser].call(xml.callbacks.result)
        else
          raise ArgumentError.new(":post_parser parameter must be a lambda/proc")
        end
      else
        return xml.callbacks.result
      end
    end

    def initialize
      @tag  = {}
      @path = []
    end

    def result
      @tag
    end

    # Callbacks

    def on_error(msg)
      raise msg
    end

    def on_start_element_ns(name, attr_hash, prefix, uri, namespaces)
      # Push parent tag
      @path << @tag
      # Create a new tag
      if @tag[name]
        @tag[name] = [ @tag[name] ] unless @tag[name].is_a?(Array)
        @tag[name] << {}
        @tag = @tag[name].last
      else
        @tag[name] = {}
        @tag = @tag[name]
      end
      # Put attributes
      attr_hash.each do |key, value|
        @tag["#{key}"] = value
      end
      # Put name spaces
      namespaces.each do |key, value|
        @tag["@xmlns#{key ? ':'+key.to_s : ''}"] = value
      end
    end

    def on_characters(chars)
      # Ignore lines that contains white spaces only
      return if chars[/\A\s*\z/m]
      # Put Text
      (@tag['@@text'] ||= '') << chars
    end

    def on_comment(msg)
      # Put Comments
      (@tag['@@comment'] ||= '') << msg
    end

    def on_end_element_ns(name, prefix, uri)
      # Special handling of empty text fields
      if @tag.is_a?(Hash) && @tag.empty? && @tag['@@text'].nil?
        @tag['@@text'] = ""
      end

      # Finalize tag's text
      if @tag.keys.count == 0
        # Set tag value to nil then the tag is blank
        name.pluralize == name ? @tag = [] : {}
      elsif @tag.keys == ['@@text']
        # Set tag value to string if it has no any other data
        @tag = @tag['@@text']
      end
      # Make sure we saved the changes
      if @path.last[name].is_a?(Array)
        # If it is an Array then update the very last item
        @path.last[name][-1] = @tag
      else
        # Otherwise just replace the tag
        @path.last[name] = @tag
      end
      # Pop parent tag
      @tag = @path.pop
    end

    def on_start_document
    end

    def on_reference (name)
    end

    def on_processing_instruction(target, data)
    end

    def on_cdata_block(cdata)
    end

    def on_has_internal_subset()
    end

    def on_internal_subset (name, external_id, system_id)
    end

    def on_is_standalone ()
    end

    def on_has_external_subset ()
    end

    def on_external_subset (name, external_id, system_id)
    end

    def on_end_document
    end
  end
end
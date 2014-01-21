module RightDevelop::Parsers
  module XmlPostParser
    begin
      require 'active_support/inflector'

      AVAILABLE = true
    rescue LoadError => e
      AVAILABLE = false
    end

    # Parses a rubified XML hash/array, removing the top level xml tag, along with
    # any arrays encoded with singular/plural for parent/child nodes.
    # Intended to allow for one set of code for validating JSON or XML responses.
    #
    # @example
    #   Initial XML:
    #   <top_level>
    #    <arrays>
    #      <array item1="one" item2="two"/>
    #      <array item3="three" item4="four"/>
    #    </arrays>
    #   </top_level>
    #
    #   Before removing nesting, after initial parsing:
    #   {
    #     'top_level' => {
    #       'arrays' => {
    #        'array' => [
    #          {'item1' => 'one', 'item2' => 'two'},
    #          {'item3' => 'three', 'item4' => 'four'}
    #        ]
    #       }
    #     }
    #   }
    #
    #   After removing nesting:
    #   {
    #     'arrays' => [
    #       {'item1' => 'one', 'item2' => 'two'},
    #       {'item3' => 'three', 'item4' => 'four'}
    #     ]
    #   }
    #
    # @param [Array or Hash] xml_object parsed XML object, such as from Parser::Sax.parse.
    # @return [Array or Hash] returns a ruby Array or Hash with top level xml tags removed,
    #   as well as any extra XML encoded array tags.
    def self.remove_nesting(xml_object)
      unless AVAILABLE
        raise NotImplementedError, "#{self.name} is unavailable on this system because libxml-ruby and/or active_support are not installed"
      end

      if xml_object.length != 1 || (!xml_object.is_a?(Hash) && !xml_object.is_a?(Array))
        raise ArgumentError, "xml_object format doesn't have a single top level entry"
      end
      if !xml_object.is_a?(Hash)
        raise TypeError, "xml_object object doesn't seem to be a Hash or an Array"
      end
      xml_object = deep_clone(xml_object)

      #if root & children are the same base word, get rid of both layers
      root_key       = xml_object.keys[0]
      root_child     = xml_object[xml_object.first[0]]
      if root_child.respond_to?(:keys)
        root_child_key = root_child.keys[0]
      else
        root_child_key = nil
      end

      #remove root key
      xml_object = xml_object[xml_object.first[0]]

      #remove extra root child key
      if root_key.singularize == root_child_key
        # Ensure object is an array (like JSON responses)
        xml_object = [xml_object[xml_object.first[0]]].flatten
      elsif !xml_object
         # Degenerate case where nothing was contained by parent node
         # (i.e. no resources were actually returned)
        xml_object = []
      end

      remove_nesting_node(xml_object)
      return xml_object
    end

    private

    # Does a deep clone of the passed ruby object. Intended for Arrays / Hashes
    #
    # @param [Object] object to deep clone
    # @return [Object] returns an exact deep copy of the passed in object
    #
    # @example BaseHelpers.deep_clone([{:a=>1},{:b=>2}])
    def self.deep_clone(object)
      Marshal.load(Marshal.dump(object))
    end

    def self.remove_nesting_node(xml_object_node)
      if xml_object_node.is_a?(Array)
        xml_object_node.each_with_index do |node,index|
          remove_nesting_node(node)
        end
      elsif xml_object_node.is_a?(Hash)
        # If child is singular version of parent, remove extra child pointer
        xml_object_node.each do |parent_key, parent_value|
          if parent_value.is_a?(Hash) && parent_value.length == 1
            child_key = parent_value.keys[0]
            if parent_key.singularize == child_key
              # Wrap xml object in an array so it matches JSON format
              child_node = xml_object_node[parent_key][child_key]
              if (child_node.is_a?(Hash) || child_node.is_a?(String))
                child_node = [child_node]
              end
              xml_object_node[parent_key] = child_node
            end
          end
          remove_nesting_node(parent_value)
        end
      end
    end
  end
end
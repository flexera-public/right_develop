# Ensure the main gem is required, since this module might be loaded using ruby -r
require 'right_develop'

module RightDevelop
  module Parsers
  end
end

require 'right_develop/parsers/xml_post_parser.rb'
require 'right_develop/parsers/sax_parser.rb'

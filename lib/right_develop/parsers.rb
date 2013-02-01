# Ensure the main gem is required, since this module might be loaded using ruby -r
require 'right_develop'

module RightDevelop
  module Parsers
  end
end

# Explicitly require everything else to avoid overreliance on autoload (1-module-deep rule)
require 'right_develop/parsers/sax_parser.rb'

require 'right_support'

# Autoload everything possible
module RightDevelop
  autoload :CI, 'right_develop/ci'
  autoload :Parsers, 'right_develop/parsers'
end

# Automatically include RightSupport networking extensions
require 'right_develop/net'

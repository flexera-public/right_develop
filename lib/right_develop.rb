require 'right_support'

# Autoload everything possible
module RightDevelop
  autoload :CI, 'right_develop/ci'
end

# Automatically include RightSupport networking extensions
require 'right_develop/net'

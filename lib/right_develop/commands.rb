module RightDevelop
  module Commands
  end
end

require 'right_develop/commands/git'
require 'right_develop/commands/server' unless RUBY_VERSION =~ /^1.8/

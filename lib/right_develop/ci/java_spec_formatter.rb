#
# Copyright (c) 2009-2011 RightScale Inc
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

require 'time'

require 'builder'

# Try to load RSpec 2.x - 1.x formatters
['rspec/core', 'spec', 'rspec/core/formatters/base_formatter', 'spec/runner/formatter/base_text_formatter'].each do |f|
  begin
    require f
  rescue LoadError
    # no-op, we will raise later
  end
end

module RightDevelop::CI
  spec = Gem.loaded_specs['rspec']
  ver  = spec && spec.version.to_s

  case ver
  when /^3/
    require 'right_develop/ci/formatters/rspec_v3'
    RSpecFormatter = RightDevelop::CI::Formatters::RSpecV3
  when /^2/
    require 'right_develop/ci/formatters/rspec_v2'
    RSpecFormatter = RightDevelop::CI::Formatters::RSpecV2
  when /^1/
    require 'right_develop/ci/formatters/rspec_v1'
    RSpecFormatter = RightDevelop::CI::Formatters::RSpecV1
  when nil
    RSpecFormatter = Object
  else
    raise LoadError,
      "Cannot define RightDevelop::CI::RSpecFormatter: unsupported RSpec version #{ver}"
  end

  # @deprecated do not refer to this class name; use RSpecFormater instead
  JavaSpecFormatter = RSpecFormatter
end

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

# Try to load RSpec 2.x - 1.x
['rspec', 'spec'].each do |f|
  begin
    require f
  rescue LoadError
    # no-op, we will raise later
  end
end

module RightDevelop::Net
  # Extra fatal exceptions to add to RightSupport::Net::RequestBalancer
  FATAL_TEST_EXCEPTIONS = []

  spec_namespaces = []

  if defined?(::RSpec::Mocks)
    # RSpec 2.x
    spec_namespaces += [::RSpec::Mocks, ::RSpec::Expectations]
  elsif defined?(::Spec::Expectations)
    # RSpec 1.x
    spec_namespaces += [::Spec::Expectations]
  end

  # Use some reflection to locate all RSpec and Test::Unit exceptions
  spec_namespaces.each do |namespace|
    namespace.constants.each do |konst|
      konst = namespace.const_get(konst)
      if konst.is_a?(Class) && konst.ancestors.include?(Exception)
        FATAL_TEST_EXCEPTIONS << konst
      end
    end
  end

  dfe = RightSupport::Net::RequestBalancer::DEFAULT_FATAL_EXCEPTIONS
  FATAL_TEST_EXCEPTIONS.each do |e|
    dfe << e unless dfe.include?(e)
  end
end

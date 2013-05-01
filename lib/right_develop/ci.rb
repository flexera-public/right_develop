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

# Ensure the main gem is required, since this module might be loaded using ruby -r
require 'right_develop'

module RightDevelop
  module CI
    # Defer loading the Rake task; it mixes the Rake DSL into everything!
    # Only the Rakefiles themselves should refer to this constant.
    autoload :RakeTask, 'right_develop/ci/rake_task'

    # Cucumber does not support a -r hook, but it does let you specify class names. Autoload
    # to the rescue!
    autoload :JavaCucumber, 'right_develop/ci/java_cucumber_formatter'
  end
end

# Explicitly require everything else to avoid overreliance on autoload (1-module-deep rule)
require 'right_develop/ci/util'
require 'right_develop/ci/java_cucumber_formatter'
require 'right_develop/ci/java_spec_formatter'

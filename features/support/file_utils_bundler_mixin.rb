# Copyright (c) 2012- RightScale Inc
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

# Magic hooks that is necessary due to Bundler/RVM craziness interfering with
# our own Cucumbers. This is necessary because our Cucumber scenarios need to create a
# Ruby app that has a distinct, separate bundle from right_develop's own Gemfile, e.g. we
# need to test what happens when RSpec or Cucumber isn't available. Therefore the subprocesses
# that RightDevelop's Cucumber suite launches, should not inherit our bundle.
module FileUtilsBundlerMixin
  def self.included(base)
    if base.respond_to?(:sh) && !base.respond_to?(:sh_without_bundler_taint)
      base.instance_eval {
        alias_method :sh_without_bundler_taint, :sh
        alias_method :sh, :sh_with_bundler_taint
      }
    end
  end

  def sh_with_bundler_taint(*params)
    Bundler.with_clean_env do
      sh_without_bundler_taint(*params)
    end
  end
end

# Install the magic hook.
Kernel.instance_eval { include(::FileUtilsBundlerMixin) }

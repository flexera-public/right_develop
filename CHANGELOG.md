# 3.1

Made CI RSpec/Cucumber integration optional; the Rake task will adapt to whichever gems are present
in the bundle.

# 3.0

Reformatted CI harnesss substantially, changing class names and definitions for better modularity
and compatibility across RSpec v1-3. Rake task interface is compatible with RightDevelop v2;
there should be no problems upgrading from v2 unless you were relying on RightDevelop internals.

# 2.0

Delegated reusable RightDevelop::Git functionality to right_git gem, removed
local class definitions. Some developer-specific git behavior remains.

Other than removing the Git functionality, no interface-breaking changes have occurred; there
should be no problems upgrading from v1 unless you were relying on the Git module.

# 1.0

Initial release calved from RightSupport.


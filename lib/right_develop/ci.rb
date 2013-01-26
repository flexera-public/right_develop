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
require 'right_develop/ci/java_cucumber_formatter'
require 'right_develop/ci/java_spec_formatter'

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

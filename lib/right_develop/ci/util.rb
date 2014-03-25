module RightDevelop::CI
  module Util
    module_function

    # Regular expression used to determine which characters of a string are allowed
    # in Java class names.
    JAVA_CLASS_NAME = /[A-Za-z0-9_]/

    # The dot character gets special treatment: even if we XML-escape it, Jenkins will assume
    # that it functions as a package separator. So, we'll replace it with an equivalent Unicode
    # character. Hooray homographic character attacks!
    JAVA_PACKAGE_SEPARATOR = '.'

    # Replacement codepoint that looks a bit like a period
    JAVE_PACKAGE_SEPARATOR_HOMOGLYPH = '&#xb7;'

    # Make a string suitable for parsing by Jenkins JUnit display plugin by escaping any non-valid
    # Java class name characters as an XML entity. This prevents Jenkins from interpreting "hi1.2"
    # as a package-and-class name.
    #
    # @param [String] name
    # @return [String] string with all non-alphanumerics replaced with an equivalent XML hex entity
    def pseudo_java_class_name(name)
      result = ''

      name.each_char do |chr|
        if chr =~ JAVA_CLASS_NAME
          result << chr
        elsif chr == JAVA_PACKAGE_SEPARATOR
          result << JAVE_PACKAGE_SEPARATOR_HOMOGLYPH
        else
          chr = chr.unpack('U')[0].to_s(16)
          result << "&#x#{chr};"
        end
      end

      result
    end
  end
end
if RUBY_VERSION =~ /^1\.8/
  require 'iconv'
end

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

    # Regular expression that matches characters that need to be escaped inside CDATA
    # c.f. http://www.w3.org/TR/xml11/#charsets
    # RestrictedChar ::= [#x1-#x8] | [#xB-#xC] | [#xE-#x1F] | [#x7F-#x84] | [#x86-#x9F]
    INVALID_CDATA_CHARACTER = /[\x01-\x08\x0b\x0c\x0e-\x1f\x7f-\x84\x86-\x9f]/

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

    # Strip invalid UTF-8 sequences from a string and entity-escape any character that can't legally
    # appear inside XML CDATA. If test output contains weird data, we could end up generating
    # invalid JUnit XML which will choke Java. Preserve the purity of essence of our precious XML
    # fluids!
    #
    # @return [String] the input with all invalid UTF-8 replaced by the empty string
    # @param [String] untrusted a string (of any encoding) that might contain invalid UTF-8 sequences
    def purify(untrusted)
      # First pass: strip bad UTF-8 characters
      if RUBY_VERSION =~ /^1\.8/
        iconv = Iconv.new('UTF-8//IGNORE', 'UTF-8')
        result = iconv.iconv(untrusted)
      else
        result = untrusted.force_encoding(Encoding::BINARY).encode('UTF-8', :undef=>:replace, :replace=>'')
      end

      # Second pass: entity escape characters that can't appear in XML CDATA.
      result.gsub(INVALID_CDATA_CHARACTER) do |ch|
        "&#x%s;" % [ch.unpack('H*').first]
      end
    end
  end
end
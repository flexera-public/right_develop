#
# Copyright (c) 2013 RightScale Inc
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

# ancestor
require 'right_develop/utility'

# localized
require 'securerandom'

module RightDevelop::Utility::Versioning

  BUILD_VERSION_REGEX = /^(\d)+\.(\d)+\.(\d)+$/

  module_function

  # Determines if version string is valid for building purposes.
  def is_valid_build_version?(version)
    return !!BUILD_VERSION_REGEX.match(version)
  end

  # Parses the given version string into numeric values.
  #
  # === Parameters
  # @param [String] version
  #
  # === Return
  # @return [Array] numeric values
  def parse_build_version(version)
    unless matched = BUILD_VERSION_REGEX.match(version)
      raise ArgumentError.new("Invalid version #{version.inspect}")
    end
    return matched[1..-1].map { |s| s.to_i }
  end

  # specific to building packages under windows
  if ::RightDevelop::Utility::Shell.is_windows?

    DEFAULT_WINDOWS_MODULE_VERSION = "1.0.0.1"
    DEFAULT_COPYRIGHT_YEARS = '2010-2013'

    # Restores the default version string in all modules to make files appear
    # unchanged to source control.
    #
    # === Return
    # @return [TrueClass] always true
    def restore_default_version(base_dir_path)
      set_version_for_modules(base_dir_path, version_string = nil)
      true
    end

    # Sets the given version string as the compilable version for all known
    # buildable modules in the given directory hierarchy. restores the
    # default version string for all modules if nil.
    #
    # === Parameters
    # @param [String] base_dir_path for search of module files
    # @param [String] version_string in <major>.<minor>.<build>[.<revision>] format or nil to restore original version
    #
    # === Return
    # @return [TrueClass] always true
    def set_version_for_modules(base_dir_path, version_string = nil)
      restore_original_version = version_string.nil?
      version_string = DEFAULT_WINDOWS_MODULE_VERSION if restore_original_version

      # match Windows-style version string to regular expression. Windows
      # versions require four fields (major.minor.build.revision) but we
      # accept three fields per RightScale convention and default the last
      # field to one.
      version_parse = (version_string + ".1").match(/(\d+)\.(\d+)\.(\d+)\.(\d+)/)
      raise "Invalid version string" unless version_parse

      # get individual values.
      major_version_number    = version_parse[1].to_i
      minor_version_number    = version_parse[2].to_i
      build_version_number    = version_parse[3].to_i
      revision_version_number = version_parse[4].to_i

      version_string = "#{major_version_number}.#{minor_version_number}.#{build_version_number}.#{revision_version_number}"

      # generate copyright string for current year or default copyright
      # years to soothe source control.
      copyright_year = restore_original_version ? DEFAULT_COPYRIGHT_YEARS : "2010-#{Time.now.year}"
      copyright_string = "Copyright (c) #{copyright_year} RightScale Inc"

      # find and replace version string in any kind of source file used by
      # C# modules that might contain version or copyright info.
      ::Dir.chdir(base_dir_path) do
        # C# assembly info.
        ::Dir.glob(File.join('**', 'AssemblyInfo.c*')).each do |file_path|
          replacements = {
            /\[assembly\: *AssemblyVersion\(\"\d+\.\d+\.\d+\.\d+\"\)\]/ => "[assembly: AssemblyVersion(\"#{version_string}\")]",
            /\[assembly\: *AssemblyFileVersion\(\"\d+\.\d+\.\d+\.\d+\"\)\]/ => "[assembly: AssemblyFileVersion(\"#{version_string}\")]",
            /\[assembly\: *AssemblyCopyright\(\".*"\)\]/ => "[assembly: AssemblyCopyright(\"#{copyright_string}\")]",
            /\[assembly\: *AssemblyCopyrightAttribute\(\".*"\)\]/ => "[assembly: AssemblyCopyrightAttribute(\"#{copyright_string}\")]"
          }
          replace_in_file(file_path, replacements)
        end

        # C# manifests.
        ::Dir.glob(File.join('**', '*.manifest')).each do |file_path|
          replacements = {/\<assemblyIdentity +version=\"\d+\.\d+\.\d+\.\d+\"/ => "<assemblyIdentity version=\"#{version_string}\""}
          replace_in_file(file_path, replacements)
        end

        # C++ resource files.
        ::Dir.glob(File.join('**', '*.rc')).each do |file_path|
          replacements = {
            /FILEVERSION +\d+, *\d+, *\d+, *\d+/ => "FILEVERSION #{major_version_number}, #{minor_version_number}, #{build_version_number}, #{revision_version_number}",
            /PRODUCTVERSION +\d+, *\d+, *\d+, *\d+/ => "PRODUCTVERSION #{major_version_number}, #{minor_version_number}, #{build_version_number}, #{revision_version_number}",
            /VALUE +"FileVersion", *\"\d+, *\d+, *\d+, *\d+\"/ => "VALUE \"FileVersion\", \"#{version_string}\"",
            /VALUE +"FileVersion", *\"\d+\.\d+\.\d+\.\d+\"/ => "VALUE \"FileVersion\", \"#{version_string}\"",
            /VALUE +"ProductVersion", *\"\d+, *\d+, *\d+, *\d+\"/ => "VALUE \"ProductVersion\", \"#{version_string}\"",
            /VALUE +"ProductVersion", *\"\d+\.\d+\.\d+\.\d+\"/ => "VALUE \"ProductVersion\", \"#{version_string}\"",
            /VALUE +"LegalCopyright", *\".*\"/ => "VALUE \"LegalCopyright\", \"#{copyright_string}\""
          }
          replace_in_file(file_path, replacements)
        end

        # wix installer project main source.
        ::Dir.glob(File.join('**', 'Product.wxs')).each do |file_path|
          # the Windows Installer only cares about the first three elements of the version
          installerized_version = "#{major_version_number}.#{minor_version_number}.#{build_version_number}"
          replacements = {/\<\?define ProductVersion=\"\d+\.\d+\.\d+\"/ => "<?define ProductVersion=\"#{installerized_version}\""}
          replace_in_file(file_path, replacements)

          # when producing a new installer, a new product code is required
          new_guid = restore_original_version ? "{00000000-0000-0000-0000-000000000000}" : generate_guid
          replacements = {/\<\?define ProductCode=\"\{.*\}\"/ => "<?define ProductCode=\"#{new_guid}\""}
          replace_in_file(file_path, replacements)
        end
      end
      true
    end

    # Replaces the given regular exressions in the given file, saving changes only
    # if necessary.
    #
    # === Parameters
    # file_path(string):: path to text file which may or may not contain strings to replace
    #
    # replacements(Hash):: map of regular expressions to literal replacement text
    def replace_in_file(file_path, replacements)
      text = ::File.read(file_path)
      changed = nil
      replacements.each_pair do |pattern, value|
        changed = text.gsub!(pattern, value) || changed
      end
      ::File.open(file_path, 'w') { |f| f.write(text) } if changed
    end

    # Generates a new GUID in Windows registry format (as expected by
    # Microsoft-style source files that contain a GUID).
    #
    # === Return
    # guid(String):: a new guid
    def generate_guid
      result = ::SecureRandom.random_bytes(16)
      a, b, c, d, e, f, g, h = result.unpack('SSSSSSSS')
      guid = sprintf('{%04X%04X-%04X-%04X-%04X-%04X%04X%04X}', a, b, c, d, e, f, g, h)
      guid
    end
  end # is_windows?

end # RightDevelop::Utility::Version

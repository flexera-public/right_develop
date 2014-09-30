require 'simplecov'
require 'coveralls'

SimpleCov.formatter = Coveralls::SimpleCov::Formatter
SimpleCov.start do
  add_filter '/features/'
  add_filter '/spec/'
  add_filter '/vendor/'
end

lib_dir = ::File.expand_path('../../../../../../lib', __FILE__)
$:.unshift(lib_dir) unless $:.include?(lib_dir)

require ::File.expand_path('../config/init', __FILE__)
require ::File.expand_path("../app/#{::RightDevelop::Testing::Server::MightApi::Config.mode}", __FILE__)

run ::RightDevelop::Testing::Server::MightApi::App.const_get(
  ::RightDevelop::Testing::Server::MightApi::Config.mode.capitalize).new

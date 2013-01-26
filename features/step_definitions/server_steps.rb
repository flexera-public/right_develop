#--  -*- mode: ruby; encoding: utf-8 -*-
# Copyright: Copyright (c) 2011 RightScale, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# 'Software'), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

require 'webrick'
require 'webrick/httpservlet'

# Mimic a generic HTTP server with various configurable behaviors
class MockServer < WEBrick::HTTPServer
  attr_accessor :thread, :port, :url

  # Overridden factory method that will tolerate Errno::EADDRINUSE in case a certain
  # TCP port is already used
  def self.new(*args)
    tries ||= 0
    super
  rescue Errno::EADDRINUSE => e
    tries += 1
    if tries > 5
      raise
    else
      retry
    end
  end

  def initialize(options={})
    @port = options[:port] || (4096 + rand(32768-4096))
    @url = "http://localhost:#{@port}"

    logger = WEBrick::Log.new(STDERR, WEBrick::Log::FATAL)
    super(options.merge(:Port => @port, :AccessLog => [], :Logger=>logger))

    # mount servlets via callback
    yield(self)

    #Start listening for HTTP in a separate thread
    @thread = Thread.new do
      self.start()
    end
  end
end

# Mimic a server that exists but hangs without providing any response, not even
# ICMP signals e.g. host unreachable or network unreachable. We simulate this
# by pointing at a port of the RightScale (my) load balancer that is not allowed
# by the security group, which causes the TCP SYN packets to be dropped with no
# acknowledgement.
class BlackholedServer
  attr_accessor :port, :url

  def initialize(options={})
    @port = options[:port] || (4096 + rand(4096))
    @url = "my.rightscale.com:#{@port}"
  end
end

Before do
  @mock_servers = []
end

# Kill running reposes after test finishes.
After do
  @mock_servers.each do |server|
    if server.is_a?(MockServer)
      server.thread.kill
    end
  end
end

Given /^(an?|\d+)? (overloaded|blackholed) servers?$/ do |number, behavior|
  number = 0 if number =~ /no/
  number = 1 if number =~ /an?/
  number = number.to_i
  
  number.times do
    case behavior
      when 'overloaded'
        proc = Proc.new do
          sleep(10)
          'Hi there! I am overloaded.'
        end
        server = MockServer.new do |s|
          s.mount('/', WEBrick::HTTPServlet::ProcHandler.new(proc))
        end
      when 'blackholed'
        server = BlackholedServer.new()
      else
        raise ArgumentError, "Unknown server behavior #{behavior}"
    end

    @mock_servers << server
  end
end

Given /^(an?|\d+)? servers? that responds? with ([0-9]+)$/ do |number, status_code|
  number = 0 if number =~ /no/
  number = 1 if number =~ /an?/
  number = number.to_i

  status_code = status_code.to_i

  proc = Proc.new do
    klass = WEBrick::HTTPStatus::CodeToError[status_code]
    klass.should_not be_nil
    raise klass, "Simulated #{status_code} response"
  end

  number.times do
    server = MockServer.new do |s|
      s.mount('/', WEBrick::HTTPServlet::ProcHandler.new(proc))
    end

    @mock_servers << server
  end
end

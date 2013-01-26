# Rails' constantize method to convert passed in policy to the actual class
def constantize(camel_cased_word)
  names = camel_cased_word.split('::')
  names.shift if names.empty? || names.first.empty?

  constant = Object
  names.each do |name|
    constant = constant.const_defined?(name) ? constant.const_get(name) : constant.const_missing(name)
  end
  constant
end

Given /^(\w+) balancing policy$/ do |policy|
  @health_check = Proc.new do |endpoint|
    begin
      RightDevelop::Net::HTTPClient.new.get(endpoint, {:timeout => 1, :open_timeout => 1})
      true
    rescue Exception => e
      false
    end
  end

  @options ||= { :policy => constantize("RightDevelop::Net::LB::" + policy), :health_check => @health_check }
end

When /^a client makes a (buggy )?load-balanced request to '(.*)'$/ do |buggy, path|
  t = RightDevelop::Net::HTTPClient::DEFAULT_OPTIONS[:timeout]
  o = RightDevelop::Net::HTTPClient::DEFAULT_OPTIONS[:open_timeout]
  step "a client makes a #{buggy}load-balanced request to '#{path}' with timeout #{t} and open_timeout #{o}"
end

When /^a client makes a (buggy )?load-balanced request to '(.*)' with timeout (\d+) and open_timeout (\d+)$/ do |buggy, path, timeout, open_timeout|
  buggy = !(buggy.nil? || buggy.empty?)

  @mock_servers.should_not be_nil
  @mock_servers.empty?.should be_false

  timeout = timeout.to_i
  open_timeout = open_timeout.to_i
  urls = @mock_servers.map { |s| s.url }
  @request_balancer = RightDevelop::Net::RequestBalancer.new(urls)
  @request_attempts = 0
  @request_t0 = Time.now
  @http_client = RightDevelop::Net::HTTPClient.new
  begin
    @request_balancer.request do |url|
      @request_attempts += 1
      raise ArgumentError, "Fall down go boom!" if buggy
      @http_client.get("#{url}#{path}", {:timeout => timeout, :open_timeout => open_timeout})
    end
  rescue Exception => e
    @request_error = e
  end
  @request_t1 = Time.now
end

Then /^the request should (\w+ ?\w*)$/ do |behavior|
  case behavior
    when 'complete'
      error_expected = false
    when 'raise'
      error_expected = true
    when /raise (\w+)/
      error_expected = true
      error_class_expected = /raise (\w+)/.match(behavior)[1]
    else
      raise ArgumentError, "Unknown request behavior #{behavior}"
  end

  if !error_expected && @request_error
    puts '!' * 80
    puts @request_error.class.inspect
    puts @request_error.class.superclass.inspect
    puts '!' * 80
  end
  @request_error.should be_nil unless error_expected
  @request_error.should_not be_nil if error_expected
  @request_error.class.name.should =~ Regexp.new(error_class_expected) if error_class_expected
end

Then /^the request should (\w+ ?\w*) in less than (\d+) seconds?$/ do |behavior, time|
  step "the request should #{behavior}"
  #allow 10% margin of error due to Ruby/OS scheduler variance
  (@request_t1.to_f - @request_t0.to_f).should <= (time.to_f * 1.10)
end

Then /^the request should be attempted once$/ do
  @request_attempts.should == 1
end

Then /^the request should be attempted ([0-9]+) times$/ do |n|
  @request_attempts.should == n.to_i
end

When /^a client makes a (buggy )?request to '(.*)'$/ do |buggy, path|
  t = RightDevelop::Net::HTTPClient::DEFAULT_OPTIONS[:timeout]
  o = RightDevelop::Net::HTTPClient::DEFAULT_OPTIONS[:open_timeout]
  When "a client makes a #{buggy}request to '#{path}' with timeout #{t} and open_timeout #{o}"
end


When /^a client makes a (buggy )?request to '(.*)' with timeout (\d+) and open_timeout (\d+)$/ do |buggy, path, timeout, open_timeout|
  buggy = !(buggy.nil? || buggy.empty?)

  @mock_servers.should_not be_nil
  @mock_servers.size.should == 1

  timeout = timeout.to_i
  open_timeout = open_timeout.to_i
  url = @mock_servers.first.url

  @http_client = RightDevelop::Net::HTTPClient.new(:timeout=>timeout, :open_timeout=>open_timeout)
  @request_t0 = Time.now
  begin
    raise ArgumentError, "Fall down go boom!" if buggy
    @http_client.get("#{url}#{path}", {:timeout => timeout, :open_timeout => open_timeout})
  rescue Exception => e
    @request_error = e
  end
  @request_t1 = Time.now
end

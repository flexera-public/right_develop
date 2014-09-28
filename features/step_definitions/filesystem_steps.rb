Then /^the directory '(.*)' should contain files/ do |dir|
  dir = ruby_app_path(dir)
  File.directory?(dir).should be_true
  Dir[File.join(dir, '*')].should_not be_empty
end

Then /^the file '(.*)' should (not )?exist?$/ do |file, negatory|
  file = ruby_app_path(file)

  if negatory.nil? || negatory.empty?
    Pathname.new(file).should exist
  else
    Pathname.new(file).should_not exist
  end
end

Then /^the file '(.*)' should mention ([0-9]) (passing|failing|skipped) test cases?$/ do |file, n, pass_fail_skip|
  file = ruby_app_path(file)
  n = Integer(n)

  Pathname.new(file).should exist

  doc = Nokogiri.XML(File.open(file, 'r'))

  all_testcases = doc.css('testcase').size
  failing_testcases = doc.css('testcase failure').size
  skipped_testcases = doc.css('testcase skipped').size
  passing_testcases = all_testcases - failing_testcases - skipped_testcases

  case pass_fail_skip
  when 'passing'
    passing_testcases.should == n
  when 'failing'
    failing_testcases.should == n
  when 'skipped'
    skipped_testcases.should == n
  else
    raise NotImplementedError, "WTF #{pass_fail_skip}"
  end
end

Then /^the file '(.*)' should (not )?mention the class (.*)$/ do |file, negate, klass|
  file = ruby_app_path(file)

  Pathname.new(file).should exist

  doc = Nokogiri.XML(File.open(file, 'r'))
  classnames = doc.css('testcase').map { |t| t['classname'][6..-1] }

  if negate
    classnames.should_not include(klass)
  else
    classnames.should include(klass)
  end
end


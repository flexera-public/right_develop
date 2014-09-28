Then /^the output should contain '(.*)'$/ do |expected_output|
  @ruby_app_output.should include(expected_output)
end

Then /^the output should not contain '(.*)'$/ do |expected_output|
  @ruby_app_output.should_not include(expected_output)
end

# Tests for RSpec progress bar sequences of '......*...EE....' -- relies on these appearing on
# their own lines of output
Then /the output should contain ([0-9]+) '(.)' progress ticks?/ do |n, character|
  n = Integer(n)

  begin
    progress = @ruby_app_output.split("\n").select { |l| l =~ /^[ .*EF]+$/ }
    count = progress.map { |l| l.scan(character).count }.inject(0) { |a, x| a + x }
    count.should == n
  rescue Exception => e
    puts "Spurious output:"
    puts @ruby_app_output
    puts '--------------------------------------------------------------'
    raise
  end
end

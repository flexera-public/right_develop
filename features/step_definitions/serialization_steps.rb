Given /^a serializer named '(.+)'$/ do |klass|
  @serializer = klass.to_const
end

Given /^a stateful Ruby class named '(.*)'$/ do |name|
  name = name.to_sym
  ivars = 1 + rand(10)


  Kernel.__send__(:remove_const, name) if Kernel.const_defined?(name)

  @stateful_ruby_class = Class.new(Object)
  Kernel.__send__(:const_set, name, @stateful_ruby_class)

  @stateful_ruby_class.instance_eval do
    define_method(:initialize) do
      ivars.times do
        self.instance_variable_set("@instance_variable_#{random_value(Integer)}", random_value(nil, [String]))
      end
    end

    define_method(:==) do |other|
      result = (Set.new(self.instance_variables) == Set.new(other.instance_variables))

      self.instance_variables.each do |ivar|
        result &&= (self.instance_variable_get(ivar) == other.instance_variable_get(ivar))
      end

      result
    end
  end
end

When /^I serialize the Ruby value: (.*)$/ do |expression|
  @ruby_value = eval(expression)
  @serialized_value = @serializer.dump(@ruby_value)
end

When /^I serialize a complex random data structure$/ do
  @ruby_value = random_value(nil, [String])
  @serialized_value = @serializer.dump(@ruby_value)
end

When /^an eldritch force deletes a key from the serialized value$/ do
  hash = RightDevelop::Data::Serializer::Encoder.load(@serialized_value)
  hash.delete(hash.keys[rand(hash.keys.size)])
  @serialized_value = @serializer.dump(hash)
end

Then /^the serialized value should be: (.*)$/ do |expression|
  if (@serialized_value =~ /^\{/) || (expression =~ /^\{/)
    # Hash: ordering of JSON representation is unimportant; load as pure JSON and compare values
    RightDevelop::Data::Serializer::Encoder.load(@serialized_value).should ==
    RightDevelop::Data::Serializer::Encoder.load(expression)
  else
    # Any other data: exact comparison
    @serialized_value.should == expression
  end
end

Then /^the serialized value should round-trip cleanly$/ do
  case @ruby_value
  when Float
    # Floating-point numbers lose some precision due to truncation
    @serializer.load(@serialized_value).should be_within(0.000001).of(@ruby_value)
  when Time
    # Times are stored with accuracy ~ 1 sec
    @serializer.load(@serialized_value).to_i.should == @ruby_value.to_i
  else
    # Everything else should compare identical
    @serializer.load(@serialized_value).should == @ruby_value
  end
end

When /^the serialized value should fail to round\-trip$/ do
  @serializer.load(@serialized_value).should_not == @ruby_value
end

Then /^the serialized value should be a JSON (.*)$/ do |json_type|
  case json_type
    when 'object'
      @serialized_value.should =~ /^\{.*\}$/
    when 'string'
      @serialized_value.should =~ /^".*"$/
    when 'number'
      @serialized_value.should =~ /^".*"$/
    when 'true', 'false', 'null'
      @serialized_value.should == json_type
    else
      raise NotImplementedError, "Unknown JSON type"
  end
end

Then /^the serialized value should have a suitable _ruby_class/ do
  @serialized_value.should =~ /"_ruby_class":"#{Regexp.escape(@ruby_value.class.name)}"/
end

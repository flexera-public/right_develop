require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper.rb')

describe RightDevelop::CI::Util do
  # The module itself
  subject { RightDevelop::CI::Util }

  context '.pseudo_java_class_name' do
    it 'does nothing to well-formed class names' do
      subject.pseudo_java_class_name('HelloWorld').should == 'HelloWorld'
      subject.pseudo_java_class_name('HelloWorld_1234_487').should == 'HelloWorld_1234_487'
    end

    it 'escapes punctuation' do
      subject.pseudo_java_class_name('Hello.abc').should == 'Hello&#x2e;abc'
      subject.pseudo_java_class_name('Hello-abc').should == 'Hello&#x2d;abc'
      subject.pseudo_java_class_name('Hello abc').should == 'Hello&#x20;abc'
    end
  end
end
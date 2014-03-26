require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper.rb')

describe RightDevelop::CI::Util do
  subject { described_class }

  context '.pseudo_java_class_name' do
    it 'does nothing to well-formed class names' do
      subject.pseudo_java_class_name('HelloWorld').should == 'HelloWorld'
      subject.pseudo_java_class_name('HelloWorld_1234_487').should == 'HelloWorld_1234_487'
    end

    it 'escapes punctuation' do
      subject.pseudo_java_class_name('Hello-abc').should == 'Hello&#x2d;abc'
      subject.pseudo_java_class_name('Hello abc').should == 'Hello&#x20;abc'
    end

    it 'uses a homoglyph for "." to foil Jenkins class-name parsing' do
       subject.pseudo_java_class_name('Hello.abc').should == 'Hello&#xb7;abc'
    end
  end

  context '.purify' do
    let(:bad_utf8) { "hello\xc1world" }

    it 'strips invalid UTF-8' do
      result = subject.purify(bad_utf8)
      if RUBY_VERSION =~ /^1\.8/
        expect(result).to eq "hello\303\201world"
      else
        expect(result).to eq 'hello?world'
      end
    end
  end
end

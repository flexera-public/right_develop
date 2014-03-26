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
    let(:bad_cdata) { "hello\x12\vworld" }
    let(:good_cdata) { "hello\r\n\tworld" }

    it 'strips invalid UTF-8' do
      result = subject.purify(bad_utf8)
      if RUBY_VERSION =~ /^1\.8/
        expect(result).to eq "helloworld"
      else
        expect(result).to eq 'helloworld'
      end
    end

    it 'entity escapes non-XML control characters' do
      expect(subject.purify(bad_cdata)).to eq 'hello&#x12;&#x0b;world'
      expect(subject.purify(good_cdata)).to eq good_cdata
    end
  end
end

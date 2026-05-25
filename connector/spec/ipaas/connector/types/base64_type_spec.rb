require 'spec_helper'

describe IPaaS::Connector::Types::Base64Type do
  it 'should define the ruby class' do
    expect(subject.ruby_class).to eq(String)
  end

  it 'should return false for nested?' do
    expect(subject.nested?).to be_falsey
  end

  it 'should provide an example' do
    field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :base64)
    expect(subject.example(field)).to eq(Base64.strict_encode64('Hello World!'))
  end

  describe 'resolve' do
    it 'should leave nils untouched' do
      expect(subject.resolve(nil)).to be_nil
    end

    it 'should leave base64 encoded strings untouched' do
      non_strict = Base64.encode64('Hello World!')
      expect(subject.resolve(non_strict)).to eq(non_strict)
    end

    it 'should leave strict base64 encoded strings untouched' do
      strict = Base64.strict_encode64('Hello World!')
      expect(subject.resolve(strict)).to eq(strict)
    end

    it 'should leave non-string values untouched' do
      expect(subject.resolve(15.12)).to eq(15.12)
    end

    it 'should strict encode base64' do
      expect(subject.resolve('Hello Moon!')).to eq(Base64.strict_encode64('Hello Moon!'))
    end
  end
end

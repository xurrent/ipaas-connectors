require 'spec_helper'

describe IPaaS::Connector::Types::UriType do
  it 'should define the ruby class' do
    expect(subject.ruby_class).to eq(String)
  end

  it 'should return false for nested?' do
    expect(subject.nested?).to be_falsey
  end

  it 'should provide an example' do
    field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :uri)
    expect(subject.example(field)).to eq('https://xurrent.com')
  end

  describe 'valid?' do
    it 'should validate HTTPS uri as valid' do
      expect(subject.valid?('https://foo.example.com')).to be_truthy
    end

    it 'should validate HTTP uri as valid' do
      expect(subject.valid?('http://foo.example.com')).to be_truthy
    end

    it 'should validate FTPS uri as valid' do
      expect(subject.valid?('ftps://foo.example.com')).to be_truthy
    end

    it 'should validate FTP uri as valid' do
      expect(subject.valid?('ftp://foo.example.com')).to be_truthy
    end

    it 'should invalidate generic URIs' do
      expect(subject.valid?('foo')).to be_falsey
    end

    it 'should invalidate incorrect URIs' do
      expect(subject.valid?('http:||bra.ziz')).to be_falsey
    end
  end
end

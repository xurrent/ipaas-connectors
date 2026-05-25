require 'spec_helper'

describe IPaaS::Connector::Types::RegexpType do
  it 'should define the ruby class' do
    expect(subject.ruby_class).to eq(Regexp)
  end

  it 'should return false for nested?' do
    expect(subject.nested?).to be_falsey
  end

  it 'should provide an example' do
    field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :regexp)
    expect(subject.example(field)).to eq(/\A[a-z]+\z/)
  end

  it 'should resolve a string to a regexp' do
    expect(subject.resolve('\A[a-z]+\z')).to eq(/\A[a-z]+\z/)
  end

  it 'should convert type to string before generating the regexp' do
    expect(subject.resolve([1, 2])).to eq(/[1, 2]/)
  end
end

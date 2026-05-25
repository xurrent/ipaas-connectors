require 'spec_helper'

describe IPaaS::Connector::Types::BinaryType do
  it 'should define the ruby class' do
    expect(subject.ruby_class).to eq(String)
  end

  it 'should return false for nested?' do
    expect(subject.nested?).to be_falsey
  end

  it 'should provide an example' do
    field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :binary)
    expect(subject.example(field)).to eq('Hello World!')
  end

  it 'should provide an example when the pattern is set' do
    field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :binary, pattern: /a/)
    expect(subject.example(field)).to eq('no-example-for-pattern')
  end
end

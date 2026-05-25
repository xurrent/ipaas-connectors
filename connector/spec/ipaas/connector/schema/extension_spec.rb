require 'spec_helper'

describe IPaaS::Connector::Schema::Extension do
  let(:schema) do
    IPaaS::Connector::Schema.new('reference')
  end

  it 'should include valid schema extensions' do
    module FooFieldExtension
      include IPaaS::Connector::Schema::Extension

      schema do
        field :included_foo, 'Included Foo', :string
      end
    end
    schema.includes(FooFieldExtension)
    expect(schema.fields.last.id).to eq(:included_foo)
    expect(schema.fields.last.label).to eq('Included Foo')
    expect(schema.fields.last.type).to eq(:string)
  end
end

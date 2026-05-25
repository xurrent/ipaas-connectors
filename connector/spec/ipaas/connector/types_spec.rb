require 'spec_helper'

describe IPaaS::Connector::Types do
  describe 'register' do
    it 'should validate ruby_class is implemented' do
      expect do
        subject.register(double(example: :foo))
      end.to raise_error('Please implement ruby_class for #[Double (anonymous)].')
    end

    it 'should validate example is implemented' do
      expect do
        subject.register(double(ruby_class: :foo))
      end.to raise_error('Please implement example for #[Double (anonymous)].')
    end

    it 'should register custom types' do
      # already registered JobType in the spec helper
      expect(subject.for(:job)).to eq(JobType)
      # for 100% code coverage
      JobType.ruby_class
      RunbookType.ruby_class
      RunbookActionType.ruby_class
    end
  end

  it 'should return all types' do
    expect(subject.all).to be_a_kind_of(Hash)
    expect(subject.all.keys.sort).to eq([:any, :base64, :binary, :boolean, :date, :date_time, :float, :hash, :integer,
                                         :job, :nested, :recurrence, :regexp, :ruby,
                                         :runbook, :runbook_action, :runbook_variable, :schema_field,
                                         :secret_string, :string, :time, :time_of_day, :time_zone, :uri,])
  end

  it 'should retrieve a specific type' do
    expect(subject.for(:integer)).to eq(IPaaS::Connector::Types::IntegerType)
  end

  it 'all example values are resolved to correct ruby class' do
    # checked in IPaaS::Connector::Mapping::ResolvedMapping#validate_type_def_type

    subject.all.each do |key, type_class|
      field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: key)
      resolved_value = type_class.resolve(type_class.example(field))
      if resolved_value.present?
        expect(resolved_value.is_a?(field.type_def.ruby_class))
          .to be_truthy, "Bad example for #{key}/#{type_class}: #{resolved_value.class}"
      end
    end
  end

  describe 'Base mixin' do
    module FooType
      include IPaaS::Connector::Types::Base
    end

    it 'should extract the key from the module name' do
      expect(FooType.key).to eq(:foo)
    end

    it 'should default nested? to false' do
      expect(FooType.nested?).to be_falsey
    end

    it 'should define the nested_example helper method' do
      nested_field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :nested)
      nested_field.field :nested, 'Nested', :string
      expect(FooType.send(:fields_example, nested_field.fields)).to eq({ nested: 'Hello World!' })
    end

    it 'should skip nil entries in fields_example' do
      nested_field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :nested)
      nested_field.field :nested, 'Nested', :string
      fields_with_nil = [nil, *nested_field.fields]
      expect(FooType.send(:fields_example, fields_with_nil)).to eq({ nested: 'Hello World!' })
    end
  end
end

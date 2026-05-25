require 'spec_helper'

describe IPaaS::Connector::Definition do
  describe 'Permissions definition' do
    it 'should not allow multiple connections in a single class' do
      expect do
        Class.new(IPaaS::Connector::Definition) do
          connector 'foo' do
          end
          connector 'bar' do
          end
        end
      end.to raise_exception('Only one connector per class allowed')
    end

    it 'allows multiple classes with connections' do
      Class.new(IPaaS::Connector::Definition) do
        connector 'foo' do |c|
          c.name 'foo-fie'
        end
      end
      Class.new(IPaaS::Connector::Definition) do
        connector 'bar' do |c|
          c.name 'barbie'
        end
      end
      expect(IPaaS::Connector.by_uuid('foo').name).to eq('foo-fie')
      expect(IPaaS::Connector.by_uuid('bar').name).to eq('barbie')
    end

    it 'disallows multiple classes with connection with the same uuid' do
      Class.new(IPaaS::Connector::Definition) do
        connector 'foo' do |c|
          c.name 'foo-fie'
        end
      end
      expect do
        Class.new(IPaaS::Connector::Definition) do
          connector 'foo' do |c|
          end
        end
      end.to raise_exception('Duplicate Connector UUID: foo, in default scope.')
      expect(IPaaS::Connector.by_uuid('foo').name).to eq('foo-fie')
    end
  end
end

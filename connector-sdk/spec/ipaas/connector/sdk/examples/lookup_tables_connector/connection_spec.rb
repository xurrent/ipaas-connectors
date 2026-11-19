require 'spec_helper'

describe 'Lookup Tables connection', :lookup_tables, :outbound_connection do
  let(:connector_id) { '01a19c65-6232-71c9-842a-1d22c682e939' }
  let(:config_schema) { connector.outbound_connection.config_schema }

  it 'requires the table and hides the columns written when the connection is saved' do
    expect(config_schema.field(:table).required).to be(true)
    expect(config_schema.field(:columns).visibility).to eq('hidden')
  end

  it 'AC9 refuses a table or columns field mapped any other way, though no step uses the connection' do
    fixed = [{ field_id: :table, fixed: 'device_map' }, { field_id: :columns, fixed: {} }]
    [{ field_id: :table, proc: "'device_map'" }, { field_id: :columns, variable: 'COLUMNS' }].each do |mapping|
      connection = IPaaS::Connector::Connection.parse(
        { uuid: SecureRandom.uuid, direction: 'outbound', name: 'Device map', connector: { uuid: connector_id },
          config_mapping: [*fixed.reject { |other| other[:field_id] == mapping[:field_id] }, mapping], }
      )

      expect(connection.valid?).to be(false)
      expect(connection.errors[:base]).to eq(['A Lookup Tables connection needs a fixed table name'])
    end
  end

  it 'accepts both fields as fixed values' do
    expect(outbound_connection.valid?).to be(true)
  end
end

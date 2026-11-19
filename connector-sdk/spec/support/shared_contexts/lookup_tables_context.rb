shared_context 'lookup tables', :lookup_tables do
  let(:table_uuid) { '01a0f6b1-2680-76e4-aee8-b520070475d4' }
  let(:device) { '01a0f6b1-3a08-7373-ae49-1852b349bd32' }
  let(:ci) { '01a0f6b1-3df0-769b-b08f-87f514d5c544' }
  let(:missing_entry_id) { '01a0f6b1-ffff-7fff-bfff-ffffffffffff' }
  let(:listed) { [{ key: device, label: 'Device ID' }, { key: ci, label: 'CI ID' }] }
  let(:columns_output) { listed.map { |column| { 'column' => column[:key], 'label' => column[:label] } } }
  let(:outbound_connection_config) do
    { table: 'device_map', columns: { table_uuid: table_uuid, table_name: 'device_map', columns: listed } }
  end

  before do
    IPaaS::Job::MemoryLookupTables.reset!
    IPaaS::Job::MemoryLookupTables.define(table_uuid, name: 'device_map', columns: listed)
  end

  def per_column(field_id, values, **others)
    [{ field_id: field_id, nested: values.map { |key, value| { field_id: key, fixed: value } } },
     *others.map { |id, value| { field_id: id, fixed: value } },]
  end

  def add(values)
    IPaaS::Job::MemoryLookupTables.new.add_entry(table_uuid, values)
  end

  def stored
    IPaaS::Job::MemoryLookupTables.entries(table_uuid).to_h { |entry| [entry[:entry_id], entry[:values]] }
  end

  def run_page(input = nil, state: :kept)
    action(input).send(:iteration_state_value=, state) unless state == :kept
    results = action.run
    [results.map { |result| [result[:schema_reference], result[:output]['entries'].pluck('entry_id')] },
     action.iteration_state_value&.to_h,]
  end
end

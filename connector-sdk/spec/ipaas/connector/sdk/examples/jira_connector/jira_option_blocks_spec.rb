require 'spec_helper'
require_relative 'jira_context'

describe 'Jira options blocks', :jira, :outbound_connection do
  let(:connector_id) { '01a13f2d-b655-7332-952d-145b7c29f5c3' }
  let(:bound_helpers) { connector.outbound_connection.helpers_definition.copy_for(outbound_connection) }
  let(:trigger_ids) do
    %w[01a13f2d-b655-7c0d-be71-eec8ecb4ea91 01a13f2d-b655-70c4-97fa-7c335f215c06
       01a13f2d-b655-7530-856c-b254c3d964f4 01a13f2d-b655-7516-8277-0b0b29316e63]
  end
  let(:dependency_values) { { project_key: 'KAN', issue_id_or_key: 'KAN-1' } }
  let(:expected_option_id) do
    { default_project: 'KAN', project_key: 'KAN', issue_type: '10001', priority: '3', transition: '31' }
  end

  before do
    helpers_proxy = bound_helpers.for_proc
    outbound_connection.define_singleton_method(:helpers) { helpers_proxy }
  end

  def stub_list(path, body, query = {})
    stub_request(:get, "#{api}/#{path}").with(query: query).to_return(status: 200, body: body.to_json)
  end

  def stub_option_lists
    page = { 'startAt' => '0', 'maxResults' => JiraConnector::MAX_PAGE_SIZE.to_s }
    stub_list('project/search', { values: [{ key: 'KAN', name: 'Kanban' }], isLast: true },
              page.merge('orderBy' => 'key'))
    stub_creatable_types('KAN', [{ id: '10001', name: 'Task' }])
    stub_list('priority/search', { values: [{ id: '3', name: 'Medium' }], isLast: true }, page)
    stub_list('issue/KAN-1/transitions', { transitions: [{ id: '31', name: 'Done' }] })
  end

  def option_schemas
    triggers = trigger_ids.map { |uuid| IPaaS::Connector::TriggerTemplate.by_uuid(uuid) }
    [['connection', connector.outbound_connection.config_schema]] +
      triggers.map { |template| [template.name, template.config_schema] } +
      connector.actions.map { |action| [action.name, action.input_schema] }
  end

  def every_options_field
    option_schemas.flat_map do |label, schema|
      ids = schema.fields.map(&:id)
      schema.fields.select(&:options).map { |field| [label, ids, field] }
    end
  end

  it 'declares only dependencies that exist as sibling fields, in every schema' do
    mismatched = every_options_field.filter_map do |label, sibling_ids, field|
      missing = field.option_dependencies - sibling_ids
      "#{label}.#{field.id} depends on #{missing.inspect}" if missing.any?
    end
    expect(mismatched).to eq([])
  end

  it 'resolves every options block through the list that field is meant to show' do
    stub_option_lists
    wrong = every_options_field.filter_map do |label, _sibling_ids, field|
      expected = expected_option_id[field.id]
      next "#{label}.#{field.id} carries options but this spec pins no list for it" if expected.nil?

      kwargs = field.option_dependencies.to_h { |name| [name, dependency_values.fetch(name)] }
      ids = field.call_function(:options, outbound_connection, **kwargs).map { |option| option[:id] }
      "#{label}.#{field.id} listed #{ids.inspect}, expected #{[expected].inspect}" unless ids == [expected]
    end
    expect(wrong).to eq([])
  end

  it 'pins the number of options blocks the sweep covers' do
    expect(every_options_field.size).to eq(19)
  end
end

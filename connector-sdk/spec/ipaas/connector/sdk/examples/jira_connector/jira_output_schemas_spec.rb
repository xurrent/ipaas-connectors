require 'spec_helper'
require_relative 'jira_context'

describe 'Jira output schemas', :jira, :outbound_connection do
  let(:connector_id) { '01a13f2d-b655-7332-952d-145b7c29f5c3' }
  let(:trigger_ids) do
    %w[01a13f2d-b655-7c0d-be71-eec8ecb4ea91 01a13f2d-b655-70c4-97fa-7c335f215c06
       01a13f2d-b655-7530-856c-b254c3d964f4 01a13f2d-b655-7516-8277-0b0b29316e63]
  end
  let(:credential_name) { /secret|password|api_?key|authorization|credential|(?<!page_)token/i }

  def output_fields
    templates = connector.actions + trigger_ids.map { |uuid| IPaaS::Connector::TriggerTemplate.by_uuid(uuid) }
    templates.flat_map do |template|
      schemas = template.respond_to?(:output_schemas) ? template.output_schemas : [template.output_schema]
      schemas.compact.flat_map { |schema| walk(template.name, schema.fields) }
    end
  end

  def walk(path, fields)
    Array(fields).flat_map do |field|
      here = "#{path} > #{field.id}"
      [[here, field]] + (field.type == :nested ? walk(here, field.fields) : [])
    end
  end

  it 'returns no field named like a credential unless it is a secret string' do
    exposed = output_fields.select { |_, field| field.id.to_s.match?(credential_name) && !field.secret_string? }
    expect(exposed.map(&:first)).to eq([])
  end

  it 'walks every action and trigger output, nested fields included' do
    expect(output_fields.map(&:first)).to include('Get Issue > issue_key', 'Search Issues > issues > issue_key',
                                                  'Get Issue Comments > comments > author > account_id')
  end
end

require 'spec_helper'

# One resolve of the include_fields as the designer stores them (a nested mapping tree)
# leaves the input, the query and the output schema describing the same selection, and
# every level of the retrieved values is available in the output for later actions to read.
describe 'GraphQL Query Action with three levels of include nesting', :action do
  include GraphqlDeepNestingHelper

  let(:connector_id) { 'd5bbb2a2-4a95-4b49-b490-56711e4455f8' }
  let(:action_template_id) { 'eb80d943-e0a3-44c7-97aa-640e243f9320' }
  let(:outbound_connection_config) { graphql_connector_outbound_connection_config }

  # The designer's shape: one mapping entry per checkbox, nested, not a single fixed hash.
  let(:include_mapping) do
    [{ field_id: :workflow, fixed: 'true' },
     { field_id: :workflow_fields,
       nested: [{ field_id: :tasks, fixed: 'true' },
                { field_id: :tasks_fields,
                  nested: [{ field_id: :approvals, fixed: 'true' },
                           { field_id: :template, fixed: 'true' },], },], },]
  end

  let(:action_input) do
    [{ field_id: :object, fixed: 'tasks' },
     { field_id: :include_fields, nested: include_mapping },]
  end

  let(:sent_queries) { [] }

  before(:each) do
    stub_graphql_connector_introspection

    queries = sent_queries
    stub_request(:post, graphql_connector_endpoint)
      .with { |request| !request.body.include?('__schema') }
      .to_return do |request|
        queries << JSON.parse(request.body)['query']
        { status: 200, headers: graphql_connector_response_headers,
          body: { data: { 'tasks' => {
            'totalCount' => 1,
            'pageInfo' => { 'hasNextPage' => false, 'endCursor' => 'end' },
            'nodes' => [{
              'id' => 'top', 'subject' => 'top task',
              'workflow' => { 'id' => 'w1', 'subject' => 'workflow',
                              'tasks' => { 'nodes' => [{
                                'id' => 'nested', 'subject' => 'nested task',
                                'approvals' => { 'nodes' => [{ 'id' => 'a1', 'status' => 'approved' }] },
                                'template' => { 'id' => 'tt1', 'subject' => 'task template' },
                              }] }, },
            }],
          } } }.to_json, }
      end
  end

  def nested_task_output_field
    nodes = action.output_schemas.first.fields.detect { |field| field.id == :nodes }
    workflow = nodes.fields.detect { |field| field.id == :workflow }
    workflow.fields.detect { |field| field.id == :tasks }
  end

  describe 'input resolution' do
    it 'resolves the stored include tree to its full depth' do
      expect(action.input[:include_fields][:workflow_fields][:tasks_fields].to_hash)
        .to eq('approvals' => true, 'template' => true)
    end
  end

  describe 'output_schema' do
    it 'declares the level-three fields below the nested connection' do
      expect(nested_task_output_field.fields.map(&:id)).to include(:approvals, :template)
    end
  end

  describe 'run' do
    it 'asks for and keeps the level-three records' do
      output = run_action
      nested_task = output[:nodes].first[:workflow][:tasks].first

      expect(sent_queries.last).to include('approvals(first: 100)')
      expect(nested_task[:approvals].map(&:to_h))
        .to eq([{ 'id' => 'a1', 'status' => 'approved' }])
      expect(nested_task[:template].to_h).to eq('id' => 'tt1', 'subject' => 'task template')
    end
  end
end

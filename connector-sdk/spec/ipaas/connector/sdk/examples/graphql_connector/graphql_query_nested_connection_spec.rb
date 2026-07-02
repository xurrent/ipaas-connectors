require 'spec_helper'

# The GraphQL response nests connection content below a 'nodes' layer
# (e.g. request -> notes -> nodes -> [note]). The generated iPaaS schema
# skips that layer (the connection field is an array of the node type).
# The output of the action must match the response schema.
describe 'GraphQL Query Action with nested connection', :action do
  include GraphqlIntrospectionHelper
  include GraphqlNestedConnectionHelper # overrides the introspection schema

  let(:connector_id) { 'd5bbb2a2-4a95-4b49-b490-56711e4455f8' }
  let(:action_template_id) { 'eb80d943-e0a3-44c7-97aa-640e243f9320' }

  let(:outbound_connection_config) { graphql_connector_outbound_connection_config }
  let(:action_input) { { object: 'requests', include_fields: { notes: true } } }

  before(:each) do
    stub_graphql_connector_introspection
    # Warm the schema cache so the input schema contains the 'notes' include
    # boolean when the input mapping is re-resolved at run start; with a cold
    # cache include_fields would be pruned and 'notes' never queried.
    action.outbound_connection.cache_write('gql_schema', graphql_connector_introspection_schema, 3600)

    stub_graphql_connector_query(
      /requests/,
      {
        'requests' => {
          'totalCount' => 1,
          'pageInfo' => { 'hasNextPage' => false, 'endCursor' => 'end' },
          'nodes' => [
            {
              'id' => 'r1',
              'subject' => 'Unable to execute searches',
              'undeclaredField' => 'stripped by output validation',
              'notes' => {
                'nodes' => [
                  { 'id' => 'n1', 'text' => 'When I enter a word in the Search box nothing happens.',
                    'internal' => false, },
                  { 'id' => 'n2', 'text' => 'Reproduced the issue. The search engine is down.',
                    'internal' => true, },
                ],
              },
            },
          ],
        },
      },
    )
  end

  # The generated output schema declares the connection as an array of the
  # node type without the intermediate nodes layer — the reason the response
  # data must be flattened before validation.
  describe 'output_schema' do
    it 'declares the nested connection as an array of records without a nodes layer' do
      nodes_field = action.output_schemas.first.fields.detect { |f| f.id == :nodes }
      notes_field = nodes_field.fields.detect { |f| f.id == :notes }

      expect(notes_field.array).to be_truthy
      expect(notes_field.fields.map(&:id)).to contain_exactly(:id, :text, :internal)
    end
  end

  describe 'run' do
    # Simple (non-connection) queries are covered by graphql_query_action_spec.rb;
    # this file focuses on the nested connection below the top-level nodes layer.
    # Full code path: dynamic output schema generation, response JSON, parsing
    # by run, and validation on the resolved mapping.
    it 'keeps the top-level nodes layer and flattens the nested connection to an array of records' do
      output = run_action
      expect(output[:total_count]).to eq(1)
      expect(output[:nodes].length).to eq(1)
      # the undeclared field is stripped, proving the record passed output
      # validation — the notes array below survives that same validation
      expect(output[:nodes].first).not_to have_key(:undeclaredField)
      # subject lives on the record itself, so this also proves the records
      # are not wrapped in a connection-shaped hash
      expect(output[:nodes].first[:subject]).to eq('Unable to execute searches')

      notes = output[:nodes].first[:notes]
      expect(notes).to be_an(Array)
      # text/internal live on the note records, so these also prove each
      # element is a note hash and not an intermediate nodes wrapper
      expect(notes.map { |n| n[:text] }).to eq(
        [
          'When I enter a word in the Search box nothing happens.',
          'Reproduced the issue. The search engine is down.',
        ],
      )
      expect(notes.map { |n| n[:internal] }).to eq([false, true])
    end

    describe 'when the nested connection is not included' do
      let(:action_input) { { object: 'requests' } }

      # Contrast case: the response stub still contains notes, but without
      # include_fields the schema does not declare it, so it is stripped.
      it 'omits the nested connection from the output' do
        output = run_action
        expect(output[:nodes].first[:subject]).to eq('Unable to execute searches')
        expect(output[:nodes].first).not_to have_key(:notes)
      end
    end

    describe 'simple object query' do
      let(:action_input) { { object: 'firstRequest', include_fields: { notes: true } } }

      it 'flattens a nested connection in the object result to an array of records' do
        stub_graphql_connector_query(
          /firstRequest/,
          {
            'firstRequest' => {
              'id' => 'r1',
              'subject' => 'Unable to execute searches',
              'notes' => { 'nodes' => [{ 'id' => 'n1', 'text' => 'first note', 'internal' => false }] },
            },
          },
        )

        output = run_action
        # the sibling field proves only the connection is rewritten, not the record
        expect(output[:subject]).to eq('Unable to execute searches')
        expect(output[:notes]).to be_an(Array)
        expect(output[:notes].map { |n| n[:text] }).to eq(['first note'])
      end
    end

    describe 'list query' do
      let(:action_input) { { object: 'recentRequests', include_fields: { notes: true } } }

      it 'flattens a nested connection in each record to an array of records' do
        stub_graphql_connector_query(
          /recentRequests/,
          {
            'recentRequests' => [
              {
                'id' => 'r1',
                'subject' => 'Unable to execute searches',
                'notes' => { 'nodes' => [{ 'id' => 'n1', 'text' => 'first note', 'internal' => false }] },
              },
            ],
          },
        )

        output = run_action
        # the sibling field proves only the connection is rewritten, not the record
        expect(output[:nodes].first[:subject]).to eq('Unable to execute searches')
        expect(output[:nodes].first[:notes]).to be_an(Array)
        expect(output[:nodes].first[:notes].map { |n| n[:text] }).to eq(['first note'])
      end
    end
  end
end

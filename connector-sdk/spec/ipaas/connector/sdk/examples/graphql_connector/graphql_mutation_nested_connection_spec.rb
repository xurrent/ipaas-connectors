require 'spec_helper'

# Mutation payloads can also contain connection fields; their { nodes: [...] }
# layer must be flattened to adhere to the array defined in the generated schema.
describe 'GraphQL Mutation Action with nested connection', :action do
  include GraphqlIntrospectionHelper
  include GraphqlNestedConnectionHelper # overrides the introspection schema

  let(:connector_id) { 'd5bbb2a2-4a95-4b49-b490-56711e4455f8' }
  let(:action_template_id) { 'f7d7f36f-4746-460a-ba28-30f817be3698' }

  let(:outbound_connection_config) { graphql_connector_outbound_connection_config }
  let(:action_input) { { mutation: 'requestUpdate', input: { subject: 'New subject' } } }

  before(:each) do
    stub_graphql_connector_introspection
    # Warm the schema cache so the input mapping resolves against the
    # mutation-specific input schema when re-resolved at run start.
    action.cache_write('gql_schema', graphql_connector_introspection_schema, 3600)

    stub_graphql_connector_query(
      /requestUpdate/,
      {
        'requestUpdate' => {
          'subject' => 'New subject',
          'undeclaredField' => 'stripped by output validation',
          'notes' => { 'nodes' => [{ 'id' => 'n1', 'text' => 'first note', 'internal' => false }] },
        },
      },
    )
  end

  # The generated output schema declares the connection as an array of the
  # node type without the intermediate nodes layer — the reason the response
  # data must be flattened before validation.
  describe 'output_schema' do
    it 'declares the nested connection as an array of records without a nodes layer' do
      notes_field = action.output_schemas.first.fields.detect { |f| f.id == :notes }

      expect(notes_field.array).to be_truthy
      expect(notes_field.fields.map(&:id)).to contain_exactly(:id, :text, :internal)
    end
  end

  describe 'run' do
    # Full code path: dynamic output schema generation, response JSON, parsing
    # by run, and validation on the resolved mapping.
    it 'flattens a nested connection in the mutation payload to an array of records' do
      output = run_action
      # the undeclared field is stripped, proving the payload passed output
      # validation — the notes array below survives that same validation
      expect(output).not_to have_key(:undeclaredField)
      # the sibling field proves only the connection is rewritten, not the payload
      expect(output[:subject]).to eq('New subject')
      expect(output[:notes]).to be_an(Array)
      expect(output[:notes].map { |n| n[:text] }).to eq(['first note'])
    end
  end
end

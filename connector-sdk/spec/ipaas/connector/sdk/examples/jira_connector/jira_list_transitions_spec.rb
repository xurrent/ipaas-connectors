require 'spec_helper'
require_relative 'jira_context'

describe 'Jira list transitions', :action, :jira do
  describe 'List Transitions' do
    let(:action_template_id) { '01a13f2d-b655-787a-a7b3-e1a913b9af22' }
    let(:action_input) { { issue_id_or_key: 'issue1' } }

    let(:transition_field) do
      {
        allowedValues: %w[red blue],
        defaultValue: 'red',
        hasDefaultValue: false,
        key: 'field_key',
        name: 'My Multi Select',
        operations: %w[set add],
        required: false,
        schema: {
          custom: 'com.atlassian.jira.plugin.system.customfieldtypes:multiselect',
          customId: 10_001,
          items: 'option',
          type: 'array',
        },
      }
    end

    let(:transition) do
      {
        id: '1',
        name: 'Start Progress',
        to: {
          id: '3',
          name: 'In Progress',
          description: 'The issue is currently being worked on.',
          iconUrl: 'https://acme.atlassian.net/images/icons/progress.gif',
          self: 'https://acme.atlassian.net/rest/api/3/status/3',
          statusCategory: {
            colorName: 'yellow',
            id: 1,
            key: 'in-flight',
            name: 'In Progress',
            self: 'https://acme.atlassian.net/rest/api/3/statuscategory/1',
          },
        },
        hasScreen: true,
        isAvailable: true,
        isConditional: false,
        isGlobal: false,
        isInitial: false,
        fields: {
          summary: transition_field,
          colour: transition_field,
        },
      }
    end

    def stub_transitions(transitions)
      stub_request(:get, "#{api}/issue/#{action_input[:issue_id_or_key]}/transitions")
        .with(query: { 'expand' => 'transitions.fields' })
        .to_return(status: 200, body: { transitions: transitions }.to_json)
    end

    it 'requests the available transitions for the given issue' do
      stub = stub_transitions([transition])

      run_action(action_input)

      expect(stub).to have_been_requested.once
    end

    it 'maps transition IDs, names, target statuses and availability' do
      stub_transitions([transition])
      output = run_action(action_input)

      expect(output[:transitions].first).to include(
        'transition_id' => '1',
        'name' => 'Start Progress',
        'to_status_id' => '3',
        'to_status_name' => 'In Progress',
        'has_screen' => true,
        'is_available' => true,
        'is_conditional' => false,
        'is_global' => false,
        'is_initial' => false
      )
    end

    it 'maps all target status details and the status category' do
      stub_transitions([transition])

      status = run_action(action_input)[:transitions].first['to_status']

      expect(status).to eq(
        'id' => '3',
        'name' => 'In Progress',
        'description' => 'The issue is currently being worked on.',
        'icon_url' => 'https://acme.atlassian.net/images/icons/progress.gif',
        'self' => 'https://acme.atlassian.net/rest/api/3/status/3',
        'status_category' => {
          'color_name' => 'yellow',
          'id' => 1,
          'key' => 'in-flight',
          'name' => 'In Progress',
          'self' => 'https://acme.atlassian.net/rest/api/3/statuscategory/1',
        }
      )
    end

    it 'preserves the complete transition screen metadata keyed by field ID' do
      stub_transitions([transition])

      fields = run_action(action_input)[:transitions].first['fields']

      expect(fields).to eq(JSON.parse(transition[:fields].to_json))
    end

    it 'maps transition screen fields with their allowed values, defaults and operations' do
      stub_transitions([transition])

      fields = run_action(action_input)[:transitions].first['screen_fields']

      expect(fields.map { |field| field['field_id'] }).to eq(%w[summary colour])
      expect(fields.first).to include(
        'field_id' => 'summary',
        'key' => 'field_key',
        'name' => 'My Multi Select',
        'required' => false,
        'has_default_value' => false,
        'default_value' => 'red',
        'allowed_values' => %w[red blue],
        'operations' => %w[set add]
      )
    end

    it 'maps all transition screen field schema properties' do
      stub_transitions([transition])

      schema = run_action(action_input)[:transitions].first['screen_fields'].first['schema']

      expect(schema).to include(
        'type' => 'array',
        'items' => 'option',
        'custom' => 'com.atlassian.jira.plugin.system.customfieldtypes:multiselect',
        'custom_id' => 10_001,
        'system' => nil
      )
    end

    it 'preserves object-valued allowed values and default values' do
      field = transition_field.merge(
        allowedValues: [{ id: '1', value: 'Red' }],
        defaultValue: { id: '1', value: 'Red' }
      )
      stub_transitions([transition.merge(fields: { customfield: field })])

      mapped = run_action(action_input)[:transitions].first['screen_fields'].first

      expect(mapped['allowed_values']).to eq([{ 'id' => '1', 'value' => 'Red' }])
      expect(mapped['default_value']).to eq({ 'id' => '1', 'value' => 'Red' })
    end

    it 'maps system field schemas when custom field properties are absent' do
      field = transition_field.merge(schema: { type: 'string', system: 'summary' })
      stub_transitions([transition.merge(fields: { summary: field })])

      schema = run_action(action_input)[:transitions].first['screen_fields'].first['schema']

      expect(schema).to include(
        'type' => 'string',
        'system' => 'summary',
        'items' => nil,
        'custom' => nil,
        'custom_id' => nil
      )
    end

    it 'returns multiple transitions in the order Jira provides them' do
      second = {
        id: '2',
        name: 'Done',
        to: { id: '4', name: 'Done' },
        hasScreen: false,
        isAvailable: false,
        isConditional: true,
        isGlobal: true,
        isInitial: false,
      }
      stub_transitions([transition, second])

      output = run_action(action_input)

      expect(output[:transitions].map { |item| item['transition_id'] }).to eq(%w[1 2])
      expect(output[:transitions].last).to include(
        'name' => 'Done',
        'to_status_id' => '4',
        'to_status_name' => 'Done',
        'has_screen' => false,
        'is_available' => false,
        'is_conditional' => true,
        'is_global' => true,
        'is_initial' => false
      )
    end

    it 'returns an empty list when no transitions are available' do
      stub_transitions([])

      expect(run_action(action_input)[:transitions]).to eq([])
    end

    it 'returns an empty list when Jira omits transitions' do
      stub_request(:get, "#{api}/issue/issue1/transitions")
        .with(query: { 'expand' => 'transitions.fields' })
        .to_return(status: 200, body: {}.to_json)

      expect(run_action(action_input)[:transitions]).to eq([])
    end

    it 'handles missing optional transition fields' do
      stub_transitions([{ id: '1', name: 'Start Progress' }])

      output = run_action(action_input)

      expect(output[:transitions].first).to include(
        'transition_id' => '1',
        'name' => 'Start Progress',
        'to_status_id' => nil,
        'to_status_name' => nil,
        'to_status' => nil,
        'has_screen' => nil,
        'is_available' => nil,
        'is_conditional' => nil,
        'is_global' => nil,
        'is_initial' => nil,
        'fields' => {},
        'screen_fields' => []
      )
    end

    it 'trims whitespace from the issue identifier' do
      stub = stub_request(:get, "#{api}/issue/issue1/transitions")
             .with(query: { 'expand' => 'transitions.fields' })
             .to_return(status: 200, body: { transitions: [] }.to_json)

      run_action({ issue_id_or_key: ' issue1 ' })

      expect(stub).to have_been_requested.once
    end

    it 'accepts a numeric issue ID' do
      stub = stub_request(:get, "#{api}/issue/10001/transitions")
             .with(query: { 'expand' => 'transitions.fields' })
             .to_return(status: 200, body: { transitions: [] }.to_json)

      run_action({ issue_id_or_key: '10001' })

      expect(stub).to have_been_requested.once
    end

    it 'rejects a blank issue ID or key before making a request' do
      expect { run_action({ issue_id_or_key: '   ' }) }
        .to raise_error(IPaaS::Error, /Field 'issue_id_or_key' is required/)

      expect(a_request(:get, %r{/issue/.*/transitions})).not_to have_been_made
    end

    it 'rejects a path-unsafe issue ID or key before calling Jira' do
      expect { run_action({ issue_id_or_key: '../issue1' }) }
        .to raise_error(IPaaS::Job::FailJob, /issue_id_or_key is not path safe/)

      expect(a_request(:get, %r{/issue/.*/transitions})).not_to have_been_made
    end

    it 'returns Jira error details when the request is invalid' do
      stub_request(:get, "#{api}/issue/issue1/transitions")
        .with(query: { 'expand' => 'transitions.fields' })
        .to_return(status: 400, body: { errorMessages: ['Invalid issue key.'] }.to_json)

      expect { run_action(action_input) }
        .to raise_error(IPaaS::Job::FailJob, 'Jira API error (HTTP 400): Invalid issue key.')
    end

    it 'explains the required permission when Jira returns 403' do
      stub_request(:get, "#{api}/issue/issue1/transitions")
        .with(query: { 'expand' => 'transitions.fields' })
        .to_return(status: 403, body: { errorMessages: ['Forbidden'] }.to_json)

      expect { run_action(action_input) }
        .to raise_error(IPaaS::Job::FailJob, /Browse Projects permission/)
    end

    it 'reports an issue that does not exist or cannot be seen' do
      stub_request(:get, "#{api}/issue/issue1/transitions")
        .with(query: { 'expand' => 'transitions.fields' })
        .to_return(status: 404, body: { errorMessages: ['Issue does not exist'] }.to_json)

      expect { run_action(action_input) }
        .to raise_error(
          IPaaS::Job::FailJob,
          /Issue issue1 was not found, or this account cannot see it \(HTTP 404\)/
        )
    end

    it 'reschedules the read when Jira returns 503' do
      stub_request(:get, "#{api}/issue/issue1/transitions")
        .with(query: { 'expand' => 'transitions.fields' })
        .to_return(status: 503, body: '')

      expect_reschedule_after(60) { run_action(action_input) }
    end

    it 'reschedules the read when Jira does not answer' do
      stub_request(:get, "#{api}/issue/issue1/transitions")
        .with(query: { 'expand' => 'transitions.fields' })
        .to_timeout

      expect_reschedule_after(60, /Jira did not answer/) do
        run_action(action_input)
      end
    end
  end
end

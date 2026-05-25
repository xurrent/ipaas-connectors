shared_context 'action', :action do
  include_context 'connector'
  include_context 'outbound connection'

  # connector id taken from action template
  let(:connector_id) { action_template.connector.uuid }

  def runbook
    @runbook ||= IPaaS::Connector::Runbook.new(SecureRandom.uuid_v7)
  end

  def action_template
    unless action_template_id
      raise "Missing action_template_id. Should be defined like: let(:action_template_id) { 'ef6a...8427d' }"
    end

    result = IPaaS::Connector::ActionTemplate.by_uuid(action_template_id)
    return result if result

    load_all_fixtures
    IPaaS::Connector::ActionTemplate.by_uuid(action_template_id).tap do |action_template|
      raise "Missing action template with id #{action_template_id}" unless action_template
      raise "Action template #{action_template_id} is invalid: #{action_template.full_error_messages}" if action_template.invalid?
    end
  end

  def action(input = nil)
    return @action if defined?(@action)

    input ||= action_input if respond_to?(:action_input)
    @action = IPaaS::Connector::Action.parse(
      runbook,
      {
        reference: SecureRandom.uuid,
        outbound_connection: {
          uuid: outbound_connection&.uuid,
        },
        action_template: {
          uuid: action_template.uuid,
        },
        input_mapping: field_mapping(input, schema: action_template.input_schema),
      },
    ).tap do |action|
      action.input # force resolve
    end
  end

  def run_action(input = nil, schema_reference: nil)
    a = action(input)
    raise IPaaS::Error, "Action invalid: #{a.full_error_messages}" unless a.valid?
    results = a.run
    if schema_reference
      results.detect{ |result| result[:schema_reference] == schema_reference }&.[](:output)
    else
      results.first&.[](:output)
    end
  end
end

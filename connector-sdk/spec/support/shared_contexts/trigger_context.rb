shared_context 'trigger', :trigger do
  include_context 'connector'
  include_context 'inbound connection'
  include_context 'outbound connection'

  before(:all) do
    TriggerServer.start
  end

  # connector id taken from trigger template
  let(:connector_id) { trigger_template.connector.uuid }

  def trigger_template
    unless trigger_template_id
      raise "Missing trigger_template_id. Should be defined like: let(:trigger_template_id) { 'ef6a...8427d' }"
    end

    result = IPaaS::Connector::TriggerTemplate.by_uuid(trigger_template_id)
    return result if result

    load_all_fixtures
    IPaaS::Connector::TriggerTemplate.by_uuid(trigger_template_id).tap do |trigger_template|
      raise "Missing trigger template with id #{trigger_template_id}" unless trigger_template
    end
  end

  def runbook
    @runbook ||= build_runbook_double
  end

  def trigger(config = nil, runbook: self.runbook)
    @trigger ||= begin
      trigger = IPaaS::Connector::Trigger.parse(runbook, runbook_trigger(config))
      allow(runbook).to receive(:trigger).and_return(trigger)
      allow(runbook).to receive(:valid?).and_return(trigger.valid?)
      trigger
    end
  end

  def runbook_trigger(config = nil)
    config ||= trigger_config if respond_to?(:trigger_config)
    hash = {
      inbound_connection: { uuid: inbound_connection.uuid },
      trigger_template: { uuid: trigger_template.uuid },
      config_mapping: field_mapping(config, schema: trigger_template.config_schema),
      blueprint_checksum: '7f83b1657ff1fc53b',
    }
    hash[:outbound_connection] = { uuid: outbound_connection.uuid } if trigger_template.outbound_traffic
    hash
  end

  private

  def build_runbook_double
    double('runbook').tap do |mock|
      stub_runbook_methods(mock)
      IPaaS::Connector::Runbook.add_record_by_uuid(mock)
    end
  end

  def stub_runbook_methods(runbook)
    allow(runbook).to receive(:uuid).and_return(SecureRandom.uuid_v7)
    allow(runbook).to receive(:account_id).and_return(5)
    allow(runbook).to receive_messages(solution: nil, store_trigger_output: nil,
                                       job_context_identifier: nil, store_job_context_identifier: nil)
  end
end

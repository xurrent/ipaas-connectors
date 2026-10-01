require 'spec_helper'

describe IPaaS::Job::Delegation::TriggerRef do
  it 'should self-reference trigger' do
    trigger = IPaaS::Connector::Trigger.new
    expect(trigger.trigger).to eq(trigger)
  end

  it 'should create an example trigger for an trigger template' do
    trigger_template = spec_connector.trigger('uuid') do
      config_schema do
        field :foo, 'Foo', :string
        field :bar, 'Bar', :integer
      end
    end

    expect(trigger_template.trigger.config[:foo]).to eq('Hello World!')
    expect(trigger_template.trigger.config[:bar]).to eq(42)
  end

  describe 'the example trigger is never kept on the shared template' do
    let(:trigger_template) do
      spec_connector.trigger('uuid') do
        config_schema { field :sep, 'Separator', :string, default: ',' }
      end
    end

    it 'shows a change to one example trigger only to that example trigger' do
      first = trigger_template.trigger
      first.config_schema.field(:poison, 'Poison', :string)

      expect(first.config_schema.field(:poison)).not_to be_nil
      expect(trigger_template.trigger.config_schema.field(:poison)).to be_nil
    end

    it 'gives the example trigger its own copy of a default, leaving the template default intact' do
      config = trigger_template.trigger.config
      config[:sep] << '-changed'

      expect(config[:sep]).to eq(',-changed')
      expect(trigger_template.config_schema.field(:sep).default).to eq(',')
      expect(trigger_template.trigger.config[:sep]).to eq(',')
    end
  end

  describe 'a job context identifier set on the shared trigger template itself' do
    let(:trigger_template) { spec_connector.trigger('uuid') { parse { nil } } }

    it 'does not reach a later read of that template' do
      trigger_template.job_context_identifier = 'from-one-account'

      expect(trigger_template.job_context_identifier).to be_nil
    end
  end

  it 'gives the example trigger the connector of its template, so its blocks and helpers have an owner' do
    skip_function_capture_validation
    trigger_template = spec_connector.trigger('uuid') do
      helper(:greeting) { 'hello' }
      config_schema do
        field :foo, 'Foo', :string
        after_update { |fields, _values| fields }
      end
    end
    example = trigger_template.trigger

    expect(example.connector).to be(spec_connector)
    expect(example.helpers.greeting).to eq('hello')
    expect(example.config[:foo]).to eq('Hello World!')
    after_update = IPaaS::Connector::Common::ProcHelper.new(example, example.config_schema.after_update,
                                                            connector: spec_connector)
    key = after_update.send(:validation_cache_key)
    expect(spec_connector.proc_validations.include?(key)).to be(true)
    expect(IPaaS::Connector::Common::ProcHelper.validated_before).not_to include(key)
  end
end

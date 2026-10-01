require 'spec_helper'

describe IPaaS::Job::Delegation::ActionRef do
  it 'should self-reference action' do
    action = IPaaS::Connector::Action.new
    expect(action.action).to eq(action)
  end

  it 'should create an example action for an action template' do
    action_template = spec_connector.action('uuid') do
      input_schema do
        field :foo, 'Foo', :string
        field :bar, 'Bar', :integer
      end
    end

    example = action_template.action
    expect(example.input[:foo]).to eq('Hello World!')
    expect(example.input[:bar]).to eq(42)
    expect(example.trigger_output).to be_a(Hash)
    expect(example.action_output('abc')).to be_nil
    expect(example.runbook.actions).to eq([example])
  end

  describe 'the example action is never kept on the shared template' do
    let(:action_template) do
      spec_connector.action('uuid') do
        input_schema { field :sep, 'Separator', :string, default: ',' }
      end
    end

    it 'shows a change to one example action only to that example action' do
      first = action_template.action
      first.input_schema.field(:poison, 'Poison', :string)

      expect(first.input_schema.field(:poison)).not_to be_nil
      expect(action_template.action.input_schema.field(:poison)).to be_nil
    end

    it 'gives the example action its own copy of a default, leaving the template default intact' do
      input = action_template.action.input
      input[:sep] << '-changed'

      expect(input[:sep]).to eq(',-changed')
      expect(action_template.input_schema.field(:sep).default).to eq(',')
      expect(action_template.action.input[:sep]).to eq(',')
    end

    it 'keeps the example runbook out of the uuid registry' do
      expect { IPaaS::Connector::Runbook.new(SecureRandom.uuid) }.to change { IPaaS::Connector::Runbook.all.size }.by(1)
      expect { action_template.action }.not_to(change { IPaaS::Connector::Runbook.all.size })
    end
  end

  it 'gives the example action the connector of its template, so its blocks and helpers have an owner' do
    skip_function_capture_validation
    action_template = spec_connector.action('uuid') do
      helper(:greeting) { 'hello' }
      input_schema do
        field :foo, 'Foo', :string
        after_update { |fields, _values| fields }
      end
    end
    example = action_template.action

    expect(example.connector).to be(spec_connector)
    expect(example.helpers.greeting).to eq('hello')
    expect(example.input[:foo]).to eq('Hello World!')
    after_update = IPaaS::Connector::Common::ProcHelper.new(example, example.input_schema.after_update,
                                                            connector: spec_connector)
    key = after_update.send(:validation_cache_key)
    expect(spec_connector.proc_validations.include?(key)).to be(true)
    expect(IPaaS::Connector::Common::ProcHelper.validated_before).not_to include(key)
  end

  describe 'a job context identifier set on the shared action template itself' do
    let(:action_template) { spec_connector.action('uuid') { run { nil } } }

    it 'does not reach a later read of that template' do
      action_template.job_context_identifier = 'from-one-account'

      expect(action_template.job_context_identifier).to be_nil
    end
  end
end

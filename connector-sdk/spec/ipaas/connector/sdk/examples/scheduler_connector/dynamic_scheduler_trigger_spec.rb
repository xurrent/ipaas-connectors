require 'spec_helper'

describe 'Dynamic Scheduler Trigger', :trigger do
  let(:trigger_template_id) { '019898e9-8b75-7116-97a8-9630b10262c9' }

  it 'should be a valid trigger' do
    expect(trigger).to be_valid
  end

  it 'should be an internal_only trigger' do
    expect(trigger.trigger_template.internal_only).to be_truthy
  end

  context 'config_schema' do
    it 'should have job_context_identifier_path field' do
      field = trigger.config_schema.field(:job_context_identifier_path)
      expect(field).to be_present
      expect(field.type).to eq(:string)
      expect(field.required).to eq(false)
      expect(field.visibility).to eq('optional')
    end
  end

  context 'output_schema' do
    it 'should have body field' do
      expect(trigger.output_schema.field(:body)).to be_present
      expect(trigger.output_schema.field(:body).type).to eq(:hash)
    end

    it 'should have triggered_at field' do
      expect(trigger.output_schema.field(:triggered_at)).to be_present
      expect(trigger.output_schema.field(:triggered_at).type).to eq(:date_time)
      expect(trigger.output_schema.field(:triggered_at).required).to be_truthy
    end
  end

  context 'parse request' do
    def validate_triggered_at(triggered_at)
      expect(triggered_at).to be_present
      expect(triggered_at).to be_a(DateTime)
      expect(triggered_at.to_i).to be_within(5).of(Time.current.to_i)
    end

    it 'should return the incoming request body and current timestamp' do
      expect(runbook).not_to receive(:store_job_context_identifier)
      data = { schedule_id: 'schedule_id_1', event_type: 'scheduled_trigger' }
      request_body = data.to_json

      request = double('request')
      allow(request).to receive(:body).and_return(double('body', read: request_body, rewind: nil))

      output = trigger.parse_request(request)

      expect(output[:body]).to eq(data.deep_stringify_keys)
      validate_triggered_at(output[:triggered_at])
    end

    it 'should handle empty request body' do
      expect(runbook).not_to receive(:store_job_context_identifier)
      request = double('request')
      allow(request).to receive(:body).and_return(double('body', read: nil, rewind: nil))

      output = trigger.parse_request(request)

      expect(output[:body]).to be_nil
      validate_triggered_at(output[:triggered_at])
    end

    it 'should handle JSON request body' do
      expect(runbook).not_to receive(:store_job_context_identifier)
      data = { custom_field: 'custom_value' }
      request_body = data.to_json

      request = double('request')
      allow(request).to receive(:body).and_return(double('body', read: request_body, rewind: nil))

      output = trigger.parse_request(request)

      expect(output[:body]).to eq(data.deep_stringify_keys)
      validate_triggered_at(output[:triggered_at])
    end

    describe 'job context identifier path handling' do
      def call_trigger(data)
        request_body = data.to_json

        request = double('request')
        allow(request).to receive(:body).and_return(double('body', read: request_body, rewind: nil))
        trigger.parse_request(request)
      end

      context 'top level property starting with body' do
        let(:trigger_config) do
          { job_context_identifier_path: 'body.custom_field' }
        end

        it 'sets based on top level property inside json body' do
          expect(runbook).to receive(:store_job_context_identifier).with('custom_value')
          call_trigger({ custom_field: 'custom_value' })
        end
      end

      context 'top level property without body' do
        let(:trigger_config) do
          { job_context_identifier_path: 'custom' }
        end

        it 'sets based on top level property inside json body' do
          expect(runbook).to receive(:store_job_context_identifier).with('foo')
          call_trigger({ custom: 'foo' })
        end
      end

      context 'nested property starting with body' do
        let(:trigger_config) do
          { job_context_identifier_path: 'body.custom_field.bar' }
        end

        it 'sets based on top level property inside json body' do
          expect(runbook).to receive(:store_job_context_identifier).with('boo')
          call_trigger({ custom_field: { bar: 'boo' } })
        end
      end

      context 'nested property not starting with body' do
        let(:trigger_config) do
          { job_context_identifier_path: 'custom_field.bar' }
        end

        it 'sets based on top level property inside json body' do
          expect(runbook).to receive(:store_job_context_identifier).with('boo')
          call_trigger({ custom_field: { bar: 'boo' } })
        end
      end

      context 'unknown key in path' do
        let(:trigger_config) do
          { job_context_identifier_path: 'custom_field.boo' }
        end

        it 'sets no context identifier' do
          expect(runbook).not_to receive(:store_job_context_identifier)
          call_trigger({ custom_field: { bar: 'boo' } })
        end
      end

      context 'error while resolving path' do
        let(:trigger_config) do
          { job_context_identifier_path: 'custom_field.boo' }
        end

        it 'sets no context identifier' do
          logs = []
          allow(trigger).to receive(:log) { |msg, inter| logs << [msg, inter] }

          expect(runbook).not_to receive(:store_job_context_identifier)
          call_trigger({ custom_field: ['boo'] })

          expect(logs)
            .to contain_exactly(
              [
                'Unable to determine job context identifier. %<error>s',
                { error: 'TypeError: no implicit conversion of String into Integer' },
              ]
            )
        end
      end
    end
  end
end

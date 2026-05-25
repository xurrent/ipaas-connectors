require 'spec_helper'

describe 'N-Central PSA Generate Ticket Trigger', :trigger do
  let(:trigger_template_id) { '0196d843-259d-7308-96bb-f44082fffecc' }
  let(:trigger_config) do
    {
      ticket_url_template: 'https://{n_central_user_name}.example.com/psa_tickets/{n_central_ticket_id}',
    }
  end

  context 'inbound_connection' do
    context 'config_schema' do
      it 'should have optional user_name field' do
        expect(connector.inbound_connection.config_schema.field(:user_name).required).to be_falsey
      end

      it 'should have optional password field' do
        expect(connector.inbound_connection.config_schema.field(:password).required).to be_falsey
      end
    end

    context 'validation' do
      let(:user_name) { 'customer1' }
      let(:password) { 'secret123' }
      let(:auth_header) { "Basic #{Base64.encode64("#{user_name}:#{password}")}" }

      let(:request_body) do
        {
          action: 'CREATE',
          title: 'Test Ticket',
          details: 'Test Details',
          ncentralTicketId: '12345',
          psaTicketNumber: 'should-be-removed',
        }
      end

      def trigger_response_error_message(headers: {})
        post_trigger(request_body, headers: headers)[:error]
      end

      context 'with fixed credentials' do
        let(:inbound_connection_config) do
          {
            user_name: user_name,
            password: make_secret_string(password),
          }
        end

        it 'accepts valid credentials' do
          expect(trigger_response_error_message(headers: { 'Authorization' => auth_header })).to be_nil
        end

        it 'rejects invalid password' do
          error_msg = trigger_response_error_message(
            headers: { 'Authorization' => "Basic #{Base64.encode64("#{user_name}:wrong")}" }
          )
          expect(error_msg).to eq('Invalid basic authentication header.')
        end

        it 'rejects invalid username' do
          error_msg = trigger_response_error_message(
            headers: { 'Authorization' => "Basic #{Base64.encode64("wrong:#{password}")}" }
          )
          expect(error_msg).to eq('Invalid basic authentication header.')
        end
      end

      context 'with dynamic credentials' do
        before do
          allow(outbound_connection.store).to receive(:read)
            .with("secret##{user_name}")
            .and_return(make_secret_string(password))
        end

        it 'accepts valid stored credentials' do
          expect(trigger_response_error_message(headers: { 'Authorization' => auth_header })).to be_nil
        end

        it 'rejects unknown user' do
          allow(outbound_connection.store).to receive(:read)
            .with('secret#unknown')
            .and_return(nil)

          error_msg = trigger_response_error_message(
            headers: { 'Authorization' => "Basic #{Base64.encode64("unknown:#{password}")}" }
          )
          expect(error_msg).to eq('Invalid basic authentication header.')
        end
      end

      it 'requires authorization header' do
        expect(trigger_response_error_message).to eq('Missing basic authentication header.')
      end

      it 'requires valid basic auth format' do
        error_msg = trigger_response_error_message(
          headers: { 'Authorization' => 'Invalid' }
        )
        expect(error_msg).to eq('Missing basic authentication header.')
      end
    end
  end

  context 'config_schema' do
    it 'requires ticket_url_template' do
      expect(trigger.config_schema.field(:ticket_url_template).required).to be_truthy
    end

    it 'validates ticket_url_template format' do
      pattern = trigger.config_schema.field(:ticket_url_template).pattern
      expect('https://example.com/psa_tickets/{n_central_ticket_id}').to match(pattern)
      expect('https://example.com/psa_tickets/').not_to match(pattern)
    end

    it 'makes custom_tags_schema optional' do
      expect(trigger.config_schema.field(:custom_tags_schema).required).to be_falsey
    end
  end

  context 'parse request' do
    before(:each) do
      outbound_connection.store.write('secret#user', make_secret_string('pass'))
    end
    let(:request_body) do
      {
        action: 'CREATE',
        title: 'Test Ticket',
        details: 'Test Details',
        ncentralTicketId: '12345',
        psaTicketNumber: 'should-be-removed',
      }
    end

    let(:basic_auth) { "Basic #{Base64.encode64('user:pass')}" }

    it 'parses valid request' do
      expect(runbook).to receive(:store_job_context_identifier).with('user')
      output = post_trigger(request_body, headers: { 'Authorization' => basic_auth })
      expect(output[:action]).to eq('CREATE')
      expect(output[:title]).to eq('Test Ticket')
      expect(output[:details]).to eq('Test Details')
      expect(output[:ncentralTicketId]).to eq('12345')
      expect(output[:psaTicketNumber]).to be_nil
      expect(output[:user_name]).to eq('user')
    end

    it 'discards test tickets' do
      request_body[:ncentralTicketId] = 'TEST_NC_TICKET_ID_123'
      output = post_trigger(request_body, headers: { 'Authorization' => basic_auth })
      expect(output[:result]).to include('Discarded')
    end

    context 'with custom tags schema' do
      let(:trigger_config) do
        {
          ticket_url_template: 'https://example.com/psa_tickets/{n_central_ticket_id}',
          custom_tags_schema: [
            { id: 'priority', label: 'Priority', type: 'string' },
          ],
        }
      end

      it 'includes valid custom tags' do
        request_body[:customTags] = { priority: 'high' }
        output = post_trigger(request_body, headers: { 'Authorization' => basic_auth })
        expect(output[:customTags]).to eq({ priority: 'high' })
      end

      it 'filters unknown custom tags' do
        request_body[:customTags] = { priority: 'high', unknown: 'value' }
        output = post_trigger(request_body, headers: { 'Authorization' => basic_auth })
        expect(output[:customTags]).to eq({ priority: 'high' })
      end
    end
  end

  describe 'respond_with' do
    let(:headers) { { 'Authorization' => "Basic #{Base64.encode64('foo-user:pass')}" } }
    let(:webhook_body) do
      <<~JSON
        {
          "action": "CREATE",
          "title": "Test Ticket",
          "details": "Test Details",
          "ncentralTicketId": "12345",
          "psaTicketNumber": "should-be-removed"
        }
      JSON
    end
    let(:request) do
      double.tap do |req|
        allow(req).to receive(:body).and_return(StringIO.new(webhook_body))
        allow(req).to receive(:headers).and_return(headers)
      end
    end

    before do
      allow(runbook).to receive(:trigger_output).and_return({ abc: :foo })
    end

    it 'bounces back the ncentralTicketId' do
      result = trigger.respond_with(request, nil, headers)

      expect(result[:status]).to eq(200)
      expect(result[:headers].key?('x-job-uuid')).to eq(false)

      body = JSON.parse(result[:body])
      expect(body['externalTicketId']).to eq('PSA-12345')
      expect(body['ticketUrl']).to eq('https://foo-user.example.com/psa_tickets/12345')
    end

    it 'sets content-type to application/json' do
      result = trigger.respond_with(request, nil, headers)
      expect(result[:headers]['content-type']).to eq('application/json; charset=utf-8')
    end
  end
end

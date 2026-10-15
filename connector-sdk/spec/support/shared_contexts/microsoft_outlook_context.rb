shared_context 'microsoft outlook', :microsoft_outlook do
  let(:tenant_id) { '9c46a35a-b7cd-42ef-9ce5-9ea1481d40f1' }
  let(:mailbox) { 'adele@contoso.com' }
  let(:default_mailbox) { mailbox }
  let(:token_url) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token" }

  let(:outbound_connection_config) do
    {
      credentials: {
        tenant_id: tenant_id,
        client_id: 'client-abc',
        client_secret: make_secret_string('secret-def'),
      },
      cloud: 'Global',
      default_mailbox: default_mailbox,
    }
  end

  def graph_message(overrides = {})
    {
      id: 'AAMkAGQz=',
      subject: 'Undeliverable: Testing from within iPaaS',
      from: { emailAddress: { name: 'Microsoft Outlook', address: 'postmaster@contoso.com' } },
      receivedDateTime: '2026-09-24T09:27:49Z',
      hasAttachments: false,
      isRead: false,
      importance: 'normal',
      bodyPreview: 'Your message could not be delivered',
    }.merge(overrides)
  end

  def expect_reschedule_after(seconds, message = nil, &step)
    Timecop.freeze do
      expect(&step).to raise_error(IPaaS::Job::RescheduleJob, message) do |error|
        expect(error.reschedule_after).to eq(seconds.seconds.from_now)
      end
    end
  end

  before(:each) do
    load_fixture('microsoft_outlook_connector')
    stub_request(:post, token_url)
      .to_return(status: 200, body: { access_token: 'outlook-token', expires_in: 3599 }.to_json)
  end
end

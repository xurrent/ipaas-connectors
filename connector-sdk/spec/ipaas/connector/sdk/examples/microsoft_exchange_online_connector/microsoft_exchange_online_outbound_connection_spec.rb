require 'spec_helper'

describe 'Microsoft Exchange Online Connection', :outbound_connection, :microsoft_exchange_online do
  # Bind the connector's helpers to this connection, as the runtime does before it runs a proc, so an inner
  # helpers.other_helper call and http_post resolve against this connection.
  let(:bound_helpers) { connector.outbound_connection.helpers_definition.copy_for(outbound_connection) }

  before(:each) do
    helpers_proxy = bound_helpers.for_proc
    outbound_connection.define_singleton_method(:helpers) { helpers_proxy }
  end

  def call_helper(name, ...)
    bound_helpers.registered_helper(name).execute(...)
  end

  def with_environment(values)
    allow(outbound_connection).to receive(:solution).and_return(double(environment: values))
  end

  describe 'cloud' do
    it 'reads the Global hosts by default' do
      outbound_connection.config[:cloud] = nil
      expect(call_helper(:cloud)).to eq(login: 'https://login.microsoftonline.com',
                                        graph: 'https://graph.microsoft.com',
                                        exchange: 'https://outlook.office365.com',
                                        exchange_environment: 'O365Default')
    end

    it 'pairs every cloud with the Exchange environment the runner connects to' do
      environments = MicrosoftExchangeOnlineConnector::CLOUDS.transform_values { |cloud| cloud[:exchange_environment] }
      expect(environments).to eq('Global' => 'O365Default', 'US Government GCC High' => 'O365USGovGCCHigh',
                                 'US Government DoD' => 'O365USGovDoD', 'China' => 'O365China')
    end

    it 'refuses a cloud it does not know' do
      outbound_connection.config[:cloud] = 'Mars'
      expect { call_helper(:cloud) }.to raise_error(IPaaS::Job::FailJob, /Cloud 'Mars' is not one of Global/)
    end
  end

  describe 'tenant_id' do
    it 'refuses an empty tenant' do
      outbound_connection.config[:credentials][:tenant_id] = ' '
      expect { call_helper(:tenant_id) }.to raise_error(IPaaS::Job::FailJob, 'Tenant ID is empty on the connection.')
    end

    it 'refuses a sign-in placeholder' do
      outbound_connection.config[:credentials][:tenant_id] = 'Common'
      expect { call_helper(:tenant_id) }.to raise_error(IPaaS::Job::FailJob, /'Common' is a sign-in placeholder/)
    end
  end

  describe 'organization' do
    it 'answers the initial domain in lower case' do
      outbound_connection.config[:organization] = ' Contoso.OnMicrosoft.com '
      expect(call_helper(:organization)).to eq('contoso.onmicrosoft.com')
    end

    it 'refuses an empty organization' do
      outbound_connection.config[:organization] = ''
      expect { call_helper(:organization) }.to raise_error(IPaaS::Job::FailJob, /Organization is empty/)
    end
  end

  describe 'exchange_access_token' do
    it 'asks for a token for the Exchange host and answers it without the Bearer prefix' do
      expect(call_helper(:exchange_access_token)).to eq('exchange-token')
      expect(a_request(:post, token_url).with(body: hash_including(
        'client_id' => 'client-abc', 'client_secret' => 'secret-def', 'grant_type' => 'client_credentials',
        'scope' => 'https://outlook.office365.com/.default',
      ))).to have_been_made
    end

    it 'asks the China login host for a token for the China Exchange host' do
      outbound_connection.config[:cloud] = 'China'
      china_url = "https://login.chinacloudapi.cn/#{tenant_id}/oauth2/v2.0/token"
      stub_request(:post, china_url)
        .with(body: hash_including('scope' => 'https://partner.outlook.cn/.default'))
        .to_return(status: 200, body: { access_token: 'china-token', expires_in: 3599 }.to_json)
      expect(call_helper(:exchange_access_token)).to eq('china-token')
    end
  end

  describe 'runner settings' do
    it 'uses the runner URL of the connection and drops a trailing slash' do
      outbound_connection.config[:runner][:url] = "#{runner_base_url}/"
      expect(call_helper(:runner_endpoint)).to eq(runner_url)
    end

    it 'uses the key of the connection' do
      expect(call_helper(:runner_api_key)).to eq('runner-key')
    end

    context 'when the connection names no runner' do
      let(:outbound_connection_config) { super().except(:runner) }

      it 'uses the runner URL and key the environment provides' do
        with_environment(exchange_runner_url: 'https://runner.xurrent.test',
                         exchange_runner_api_key: make_secret_string('platform-key'))
        expect(call_helper(:runner_endpoint)).to eq('https://runner.xurrent.test/v1/cmdlets')
        expect(call_helper(:runner_api_key)).to eq('platform-key')
      end

      it 'says the runner is not enabled when the environment has no URL' do
        with_environment({})
        expect { call_helper(:runner_endpoint) }
          .to raise_error(IPaaS::Job::FailJob, /No Exchange runner is configured for this environment/)
      end

      it 'says the key is missing when the environment has no key' do
        with_environment({})
        expect { call_helper(:runner_api_key) }
          .to raise_error(IPaaS::Job::FailJob, /The Exchange runner has no API key configured/)
      end
    end
  end

  describe 'run_cmdlet' do
    let(:parameters) { { Identity: 'support@contoso.com' } }

    it 'posts the cmdlet, its parameters and the session details, and answers the output' do
      stub_cmdlet('Get-Mailbox', output: [{ Name: 'Support' }])
      expect(call_helper(:run_cmdlet, 'Get-Mailbox', parameters)).to eq(ok: true, output: [{ 'Name' => 'Support' }])
      expect(a_request(:post, runner_url).with(
               headers: { 'Authorization' => 'Bearer runner-key' },
               body: { organization: organization, exchange_environment: 'O365Default', access_token: 'exchange-token',
                       cmdlet: 'Get-Mailbox', parameters: parameters, }.to_json,
             )).to have_been_made
    end

    it 'skips the Graph token, which the runner does not accept' do
      stub_cmdlet('Get-Mailbox', output: [])
      call_helper(:run_cmdlet, 'Get-Mailbox', parameters)
      expect(a_request(:post, token_url).with(body: hash_including('scope' => 'https://graph.microsoft.com/.default')))
        .not_to have_been_made
    end

    it 'refuses a cmdlet outside the allow-list without calling the runner' do
      expect { call_helper(:run_cmdlet, 'Remove-Mailbox', parameters) }
        .to raise_error(IPaaS::Error, "cmdlet 'Remove-Mailbox' is not on the runner allow-list")
      expect(a_request(:post, runner_url)).not_to have_been_made
    end

    it 'fails when the runner answers success without an output list' do
      stub_request(:post, runner_url).to_return(status: 200, body: { output: 'done' }.to_json)
      expect { call_helper(:run_cmdlet, 'Get-Mailbox', parameters) }
        .to raise_error(IPaaS::Error, 'Exchange runner answered Get-Mailbox without an output list')
    end

    it 'answers the error the runner reported' do
      stub_cmdlet_error('Get-Mailbox', status: 404, category: 'not_found',
                                       error_id: '[FailureCategory=Cmdlet-ManagementObjectNotFoundException]',
                                       message: "The operation couldn't be performed because object couldn't be found.")
      expect(call_helper(:run_cmdlet, 'Get-Mailbox', parameters))
        .to eq(ok: false, status: 404, category: 'not_found',
               error_id: '[FailureCategory=Cmdlet-ManagementObjectNotFoundException]',
               message: "The operation couldn't be performed because object couldn't be found.")
    end

    it 'answers the raw body when the runner sent no error object' do
      stub_request(:post, runner_url).to_return(status: 502, body: 'Bad Gateway')
      expect(call_helper(:run_cmdlet, 'Get-Mailbox', parameters))
        .to include(ok: false, status: 502, category: '', error_id: '', message: 'Bad Gateway')
    end

    it 'says there was no body when the runner sent none' do
      stub_request(:post, runner_url).to_return(status: 500, body: '')
      expect(call_helper(:run_cmdlet, 'Get-Mailbox', parameters)[:message]).to eq('no response body')
    end

    it 'pauses the step when Exchange throttles the tenant' do
      stub_request(:post, runner_url).to_return(status: 429, body: '', headers: { 'Retry-After' => '30' })
      expect_reschedule_after(30) { call_helper(:run_cmdlet, 'Get-Mailbox', parameters) }
    end

    it 'pauses the step when the runner is unavailable' do
      stub_request(:post, runner_url).to_return(status: 503, body: '')
      expect_reschedule_after(60) { call_helper(:run_cmdlet, 'Get-Mailbox', parameters) }
    end
  end

  describe 'exchange_cmdlet' do
    it 'answers the output of a cmdlet that succeeded' do
      stub_cmdlet('Get-AcceptedDomain', output: [{ DomainName: 'contoso.com' }])
      expect(call_helper(:exchange_cmdlet, 'Get-AcceptedDomain', {})).to eq([{ 'DomainName' => 'contoso.com' }])
    end

    it 'names the runner key when the runner refuses it' do
      stub_cmdlet_error('Get-AcceptedDomain', status: 401, error_id: '', category: 'unauthorized')
      expect { call_helper(:exchange_cmdlet, 'Get-AcceptedDomain', {}) }
        .to raise_error(IPaaS::Job::FailJob, /The Exchange runner refused its API key/)
    end

    it 'names the permission and role when Exchange refuses the cmdlet' do
      stub_cmdlet_error('Get-AcceptedDomain', status: 403, error_id: '', category: 'forbidden',
                                              message: 'Access denied.')
      expect { call_helper(:exchange_cmdlet, 'Get-AcceptedDomain', {}) }
        .to raise_error(IPaaS::Job::FailJob, 'Exchange Online refused Get-AcceptedDomain: Access denied. Check that ' \
                                             'the app holds Exchange.ManageAsApp and an Exchange role that includes ' \
                                             'this cmdlet.')
    end

    it 'quotes the status, category and message of any other failure' do
      stub_cmdlet_error('Get-AcceptedDomain', status: 400, error_id: 'X', category: 'invalid', message: 'Bad value.')
      expect { call_helper(:exchange_cmdlet, 'Get-AcceptedDomain', {}) }
        .to raise_error(IPaaS::Job::FailJob, 'Get-AcceptedDomain failed with HTTP 400 (invalid): Bad value.')
    end

    it 'leaves the category out when the runner gave none' do
      stub_request(:post, runner_url).to_return(status: 502, body: 'Bad Gateway')
      expect { call_helper(:exchange_cmdlet, 'Get-AcceptedDomain', {}) }
        .to raise_error(IPaaS::Job::FailJob, 'Get-AcceptedDomain failed with HTTP 502: Bad Gateway')
    end
  end

  describe 'authenticate' do
    let(:request) { Faraday::Request.create(:get) { |built| built.headers = {} } }

    it 'puts a Graph token on the request' do
      outbound_connection.authenticate_request(request)
      expect(request.headers['Authorization']).to eq('Bearer graph-token')
    end
  end

  describe 'config_tester' do
    it 'reads one mailbox through the runner and says the session opened' do
      stub_cmdlet('Get-Mailbox', output: [{ Name: 'Support' }])
      expect(outbound_connection.config_tester)
        .to eq(status: :success,
               message: 'Connection successful. The runner opened Exchange Online for contoso.onmicrosoft.com.')
      expect(runner_request('Get-Mailbox', { ResultSize: 1 })).to have_been_made
    end

    it 'reports failed with the reason when the runner or Exchange refuses' do
      stub_cmdlet_error('Get-Mailbox', status: 401, error_id: '', category: 'unauthorized')
      expect(outbound_connection.config_tester)
        .to eq(status: :failed, message: 'The Exchange runner refused its API key. Check Runner API key on the ' \
                                         'connection, or ask Xurrent support.')
    end
  end
end

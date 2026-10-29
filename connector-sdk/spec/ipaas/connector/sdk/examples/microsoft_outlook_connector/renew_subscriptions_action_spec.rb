require 'spec_helper'

describe 'Microsoft Outlook Renew Subscriptions Action', :action, :microsoft_outlook do
  let(:action_template_id) { '01a10f63-a1f8-7eac-b111-e7ac03240ed8' }
  let(:graph) { 'https://graph.microsoft.com/v1.0' }
  let(:subscriptions_url) { "#{graph}/subscriptions" }
  let(:batch_url) { "#{graph}/$batch" }
  let(:runbook_id) { '01a13544-c2d4-7cc7-8726-e73182d73e05' }
  let(:other_runbook_id) { '01a13544-c2d4-7cc7-8726-e73182d73e06' }
  let(:endpoint) { "https://ipaas.example.com/inbound/1/solution/#{runbook_id}" }
  let(:other_endpoint) { "https://ipaas.example.com/inbound/1/solution/#{other_runbook_id}" }
  let(:subscription_id) { '0fc0f4a5-3f6e-4bc5-9d1a-52e2c5b81e0c' }
  let(:other_subscription_id) { 'b6b2b0d1-6f1a-4a1e-9a01-7c3e0f9a55aa' }
  let(:new_subscription_id) { '3d1f0c2e-5a6b-4c7d-8e9f-0a1b2c3d4e5f' }
  let(:renewed_until) { '2026-10-20T13:36:18Z' }
  let(:soon) { 6.hours.from_now.utc.iso8601 }
  let(:later) { 3.days.from_now.utc.iso8601 }
  let(:mail_resource) { 'users/adele@contoso.com/mailFolders/inbox/messages' }
  let(:access_denied) { { error: { code: 'ErrorAccessDenied', message: 'Access is denied.' } } }
  let(:refused_secret) { { error: 'invalid_client', error_description: 'The secret is wrong.' }.to_json }
  let(:sent_creates) { [] }
  let(:sent_batches) { [] }
  let(:batch_answers) { {} }
  let(:first_request_renewed) do
    { responses: [{ id: '0', status: 200, body: { expirationDateTime: renewed_until } }] }.to_json
  end

  def row(id: subscription_id, mailbox: 'adele@contoso.com', folder: 'inbox', expires_at: soon, endpoint: self.endpoint)
    base = { 'resource' => "users/#{mailbox}/mailFolders/#{folder}/messages", 'mailbox' => mailbox,
             'folder' => folder, 'endpoint' => endpoint, }
    return base unless id

    base.merge('id' => id, 'client_state' => make_secret_string('state-1').to_s, 'expires_at' => expires_at)
  end

  def bobs_row(expires_at: soon)
    row(id: other_subscription_id, mailbox: 'bob@contoso.com', expires_at: expires_at, endpoint: other_endpoint)
  end

  def held(id, endpoint: self.endpoint, resource: mail_resource)
    { id: id, notificationUrl: endpoint, resource: resource, changeType: 'created', expirationDateTime: soon }
  end

  def store(rows)
    action({}).outbound_connection.store.write(MicrosoftOutlookConnector::SUBSCRIPTIONS_STORE_KEY, rows)
  end

  def stored_rows
    action.outbound_connection.store.read(MicrosoftOutlookConnector::SUBSCRIPTIONS_STORE_KEY)
  end

  def rows_past_one_batch
    (1..(MicrosoftOutlookConnector::BATCH_REQUEST_LIMIT + 1)).to_h do |number|
      id = format('%08d-0000-4000-8000-000000000000', number)
      ["runbook-#{number}", row(id: id, endpoint: "https://ipaas.example.com/inbound/1/solution/runbook-#{number}")]
    end
  end

  def stub_list_of(rows)
    stub_list(*rows.map { |_key, stored| held(stored['id'], endpoint: stored['endpoint']) })
  end

  def stub_list(*subscriptions)
    stub_request(:get, subscriptions_url)
      .to_return(status: 200, body: { value: subscriptions }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def stub_create(status: 201, body: { id: subscription_id, expirationDateTime: renewed_until }, headers: {})
    stub_request(:post, subscriptions_url)
      .with { |request| sent_creates.push(JSON.parse(request.body)) }
      .to_return do |_request|
        yield if block_given?
        { status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' }.merge(headers) }
      end
  end

  def stub_batch(status: 200, headers: {})
    stub_request(:post, batch_url)
      .with { |request| sent_batches.push(JSON.parse(request.body)['requests']) }
      .to_return do |request|
        yield if block_given?
        { status: status, body: batch_body(request).to_json,
          headers: { 'Content-Type' => 'application/json' }.merge(headers), }
      end
  end

  def batch_body(request)
    { responses: JSON.parse(request.body)['requests'].map { |sent| { id: sent['id'] }.merge(batch_answer(sent)) } }
  end

  def batch_answer(sent)
    id = sent['url'].split('/').last
    batch_answers[id] || { status: 200, body: { id: id, expirationDateTime: renewed_until } }
  end

  def stub_delete(id, status: 204, body: '')
    stub_request(:delete, "#{subscriptions_url}/#{id}").to_return(status: status, body: body)
  end

  def record_log
    output = StringIO.new
    action({}).logger = Logger.new(output)
    output
  end

  def refuse_credentials_after_the_list
    stub_request(:post, token_url)
      .to_return({ status: 200, body: { access_token: 'outlook-token', expires_in: 0 }.to_json },
                 { status: 401, body: refused_secret })
  end

  def run_failed(count = 1)
    "#{count} subscription(s) could not be kept alive. The run log names each one."
  end

  describe 'a run with nothing due' do
    it 'lists what Microsoft holds and touches nothing when every subscription is fresh' do
      store(runbook_id => row(expires_at: later))
      stub_list(held(subscription_id))
      output = run_action({})
      expect(output[:results]).to eq([])
      expect(output.to_h).to include('created' => 0, 'renewed' => 0, 'removed' => 0)
      expect(a_request(:get, subscriptions_url)).to have_been_made.once
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'ends quietly, asks Microsoft nothing, and says which connection to use, when the connection records nothing' do
      store({})
      logged = record_log
      expect(run_action({})[:results]).to eq([])
      expect(a_request(:any, /graph\.microsoft\.com/)).not_to have_been_made
      expect(logged.string).to include(MicrosoftOutlookConnector::NOTHING_RECORDED)
    end
  end

  describe 'creating a subscription' do
    it 'creates the subscription of a trigger that was deployed but never subscribed' do
      store(runbook_id => row(id: nil))
      stub_list
      stub_create
      output = run_action({})
      expect(sent_creates.last).to include('changeType' => 'created', 'notificationUrl' => endpoint,
                                           'resource' => mail_resource)
      expect(output[:created]).to eq(1)
      expect(output[:results].first.to_h).to include('runbook_id' => runbook_id, 'outcome' => 'created',
                                                     'subscription_id' => subscription_id,
                                                     'mailbox' => 'adele@contoso.com')
    end

    it 'sends no lifecycle address, and stores the id, the expiry and the client state it sent, encrypted' do
      store(runbook_id => row(id: nil))
      stub_list
      stub_create
      run_action({})
      expect(sent_creates.last).not_to have_key('lifecycleNotificationUrl')
      stored = stored_rows[runbook_id]
      expect(stored['id']).to eq(subscription_id)
      expect(stored['expires_at']).to eq(renewed_until)
      expect(stored['client_state']).not_to eq(sent_creates.last['clientState'])
      expect(new_secret_string(stored['client_state']).decrypt).to eq(sent_creates.last['clientState'])
    end

    it 'gives each subscription its own client state' do
      store(runbook_id => row(id: nil), other_runbook_id => bobs_row.except('id', 'client_state', 'expires_at'))
      stub_list
      stub_create
      run_action({})
      expect(sent_creates.map { |body| body['clientState'] }.uniq.length).to eq(2)
    end

    it 'creates from the address an earlier version filed the row under, when the row carries none' do
      store(endpoint => row(id: nil).except('endpoint'))
      stub_list
      stub_create
      output = run_action({})
      expect(sent_creates.last['notificationUrl']).to eq(endpoint)
      expect(stored_rows[endpoint]['id']).to eq(subscription_id)
      expect(output[:results].first[:runbook_id]).to eq(runbook_id)
    end

    it 'creates a new subscription when the stored one is missing from what Microsoft holds' do
      store(runbook_id => row(expires_at: later))
      stub_list
      stub_create(body: { id: new_subscription_id, expirationDateTime: renewed_until })
      output = run_action({})
      expect(a_request(:post, batch_url)).not_to have_been_made
      expect(output[:results].first[:outcome]).to eq('created')
      expect(stored_rows[runbook_id]['id']).to eq(new_subscription_id)
    end

    it 'fails the row of a trigger that recorded nothing to watch, logs it, and fails the run' do
      store(runbook_id => { 'mailbox' => 'adele@contoso.com', 'folder' => 'inbox', 'endpoint' => endpoint })
      stub_list
      logged = record_log
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, run_failed)
      expect(logged.string).to include("for #{runbook_id}: This subscription records nothing to watch")
      expect(a_request(:post, subscriptions_url)).not_to have_been_made
    end

    it 'names both causes when Microsoft refuses the create, finishes the other rows, and fails the run' do
      store(runbook_id => row(id: nil), other_runbook_id => bobs_row)
      stub_list(held(other_subscription_id, endpoint: other_endpoint))
      stub_create(status: 400, body: { error: { code: 'ValidationError',
                                                message: 'Subscription validation request failed.', } })
      stub_batch
      logged = record_log
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, run_failed)
      expect(stored_rows[other_runbook_id]['expires_at']).to eq(renewed_until)
      expect(logged.string).to include("#{mail_resource} for #{runbook_id}: Microsoft did not create the " \
                                       'subscription. Microsoft Graph returned HTTP 400 ValidationError: ' \
                                       'Subscription validation request failed. Microsoft checks that it can reach ' \
                                       'the trigger')
    end

    it 'fails the row when Microsoft answers a create with no subscription id' do
      store(runbook_id => row(id: nil))
      stub_list
      stub_create(body: { expirationDateTime: renewed_until })
      logged = record_log
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, run_failed)
      expect(logged.string).to include('created a subscription with no subscription id. The next run removes it.')
    end

    it 'reschedules the step for the wait Microsoft asks for when a create is rate limited' do
      store(runbook_id => row(id: nil))
      stub_list
      stub_create(status: 429, body: {}, headers: { 'Retry-After' => '3' })
      expect_reschedule_after(3) { run_action({}) }
    end

    it 'fails the run at once when Microsoft refuses the connection credentials, instead of failing every row' do
      store(runbook_id => row(id: nil), other_runbook_id => bobs_row)
      stub_request(:post, token_url).to_return(status: 401, body: refused_secret)
      expect { run_action({}) }.to raise_error(IPaaS::Job::Outbound::CustomerCredentialsError)
      expect(stored_rows[runbook_id]).to eq(row(id: nil))
    end

    it 'fails the run at once when the credentials stop working before a create, instead of failing the row' do
      store(runbook_id => row(id: nil))
      stub_list
      stub_create
      refuse_credentials_after_the_list
      expect { run_action({}) }.to raise_error(IPaaS::Job::Outbound::CustomerCredentialsError)
      expect(a_request(:get, subscriptions_url)).to have_been_made.once
      expect(a_request(:post, subscriptions_url)).not_to have_been_made
      expect(stored_rows[runbook_id]).to eq(row(id: nil))
    end
  end

  describe 'renewing the subscriptions Microsoft holds' do
    it 'renews, in one batch, every subscription that ends within a day' do
      store(runbook_id => row, other_runbook_id => bobs_row)
      stub_list(held(subscription_id), held(other_subscription_id, endpoint: other_endpoint))
      stub_batch
      output = run_action({})
      expect(sent_batches.length).to eq(1)
      expect(sent_batches.first.map { |request| request['method'] }).to all(eq('PATCH'))
      expect(sent_batches.first.map { |request| request['url'] })
        .to contain_exactly("/subscriptions/#{subscription_id}", "/subscriptions/#{other_subscription_id}")
      expect(output[:renewed]).to eq(2)
      expect(output[:results].map { |result| result[:outcome] }).to eq(%w[renewed renewed])
      expect(stored_rows.values.map { |stored| stored['expires_at'] }).to all(eq(renewed_until))
    end

    it 'asks Microsoft for an expiry thirty minutes inside the seven days it allows a mail subscription, in UTC' do
      Timecop.freeze(Time.utc(2026, 10, 5, 12)) do
        store(runbook_id => row(expires_at: '2026-10-05T18:00:00Z'))
        stub_list(held(subscription_id))
        stub_batch
        run_action({})
      end
      expect(sent_batches.first.first['body']['expirationDateTime']).to eq('2026-10-12T11:30:00Z')
    end

    it 'leaves a subscription alone until it ends within a day' do
      store(runbook_id => row(expires_at: later), other_runbook_id => bobs_row)
      stub_list(held(subscription_id), held(other_subscription_id, endpoint: other_endpoint))
      stub_batch
      output = run_action({})
      expect(sent_batches.first.map { |request| request['url'] }).to eq(["/subscriptions/#{other_subscription_id}"])
      expect(output[:results].map { |result| result[:runbook_id] }).to eq([other_runbook_id])
    end

    it 'renews a subscription whose stored expiry is missing' do
      store(runbook_id => row(expires_at: nil))
      stub_list(held(subscription_id))
      stub_batch
      expect(run_action({})[:renewed]).to eq(1)
    end

    it 'sends the renewals twenty at a time' do
      limit = MicrosoftOutlookConnector::BATCH_REQUEST_LIMIT
      rows = rows_past_one_batch
      store(rows)
      stub_list_of(rows)
      stub_batch
      output = run_action({})
      expect(sent_batches.map(&:length)).to eq([limit, 1])
      expect(output[:renewed]).to eq(limit + 1)
    end

    it 'creates a new subscription when a renewal answers 404' do
      store(runbook_id => row)
      stub_list(held(subscription_id))
      batch_answers[subscription_id] = { status: 404, body: { error: { code: 'ResourceNotFound', message: 'gone' } } }
      stub_batch
      stub_create(body: { id: new_subscription_id, expirationDateTime: renewed_until })
      output = run_action({})
      expect(output[:created]).to eq(1)
      expect(output[:renewed]).to eq(0)
      expect(stored_rows[runbook_id]['id']).to eq(new_subscription_id)
    end

    it 'reports a renewal Microsoft refused on its row, renews the others, and fails the run' do
      store(runbook_id => row, other_runbook_id => bobs_row)
      stub_list(held(subscription_id), held(other_subscription_id, endpoint: other_endpoint))
      batch_answers[subscription_id] = { status: 403, body: access_denied }
      stub_batch
      logged = record_log
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, run_failed)
      expect(stored_rows[other_runbook_id]['expires_at']).to eq(renewed_until)
      expect(stored_rows[runbook_id]['expires_at']).to eq(soon)
      expect(logged.string).to include("#{mail_resource} for #{runbook_id}: Microsoft Graph returned HTTP 403 " \
                                       'ErrorAccessDenied: Access is denied.')
    end

    it 'renews a subscription whose stored expiry cannot be read' do
      store(runbook_id => row(expires_at: 'not a time'))
      stub_list(held(subscription_id))
      stub_batch
      expect(run_action({})[:renewed]).to eq(1)
    end

    it 'stores the expiry it asked for when Microsoft answers a renewal without one' do
      Timecop.freeze(Time.utc(2026, 10, 5, 12)) do
        store(runbook_id => row(expires_at: '2026-10-05T18:00:00Z'))
        stub_list(held(subscription_id))
        batch_answers[subscription_id] = { status: 200, body: 'renewed' }
        stub_batch
        run_action({})
      end
      expect(stored_rows[runbook_id]['expires_at']).to eq('2026-10-12T11:30:00Z')
    end

    it 'fails every row of a batch Microsoft refuses, still sends the other batches, and fails the run' do
      limit = MicrosoftOutlookConnector::BATCH_REQUEST_LIMIT
      rows = rows_past_one_batch
      store(rows)
      stub_list_of(rows)
      stub_request(:post, batch_url)
        .to_return({ status: 403, body: access_denied.to_json }, { status: 200, body: first_request_renewed })
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, run_failed(limit))
      expect(a_request(:post, batch_url)).to have_been_made.twice
      expect(stored_rows["runbook-#{limit + 1}"]['expires_at']).to eq(renewed_until)
    end

    it 'fails every row of a batch whose answer it cannot read, still sends the rest and creates, and fails the run' do
      limit = MicrosoftOutlookConnector::BATCH_REQUEST_LIMIT
      rows = rows_past_one_batch
      store(rows.merge(other_runbook_id => bobs_row.except('id', 'client_state', 'expires_at')))
      stub_list_of(rows)
      stub_request(:post, batch_url)
        .to_return({ status: 200, body: '[]' }, { status: 200, body: first_request_renewed })
      stub_create(body: { id: new_subscription_id, expirationDateTime: renewed_until })
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, run_failed(limit))
      expect(a_request(:post, batch_url)).to have_been_made.twice
      expect(stored_rows["runbook-#{limit + 1}"]['expires_at']).to eq(renewed_until)
      expect(stored_rows[other_runbook_id]['id']).to eq(new_subscription_id)
    end

    it 'fails the row of a batch whose answers are not objects, and fails the run' do
      store(runbook_id => row)
      stub_list(held(subscription_id))
      stub_request(:post, batch_url).to_return(status: 200, body: { responses: [7] }.to_json)
      logged = record_log
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, run_failed)
      expect(logged.string).to include('a response that is not an object')
    end

    it 'fails the row of a batch that answers a request it never sent, and fails the run' do
      store(runbook_id => row)
      stub_list(held(subscription_id))
      stub_request(:post, batch_url).to_return(status: 200, body: { responses: [{ id: '99', status: 200 }] }.to_json)
      logged = record_log
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, run_failed)
      expect(logged.string).to include("answered request '99', which this batch never sent")
    end

    it 'fails the row of a batch that answers one request twice, and fails the run' do
      store(runbook_id => row)
      stub_list(held(subscription_id))
      renewed = { id: '0', status: 200, body: { expirationDateTime: renewed_until } }
      twice = { responses: [renewed, { id: '0', status: 404 }] }
      stub_request(:post, batch_url).to_return(status: 200, body: twice.to_json)
      logged = record_log
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, run_failed)
      expect(logged.string).to include('answered one request of this batch more than once')
      expect(a_request(:post, subscriptions_url)).not_to have_been_made
    end

    it 'fails the row whose refusal carries a text body, still creates, and fails the run' do
      store(runbook_id => row, other_runbook_id => bobs_row.except('id', 'client_state', 'expires_at'))
      stub_list(held(subscription_id))
      batch_answers[subscription_id] = { status: 403, body: 'denied' }
      stub_batch
      stub_create(body: { id: new_subscription_id, expirationDateTime: renewed_until })
      logged = record_log
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, run_failed)
      expect(logged.string).to include("#{mail_resource} for #{runbook_id}: Microsoft Graph returned HTTP 403 : " \
                                       'no error details')
      expect(stored_rows[other_runbook_id]['id']).to eq(new_subscription_id)
    end

    it 'fails the row whose answer carries a status that is not a number, and fails the run' do
      store(runbook_id => row)
      stub_list(held(subscription_id))
      batch_answers[subscription_id] = { status: true }
      stub_batch
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, run_failed)
      expect(stored_rows[runbook_id]['expires_at']).to eq(soon)
    end

    it 'renews before it creates, so a create Microsoft makes wait does not hold back the renewals' do
      store(runbook_id => row, other_runbook_id => bobs_row.except('id', 'client_state', 'expires_at'))
      stub_list(held(subscription_id))
      stub_batch
      stub_create(status: 429, body: {}, headers: { 'Retry-After' => '3' })
      expect_reschedule_after(3) { run_action({}) }
      expect(stored_rows[runbook_id]['expires_at']).to eq(renewed_until)
    end

    it 'still renews, trusting the stored ids, when Microsoft refuses to list its subscriptions' do
      store(runbook_id => row)
      stub_request(:get, subscriptions_url).to_return(status: 403, body: access_denied.to_json)
      stub_batch
      logged = record_log
      output = run_action({})
      expect(output[:renewed]).to eq(1)
      expect(a_request(:post, subscriptions_url)).not_to have_been_made
      expect(logged.string).to include('Microsoft did not list its subscriptions')
    end

    it 'reschedules the step for the wait Microsoft asks for when the batch itself is rate limited' do
      store(runbook_id => row)
      stub_list(held(subscription_id))
      stub_batch(status: 429, headers: { 'Retry-After' => '3' })
      expect_reschedule_after(3) { run_action({}) }
    end

    it 'reschedules the step on a passing Microsoft server error instead of burning the subscription' do
      store(runbook_id => row)
      stub_list(held(subscription_id))
      stub_batch(status: 502)
      expect_reschedule_after(60) { run_action({}) }
    end

    it 'trusts the stored id, and renews rather than creates, when Microsoft cuts the list short' do
      next_page = "#{subscriptions_url}?page=2"
      cut_short = { value: [], '@odata.nextLink': next_page }.to_json
      stub_request(:get, subscriptions_url).to_return(status: 200, body: cut_short)
      stub_request(:get, next_page).to_return(status: 200, body: cut_short)
      store(runbook_id => row)
      stub_batch
      output = run_action({})
      list_requests = MicrosoftOutlookConnector::MAX_SUBSCRIPTION_LIST_REQUESTS
      expect(a_request(:get, next_page)).to have_been_made.times(list_requests - 1)
      expect(output[:renewed]).to eq(1)
      expect(a_request(:post, subscriptions_url)).not_to have_been_made
    end

    it 'trusts the stored ids, and logs one reason, when the list Microsoft answers is not a list' do
      stub_request(:get, subscriptions_url).to_return(status: 200, body: { value: 'unexpected' }.to_json)
      store(runbook_id => row)
      stub_batch
      logged = record_log
      output = run_action({})
      expect(output[:renewed]).to eq(1)
      expect(a_request(:post, subscriptions_url)).not_to have_been_made
      expect(logged.string).to include('Microsoft did not list its subscriptions, so this run trusts every stored ' \
                                       'subscription id: Microsoft Graph returned a subscription list that is not ' \
                                       'a list of subscriptions.')
      expect(logged.string.scan('not a list of subscriptions').length).to eq(1)
      expect(logged.string).not_to include('more subscriptions than')
    end

    it 'trusts the stored ids when the list Microsoft answers holds something that is not a subscription' do
      stub_request(:get, subscriptions_url).to_return(status: 200, body: { value: [held(subscription_id), 7] }.to_json)
      store(runbook_id => row)
      stub_batch
      logged = record_log
      output = run_action({})
      expect(output[:renewed]).to eq(1)
      expect(logged.string).to include('not a list of subscriptions')
    end

    it 'trusts the stored ids when Microsoft answers the list with a body that is not an object' do
      stub_request(:get, subscriptions_url).to_return(status: 200, body: '[]')
      store(runbook_id => row)
      stub_batch
      logged = record_log
      output = run_action({})
      expect(output[:renewed]).to eq(1)
      expect(logged.string).to include('Microsoft Graph returned a value that is not an object')
    end

    it 'trusts the stored ids, and follows no link, when the next page of the list is on another host' do
      elsewhere = 'https://elsewhere.example.com/v1.0/subscriptions?page=2'
      foreign_page = { value: [], '@odata.nextLink': elsewhere }.to_json
      stub_request(:get, subscriptions_url).to_return(status: 200, body: foreign_page)
      store(runbook_id => row)
      stub_batch
      logged = record_log
      output = run_action({})
      expect(output[:renewed]).to eq(1)
      expect(a_request(:get, elsewhere)).not_to have_been_made
      expect(logged.string).to include('next page link that is not on')
    end

    it 'reschedules the step for the wait Microsoft asks for when the list is rate limited' do
      store(runbook_id => row)
      stub_request(:get, subscriptions_url).to_return(status: 429, body: '{}', headers: { 'Retry-After' => '3' })
      expect_reschedule_after(3) { run_action({}) }
    end

    it 'fails the row Microsoft left out of a batch answer, renews the others, and fails the run' do
      store(runbook_id => row, other_runbook_id => bobs_row)
      stub_list(held(subscription_id), held(other_subscription_id, endpoint: other_endpoint))
      answered = { responses: [{ id: '1', status: 200, body: { expirationDateTime: renewed_until } }] }
      stub_request(:post, batch_url).to_return(status: 200, body: answered.to_json)
      logged = record_log
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, run_failed)
      expect(logged.string).to include("#{mail_resource} for #{runbook_id}: Microsoft Graph returned no answer " \
                                       'for this request.')
      expect(stored_rows[other_runbook_id]['expires_at']).to eq(renewed_until)
      expect(stored_rows[runbook_id]['expires_at']).to eq(soon)
    end

    it 'fails the run at once when the credentials stop working before a renewal, instead of failing the row' do
      store(runbook_id => row)
      stub_list(held(subscription_id))
      stub_batch
      refuse_credentials_after_the_list
      expect { run_action({}) }.to raise_error(IPaaS::Job::Outbound::CustomerCredentialsError)
      expect(a_request(:get, subscriptions_url)).to have_been_made.once
      expect(a_request(:post, batch_url)).not_to have_been_made
      expect(stored_rows[runbook_id]['expires_at']).to eq(soon)
    end
  end

  describe 'subscriptions nobody recorded' do
    it 'deletes a subscription that points at a trigger of this connection but is not recorded' do
      store(runbook_id => row(expires_at: later))
      stub_list(held(subscription_id), held(other_subscription_id))
      stub_delete(other_subscription_id)
      output = run_action({})
      expect(a_request(:delete, "#{subscriptions_url}/#{other_subscription_id}")).to have_been_made.once
      expect(output[:removed]).to eq(1)
      expect(output[:results].first.to_h).to include('outcome' => 'removed', 'subscription_id' => other_subscription_id,
                                                     'runbook_id' => runbook_id, 'resource' => mail_resource,
                                                     'mailbox' => 'adele@contoso.com', 'expires_at' => soon)
    end

    it 'reports the watch and expiry of the subscription it deleted, not those of the one the row records' do
      archive = 'users/adele@contoso.com/mailFolders/archive/messages'
      store(runbook_id => row(expires_at: later))
      stub_list(held(subscription_id), held(other_subscription_id, resource: archive))
      stub_delete(other_subscription_id)
      output = run_action({})
      expect(output[:results].first.to_h).to include('subscription_id' => other_subscription_id, 'resource' => archive,
                                                     'mailbox' => nil, 'folder' => nil, 'expires_at' => soon)
    end

    it 'leaves alone a listed subscription whose id is not a Microsoft subscription id' do
      store(runbook_id => row(expires_at: later))
      stub_list(held(subscription_id), held('not-a-subscription-id'))
      output = run_action({})
      expect(output[:removed]).to eq(0)
      expect(a_request(:delete, %r{subscriptions/})).not_to have_been_made
    end

    it 'reads the rows again only for a subscription that no row records' do
      store(runbook_id => row(expires_at: later), other_runbook_id => bobs_row(expires_at: later))
      stub_list(held(subscription_id), held(other_subscription_id, endpoint: other_endpoint))
      connection_store = action({}).outbound_connection.store
      allow(connection_store).to receive(:read).and_call_original
      run_action({})
      expect(connection_store).to have_received(:read).with(MicrosoftOutlookConnector::SUBSCRIPTIONS_STORE_KEY).twice
    end

    it 'leaves alone a subscription of this application that points somewhere else' do
      store(runbook_id => row(expires_at: later))
      stub_list(held(subscription_id),
                held(other_subscription_id, endpoint: 'https://ipaas.example.com/inbound/1/other-solution/runbook'))
      run_action({})
      expect(a_request(:delete, /subscriptions/)).not_to have_been_made
    end

    it 'leaves alone a subscription another run recorded after this run read the rows' do
      store(runbook_id => row(expires_at: later))
      stub_list(held(subscription_id), held(other_subscription_id), held(new_subscription_id))
      stub_request(:delete, "#{subscriptions_url}/#{other_subscription_id}").to_return do
        store(runbook_id => row(id: new_subscription_id, expires_at: later))
        { status: 204, body: '' }
      end
      run_action({})
      expect(a_request(:delete, "#{subscriptions_url}/#{new_subscription_id}")).not_to have_been_made
    end

    it 'drops a row filed under the trigger address when the row under its runbook records the same address' do
      store(runbook_id => row(expires_at: later), endpoint => row(id: other_subscription_id).except('endpoint'))
      stub_list(held(subscription_id), held(other_subscription_id))
      stub_delete(other_subscription_id)
      output = run_action({})
      expect(a_request(:delete, "#{subscriptions_url}/#{other_subscription_id}")).to have_been_made.once
      expect(output[:results].map { |result| result[:outcome] }).to eq(['removed'])
    end

    it 'reports a subscription it could not delete and fails the run' do
      store(runbook_id => row(expires_at: later))
      stub_list(held(subscription_id), held(other_subscription_id))
      stub_delete(other_subscription_id, status: 403, body: access_denied.to_json)
      logged = record_log
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, run_failed)
      expect(logged.string).to include("#{mail_resource} for #{runbook_id}: Microsoft Graph returned HTTP 403 " \
                                       'ErrorAccessDenied')
    end

    it 'fails the run at once when the credentials stop working before a delete, instead of failing the row' do
      store(runbook_id => row(expires_at: later))
      stub_list(held(subscription_id), held(other_subscription_id))
      stub_delete(other_subscription_id)
      refuse_credentials_after_the_list
      expect { run_action({}) }.to raise_error(IPaaS::Job::Outbound::CustomerCredentialsError)
      expect(a_request(:get, subscriptions_url)).to have_been_made.once
      expect(a_request(:delete, "#{subscriptions_url}/#{other_subscription_id}")).not_to have_been_made
    end
  end

  describe 'rows that change while Microsoft is answering' do
    it 'keeps a row another trigger recorded while this subscription was being created' do
      store(runbook_id => row(id: nil))
      stub_list
      stub_create { store(runbook_id => row(id: nil), other_runbook_id => bobs_row(expires_at: later)) }
      run_action({})
      expect(stored_rows.keys).to contain_exactly(runbook_id, other_runbook_id)
      expect(stored_rows[runbook_id]['id']).to eq(subscription_id)
    end

    it 'deletes a subscription it created for a trigger that changed while Microsoft was creating it' do
      store(runbook_id => row(id: nil))
      stub_list
      stub_create { store(runbook_id => row(id: nil, folder: 'archive')) }
      stub_delete(subscription_id)
      output = run_action({})
      expect(output[:results].first[:outcome]).to eq('skipped')
      expect(a_request(:delete, "#{subscriptions_url}/#{subscription_id}")).to have_been_made.once
      expect(stored_rows[runbook_id]).to eq(row(id: nil, folder: 'archive'))
    end

    it 'deletes a subscription it created when another run stored a different one meanwhile' do
      store(runbook_id => row(id: nil))
      stub_list
      stub_create { store(runbook_id => row(id: other_subscription_id, expires_at: later)) }
      stub_delete(subscription_id)
      output = run_action({})
      expect(output[:results].first[:outcome]).to eq('skipped')
      expect(stored_rows[runbook_id]['id']).to eq(other_subscription_id)
    end

    it 'stores nothing for a subscription whose trigger was deprovisioned while Microsoft was renewing it' do
      store(runbook_id => row, other_runbook_id => bobs_row)
      stub_list(held(subscription_id), held(other_subscription_id, endpoint: other_endpoint))
      stub_batch { store(other_runbook_id => bobs_row) }
      output = run_action({})
      expect(output[:results].map { |result| [result[:runbook_id], result[:outcome]] })
        .to contain_exactly([runbook_id, 'skipped'], [other_runbook_id, 'renewed'])
      expect(stored_rows.keys).to eq([other_runbook_id])
      expect(stored_rows[other_runbook_id]['expires_at']).to eq(renewed_until)
    end
  end
end

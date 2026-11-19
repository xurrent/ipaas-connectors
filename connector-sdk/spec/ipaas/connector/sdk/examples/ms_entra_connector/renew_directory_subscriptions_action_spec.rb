require 'spec_helper'

describe 'Microsoft Entra Renew Directory Subscriptions Action', :action, :ms_entra do
  let(:action_template_id) { '01a1a1c8-debd-77d8-a35b-763f55973100' }
  let(:subscriptions_url) { "#{graph}/subscriptions" }
  let(:batch_url) { "#{graph}/$batch" }
  let(:runbook_id) { '01a13544-c2d4-7cc7-8726-e73182d73e05' }
  let(:other_runbook_id) { '01a13544-c2d4-7cc7-8726-e73182d73e06' }
  let(:endpoint) { "https://ipaas.example.com/inbound/1/solution/#{runbook_id}" }
  let(:other_endpoint) { "https://ipaas.example.com/inbound/1/solution/#{other_runbook_id}" }
  let(:subscription_id) { '0fc0f4a5-3f6e-4bc5-9d1a-52e2c5b81e0c' }
  let(:other_subscription_id) { 'b6b2b0d1-6f1a-4a1e-9a01-7c3e0f9a55aa' }
  let(:new_subscription_id) { '3d1f0c2e-5a6b-4c7d-8e9f-0a1b2c3d4e5f' }
  let(:renewed_until) { '2026-11-30T13:36:18Z' }
  let(:soon) { 23.hours.from_now.utc.iso8601 }
  let(:later) { 25.hours.from_now.utc.iso8601 }
  let(:sent_creates) { [] }
  let(:sent_batches) { [] }
  let(:batch_answers) { {} }

  def row(id: subscription_id, change_type: 'updated', resource: 'users', expires_at: soon, endpoint: self.endpoint)
    base = { 'resource' => resource, 'change_type' => change_type, 'endpoint' => endpoint }
    return base unless id

    base.merge('id' => id, 'client_state' => make_secret_string('state-1').to_s, 'expires_at' => expires_at)
  end

  def held(id, endpoint: self.endpoint)
    { id: id, notificationUrl: endpoint, resource: 'users', changeType: 'updated', expirationDateTime: later }
  end

  def store(rows)
    action({}).outbound_connection.store.write(MsEntraConnector::SUBSCRIPTIONS_STORE_KEY, rows)
  end

  def stored_rows
    action.outbound_connection.store.read(MsEntraConnector::SUBSCRIPTIONS_STORE_KEY)
  end

  def record_log
    output = StringIO.new
    action({}).logger = Logger.new(output)
    output
  end

  def rows_past_one_batch
    (1..(MsEntraConnector::BATCH_REQUEST_LIMIT + 1)).to_h do |number|
      id = format('%08d-0000-4000-8000-000000000000', number)
      ["runbook-#{number}", row(id: id, endpoint: "https://ipaas.example.com/inbound/1/solution/runbook-#{number}")]
    end
  end

  def stub_list(*subscriptions)
    stub_request(:get, subscriptions_url).to_return do
      yield if block_given?
      { status: 200, body: { value: subscriptions }.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def stub_create(status: 201, body: { id: subscription_id, expirationDateTime: renewed_until })
    stub_request(:post, subscriptions_url)
      .with { |request| sent_creates.push(JSON.parse(request.body)) }
      .to_return do |_request|
        yield if block_given?
        { status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
      end
  end

  def stub_batch
    stub_request(:post, batch_url)
      .with { |request| sent_batches.push(JSON.parse(request.body)['requests']) }
      .to_return do |request|
        yield if block_given?
        { status: 200, body: batch_body(request).to_json, headers: { 'Content-Type' => 'application/json' } }
      end
  end

  def batch_body(request)
    { responses: JSON.parse(request.body)['requests'].map { |sent| { id: sent['id'] }.merge(batch_answer(sent)) } }
  end

  def batch_answer(sent)
    id = sent['url'].split('/').last
    batch_answers[id] || { status: 200, body: { id: id, expirationDateTime: renewed_until } }
  end

  def stub_delete(id)
    stub_request(:delete, "#{subscriptions_url}/#{id}").to_return(status: 204, body: '')
  end

  def run_failed(count = 1)
    "#{count} subscription(s) could not be kept alive. The run log names each one."
  end

  describe 'a connection that records nothing' do
    it 'answers zero counts and asks Microsoft Graph nothing' do
      store({})
      output = run_action({})
      expect(output.to_h).to include('created' => 0, 'renewed' => 0, 'removed' => 0, 'results' => [])
      expect(a_request(:any, /graph\.microsoft\.com/)).not_to have_been_made
    end
  end

  describe 'creating a subscription' do
    it 'creates an updated subscription for a recorded row with none, thirty minutes inside the 29 days' do
      Timecop.freeze(Time.utc(2026, 10, 5, 12)) do
        store(runbook_id => row(id: nil))
        stub_list
        stub_create(body: { id: subscription_id })
        run_action({})
      end
      expect(sent_creates.length).to eq(1)
      expect(sent_creates.first).to include('changeType' => 'updated', 'resource' => 'users',
                                            'notificationUrl' => endpoint,
                                            'expirationDateTime' => '2026-11-03T11:30:00Z')
      expect(sent_creates.first['clientState']).to be_present
    end

    it 'sends the deleted change type the row records' do
      store(runbook_id => row(id: nil, change_type: 'deleted', resource: 'groups'))
      stub_list
      stub_create
      run_action({})
      expect(sent_creates.first).to include('changeType' => 'deleted', 'resource' => 'groups')
    end

    it 'stores the subscription id, the encrypted client state it sent, and the expiry on the row' do
      store(runbook_id => row(id: nil))
      stub_list
      stub_create
      output = run_action({})
      stored = stored_rows[runbook_id]
      expect(stored['id']).to eq(subscription_id)
      expect(stored['expires_at']).to eq(renewed_until)
      expect(stored['client_state']).not_to eq(sent_creates.first['clientState'])
      expect(new_secret_string(stored['client_state']).decrypt).to eq(sent_creates.first['clientState'])
      expect(output[:created]).to eq(1)
      expect(output[:results].first.to_h).to include('runbook_id' => runbook_id, 'outcome' => 'created',
                                                     'change_type' => 'updated', 'subscription_id' => subscription_id)
    end

    it 'creates a new subscription for a row whose stored id Microsoft Graph no longer holds' do
      store(runbook_id => row(expires_at: later))
      stub_list
      stub_create(body: { id: new_subscription_id, expirationDateTime: renewed_until })
      output = run_action({})
      expect(a_request(:post, batch_url)).not_to have_been_made
      expect(output[:results].first[:outcome]).to eq('created')
      expect(stored_rows[runbook_id]['id']).to eq(new_subscription_id)
    end

    it 'stores the expiry it asked for when Microsoft answers the create without one' do
      Timecop.freeze(Time.utc(2026, 10, 5, 12)) do
        store(runbook_id => row(id: nil))
        stub_list
        stub_create(body: { id: subscription_id })
        run_action({})
      end
      expect(stored_rows[runbook_id]['expires_at']).to eq('2026-11-03T11:30:00Z')
    end

    it 'keeps the old client state as the previous one when it recreates a subscription Microsoft no longer holds' do
      store(runbook_id => row(expires_at: later))
      stub_list
      stub_create(body: { id: new_subscription_id, expirationDateTime: renewed_until })
      run_action({})
      expect(new_secret_string(stored_rows[runbook_id]['previous_client_state']).decrypt).to eq('state-1')
    end

    it 'names both causes when Microsoft refuses the create, finishes the other rows, and fails the run' do
      store(runbook_id => row(id: nil), other_runbook_id => row(id: other_subscription_id, endpoint: other_endpoint))
      stub_list(held(other_subscription_id, endpoint: other_endpoint))
      stub_create(status: 400, body: { error: { code: 'ValidationError',
                                                message: 'Subscription validation request failed.', } })
      stub_batch
      logged = record_log
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, run_failed)
      expect(stored_rows[other_runbook_id]['expires_at']).to eq(renewed_until)
      expect(logged.string).to include("users for #{runbook_id}: Microsoft did not create the subscription. " \
                                       'Microsoft Graph returned HTTP 400 ValidationError: Subscription ' \
                                       'validation request failed. Microsoft checks that it can reach the trigger')
    end

    it 'deletes the subscription it created when the row changed while Microsoft Graph was answering' do
      store(runbook_id => row(id: nil))
      stub_list
      stub_create { store(runbook_id => row(id: nil, change_type: 'deleted')) }
      stub_delete(subscription_id)
      output = run_action({})
      expect(output[:results].first[:outcome]).to eq('skipped')
      expect(a_request(:delete, "#{subscriptions_url}/#{subscription_id}")).to have_been_made.once
      expect(stored_rows[runbook_id]).to eq(row(id: nil, change_type: 'deleted'))
    end

    it 'fails the row when Microsoft answers the create with an id that is not a GUID' do
      store(runbook_id => row(id: nil))
      stub_list
      stub_create(body: { id: 'not-a-guid', expirationDateTime: renewed_until })
      logged = record_log
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, run_failed)
      expect(logged.string).to include('Microsoft Graph created a subscription without a valid subscription id.')
    end

    it 'fails the row, and creates nothing, when the row records nothing to watch' do
      store(runbook_id => row(id: nil).except('resource'))
      stub_list
      stub_create
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, run_failed)
      expect(a_request(:post, subscriptions_url)).not_to have_been_made
    end
  end

  describe 'renewing' do
    it 'renews, through one batch PATCH, a subscription that ends in 23 hours' do
      store(runbook_id => row)
      stub_list(held(subscription_id))
      stub_batch
      output = run_action({})
      expect(sent_batches.length).to eq(1)
      expect(sent_batches.first.map { |request| [request['method'], request['url']] })
        .to eq([['PATCH', "/subscriptions/#{subscription_id}"]])
      expect(output[:renewed]).to eq(1)
      expect(stored_rows[runbook_id]['expires_at']).to eq(renewed_until)
    end

    it 'sends the new expiry in the body of the batch PATCH' do
      Timecop.freeze(Time.utc(2026, 10, 5, 12)) do
        store(runbook_id => row(expires_at: 1.hour.from_now.utc.iso8601))
        stub_list(held(subscription_id))
        stub_batch
        run_action({})
      end
      expect(sent_batches.first.first['body']).to eq('expirationDateTime' => '2026-11-03T11:30:00Z')
    end

    it 'stores the expiry it asked for when Microsoft answers the renewal without one' do
      Timecop.freeze(Time.utc(2026, 10, 5, 12)) do
        store(runbook_id => row(expires_at: 1.hour.from_now.utc.iso8601))
        stub_list(held(subscription_id))
        batch_answers[subscription_id] = { status: 200, body: {} }
        stub_batch
        run_action({})
      end
      expect(stored_rows[runbook_id]['expires_at']).to eq('2026-11-03T11:30:00Z')
    end

    it 'skips, and stores nothing, when the trigger is removed while Microsoft answers the renew batch' do
      store(runbook_id => row)
      stub_list(held(subscription_id))
      stub_batch { store({}) }
      output = run_action({})
      expect(output[:results].first[:outcome]).to eq('skipped')
      expect(stored_rows).to eq({})
    end

    it 'skips, and keeps the newer id, when the row records another subscription by the time the batch answers' do
      store(runbook_id => row)
      stub_list(held(subscription_id))
      stub_batch { store(runbook_id => row(id: new_subscription_id, expires_at: later)) }
      output = run_action({})
      expect(output[:results].first[:outcome]).to eq('skipped')
      expect(stored_rows[runbook_id]['id']).to eq(new_subscription_id)
    end

    it 'reschedules the run when Microsoft answers the renew batch with 502' do
      store(runbook_id => row)
      stub_list(held(subscription_id))
      stub_request(:post, batch_url).to_return(status: 502, body: 'Bad Gateway')
      expect { run_action({}) }.to raise_error(IPaaS::Job::RescheduleJob)
    end

    it 'fails the row when Microsoft answers one request of the renew batch twice' do
      store(runbook_id => row)
      stub_list(held(subscription_id))
      twice = { id: '0', status: 200, body: { expirationDateTime: renewed_until } }
      stub_request(:post, batch_url).to_return(status: 200, body: { responses: [twice, twice] }.to_json)
      logged = record_log
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, run_failed)
      expect(logged.string).to include('Microsoft Graph answered one request of this batch more than once')
    end

    it 'fails the row when the renew batch answers a request it never sent' do
      store(runbook_id => row)
      stub_list(held(subscription_id))
      answers = [{ id: '0', status: 200, body: {} }, { id: '7', status: 200, body: {} }]
      stub_request(:post, batch_url).to_return(status: 200, body: { responses: answers }.to_json)
      logged = record_log
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, run_failed)
      expect(logged.string).to include("Microsoft Graph answered request '7', which this batch never sent")
    end

    it 'leaves alone a subscription that ends in 25 hours' do
      store(runbook_id => row(expires_at: later))
      stub_list(held(subscription_id))
      output = run_action({})
      expect(a_request(:post, batch_url)).not_to have_been_made
      expect(output.to_h).to include('created' => 0, 'renewed' => 0, 'removed' => 0, 'results' => [])
    end

    it 'sends 21 expiring subscriptions in two batches of 20 and 1' do
      rows = rows_past_one_batch
      store(rows)
      stub_list(*rows.values.map { |stored| held(stored['id'], endpoint: stored['endpoint']) })
      stub_batch
      output = run_action({})
      expect(sent_batches.map(&:length)).to eq([20, 1])
      expect(output[:renewed]).to eq(21)
    end

    it 'recreates the subscription a batch answers 404, fails the one it answers 500, and fails the run after both' do
      store(runbook_id => row, other_runbook_id => row(id: other_subscription_id, endpoint: other_endpoint))
      stub_list(held(subscription_id), held(other_subscription_id, endpoint: other_endpoint))
      batch_answers[subscription_id] = { status: 404, body: { error: { code: 'ResourceNotFound', message: 'gone' } } }
      server_error = { error: { code: 'InternalServerError', message: 'try later' } }
      batch_answers[other_subscription_id] = { status: 500, body: server_error }
      stub_batch
      stub_create(body: { id: new_subscription_id, expirationDateTime: renewed_until })
      logged = record_log
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, run_failed)
      expect(stored_rows[runbook_id]['id']).to eq(new_subscription_id)
      expect(stored_rows[other_runbook_id]['expires_at']).to eq(soon)
      expect(logged.string).to include("users for #{other_runbook_id}: Microsoft Graph returned HTTP 500 " \
                                       'InternalServerError: try later')
    end
  end

  describe 'subscriptions nobody recorded' do
    it 'deletes a subscription that points at a recorded endpoint under an id no row records' do
      store(runbook_id => row(expires_at: later))
      stub_list(held(subscription_id), held(other_subscription_id))
      stub_delete(other_subscription_id)
      output = run_action({})
      expect(a_request(:delete, "#{subscriptions_url}/#{other_subscription_id}")).to have_been_made.once
      expect(output[:removed]).to eq(1)
      expect(output[:results].first.to_h).to include('outcome' => 'removed', 'runbook_id' => runbook_id,
                                                     'subscription_id' => other_subscription_id)
    end

    it 'leaves alone a subscription whose notification address is no endpoint of this connection' do
      store(runbook_id => row(expires_at: later))
      stub_list(held(subscription_id),
                held(other_subscription_id, endpoint: 'https://ipaas.example.com/inbound/1/other-solution/runbook'))
      output = run_action({})
      expect(a_request(:delete, /subscriptions/)).not_to have_been_made
      expect(output[:removed]).to eq(0)
    end

    it 'deletes nothing when a recorded row leaves the store while Microsoft lists the subscriptions' do
      store(runbook_id => row(expires_at: later))
      stub_list(held(subscription_id)) { store({}) }
      stub_delete(subscription_id)
      output = run_action({})
      expect(a_request(:delete, "#{subscriptions_url}/#{subscription_id}")).not_to have_been_made
      expect(output[:removed]).to eq(0)
    end

    it 'deletes nothing when a trigger records a new subscription while Microsoft lists the subscriptions' do
      store(runbook_id => row(id: other_subscription_id, expires_at: later))
      stub_list(held(subscription_id), held(other_subscription_id)) { store(runbook_id => row(expires_at: later)) }
      stub_delete(subscription_id)
      output = run_action({})
      expect(a_request(:delete, "#{subscriptions_url}/#{subscription_id}")).not_to have_been_made
      expect(output[:removed]).to eq(0)
    end
  end

  describe 'listing what Microsoft Graph holds' do
    it 'stops after 10 list pages and trusts the stored id instead of creating a subscription' do
      next_page = "#{subscriptions_url}?page=2"
      cut_short = { value: [], '@odata.nextLink': next_page }.to_json
      stub_request(:get, subscriptions_url).to_return(status: 200, body: cut_short)
      stub_request(:get, next_page).to_return(status: 200, body: cut_short)
      store(runbook_id => row(expires_at: later))
      logged = record_log
      output = run_action({})
      expect(a_request(:get, subscriptions_url)).to have_been_made.once
      expect(a_request(:get, next_page)).to have_been_made.times(9)
      expect(a_request(:post, subscriptions_url)).not_to have_been_made
      expect(output[:created]).to eq(0)
      expect(logged.string).to include('Microsoft holds more subscriptions than 10 pages list')
    end

    it 'trusts the stored ids, and sends nothing to the other host, when the next list page is on another host' do
      elsewhere = 'https://elsewhere.example.com/v1.0/subscriptions?page=2'
      stub_request(:get, subscriptions_url)
        .to_return(status: 200, body: { value: [], '@odata.nextLink': elsewhere }.to_json)
      store(runbook_id => row(expires_at: later))
      logged = record_log
      output = run_action({})
      expect(a_request(:any, /elsewhere\.example\.com/)).not_to have_been_made
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
      expect(output[:created]).to eq(0)
      expect(logged.string).to include('Microsoft did not list its subscriptions, so this run trusts every stored')
    end
  end
end

require 'spec_helper'

# The trigger owns the ClickUp webhook end to end: provision creates it, deprovision takes it down,
# and parse verifies ClickUp's signature before a job is ever created. None of that is reachable
# from the option helpers, so it is covered here. The webhook is registered on the Workspace the
# connection carries, which is the one Workspace the trigger still sends to ClickUp.
describe 'ClickUp Event Trigger', :trigger do
  let(:trigger_template_id) { '019fed58-1d55-76d4-bdfc-16fcf316c40c' }
  let(:base_url) { 'https://api.clickup.com/api/v2' }
  let(:api_token) { 'pk_test_token' }
  let(:workspace_id) { '90' }
  let(:outbound_connection_config) do
    { api_token: make_secret_string(api_token), workspace_id: workspace_id }
  end
  let(:trigger_config) { { event: ['taskStatusUpdated'] } }

  let(:webhook_secret) { 'clickup_webhook_signing_secret' }

  def create_webhook_stub(response: nil, workspace: '90')
    body = response || { id: 'wh-new', webhook: { id: 'wh-new', secret: webhook_secret } }
    stub_request(:post, "#{base_url}/team/#{workspace}/webhook")
      .to_return(status: 200, body: body.to_json)
  end

  def delete_webhook_stub(webhook_id, status: 200, body: '{}', headers: {})
    stub_request(:delete, "#{base_url}/webhook/#{webhook_id}")
      .to_return(status: status, body: body, headers: headers)
  end

  def stored_webhook
    trigger.store.read('webhook')
  end

  def seed_stored_webhook(id: 'wh-old', secret: webhook_secret, signature: 'a-previous-signature')
    trigger.store.write('webhook', {
      'id' => id,
      'secret' => make_secret_string(secret).to_s,
      'signature' => signature,
    })
  end

  # Every part except the endpoint is a seeded literal. Rebuilding a part from the same expression
  # the connector builds makes both sides move in one edit, so dropping that part from the
  # signature would leave this green. The endpoint is the framework's own value and has no literal
  # to seed, so it is read from the trigger and is the one part this does not pin.
  def current_signature
    { workspace_id: '90', endpoint: trigger.endpoint,
      events: ['taskStatusUpdated'], scope: {}, }.to_json
  end

  describe 'authenticate' do
    it 'sends a personal token exactly as ClickUp issued it' do
      stub = create_webhook_stub.with(headers: { 'Authorization' => 'pk_test_token' })

      trigger.provision

      expect(stub).to have_been_requested.once
    end

    context 'with an OAuth2 access token' do
      let(:api_token) { 'oauth_access_token_value' }

      it 'sends it with the Bearer scheme' do
        stub = create_webhook_stub.with(headers: { 'Authorization' => 'Bearer oauth_access_token_value' })

        trigger.provision

        expect(stub).to have_been_requested.once
      end
    end
  end

  describe 'provision' do
    it 'creates the webhook and stores its id, its secret and the signature of what it subscribed to' do
      stub = create_webhook_stub

      trigger.provision

      expect(stub).to have_been_requested.once
      expect(stored_webhook[:id]).to eq('wh-new')
      expect(new_secret_string(stored_webhook[:secret]).decrypt).to eq(webhook_secret)
      expect(stored_webhook[:signature]).to eq(current_signature)
    end

    it 'subscribes to every selected event in one webhook' do
      trigger_config[:event] = %w[taskStatusUpdated taskCreated]
      stub = create_webhook_stub
             .with(body: hash_including('events' => %w[taskCreated taskStatusUpdated]))

      trigger.provision

      expect(stub).to have_been_requested.once
    end

    it 'sends the trigger endpoint as the delivery target' do
      stub = create_webhook_stub.with(body: hash_including('endpoint' => trigger.endpoint))

      trigger.provision

      expect(stub).to have_been_requested.once
    end

    it 'does nothing when the stored signature already matches the current subscription' do
      seed_stored_webhook(signature: current_signature)
      stub = create_webhook_stub

      trigger.provision

      expect(stub).not_to have_been_requested
      expect(stored_webhook[:id]).to eq('wh-old')
    end

    # The signature is the whole subscription. Leaving the workspace out of it made a trigger moved
    # to another Workspace match its own stored entry and keep pointing at the old one.
    #
    # The seeded signature is the PRE-FIX shape, with no workspace_id at all. Seeding the fixed
    # shape with a different workspace proves nothing: the two strings differ either way, so the
    # example stayed green with workspace_id removed from the signature again.
    it 're-subscribes when only the workspace changed' do
      seed_stored_webhook(signature: { endpoint: trigger.endpoint,
                                       events: ['taskStatusUpdated'], scope: {}, }.to_json)
      create = create_webhook_stub
      delete = delete_webhook_stub('wh-old')

      trigger.provision

      expect(create).to have_been_requested.once
      expect(delete).to have_been_requested.once
      expect(stored_webhook[:id]).to eq('wh-new')
    end

    # The whole point of moving the field: a second connection registers on a second Workspace.
    context 'on a connection carrying a different workspace' do
      let(:workspace_id) { '77' }

      it 'registers the webhook there instead' do
        stub = create_webhook_stub(workspace: '77')

        trigger.provision

        expect(stub).to have_been_requested.once
      end
    end

    context 'when the connection has no workspace selected' do
      let(:outbound_connection_config) { { api_token: make_secret_string(api_token) } }

      # The Workspace is no longer a trigger field, so the connection is the only place to fix it
      # and the message has to say so.
      it 'fails naming the connection, and registers nothing' do
        expect { trigger.provision }.to raise_error(IPaaS::Job::FailJob, /no Workspace selected/)
        expect(a_request(:post, /api\.clickup\.com/)).not_to have_been_made
      end
    end

    it 'carries no workspace field in its own config schema' do
      expect(trigger_template.config_schema.fields.map(&:id)).not_to include(:workspace_id)
    end

    it 're-subscribes when the selected events changed' do
      seed_stored_webhook(signature: { workspace_id: '90', endpoint: trigger.endpoint,
                                       events: ['taskCreated'], scope: {}, }.to_json)
      create = create_webhook_stub
      delete = delete_webhook_stub('wh-old')

      trigger.provision

      expect(create).to have_been_requested.once
      expect(delete).to have_been_requested.once
      expect(stored_webhook[:id]).to eq('wh-new')
    end

    it 'sends the list filter to ClickUp so it never delivers what the trigger would drop' do
      trigger_config[:list_id] = '9'
      stub = create_webhook_stub.with(body: hash_including('list_id' => '9'))

      trigger.provision

      expect(stub).to have_been_requested.once
    end

    it 'falls back to the folder filter when no list is chosen' do
      trigger_config[:space_id] = '5'
      trigger_config[:folder_id] = '7'
      stub = create_webhook_stub.with(body: hash_including('folder_id' => '7'))

      trigger.provision

      expect(stub).to have_been_requested.once
    end

    it 'falls back to the space filter when neither a list nor a folder is chosen' do
      trigger_config[:space_id] = '5'
      stub = create_webhook_stub.with(body: hash_including('space_id' => '5'))

      trigger.provision

      expect(stub).to have_been_requested.once
    end

    it 'sends no location key at all when no filter is set' do
      stub = create_webhook_stub.with { |request| JSON.parse(request.body).keys.sort == %w[endpoint events] }

      trigger.provision

      expect(stub).to have_been_requested.once
    end

    # The new webhook is live at ClickUp the moment the create returns. Storing it first means a
    # failed clean-up of the old one costs a stale subscription; storing it last lost the new
    # webhook's id and secret for good, because a 429 raises RescheduleJob and skipped the write.
    it 'keeps the new webhook when removing the previous one is rate limited' do
      seed_stored_webhook
      create = create_webhook_stub
      # The `with` block asserts the ORDERING, not just the outcome: the new webhook has to be in
      # the store by the time the delete goes out. Without it, moving the write after the delete
      # left every example in this file green, because the rescue hides the difference.
      delete = delete_webhook_stub('wh-old', status: 429, body: 'slow down', headers: { 'Retry-After' => '30' })
               .with { stored_webhook.is_a?(Hash) && stored_webhook[:id] == 'wh-new' }

      expect { trigger.provision }.not_to raise_error

      expect(create).to have_been_requested.once
      expect(delete).to have_been_requested.once
      expect(stored_webhook[:id]).to eq('wh-new')
      expect(new_secret_string(stored_webhook[:secret]).decrypt).to eq(webhook_secret)
    end

    # The stored row is the only thing that names the webhook being replaced. This id used to live
    # in a local, so a rate limited delete lost it, and the signature check at the top of provision
    # skipped the delete on every later run, leaving the old webhook live for ever.
    it 'keeps the replaced id in the store when the delete is rate limited' do
      seed_stored_webhook
      create_webhook_stub
      delete_webhook_stub('wh-old', status: 429, body: 'slow down')

      trigger.provision

      expect(stored_webhook[:id]).to eq('wh-new')
      expect(stored_webhook[:replaces]).to eq('wh-old')
    end

    # The drain runs before the signature check, which is the only place a later run can still
    # reach a webhook left behind: once the signature matches, every line below it is skipped.
    # The cleared id afterwards is what proves the drain ran rather than the delete being retried.
    it 'deletes a webhook left behind by an earlier run even when the signature already matches' do
      seed_stored_webhook
      create_webhook_stub
      delete_webhook_stub('wh-old', status: 429, body: 'slow down')
      trigger.provision
      matching_signature = stored_webhook[:signature]
      delete = delete_webhook_stub('wh-old')

      trigger.provision

      # Twice counts the rate limited attempt above and this one, which is the point: the second
      # run reached the delete again even though its signature already matched.
      expect(delete).to have_been_requested.twice
      expect(stored_webhook[:signature]).to eq(matching_signature)
      expect(stored_webhook[:replaces]).to be_blank
    end

    it 'keeps the new webhook when removing the previous one fails outright' do
      seed_stored_webhook
      create = create_webhook_stub
      delete = delete_webhook_stub('wh-old', status: 500, body: 'boom')

      expect { trigger.provision }.not_to raise_error

      expect(create).to have_been_requested.once
      expect(delete).to have_been_requested.once
      expect(stored_webhook[:id]).to eq('wh-new')
    end

    # Without this the webhook stays live at ClickUp with nothing able to verify or remove it.
    it 'takes the new webhook back down when ClickUp returns no signing secret' do
      create_webhook_stub(response: { webhook: { id: 'wh-orphan' } })
      delete = delete_webhook_stub('wh-orphan')

      expect { trigger.provision }.to raise_error(IPaaS::Job::FailJob, 'ClickUp did not return a webhook secret')

      expect(delete).to have_been_requested.once
      expect(stored_webhook).to be_nil
    end

    # The clean-up path validates the id it was handed too, so an unusable one is logged and the
    # caller still reports the real problem rather than the clean-up's.
    it 'still reports the missing secret when the id ClickUp returned is not path safe' do
      create_webhook_stub(response: { webhook: { id: 'wh/evil' } })

      expect { trigger.provision }.to raise_error(IPaaS::Job::FailJob, 'ClickUp did not return a webhook secret')

      expect(a_request(:delete, /api\.clickup\.com/)).not_to have_been_made
    end

    it 'fails without a delete when ClickUp returns no webhook id at all' do
      create_webhook_stub(response: { webhook: { secret: webhook_secret } })

      expect { trigger.provision }.to raise_error(IPaaS::Job::FailJob, 'ClickUp did not return a webhook id')

      expect(a_request(:delete, %r{#{base_url}/webhook})).not_to have_been_made
    end

    it 'fails when no event is selected' do
      trigger_config[:event] = []

      expect { trigger.provision }.to raise_error(IPaaS::Job::FailJob, 'No event selected for the trigger')
      expect(a_request(:post, /api\.clickup\.com/)).not_to have_been_made
    end

    context 'when the workspace on the connection is not path safe' do
      let(:workspace_id) { '90/webhook/evil' }

      it 'fails before it reaches ClickUp' do
        expect { trigger.provision }
          .to raise_error(IPaaS::Job::FailJob, %r{workspace_id is not path safe: '90/webhook/evil'})
        expect(a_request(:post, /api\.clickup\.com/)).not_to have_been_made
      end
    end
  end

  describe 'deprovision' do
    it 'deletes the webhook and forgets it' do
      seed_stored_webhook
      delete = delete_webhook_stub('wh-old')

      trigger.deprovision

      expect(delete).to have_been_requested.once
      expect(stored_webhook).to be_nil
    end

    it 'forgets the webhook even when ClickUp refuses the delete' do
      seed_stored_webhook
      delete = delete_webhook_stub('wh-old', status: 500, body: 'boom')

      expect { trigger.deprovision }.not_to raise_error

      expect(delete).to have_been_requested.once
      expect(stored_webhook).to be_nil
    end

    # The stored id is the last thing that can reach the webhook, so a 429 must not consume it.
    # Forgetting here would leave the webhook live at ClickUp with nothing able to delete it.
    it 'keeps the webhook id when the delete is only rate limited, so the retry can still remove it' do
      seed_stored_webhook
      delete = delete_webhook_stub('wh-old', status: 429, body: 'slow down')

      expect { trigger.deprovision }.to raise_error(IPaaS::Job::RescheduleJob)

      expect(delete).to have_been_requested.once
      expect(stored_webhook).to include('id' => 'wh-old')
    end

    it 'does nothing when there is no webhook to remove' do
      expect { trigger.deprovision }.not_to raise_error

      expect(a_request(:delete, /api\.clickup\.com/)).not_to have_been_made
    end
  end

  describe 'parse' do
    # ClickUp signs the raw body with the per-webhook secret: a hex HMAC-SHA256 in X-Signature.
    def clickup_signature(raw_body, secret: webhook_secret)
      OpenSSL::HMAC.hexdigest('SHA256', secret, raw_body)
    end

    def delivery(payload, signature: :valid, raw_body: nil)
      body = raw_body || payload.to_json
      header = signature == :valid ? clickup_signature(body) : signature
      headers = header.nil? ? {} : { 'X-Signature' => header }
      trigger.parse_request(double('request', body: StringIO.new(body), headers: headers))
    end

    let(:status_change_payload) do
      {
        event: 'taskStatusUpdated',
        task_id: 'task-1',
        webhook_id: 'wh-old',
        list_id: '9',
        history_items: [
          { id: 'h1', type: 1, date: '1642740510345', field: 'status',
            before: { status: 'to do', color: '#f9d900' },
            after: { status: 'in progress', color: '#7C4DFF' }, },
        ],
      }
    end

    before { seed_stored_webhook }

    context 'signature verification' do
      it 'accepts a delivery signed with the stored secret' do
        stub_request(:get, "#{base_url}/task/task-1").to_return(status: 200, body: { id: 'task-1' }.to_json)

        expect(delivery(status_change_payload)[:event]).to eq('taskStatusUpdated')
      end

      it 'discards a delivery with no body' do
        expect { delivery(nil, raw_body: '') }
          .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'Webhook request has no body')
      end

      it 'discards a delivery when the trigger has no stored secret' do
        trigger.store.delete('webhook')

        expect { delivery(status_change_payload) }
          .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'Trigger is not subscribed (no stored webhook secret)')
      end

      it 'discards a delivery with no X-Signature header' do
        expect { delivery(status_change_payload, signature: nil) }
          .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'Missing X-Signature header')
      end

      it 'discards a delivery signed with the wrong secret' do
        body = status_change_payload.to_json
        forged = clickup_signature(body, secret: 'not-the-secret')

        expect { delivery(status_change_payload, signature: forged) }
          .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'Invalid webhook signature')
      end

      # The signature covers the exact bytes, so a body edited in flight no longer matches.
      it 'discards a delivery whose body was altered after signing' do
        signed = clickup_signature(status_change_payload.to_json)
        tampered = status_change_payload.merge(task_id: 'someone-elses-task').to_json

        expect { delivery(nil, raw_body: tampered, signature: signed) }
          .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'Invalid webhook signature')
      end

      it 'makes no outbound call for a delivery it discards' do
        expect { delivery(status_change_payload, signature: 'nonsense') }
          .to raise_error(IPaaS::Job::DiscardTriggerEvent)
        expect(a_request(:get, /api\.clickup\.com/)).not_to have_been_made
      end
    end

    context 'task hydration' do
      it 'fetches the full task for a task event' do
        stub = stub_request(:get, "#{base_url}/task/task-1")
               .to_return(status: 200, body: { id: 'task-1', name: 'Write it up' }.to_json)

        output = delivery(status_change_payload)

        expect(stub).to have_been_requested.once
        expect(output[:task][:name]).to eq('Write it up')
      end

      # The payload carries the whole before/after of the change. The output schema declares four
      # history keys, so those are all a runbook can read, whatever else ClickUp chose to send.
      it 'exposes only the declared history keys out of what ClickUp sent' do
        stub_request(:get, "#{base_url}/task/task-1").to_return(status: 200, body: { id: 'task-1' }.to_json)

        history = delivery(status_change_payload)[:history_items]

        expect(history.map { |item| item.to_h.symbolize_keys })
          .to eq([{ id: 'h1', type: 1, date: '1642740510345', field: 'status' }])
      end

      it 'does not fetch a task that was just deleted' do
        payload = { event: 'taskDeleted', task_id: 'task-1', webhook_id: 'wh-old', history_items: [] }

        output = delivery(payload)

        expect(a_request(:get, /api\.clickup\.com/)).not_to have_been_made
        expect(output[:task]).to be_nil
      end

      it 'passes a non-task event through without hydrating' do
        payload = { event: 'listUpdated', list_id: '9', webhook_id: 'wh-old', history_items: [] }

        output = delivery(payload)

        expect(a_request(:get, /api\.clickup\.com/)).not_to have_been_made
        expect(output[:event]).to eq('listUpdated')
      end

      it 'rejects a task id that is not path safe rather than build a URL from it' do
        payload = status_change_payload.merge(task_id: 'task-1/comment/9')

        expect { delivery(payload) }
          .to raise_error(IPaaS::Job::FailJob, %r{task_id is not path safe: 'task-1/comment/9'})
        expect(a_request(:get, /api\.clickup\.com/)).not_to have_been_made
      end
    end

    context 'status filter' do
      let(:trigger_config) do
        { event: ['taskStatusUpdated'], status_filter: 'in progress' }
      end

      it 'starts the workflow when the new status matches' do
        stub_request(:get, "#{base_url}/task/task-1").to_return(status: 200, body: { id: 'task-1' }.to_json)

        expect(delivery(status_change_payload)[:event]).to eq('taskStatusUpdated')
      end

      it 'matches regardless of the case ClickUp sends' do
        stub_request(:get, "#{base_url}/task/task-1").to_return(status: 200, body: { id: 'task-1' }.to_json)
        payload = status_change_payload
        payload[:history_items][0][:after][:status] = 'In Progress'

        expect(delivery(payload)[:event]).to eq('taskStatusUpdated')
      end

      it 'discards a change to any other status' do
        payload = status_change_payload
        payload[:history_items][0][:after][:status] = 'done'

        expect { delivery(payload) }
          .to raise_error(IPaaS::Job::DiscardTriggerEvent, "Status 'done' does not match filter 'in progress'")
        # The filters deliberately run before hydration, so a filtered-out event costs no Get Task.
        expect(a_request(:get, /api\.clickup\.com/)).not_to have_been_made
      end

      it 'leaves every other event alone' do
        payload = { event: 'listUpdated', list_id: '9', webhook_id: 'wh-old', history_items: [] }

        expect(delivery(payload)[:event]).to eq('listUpdated')
      end

      # ClickUp sends a bare string for before/after on text fields such as name and content.
      # Digging into one raised TypeError, which is neither FailJob nor DiscardTriggerEvent, so it
      # escaped the trigger handlers as a 500 instead of a discard.
      it 'reads past a history item whose before and after are plain strings' do
        stub_request(:get, "#{base_url}/task/task-1").to_return(status: 200, body: { id: 'task-1' }.to_json)
        payload = status_change_payload
        payload[:history_items].unshift({ id: 'h0', type: 1, date: '1642740510345', field: 'name',
                                          before: 'Old name', after: 'New name', })

        expect(delivery(payload)[:event]).to eq('taskStatusUpdated')
      end

      it 'discards rather than raises when every history item carries a string' do
        payload = status_change_payload
        payload[:history_items] = [{ id: 'h0', type: 1, date: '1642740510345', field: 'content',
                                     before: 'before text', after: 'after text', }]

        expect { delivery(payload) }.to raise_error(IPaaS::Job::DiscardTriggerEvent, /does not match filter/)
      end
    end

    context 'assignee filter' do
      let(:trigger_config) do
        { event: ['taskAssigneeUpdated'], assignee_filter: '184' }
      end

      # ClickUp names the user at after.id when one is added and at before.id when one is removed.
      def assignee_payload(field:, before: nil, after: nil)
        {
          event: 'taskAssigneeUpdated', task_id: 'task-1', webhook_id: 'wh-old',
          history_items: [{ id: 'h1', type: 1, date: '1642740510345', field: field,
                            before: before, after: after, }],
        }
      end

      it 'starts the workflow when the filtered user is added' do
        stub_request(:get, "#{base_url}/task/task-1").to_return(status: 200, body: { id: 'task-1' }.to_json)
        payload = assignee_payload(field: 'assignee_add', after: { id: 184, username: 'Sam' })

        expect(delivery(payload)[:event]).to eq('taskAssigneeUpdated')
      end

      it 'starts the workflow when the filtered user is removed' do
        stub_request(:get, "#{base_url}/task/task-1").to_return(status: 200, body: { id: 'task-1' }.to_json)
        payload = assignee_payload(field: 'assignee_rem', before: { id: 184, username: 'Sam' })

        expect(delivery(payload)[:event]).to eq('taskAssigneeUpdated')
      end

      it 'discards a change involving somebody else' do
        payload = assignee_payload(field: 'assignee_add', after: { id: 999, username: 'Alex' })

        expect { delivery(payload) }
          .to raise_error(IPaaS::Job::DiscardTriggerEvent, "Assignee '184' not involved in this change")
        expect(a_request(:get, /api\.clickup\.com/)).not_to have_been_made
      end

      # The same string-valued side that broke the status filter reaches this one too.
      it 'reads past a history item whose before and after are plain strings' do
        stub_request(:get, "#{base_url}/task/task-1").to_return(status: 200, body: { id: 'task-1' }.to_json)
        payload = assignee_payload(field: 'assignee_add', after: { id: 184, username: 'Sam' })
        payload[:history_items].unshift({ id: 'h0', type: 1, date: '1642740510345', field: 'name',
                                          before: 'Old name', after: 'New name', })

        expect(delivery(payload)[:event]).to eq('taskAssigneeUpdated')
      end
    end

    # webhook_id is the same on every delivery this trigger receives, so using it as the job context
    # identifier made a runbook set to one-run-per-context serialise unrelated Lists.
    context 'job context identifier' do
      let(:trigger_config) { { event: ['listCreated'] } }

      def identifier_for(payload)
        captured = nil
        allow(trigger.runbook).to receive(:store_job_context_identifier) { |value| captured = value }
        delivery(payload)
        captured
      end

      it 'names the list on a list event rather than the subscription' do
        first = identifier_for({ event: 'listCreated', list_id: '111', webhook_id: 'wh-old', history_items: [] })

        expect(first).to eq('111')
      end

      it 'gives two different lists two different identifiers' do
        first = identifier_for({ event: 'listCreated', list_id: '111', webhook_id: 'wh-old', history_items: [] })
        second = identifier_for({ event: 'listCreated', list_id: '222', webhook_id: 'wh-old', history_items: [] })

        expect(first).not_to eq(second)
      end

      it 'falls back to the webhook when the payload names no resource' do
        identifier = identifier_for({ event: 'listCreated', webhook_id: 'wh-old', history_items: [] })

        expect(identifier).to eq('wh-old')
      end
    end

    # A verified delivery whose body is malformed still has to say so rather than travel on.
    it 'fails on a signed delivery whose body is a JSON array' do
      expect { delivery({}, raw_body: [{ event: 'taskCreated' }].to_json) }
        .to raise_error(IPaaS::Job::FailJob, /expected a JSON object, got Array/)
    end

    it 'fails on a signed delivery whose body is not JSON at all' do
      expect { delivery({}, raw_body: 'not json') }
        .to raise_error(IPaaS::Job::FailJob, /Invalid ClickUp webhook body/)
    end

    it 'fails on a signed delivery that names no event' do
      expect { delivery({ task_id: 'task-1', webhook_id: 'wh-old' }) }
        .to raise_error(IPaaS::Job::FailJob, 'Webhook payload has no event')
    end

    it 'answers a signed delivery over the real inbound endpoint' do
      stub_request(:get, "#{base_url}/task/task-1").to_return(status: 200, body: { id: 'task-1' }.to_json)
      body = status_change_payload.to_json

      output = post_trigger(status_change_payload, headers: { 'X-Signature' => clickup_signature(body) })

      expect(output[:event]).to eq('taskStatusUpdated')
    end

    it 'answers a forged delivery with a discard rather than an error' do
      output = post_trigger(status_change_payload, headers: { 'X-Signature' => 'forged' })

      expect(output[:result]).to eq('Discarded')
    end
  end
end

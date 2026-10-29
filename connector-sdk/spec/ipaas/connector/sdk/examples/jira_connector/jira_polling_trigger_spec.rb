require 'spec_helper'
require_relative 'jira_context'

shared_context 'jira polling' do
  let(:search_url) { "#{api}/search/jql" }
  let(:now) { Time.utc(2026, 10, 26, 12, 0, 0) }
  let(:settled_ms) { (now.to_i - JiraConnector::POLL_SETTLE_SECONDS) * 1000 }
  let(:cursor_time) { Time.utc(2026, 10, 26, 11, 40, 0) }
  let(:cursor_ms) { cursor_time.to_i * 1000 }
  let(:solution) { double('solution', uuid: 'solution-1') }
  let(:description_document) do
    { type: 'doc', content: [{ type: 'paragraph', content: [{ type: 'text', text: 'Broken' }] }] }
  end

  around { |example| Timecop.freeze(now) { example.run } }

  before do
    allow(trigger).to receive(:solution).and_return(solution)
    allow(runbook).to receive(:trigger_output).and_return(nil)
    stub_trigger_projects
  end

  def check_delivered(payload = { schedule_reference: 'ref-1' })
    output = post_trigger(payload)
    trigger.respond_with(tick_request('/inbound/1/solution/runbook'), double('job', uuid: 'job-1'), {}, {})
    output
  end

  def check_dropped
    output = post_trigger({ schedule_reference: 'ref-1' })
    trigger.respond_with(tick_request('/inbound/1/solution/runbook'), nil, {},
                         { error: IPaaS::Job::DiscardTriggerEvent.new })
    output
  end

  def jira_time(time)
    time.utc.strftime('%FT%T.%L%z')
  end

  def jira_issue(number, created)
    fields = { summary: "Issue #{number}", description: description_document, project: { key: 'KAN' },
               created: jira_time(created), updated: jira_time(created), }
    { id: (10_000 + number).to_s, key: "KAN-#{number}", fields: fields }
  end

  def search_page(issues, last: true)
    { status: 200, body: { issues: issues, isLast: last }.to_json }
  end

  def full_page(page_number)
    first = (page_number * JiraConnector::MAX_PAGE_SIZE) + 1
    issues = (first...(first + JiraConnector::MAX_PAGE_SIZE)).map { |number| jira_issue(number, cursor_time + number) }
    search_page(issues, last: false)
  end

  def poll_cursor(at: cursor_ms, keys: [], cursor_scope: scope, cursor_field: time_field)
    { at: at, keys: keys, scope: cursor_scope, time_field: cursor_field }
  end

  def seed_cursor(**)
    trigger.store.write('poll_cursor', poll_cursor(**))
  end

  def stored_cursor
    trigger.store.read('poll_cursor').to_h.symbolize_keys
  end

  def stub_search(*responses)
    sent_jql = []
    stub_request(:post, search_url).to_return do |request|
      sent_jql.push(JSON.parse(request.body)['jql'])
      responses.size > 1 ? responses.shift : responses.first
    end
    sent_jql
  end

  def tick_request(path)
    Rack::Request.new(Rack::MockRequest.env_for(path, method: 'POST', input: '{"schedule_reference":"ref-1"}',
                                                      'CONTENT_TYPE' => 'application/json'))
  end
end

describe 'Jira New Issue Polling Trigger', :jira, :trigger do
  include_context 'jira polling'

  let(:trigger_template_id) { '01a13f2d-b655-7530-856c-b254c3d964f4' }
  let(:time_field) { 'created' }
  let(:scope) { 'project = "KAN"' }
  let(:trigger_config) { { project_key: 'KAN', poll_minutes: 10 } }

  it 'only runs from the iPaaS scheduler and calls Jira' do
    expect(trigger.trigger_template.internal_only).to be(true)
    expect(trigger.trigger_template.outbound_traffic).to be(true)
  end

  describe 'provision' do
    it 'creates a schedule that runs every chosen number of minutes' do
      allow(solution).to receive(:create_schedule!).and_return({ success: true, schedule_reference: 'ref-1' })

      trigger.provision

      expect(solution).to have_received(:create_schedule!)
        .with(runbook.uuid, hash_including(frequency: 'minutely', interval: 10, time_zone: 'UTC', reference: anything))
      expect(trigger.store.read('schedule').to_h.symbolize_keys).to eq(reference: 'ref-1')
    end

    it 'starts the cursor a settle period before now, so issues of the last five minutes still come' do
      allow(solution).to receive(:create_schedule!).and_return({ success: true, schedule_reference: 'ref-1' })

      trigger.provision

      expect(stored_cursor).to eq(poll_cursor(at: settled_ms))
    end

    it 'reads the project with short timeouts, so a slow Jira cannot outlast the promote' do
      reads = []
      allow(trigger).to receive(:http_get).and_wrap_original do |original, url, *rest, **options|
        reads.push([url, options])
        original.call(url, *rest, **options)
      end
      allow(solution).to receive(:create_schedule!).and_return({ success: true, schedule_reference: 'ref-1' })

      trigger.provision

      expect(reads.map(&:first)).to include("#{api}/project/KAN")
      expect(reads.map(&:last)).to all(include(open_timeout: JiraConnector::SHORT_OPEN_TIMEOUT,
                                               timeout: JiraConnector::SHORT_TIMEOUT))
    end

    it 'refuses the promote and makes no schedule when this account cannot open the project' do
      stub_missing_project('KAN')
      allow(solution).to receive(:create_schedule!)

      expect { trigger.provision }.to raise_error(
        IPaaS::Job::FailJob,
        'Project KAN was not found, or this account cannot see it (HTTP 404): ' \
        "No project could be found with key 'KAN'.",
      )
      expect(solution).not_to have_received(:create_schedule!)
      expect(trigger.store.read('poll_cursor')).to be_nil
    end

    context 'with an issue type the project does not have' do
      let(:trigger_config) { { project_key: 'KAN', issue_type: '10009', poll_minutes: 10 } }

      it 'refuses the promote and makes no schedule' do
        allow(solution).to receive(:create_schedule!)

        expect { trigger.provision }.to raise_error(
          IPaaS::Job::FailJob, 'Project KAN has no issue type with ID 10009. Pick the issue type from the list.'
        )
        expect(solution).not_to have_received(:create_schedule!)
      end
    end

    it 'keeps the schedule and the cursor when the runbook is promoted again with the same choices' do
      allow(solution).to receive(:create_schedule!).and_return({ success: true, schedule_reference: 'ref-1' })
      allow(solution).to receive(:update_schedule).and_return({ success: true })
      trigger.provision
      Timecop.freeze(now + 3600)

      trigger.provision

      expect(solution).to have_received(:create_schedule!).once
      expect(stored_cursor[:at]).to eq(settled_ms)
    end

    it 'saves when it started the cursor, and keeps that time when promoted again with the same choices' do
      allow(solution).to receive(:create_schedule!).and_return({ success: true, schedule_reference: 'ref-1' })
      allow(solution).to receive(:update_schedule).and_return({ success: true })
      trigger.provision
      Timecop.freeze(now + 3600)

      trigger.provision

      expect(trigger.store.read('poll_setup').to_h.symbolize_keys).to eq(at: now.to_f)
    end

    it 'changes the number of minutes on the stored schedule, so a paused schedule stays paused' do
      trigger.store.write('schedule', { reference: 'ref-1' })
      allow(solution).to receive(:update_schedule).and_return({ success: true })

      trigger.provision

      expect(solution).to have_received(:update_schedule)
        .with('ref-1', { frequency: 'minutely', interval: 10, time_zone: 'UTC' })
      expect(trigger.store.read('schedule').to_h.symbolize_keys).to eq(reference: 'ref-1')
    end

    it 'creates the schedule again when iPaaS no longer has the stored one' do
      trigger.store.write('schedule', { reference: 'ref-gone' })
      allow(solution).to receive(:update_schedule).and_return({ success: false, error: 'Schedule not found' })
      allow(solution).to receive(:create_schedule!).and_return({ success: true, schedule_reference: 'ref-new' })

      trigger.provision

      expect(solution).to have_received(:update_schedule).with('ref-gone', hash_including(interval: 10))
      expect(trigger.store.read('schedule').to_h.symbolize_keys).to eq(reference: 'ref-new')
    end

    it 'fails with the reason when iPaaS does not update the stored schedule' do
      trigger.store.write('schedule', { reference: 'ref-1' })
      allow(solution).to receive(:update_schedule).and_return({ success: false, error: 'Schedule update failed' })

      expect { trigger.provision }
        .to raise_error(IPaaS::Job::FailJob, /schedule of this Jira trigger was not updated: Schedule update failed/)
    end

    it 'starts the cursor again when the project changes' do
      trigger.store.write('schedule', { reference: 'ref-1' })
      allow(solution).to receive(:update_schedule).and_return({ success: true })
      seed_cursor(cursor_scope: 'project = "OPS"')

      trigger.provision

      expect(stored_cursor).to eq(poll_cursor(at: settled_ms))
    end

    it 'deletes the webhook a New/Updated Issue trigger of this runbook left behind' do
      seed_stored_webhook(id: '55', host: 'acme.atlassian.net')
      delete = stub_request(:delete, "#{webhook_api}/55").to_return(status: 204, body: '')
      allow(solution).to receive(:create_schedule!).and_return({ success: true, schedule_reference: 'ref-1' })

      trigger.provision

      expect(delete).to have_been_requested.once
      expect(trigger.store.read('webhook')).to be_nil
    end

    it 'starts the cursor at the promotion when it takes over from a real-time trigger, which delivered until now' do
      seed_stored_webhook(id: '55')
      stub_request(:delete, "#{webhook_api}/55").to_return(status: 204, body: '')
      allow(solution).to receive(:create_schedule!).and_return({ success: true, schedule_reference: 'ref-1' })

      trigger.provision

      expect(stored_cursor).to eq(poll_cursor(at: now.to_i * 1000))
    end

    context 'with an issue type name instead of an ID' do
      let(:trigger_config) { { project_key: 'KAN', issue_type: 'Task', poll_minutes: 10 } }

      it 'refuses it before it creates a schedule that could only fail' do
        allow(solution).to receive(:create_schedule!).and_return({ success: true, schedule_reference: 'ref-1' })

        expect { trigger.provision }.to raise_error(IPaaS::Job::FailJob, /is not a Jira issue type ID/)
        expect(solution).not_to have_received(:create_schedule!)
      end
    end

    it 'fails with the reason when iPaaS does not create the schedule' do
      allow(solution).to receive(:create_schedule!)
        .and_return({ success: false, error: 'Trigger template x is not supported for scheduling.' })

      expect { trigger.provision }
        .to raise_error(IPaaS::Job::FailJob, /schedule of this Jira trigger was not created: Trigger template x/)
    end
  end

  describe 'deprovision' do
    it 'deletes the schedule and keeps the cursor for a later provision' do
      trigger.store.write('schedule', { reference: 'ref-1', minutes: 10 })
      seed_cursor
      allow(solution).to receive(:soft_delete_schedule)

      trigger.deprovision

      expect(solution).to have_received(:soft_delete_schedule).with('ref-1')
      expect(trigger.store.read('schedule')).to be_nil
      expect(stored_cursor[:at]).to eq(cursor_ms)
    end
  end

  describe 'a scheduler check' do
    before { seed_cursor }

    it 'delivers every new issue of one check in one run and moves the cursor to the last one' do
      stub_request(:post, search_url)
        .to_return(search_page([jira_issue(1, cursor_time + 1.2), jira_issue(2, cursor_time + 3.5)]))

      output = check_delivered

      expect(output[:issues].pluck(:issue_key)).to eq(%w[KAN-1 KAN-2])
      expect(output[:issues].first).to include(description: 'Broken', project: 'KAN')
      expect(output[:issues].first[:fields]).not_to have_key(:description)
      expect(stored_cursor).to eq(poll_cursor(at: cursor_ms + 3000, keys: ['KAN-2']))
    end

    it 'keeps the cursor until iPaaS has saved the job of the check' do
      stub_request(:post, search_url).to_return(search_page([jira_issue(1, cursor_time + 1)]))

      post_trigger({ schedule_reference: 'ref-1' })

      expect(stored_cursor).to eq(poll_cursor)
    end

    it 'delivers the same issues again when the concurrency limit of the runbook dropped the check' do
      sent_jql = stub_search(search_page([jira_issue(1, cursor_time + 1)]))

      check_dropped
      output = check_delivered

      expect(sent_jql.uniq.size).to eq(1)
      expect(output[:issues].pluck(:issue_key)).to eq(['KAN-1'])
      expect(stored_cursor).to eq(poll_cursor(at: cursor_ms + 1000, keys: ['KAN-1']))
    end

    it 'does not count checks the concurrency limit dropped towards giving up on their issues' do
      stub_search(search_page([jira_issue(1, cursor_time + 1)]))

      4.times { check_dropped }

      expect(stored_cursor).to eq(poll_cursor)
    end

    it 'goes on after issues that three checks in a row found but never delivered, naming them in the log' do
      stuck = search_page([jira_issue(1, cursor_time + 1)])
      sent_jql = stub_search(stuck, stuck, stuck, search_page([jira_issue(2, cursor_time + 4)]))
      allow(trigger).to receive(:log)

      3.times { post_trigger({ schedule_reference: 'ref-1' }) }
      output = check_delivered

      expect(sent_jql.last).to include("created >= #{cursor_ms + 1000}").and include('key in ("KAN-1")')
      expect(trigger).to have_received(:log).with(/Jira issues KAN-1 were found by 3 checks in a row and never/)
      expect(output[:issues].pluck(:issue_key)).to eq(['KAN-2'])
      expect(stored_cursor).to eq(poll_cursor(at: cursor_ms + 4000, keys: ['KAN-2']))
    end

    it 'moves no cursor when a designer run made a job' do
      stub_request(:post, search_url).to_return(search_page([jira_issue(1, cursor_time + 1)]))
      post_trigger({ schedule_reference: 'ref-1' })

      trigger.respond_with(tick_request('/solutions/solution/runbooks/runbook/run'), double('job', uuid: 'job-1'),
                           {}, {})

      expect(stored_cursor).to eq(poll_cursor)
    end

    it 'asks Jira for the settled window in created order with the issue fields' do
      search = stub_request(:post, search_url)
               .with(body: {
                 jql: "#{scope} AND created >= #{cursor_ms} AND created <= #{settled_ms} ORDER BY created ASC, key ASC",
                 maxResults: JiraConnector::MAX_PAGE_SIZE,
                 fields: JiraConnector::DEFAULT_ISSUE_FIELDS - [JiraConnector::COMMENT_FIELD],
               })
               .to_return(search_page([jira_issue(1, cursor_time + 1)]))

      post_trigger({ schedule_reference: 'ref-1' })

      expect(search).to have_been_requested.once
    end

    it 'names the check by its start and first issue, for the deduplication ID and the job context' do
      stub_request(:post, search_url).to_return(search_page([jira_issue(4, cursor_time), jira_issue(5, cursor_time)]))

      output = post_trigger({ schedule_reference: 'ref-1' })

      expect(output[:deduplication_id]).to eq("created-#{cursor_ms}-KAN-4-2")
      expect(runbook).to have_received(:store_job_context_identifier).with("created-#{cursor_ms}-KAN-4-2")
    end

    it 'leaves out the issues it already delivered in the second the cursor points at' do
      seed_cursor(keys: %w[KAN-1 KAN-2])
      sent_jql = stub_search(search_page([jira_issue(3, cursor_time)]))

      check_delivered

      expect(sent_jql.first).to include(
        "NOT (created < #{cursor_ms + 1000} AND key in (\"KAN-1\", \"KAN-2\"))"
      )
      expect(stored_cursor[:keys]).to eq(%w[KAN-1 KAN-2 KAN-3])
    end

    it 'does not deliver an issue twice across two checks' do
      sent_jql = stub_search(search_page([jira_issue(1, cursor_time + 2.1), jira_issue(2, cursor_time + 2.8)]),
                             search_page([jira_issue(3, cursor_time + 2.9)]))

      check_delivered
      check_delivered

      expect(sent_jql.last).to start_with("#{scope} AND created >= #{cursor_ms + 2000} AND")
      expect(sent_jql.last).to include('key in ("KAN-1", "KAN-2")')
      expect(stored_cursor[:keys]).to eq(%w[KAN-1 KAN-2 KAN-3])
    end

    it 'starts no run and keeps the cursor when nothing is new' do
      stub_request(:post, search_url).to_return(search_page([]))

      expect(post_trigger({ schedule_reference: 'ref-1' })).to eq(result: 'Discarded')
      expect(stored_cursor).to eq(poll_cursor)
    end

    it 'reads at most five pages in one check and leaves the rest to the next check' do
      pages = (0..JiraConnector::POLL_MAX_PAGES).map { |page_number| full_page(page_number) }
      sent_jql = stub_search(*pages)
      last_number = JiraConnector::POLL_MAX_PAGES * JiraConnector::MAX_PAGE_SIZE

      output = check_delivered

      expect(output[:issues].size).to eq(last_number)
      expect(sent_jql.size).to eq(JiraConnector::POLL_MAX_PAGES)
      expect(sent_jql[1]).to include("created >= #{cursor_ms + (JiraConnector::MAX_PAGE_SIZE * 1000)} AND")
      expect(stored_cursor).to eq(poll_cursor(at: cursor_ms + (last_number * 1000), keys: ["KAN-#{last_number}"]))
    end

    it 'goes on inside a second that holds more than one page of issues' do
      crowded = (1..JiraConnector::MAX_PAGE_SIZE).map { |number| jira_issue(number, cursor_time + 7) }
      first_keys = crowded.pluck(:key)
      sent_jql = stub_search(search_page(crowded, last: false),
                             search_page([jira_issue(JiraConnector::MAX_PAGE_SIZE + 1, cursor_time + 7)]))

      check_delivered

      expect(sent_jql.last).to include("key in (#{first_keys.map { |key| "\"#{key}\"" }.join(', ')})")
      expect(stored_cursor[:keys]).to eq(first_keys + ["KAN-#{JiraConnector::MAX_PAGE_SIZE + 1}"])
    end

    it 'stops reading pages once the time for one check is spent' do
      stub_request(:post, search_url).to_return do
        Timecop.freeze(Time.now + JiraConnector::POLL_TIME_BUDGET_SECONDS)
        full_page(0)
      end

      output = post_trigger({ schedule_reference: 'ref-1' })

      expect(output[:issues].size).to eq(JiraConnector::MAX_PAGE_SIZE)
      expect(a_request(:post, search_url)).to have_been_made.once
    end

    it 'delivers what it read when Jira limits the rate after the first page' do
      stub_request(:post, search_url)
        .to_return(full_page(0))
        .then.to_return(status: 429, headers: { 'Retry-After' => '30' }, body: '')

      output = check_delivered

      expect(output[:issues].size).to eq(JiraConnector::MAX_PAGE_SIZE)
      expect(stored_cursor[:keys]).to eq(["KAN-#{JiraConnector::MAX_PAGE_SIZE}"])
    end

    it 'delivers what it read when the connection breaks on a later page' do
      stub_request(:post, search_url).to_return(full_page(0)).then.to_timeout

      output = check_delivered

      expect(output[:issues].size).to eq(JiraConnector::MAX_PAGE_SIZE)
      expect(stored_cursor[:keys]).to eq(["KAN-#{JiraConnector::MAX_PAGE_SIZE}"])
    end

    it 'tries again later and keeps the cursor when the connection breaks on the first page' do
      stub_request(:post, search_url).to_timeout

      expect_reschedule_after(60, /Jira did not answer/) do
        trigger.parse_request(tick_request('/inbound/1/solution/runbook'))
      end
      expect(stored_cursor).to eq(poll_cursor)
    end

    it 'tries again later and keeps the cursor when Jira limits the rate on the first page' do
      stub_request(:post, search_url).to_return(status: 429, headers: { 'Retry-After' => '30' }, body: '')

      expect_reschedule_after(30) { trigger.parse_request(tick_request('/inbound/1/solution/runbook')) }
      expect(stored_cursor).to eq(poll_cursor)
    end

    it 'tries again later and keeps the cursor when Jira limits the rate on the first page without saying how long' do
      stub_request(:post, search_url).to_return(status: 429, body: '')

      expect_reschedule_after(60) { trigger.parse_request(tick_request('/inbound/1/solution/runbook')) }
      expect(stored_cursor).to eq(poll_cursor)
    end

    it 'waits for a check that still holds the lock, without searching' do
      search = stub_request(:post, search_url).to_return(search_page([jira_issue(1, cursor_time)]))
      trigger.locker.try_acquire('poll', ttl_seconds: 60)
      contention = IPaaS::Job::Lock::RETRY_AFTER_CONTENTION
      jitter = IPaaS::Job::Lock::RETRY_AFTER_CONTENTION_JITTER

      Timecop.freeze do
        expect { trigger.parse_request(tick_request('/inbound/1/solution/runbook')) }
          .to raise_error(IPaaS::Job::RescheduleJob, /Lock held by another worker/) do |error|
            expect(error.reschedule_after).to be_between(contention.from_now, (contention + jitter).from_now)
          end
      end
      expect(search).not_to have_been_requested
    end

    it 'never moves the cursor back behind a check that saved a later one' do
      later = poll_cursor(at: cursor_ms + 60_000, keys: ['KAN-9'])
      stub_request(:post, search_url).to_return do
        trigger.store.write('poll_cursor', later)
        search_page([jira_issue(1, cursor_time + 1)])
      end

      post_trigger({ schedule_reference: 'ref-1' })

      expect(stored_cursor).to eq(later)
    end

    it 'keeps the cursor that a promote to another project saved while the check ran' do
      promoted = poll_cursor(at: settled_ms, cursor_scope: 'project = "OPS"')
      stub_request(:post, search_url).to_return do
        trigger.store.write('poll_cursor', promoted)
        search_page([jira_issue(1, cursor_time + 1)])
      end

      post_trigger({ schedule_reference: 'ref-1' })

      expect(stored_cursor).to eq(promoted)
    end

    it 'keeps the cursor that a promote to another project saved in the same second while the check ran' do
      promoted = poll_cursor(at: settled_ms, cursor_scope: 'project = "OPS"')
      stub_request(:post, search_url).to_return do
        trigger.store.write('poll_cursor', promoted)
        search_page([jira_issue(1, now - JiraConnector::POLL_SETTLE_SECONDS)])
      end

      post_trigger({ schedule_reference: 'ref-1' })

      expect(stored_cursor).to eq(promoted)
    end

    it 'keeps the cursor of another project that a promote saved moments ago, and searches nothing' do
      promoted = IPaaS::Connector::Trigger.parse(runbook, runbook_trigger({ project_key: 'OPS', poll_minutes: 10 }))
      allow(promoted).to receive_messages(solution: solution, store: trigger.store)
      allow(solution).to receive(:create_schedule!).and_return({ success: true, schedule_reference: 'ref-1' })
      promoted.provision
      search = stub_request(:post, search_url).to_return(search_page([]))
      Timecop.freeze(now + JiraConnector::POLL_SETUP_GRACE_SECONDS - 1)

      expect(post_trigger({ schedule_reference: 'ref-1' })).to eq(result: 'Discarded')
      expect(stored_cursor).to eq(poll_cursor(at: settled_ms, cursor_scope: 'project = "OPS"'))
      expect(search).not_to have_been_requested
    end

    it 'starts its own cursor over another project whose cursor was started longer ago than the grace period' do
      seed_cursor(cursor_scope: 'project = "OPS"')
      trigger.store.write('poll_setup', { at: (now - JiraConnector::POLL_SETUP_GRACE_SECONDS).to_f })

      expect(post_trigger({ schedule_reference: 'ref-1' })).to eq(result: 'Discarded')
      expect(stored_cursor).to eq(poll_cursor(at: settled_ms))
    end

    it 'saves a fresh cursor and searches nothing when the stored cursor belongs to the Updated Issue trigger' do
      seed_cursor(cursor_field: 'updated')
      search = stub_request(:post, search_url).to_return(search_page([]))

      expect(post_trigger({ schedule_reference: 'ref-1' })).to eq(result: 'Discarded')
      expect(stored_cursor).to eq(poll_cursor(at: settled_ms))
      expect(search).not_to have_been_requested
    end

    it 'fails the check with the reason Jira gives' do
      reason = "The value 'KAN' does not exist for the field 'project'."
      stub_request(:post, search_url).to_return(status: 400, body: { errorMessages: [reason] }.to_json)

      output = post_trigger({ schedule_reference: 'ref-1' })

      expect(output[:error]).to include(reason)
      expect(stored_cursor).to eq(poll_cursor)
    end
  end

  describe 'a scheduler check with no stored cursor' do
    it 'saves the cursor a promote did not save, so the next check searches from there, but a preview saves none' do
      sent_jql = stub_search(search_page([]))

      expect { trigger.parse_request(tick_request('/debug-inbound/1/solution/runbook/main')) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent)
      expect(trigger.store.read('poll_cursor')).to be_nil
      post_trigger({ schedule_reference: 'ref-1' })
      Timecop.freeze(now + 300)
      post_trigger({ schedule_reference: 'ref-1' })

      expect(sent_jql).to eq(
        ["#{scope} AND created >= #{settled_ms} AND created <= #{settled_ms} ORDER BY created ASC, key ASC",
         "#{scope} AND created >= #{settled_ms} AND created <= #{settled_ms + 300_000} ORDER BY created ASC, key ASC",]
      )
    end
  end

  describe 'a designer run' do
    it 'shows what the next check finds without moving the cursor or taking the lock' do
      seed_cursor
      stub_request(:post, search_url).to_return(search_page([jira_issue(1, cursor_time + 1)]))
      trigger.locker.try_acquire('poll', ttl_seconds: 60)

      output = trigger.parse_request(tick_request('/debug-inbound/1/solution/runbook/main'))

      expect(JSON.parse(output.to_json).dig('issues', 0, 'issue_key')).to eq('KAN-1')
      expect(stored_cursor).to eq(poll_cursor)
    end

    it 'gives the job a context identifier that no scheduler check uses' do
      seed_cursor
      stub_request(:post, search_url).to_return(search_page([jira_issue(1, cursor_time + 1)]))

      trigger.parse_request(tick_request('/debug-inbound/1/solution/runbook/main'))
      trigger.parse_request(tick_request('/inbound/1/solution/runbook'))

      expect(runbook).to have_received(:store_job_context_identifier).with("preview-created-#{cursor_ms}-KAN-1-1")
      expect(runbook).to have_received(:store_job_context_identifier).with("created-#{cursor_ms}-KAN-1-1")
    end
  end
end

describe 'Jira Updated Issue Polling Trigger', :jira, :trigger do
  include_context 'jira polling'

  let(:trigger_template_id) { '01a13f2d-b655-7516-8277-0b0b29316e63' }
  let(:time_field) { 'updated' }
  let(:trigger_config) { { project_key: 'KAN', issue_type: '10001', poll_minutes: 1 } }
  let(:scope) { 'project = "KAN" AND issuetype = 10001' }
  let(:updated_issue) do
    updated = Time.at(1_792_000_004, in: 'UTC').strftime('%FT%T.%L%z')
    { id: '1', key: 'KAN-1', fields: { created: '2020-01-01T00:00:00.000+0000', updated: updated } }
  end

  it 'only runs from the iPaaS scheduler' do
    expect(trigger.trigger_template.internal_only).to be(true)
  end

  it 'starts the cursor again at promotion when the runbook switches from the New Issue trigger' do
    seed_cursor(at: settled_ms - 600_000, keys: ['KAN-5'], cursor_field: 'created')
    allow(solution).to receive(:create_schedule!).and_return({ success: true, schedule_reference: 'ref-1' })

    trigger.provision

    expect(stored_cursor).to eq(at: settled_ms, keys: [], scope: scope, time_field: 'updated')
  end

  it 'leaves an issue whose update time is past the settle bound to the next check, which delivers it once' do
    seed_cursor(at: cursor_ms)
    stub_search(search_page([jira_issue(1, cursor_time + 1), jira_issue(2, now)]), search_page([jira_issue(2, now)]))

    first = check_delivered
    Timecop.freeze(now + JiraConnector::POLL_SETTLE_SECONDS + 1)
    second = check_delivered

    expect([first, second].map { |output| output[:issues].pluck(:issue_key) }).to eq([['KAN-1'], ['KAN-2']])
  end

  it 'goes on after a full page whose last issue reports a later update time, so no issue after it is skipped' do
    seed_cursor(at: cursor_ms)
    crowded = (1...JiraConnector::MAX_PAGE_SIZE).map { |number| jira_issue(number, cursor_time + number) }
    late = jira_issue(JiraConnector::MAX_PAGE_SIZE, now)
    sent_jql = stub_search(search_page(crowded + [late], last: false),
                           search_page([jira_issue(JiraConnector::MAX_PAGE_SIZE + 1, cursor_time + 500)]))

    output = post_trigger({ schedule_reference: 'ref-1' })

    last_kept_ms = cursor_ms + ((JiraConnector::MAX_PAGE_SIZE - 1) * 1000)
    expect(sent_jql.last).to include("updated >= #{last_kept_ms} AND")
    expect(output[:issues].pluck(:issue_key)).to include("KAN-#{JiraConnector::MAX_PAGE_SIZE + 1}")
  end

  it 'searches the issue type on the update time and moves the cursor by it' do
    seed_cursor(at: 1_792_000_000_000)
    search = stub_request(:post, search_url)
             .with { |request| JSON.parse(request.body)['jql'].start_with?("#{scope} AND updated >= 1792000000000") }
             .to_return(status: 200, body: { issues: [updated_issue], isLast: true }.to_json)

    output = check_delivered

    expect(search).to have_been_requested.once
    expect(output[:deduplication_id]).to eq('updated-1792000000000-KAN-1-1')
    expect(trigger.store.read('poll_cursor')['at']).to eq(1_792_000_004_000)
  end
end

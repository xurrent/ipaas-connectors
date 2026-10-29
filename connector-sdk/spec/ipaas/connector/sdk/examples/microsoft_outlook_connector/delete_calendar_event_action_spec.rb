require 'spec_helper'

describe 'Microsoft Outlook Delete Calendar Event Action', :action, :microsoft_outlook do
  let(:action_template_id) { '8ea14b2b-eaff-4350-9011-a0d5ad5b90f4' }
  let(:event_id) { 'AAMkAGQzOGVlNTJkLWMzMzYtNDgzNi04ZWQyLWZhMDc5YmJmNzY4NQBGAAAAAACPEjqyAAA=' }
  let(:event_url) { "https://graph.microsoft.com/v1.0/users/#{mailbox}/events/#{event_id}" }

  def input(overrides = {})
    { event_id: event_id, mailbox: nil }.merge(overrides)
  end

  def stub_delete(status: 204, body: '', url: event_url, headers: {})
    stub_request(:delete, url).to_return(status: status, body: body, headers: headers)
  end

  def stub_error(status, code, message, headers: {})
    stub_delete(status: status, body: { error: { code: code, message: message } }.to_json,
                headers: headers.merge('Content-Type' => 'application/json'))
  end

  describe 'when Microsoft deletes the event' do
    # Measured on 2026-10-14: the delete answers 204 with no body.
    it 'reports the event as deleted by this step' do
      stub_delete
      expect(run_action(input)).to eq({ 'deleted' => true, 'event_id' => event_id, 'mailbox' => mailbox })
    end

    it 'deletes from the mailbox the step names, and reports that mailbox' do
      shared_url = "https://graph.microsoft.com/v1.0/users/support@contoso.com/events/#{event_id}"
      stub_delete(url: shared_url)
      expect(run_action(input(mailbox: 'support@contoso.com'))).to include('mailbox' => 'support@contoso.com')
      expect(a_request(:delete, shared_url)).to have_been_made
    end

    it 'deletes and reports the event id without the spaces around it' do
      stub_delete
      expect(run_action(input(event_id: "  #{event_id} "))).to include('event_id' => event_id)
      expect(a_request(:delete, event_url)).to have_been_made
    end

    it 'deletes an event whose id is exactly the longest length' do
      longest = 'A' * MicrosoftOutlookConnector::MAX_GRAPH_ID_LENGTH
      stub_delete(url: "https://graph.microsoft.com/v1.0/users/#{mailbox}/events/#{longest}")
      expect(run_action(input(event_id: longest))).to include('deleted' => true)
    end

    it 'fails the job when Graph answers a success status that is not the deleted one' do
      stub_delete(status: 200, body: '{}')
      expect { run_action(input) }.to raise_error(IPaaS::Job::FailJob, /HTTP 200/)
    end
  end

  describe 'when Microsoft has no such event' do
    # Measured on 2026-10-14: a second delete of the same event answers 404 ErrorItemNotFound.
    it 'passes and reports the event as not deleted by this step' do
      stub_error(404, 'ErrorItemNotFound', 'The specified object was not found in the store.')
      expect(run_action(input)).to eq({ 'deleted' => false, 'event_id' => event_id, 'mailbox' => mailbox })
    end

    # Measured on 2026-10-14: an unknown mailbox is a 404 as well, and that one must not pass as deleted.
    it 'fails the job when the 404 is about the mailbox' do
      stub_error(404, 'ErrorInvalidUser', "The requested user '#{mailbox}' is invalid.")
      expect { run_action(input) }
        .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph returned HTTP 404 ErrorInvalidUser: The requested ' \
                                             "user '#{mailbox}' is invalid.")
    end

    it 'fails the job when a 404 carries no Microsoft error' do
      stub_delete(status: 404, body: 'Not Found')
      expect { run_action(input) }.to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph returned HTTP 404 : Not Found')
    end
  end

  describe 'when Microsoft refuses the delete' do
    it 'names the mailbox and the permission to check when Microsoft refuses the mailbox' do
      stub_error(403, 'ErrorAccessDenied', 'Access is denied. Check credentials and try again.')
      expect { run_action(input) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 403 ErrorAccessDenied: Access is denied. Check credentials ' \
                        "and try again. Microsoft refused mailbox '#{mailbox}'. Check that the app holds the " \
                        'Calendars.ReadWrite application permission for this mailbox.')
    end

    # A delete that ran before the pause leaves nothing for the rerun to delete twice, so a server error is
    # safe to pause on, unlike a create without a Transaction ID.
    it 'pauses the step on a server error' do
      stub_error(502, 'BadGateway', 'Bad gateway.', headers: { 'Retry-After' => '6' })
      expect_reschedule_after(6) { run_action(input) }
    end
  end

  describe 'what it refuses before it calls Microsoft' do
    before { stub_request(:delete, /events/) }

    # Measured on 2026-10-14: an id that is not one answers 400 ErrorInvalidIdMalformed. The id Outlook on the
    # web shows in its address uses + and / where Graph uses - and _.
    it 'refuses an id copied from a browser address bar' do
      expect { run_action(input(event_id: 'AAMkAGQz+CfyiTy/SaMn%3D')) }
        .to raise_error(IPaaS::Job::FailJob, "Event ID 'AAMkAGQz+CfyiTy/SaMn%3D' is not a Microsoft Graph event id. " \
                                             'Map the Event ID an earlier step returned, not one copied from a ' \
                                             'browser address bar.')
      expect(a_request(:delete, /events/)).not_to have_been_made
    end

    # Measured on 2026-10-14: a live event id is 152 characters.
    it 'refuses an id longer than any Microsoft Graph id' do
      long_id = 'A' * (MicrosoftOutlookConnector::MAX_GRAPH_ID_LENGTH + 1)
      expect { run_action(input(event_id: long_id)) }
        .to raise_error(IPaaS::Job::FailJob, /\AEvent ID '#{long_id}' is not a Microsoft Graph event id/)
      expect(a_request(:delete, /events/)).not_to have_been_made
    end

    context 'when the connection carries no default mailbox' do
      let(:default_mailbox) { nil }

      it 'refuses to delete when no mailbox is set on the step or on the connection' do
        expect { run_action(input) }
          .to raise_error(IPaaS::Job::FailJob, 'No mailbox. Set Mailbox on this step, or Default mailbox on the ' \
                                               'connection.')
        expect(a_request(:delete, /events/)).not_to have_been_made
      end
    end
  end
end

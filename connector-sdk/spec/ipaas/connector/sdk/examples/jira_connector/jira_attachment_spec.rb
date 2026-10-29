require 'spec_helper'
require_relative 'jira_context'

describe 'Jira attachment actions', :action, :jira do
  let(:jira_attachment) do
    { id: 77, filename: 'report.csv', size: 5, mimeType: 'text/csv',
      content: "#{api}/attachment/content/77", created: '2026-10-15T00:00:00.000+0000',
      author: { accountId: 'acc-1', displayName: 'Bot' }, }
  end

  describe 'Upload Attachment' do
    let(:action_template_id) { '01a13f2d-b655-72af-bb3b-2f4cbb96b4fb' }
    let(:upload_input) do
      { issue_id_or_key: 'KAN-1', filename: 'report.csv', content_bytes: Base64.strict_encode64('a,b,c') }
    end
    let(:attachment_settings) { { enabled: true, uploadLimit: 1_000_000 } }

    before do
      stub_request(:get, "#{api}/attachment/meta").to_return(status: 200, body: attachment_settings.to_json)
    end

    it 'sends the X-Atlassian-Token header, without which Jira CSRF guard rejects the upload' do
      stub = stub_request(:post, "#{api}/issue/KAN-1/attachments")
             .with(headers: { 'X-Atlassian-Token' => 'no-check' })
             .to_return(status: 200, body: [jira_attachment].to_json)
      run_action(upload_input)
      expect(stub).to have_been_requested.once
    end

    it 'uploads the decoded bytes, not the base64 text of them' do
      stub = stub_request(:post, "#{api}/issue/KAN-1/attachments")
             .with { |req| req.body.include?('a,b,c') && !req.body.include?('YSxiLGM=') }
             .to_return(status: 200, body: [jira_attachment].to_json)
      run_action(upload_input)
      expect(stub).to have_been_requested.once
    end

    it 'returns each attachment Jira sends back with its ID, content type and author' do
      stub_request(:post, "#{api}/issue/KAN-1/attachments")
        .to_return(status: 200, body: [jira_attachment].to_json)
      attachment = run_action(upload_input)[:attachments].first
      expect(attachment).to include(attachment_id: '77', filename: 'report.csv', size: 5, content_type: 'text/csv')
      expect(attachment[:author]).to include(account_id: 'acc-1', display_name: 'Bot')
    end

    it 'fails rather than uploading twice when Jira answers 503' do
      stub_request(:post, "#{api}/issue/KAN-1/attachments").to_return(status: 503, body: '')
      expect { run_action(upload_input) }.to raise_error(IPaaS::Job::FailJob, /HTTP 503/)
    end

    it 'sends a double quote and a line break in the file name as an underscore, as Jira stores such a name' do
      stub = stub_request(:post, "#{api}/issue/KAN-1/attachments")
             .with { |req| req.body.include?('filename="my_re__port_.csv"') }
             .to_return(status: 200, body: [jira_attachment].to_json)
      run_action(upload_input.merge(filename: "my\"re\r\nport\".csv"))
      expect(stub).to have_been_requested.once
    end

    it 'uploads an empty file, as Download Attachment returns one for an empty attachment' do
      stub = stub_request(:post, "#{api}/issue/KAN-1/attachments")
             .with { |req| req.body.include?('filename="empty.txt"') }
             .to_return(status: 200, body: [jira_attachment.merge(filename: 'empty.txt', size: 0)].to_json)
      output = run_action(upload_input.merge(filename: 'empty.txt', content_bytes: ''))
      expect(stub).to have_been_requested.once
      expect(output[:attachments].first).to include(filename: 'empty.txt', size: 0)
    end

    it 'fails before sending anything when Content is not given' do
      expect { run_action(upload_input.except(:content_bytes)) }
        .to raise_error(IPaaS::Job::FailJob, 'Upload Attachment needs Content, the file as base64 text.')
      expect(a_request(:post, %r{/attachments})).not_to have_been_made
    end

    it 'sends the content type it detects from the file name' do
      stub = stub_request(:post, "#{api}/issue/KAN-1/attachments")
             .with { |req| req.body.include?('Content-Type: text/csv') }
             .to_return(status: 200, body: [jira_attachment].to_json)
      run_action(upload_input)
      expect(stub).to have_been_requested.once
    end

    it 'sends the content type given instead of the one the file name suggests' do
      stub = stub_request(:post, "#{api}/issue/KAN-1/attachments")
             .with { |req| req.body.include?('Content-Type: application/vnd.ms-excel') }
             .to_return(status: 200, body: [jira_attachment].to_json)
      run_action(upload_input.merge(content_type: 'application/vnd.ms-excel'))
      expect(stub).to have_been_requested.once
    end

    it 'says the file may have been attached when Jira does not answer the upload' do
      stub_request(:post, "#{api}/issue/KAN-1/attachments").to_timeout
      expect { run_action(upload_input) }
        .to raise_error(IPaaS::Job::FailJob, /\AJira did not answer \(.*\)\. The change may have been made/)
    end

    it 'takes every output of Download Attachment that it needs under the same field ID' do
      download = IPaaS::Connector::ActionTemplate.by_uuid('01a13f2d-b655-747c-81ac-7bfb9c128a0a')
      upload_fields = action_template.input_schema.fields.map(&:id) - [:issue_id_or_key]
      expect(download.output_schemas.first.fields.map(&:id)).to include(*upload_fields)
    end

    context 'when the file is larger than the site allows' do
      let(:attachment_settings) { { enabled: true, uploadLimit: 4 } }

      it 'refuses a file over the site limit before sending it' do
        expect { run_action(upload_input) }.to raise_error(
          IPaaS::Job::FailJob,
          'The file is 5 bytes, over the 4-byte attachment size limit of this Jira site. Nothing was uploaded.'
        )
        expect(a_request(:post, %r{/attachments})).not_to have_been_made
      end
    end

    context 'when the site reports no size limit' do
      let(:attachment_settings) { { enabled: true, uploadLimit: 0 } }

      it 'sends the file when the site reports no size limit' do
        stub = stub_request(:post, "#{api}/issue/KAN-1/attachments").to_return(status: 200, body: '[]')
        run_action(upload_input)
        expect(stub).to have_been_requested.once
      end
    end

    context 'when the site has attachments turned off' do
      let(:attachment_settings) { { enabled: false, uploadLimit: 1_000_000 } }

      it 'refuses the file before sending it when attachments are off' do
        expect { run_action(upload_input) }
          .to raise_error(IPaaS::Job::FailJob, 'Attachments are turned off on this Jira site. Nothing was uploaded.')
        expect(a_request(:post, %r{/attachments})).not_to have_been_made
      end
    end

    it 'names both limits when Jira refuses the file as too large' do
      stub_request(:post, "#{api}/issue/KAN-1/attachments")
        .to_return(status: 413, body: { errorMessages: ['Too big'] }.to_json)
      expect { run_action(upload_input) }.to raise_error(
        IPaaS::Job::FailJob,
        'Jira refused the file as too large (HTTP 413): Too big. The file is over the attachment size limit of ' \
        'the site, or the issue has reached its limit of attachments.'
      )
    end
  end

  describe 'Download Attachment' do
    let(:action_template_id) { '01a13f2d-b655-747c-81ac-7bfb9c128a0a' }
    let(:attachment_metadata) { jira_attachment }

    before do
      stub_request(:get, "#{api}/attachment/77").to_return(status: 200, body: attachment_metadata.to_json)
    end

    it 'returns the file name, the base64 content, the content type and the size' do
      stub = stub_request(:get, "#{api}/attachment/content/77")
             .with(query: { 'redirect' => 'false' })
             .to_return(status: 200, body: 'a,b,c')
      output = run_action({ attachment_id: '77' })
      expect(stub).to have_been_requested.once
      expect(output).to include(filename: 'report.csv', content_bytes: Base64.strict_encode64('a,b,c'),
                                content_type: 'text/csv', size: 5)
    end

    context 'when the metadata names another host for the content' do
      let(:attachment_metadata) { jira_attachment.merge(content: 'https://evil.example/collect/77') }

      it 'reads the content through the Jira API it built, so the credential never reaches that host' do
        stub = stub_request(:get, "#{api}/attachment/content/77").with(query: { 'redirect' => 'false' })
                                                                 .to_return(status: 200, body: 'a,b,c')
        run_action({ attachment_id: '77' })
        expect(stub).to have_been_requested.once
        expect(a_request(:any, /evil\.example/)).not_to have_been_made
      end
    end

    context 'when the file is empty' do
      let(:attachment_metadata) { jira_attachment.merge(filename: 'empty.txt', size: 0) }

      it 'returns an empty file with empty content' do
        stub_request(:get, "#{api}/attachment/content/77")
          .with(query: hash_including({}))
          .to_return(status: 200, body: '')
        expect(run_action({ attachment_id: '77' })).to include(filename: 'empty.txt', content_bytes: '', size: 0)
      end
    end

    it 'fails with Jira own words rather than returning empty content' do
      stub_request(:get, "#{api}/attachment/content/77")
        .with(query: hash_including({}))
        .to_return(status: 404, body: { errorMessages: ['Attachment not found'], errors: {} }.to_json)
      expect { run_action({ attachment_id: '77' }) }
        .to raise_error(IPaaS::Job::FailJob, /Attachment not found/)
    end

    it 'names the attachment that was not found' do
      stub_request(:get, "#{api}/attachment/content/77")
        .with(query: hash_including({}))
        .to_return(status: 404, body: { errorMessages: ['Gone'] }.to_json)
      expect { run_action({ attachment_id: '77' }) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Attachment 77 was not found, or this account cannot see it (HTTP 404): Gone')
    end

    it 'tries again later when Jira answers 504' do
      stub_request(:get, "#{api}/attachment/content/77")
        .with(query: hash_including({}))
        .to_return(status: 504, body: '')
      expect_reschedule_after(60) { run_action({ attachment_id: '77' }) }
    end

    it 'tries again later when the connection breaks during the download' do
      stub_request(:get, "#{api}/attachment/content/77").with(query: hash_including({})).to_timeout
      expect_reschedule_after(60, /Jira did not answer/) { run_action({ attachment_id: '77' }) }
    end

    context 'when the file is over the download limit' do
      let(:attachment_metadata) { jira_attachment.merge(size: JiraConnector::MAX_DOWNLOAD_BYTES + 1) }

      it 'refuses it before downloading the bytes' do
        expect { run_action({ attachment_id: '77' }) }.to raise_error(
          IPaaS::Job::FailJob,
          "Attachment 77 is #{JiraConnector::MAX_DOWNLOAD_BYTES + 1} bytes, over the " \
          "#{JiraConnector::MAX_DOWNLOAD_BYTES}-byte limit of one runbook step."
        )
        expect(a_request(:get, %r{attachment/content})).not_to have_been_made
      end
    end
  end

  describe 'Get Issue Attachments' do
    let(:action_template_id) { '01a13f2d-b655-7f6b-8ed3-47b6e372444b' }

    it 'reads only the attachment field of the issue and maps each attachment' do
      stub_request(:get, "#{api}/issue/KAN-1")
        .with(query: { 'fields' => 'attachment' })
        .to_return(status: 200, body: { id: '10001', key: 'KAN-1', fields: { attachment: [jira_attachment] } }.to_json)
      output = run_action({ issue_id_or_key: 'kan-1' })
      expect(output).to include(issue_id: '10001', issue_key: 'KAN-1')
      expect(output[:attachments].first)
        .to include(attachment_id: '77', filename: 'report.csv', content_type: 'text/csv')
      expect(output[:attachments].first[:author]).to include(account_id: 'acc-1')
    end

    it 'returns an empty list for an issue without attachments' do
      stub_request(:get, "#{api}/issue/KAN-1")
        .with(query: hash_including({}))
        .to_return(status: 200, body: { id: '10001', key: 'KAN-1', fields: {} }.to_json)
      expect(run_action({ issue_id_or_key: 'KAN-1' })[:attachments]).to eq([])
    end

    it 'names the issue whose attachments were not found' do
      stub_request(:get, "#{api}/issue/KAN-9")
        .with(query: hash_including({}))
        .to_return(status: 404, body: { errorMessages: ['Issue does not exist'] }.to_json)
      expect { run_action({ issue_id_or_key: 'KAN-9' }) }
        .to raise_error(IPaaS::Job::FailJob, /\AIssue KAN-9 was not found, or this account cannot see it/)
    end
  end
end

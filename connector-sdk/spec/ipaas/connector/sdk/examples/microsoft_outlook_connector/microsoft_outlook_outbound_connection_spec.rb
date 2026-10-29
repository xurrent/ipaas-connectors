require 'spec_helper'

describe 'Microsoft Outlook Connection', :outbound_connection, :microsoft_outlook do
  let(:connector_id) { '01a0d336-be93-7f28-ad86-75b8273e1010' }
  let(:inbox_url) { "https://graph.microsoft.com/v1.0/users/#{mailbox}/mailFolders/inbox" }
  let(:subscription_id) { 'e72c141e-e8af-4937-a7bd-bb9568659700' }

  def credentials_for(tenant = tenant_id)
    { tenant_id: tenant, client_id: 'client-abc', client_secret: make_secret_string('secret-def') }
  end

  let(:outbound_connection_config) do
    { credentials: credentials_for, cloud: 'Global', default_mailbox: mailbox }
  end

  # Bind the connector's helpers to this connection, as the runtime does before it runs a proc, so an
  # inner helpers.other_helper call and http_get resolve against this connection. copy_to is split into
  # its two halves here so the spec keeps the Helpers object: the proxy it installs dispatches
  # registered names only, so a helper cannot be reached by name through it.
  let(:bound_helpers) { connector.outbound_connection.helpers_definition.copy_for(outbound_connection) }

  before(:each) do
    helpers_proxy = bound_helpers.for_proc
    outbound_connection.define_singleton_method(:helpers) { helpers_proxy }
  end

  # `...` forwards keywords, which `*` does not: a helper that takes `mailbox:` would receive a positional
  # hash, leave the keyword on its default and pass an example that proved nothing.
  def call_helper(name, ...)
    bound_helpers.registered_helper(name).execute(...)
  end

  def graph_response(status, body)
    double(status: status, body: body)
  end

  describe 'cloud' do
    it 'reads the login host and the Graph host of the selected cloud' do
      expect(call_helper(:cloud)).to eq({ login: 'https://login.microsoftonline.com',
                                          graph: 'https://graph.microsoft.com', })
    end

    it 'falls back to Global when the connection carries no cloud' do
      outbound_connection.config[:cloud] = nil
      expect(call_helper(:cloud)[:graph]).to eq('https://graph.microsoft.com')
    end

    it 'reads the China hosts when China is selected' do
      outbound_connection.config[:cloud] = 'China'
      expect(call_helper(:cloud)).to eq({ login: 'https://login.chinacloudapi.cn',
                                          graph: 'https://microsoftgraph.chinacloudapi.cn', })
    end

    it 'fails the job and names the field when the saved cloud is not one we know' do
      outbound_connection.config[:cloud] = 'Mars'
      expect { call_helper(:cloud) }
        .to raise_error(IPaaS::Job::FailJob, /Cloud 'Mars' is not one of .*Open the connection and select a Cloud/)
    end

    # The cloud helper also asserts that the entry it found carries both hosts, which is a state that cannot
    # happen while CLOUDS is correct. That assertion is not exercised here: reaching it needs stub_const on
    # CLOUDS, and the proc sandbox then refuses the constant ("Access to 'CLOUDS' is not allowed"), because a
    # stubbed constant is no longer defined in the connector's own file. An example that stubs it passes only
    # when an earlier example in the same run has already warmed the sandbox verdict, so it would be flaky.
  end

  describe 'tenant_id' do
    it 'strips surrounding whitespace' do
      outbound_connection.config[:credentials][:tenant_id] = "  #{tenant_id}  "
      expect(call_helper(:tenant_id)).to eq(tenant_id)
    end

    it 'fails the job when the tenant is empty' do
      outbound_connection.config[:credentials][:tenant_id] = '   '
      expect { call_helper(:tenant_id) }.to raise_error(IPaaS::Job::FailJob, /Tenant ID is empty/)
    end

    it 'refuses a sign-in placeholder, whatever its case' do
      outbound_connection.config[:credentials][:tenant_id] = 'Common'
      expect { call_helper(:tenant_id) }
        .to raise_error(IPaaS::Job::FailJob, /'Common' is a sign-in placeholder/)
    end

    it 'refuses the organizations placeholder' do
      outbound_connection.config[:credentials][:tenant_id] = 'organizations'
      expect { call_helper(:tenant_id) }.to raise_error(IPaaS::Job::FailJob, /sign-in placeholder/)
    end

    it 'refuses the consumers placeholder' do
      outbound_connection.config[:credentials][:tenant_id] = 'consumers'
      expect { call_helper(:tenant_id) }.to raise_error(IPaaS::Job::FailJob, /sign-in placeholder/)
    end
  end

  describe 'token_url and graph_url' do
    it 'builds the token endpoint from the login host and the tenant' do
      expect(call_helper(:token_url)).to eq(token_url)
    end

    it 'builds a Graph URL from the Graph host and the API version' do
      expect(call_helper(:graph_url, '/users/x/messages'))
        .to eq('https://graph.microsoft.com/v1.0/users/x/messages')
    end

    # The assertion: every caller passes a rooted path, so a path without a leading slash is a state that
    # cannot happen while the connector is correct.
    it 'raises when a caller passes a path that is not rooted' do
      expect { call_helper(:graph_url, 'users/x/messages') }
        .to raise_error(IPaaS::Error, %r{graph path 'users/x/messages' does not start with a slash})
    end
  end

  describe 'token_body' do
    it 'asks for a client credentials token with the decrypted secret and the Graph scope' do
      expect(call_helper(:token_body))
        .to eq({ client_id: 'client-abc', client_secret: 'secret-def', grant_type: 'client_credentials',
                 scope: 'https://graph.microsoft.com/.default', })
    end

    it 'asks for the scope of the Graph host the selected cloud uses' do
      outbound_connection.config[:cloud] = 'US Government DoD'
      expect(call_helper(:token_body)[:scope]).to eq('https://dod-graph.microsoft.us/.default')
    end
  end

  describe 'normalize_mailbox and mailbox_for' do
    it 'drops a mailto prefix and the whitespace around it' do
      expect(call_helper(:normalize_mailbox, '  MAILTO:adele@contoso.com ')).to eq('adele@contoso.com')
    end

    it 'takes the value the step supplied' do
      expect(call_helper(:mailbox_for, 'other@contoso.com')).to eq('other@contoso.com')
    end

    it 'uses the default mailbox of the connection when the step leaves it empty' do
      expect(call_helper(:mailbox_for, '   ')).to eq(mailbox)
    end

    it 'fails the job and names both places when neither carries a mailbox' do
      outbound_connection.config[:default_mailbox] = nil
      expect { call_helper(:mailbox_for, nil) }
        .to raise_error(IPaaS::Job::FailJob, /Set Mailbox on this step, or Default mailbox on the connection/)
    end

    # Graph reads a slash as the end of the address and answers a routing error naming neither the
    # value nor the problem, so the connector refuses it before the call and says which field holds it.
    it 'refuses a mailbox holding a slash, and says Mailbox because that is the field it read' do
      expect { call_helper(:normalize_mailbox, 'contoso/adele') }
        .to raise_error(IPaaS::Job::FailJob, "Mailbox 'contoso/adele' holds a slash, a backslash or a percent sign, " \
                                             'which changes how Microsoft Graph reads the address. Microsoft answers ' \
                                             'a routing error that names neither the value nor the problem. Use a ' \
                                             'user principal name, an object id or an SMTP address.')
    end

    it 'refuses a backslash the same way' do
      expect { call_helper(:normalize_mailbox, 'contoso\\adele') }
        .to raise_error(IPaaS::Job::FailJob, /holds a slash, a backslash or a percent sign/)
    end

    it 'refuses a percent sign, so an encoded slash never reaches a URL' do
      expect { call_helper(:normalize_mailbox, 'x%2F..%2Fgroups') }
        .to raise_error(IPaaS::Job::FailJob, /holds a slash, a backslash or a percent sign/)
    end
  end

  describe 'folder_for' do
    it 'defaults to the inbox' do
      expect(call_helper(:folder_for, nil)).to eq('inbox')
    end

    it 'admits a real Graph folder id' do
      identifier = 'AAMkAGQzOGVlNTJkLWMzMzYtNDgzNi04ZWQyLWZhMDc5YmJmNzY4NQAuAAAAAACNg_CfyiTySaMnuVjjxVl2AQBI' \
                   'zshfbRZ8SaULyxi-fjtsAAAAAAEMAAA='
      expect(call_helper(:folder_for, identifier)).to eq(identifier)
    end

    it 'refuses a display name, because Graph answers a malformed id error for it' do
      expect { call_helper(:folder_for, 'Sent Items') }
        .to raise_error(IPaaS::Job::FailJob, /A display name such as Sent Items is not accepted/)
    end

    it 'refuses a value carrying a path separator' do
      expect { call_helper(:folder_for, '../../users/someone@contoso.com/mailFolders/inbox') }
        .to raise_error(IPaaS::Job::FailJob, /is not a well-known name/)
    end

    it 'refuses a value longer than a folder id can be' do
      too_long = 'a' * (MicrosoftOutlookConnector::MAX_FOLDER_LENGTH + 1)
      expect { call_helper(:folder_for, too_long) }
        .to raise_error(IPaaS::Job::FailJob, /Folder is #{too_long.length} characters long/)
    end

    it 'admits a value of exactly the longest length it allows' do
      longest = 'a' * MicrosoftOutlookConnector::MAX_FOLDER_LENGTH
      expect(call_helper(:folder_for, longest)).to eq(longest)
    end
  end

  describe 'escape_segment and messages_url' do
    it 'encodes every character that would change what the URL means' do
      expect(call_helper(:escape_segment, 'a%b#c?d e/f')).to eq('a%25b%23c%3Fd%20e%2Ff')
    end

    it 'encodes the percent before anything else, so an encoding is never encoded twice' do
      expect(call_helper(:escape_segment, '%23')).to eq('%2523')
    end

    it 'builds the messages collection URL for a mailbox and a folder' do
      expect(call_helper(:messages_url, mailbox, 'inbox'))
        .to eq("https://graph.microsoft.com/v1.0/users/#{mailbox}/mailFolders/inbox/messages")
    end

    it 'keeps an external user principal name inside its own path segment' do
      expect(call_helper(:messages_url, 'guest_gmail.com#EXT#@contoso.com', 'inbox'))
        .to eq('https://graph.microsoft.com/v1.0/users/guest_gmail.com%23EXT%23@contoso.com/mailFolders/inbox/messages')
    end
  end

  describe 'user_path' do
    it 'names the mailbox under the users collection' do
      expect(call_helper(:user_path, mailbox)).to eq("/users/#{mailbox}")
    end

    it 'escapes the mailbox, so an external user principal name stays one path segment' do
      expect(call_helper(:user_path, 'guest_gmail.com#EXT#@contoso.com'))
        .to eq('/users/guest_gmail.com%23EXT%23@contoso.com')
    end
  end

  describe 'attachments_url and attachment_url' do
    let(:message_id) { 'AAMkAGQzOGVlNTJk=' }
    let(:attachment_id) { 'AAMkAGQzOGVlNTJkLWMzMzY=' }
    let(:attachments_url) { "https://graph.microsoft.com/v1.0/users/#{mailbox}/messages/#{message_id}/attachments" }

    it 'builds the attachments collection URL of one message' do
      expect(call_helper(:attachments_url, mailbox, message_id)).to eq(attachments_url)
    end

    it 'puts the attachment id on the end of the collection URL' do
      expect(call_helper(:attachment_url, mailbox, message_id, attachment_id))
        .to eq("#{attachments_url}/#{attachment_id}")
    end

    it 'keeps a message id and an attachment id carrying a slash inside their own path segments' do
      expect(call_helper(:attachment_url, mailbox, 'a/b', 'c/d'))
        .to eq("https://graph.microsoft.com/v1.0/users/#{mailbox}/messages/a%2Fb/attachments/c%2Fd")
    end
  end

  describe 'attachment_summary' do
    def attachment_row(overrides = {})
      { 'id' => 'AAMkAGQz=', 'name' => 'report.pdf', 'contentType' => 'application/pdf',
        'size' => 1163, 'isInline' => false, }.merge(overrides)
    end

    it 'maps the five names the list asks Microsoft for' do
      expect(call_helper(:attachment_summary, attachment_row))
        .to eq({ attachment_id: 'AAMkAGQz=', name: 'report.pdf', content_type: 'application/pdf',
                 size_in_bytes: 1163, is_inline: false, })
    end

    # A message attached to a message is listed with a name and a size and no content type, so the row is
    # carried through as it is rather than refused here. Download Attachment is where it is refused.
    it 'carries the empty content type of a message attached to a message' do
      row = attachment_row('contentType' => nil, 'name' => 'attached message')
      expect(call_helper(:attachment_summary, row)[:content_type]).to be_nil
    end

    # The assertion: every attachment Graph returns carries an id, so a row without one is a state that
    # cannot happen. It would reach the runbook as a row Download Attachment can never be given.
    it 'raises when Microsoft returns an attachment with no id' do
      expect { call_helper(:attachment_summary, attachment_row('id' => '')) }
        .to raise_error(IPaaS::Error, 'Microsoft Graph returned an attachment with no id')
    end
  end

  describe 'attachment_size' do
    it 'reads the size Microsoft reports' do
      expect(call_helper(:attachment_size, { 'id' => 'AAMkAGQz=', 'size' => 60_180 })).to eq(60_180)
    end

    # The assertion: size is one of the names ATTACHMENT_SELECT asks for and Graph always answers it with a
    # whole number. A missing one reads as nil, and nil.to_i is 0, so a size limit built on it would let
    # every file through without comparing anything.
    it 'raises when the size Microsoft reports is not a whole number of bytes' do
      expect { call_helper(:attachment_size, { 'id' => 'AAMkAGQz=' }) }
        .to raise_error(IPaaS::Error, /attachment 'AAMkAGQz=' with a size of '', which is not a whole number/)
    end
  end

  describe 'attachment_kind' do
    it 'reads the type Microsoft returns, which a select cannot ask for' do
      row = { 'id' => 'AAMkAGQz=', '@odata.type' => '#microsoft.graph.itemAttachment' }
      expect(call_helper(:attachment_kind, row)).to eq('#microsoft.graph.itemAttachment')
    end

    # The assertion: Graph returns @odata.type on every attachment row under every select, and naming it in a
    # select is HTTP 400, so it can be read but never requested. A blank one leaves a message attached to a
    # message and a link to a cloud file looking exactly like a file that can be downloaded.
    it 'raises when Microsoft returns an attachment with no @odata.type' do
      expect { call_helper(:attachment_kind, { 'id' => 'AAMkAGQz=' }) }
        .to raise_error(IPaaS::Error, /attachment 'AAMkAGQz=' with no '@odata.type'/)
    end
  end

  describe 'attachment_content' do
    it 'hands back the base64 Microsoft sends, untouched' do
      expect(call_helper(:attachment_content, { 'id' => 'AAMkAGQz=', 'contentBytes' => 'aGVsbG8=' }))
        .to eq('aGVsbG8=')
    end

    # A file of no bytes is still a file, and its contentBytes is an empty String. The guard below reads the
    # type rather than the emptiness, so this row passes and the one with no key at all does not.
    it 'returns an empty string for a file of no bytes' do
      expect(call_helper(:attachment_content, { 'id' => 'AAMkAGQz=', 'contentBytes' => '' })).to eq('')
    end

    # The assertion: the content read asks for the bytes through the fileAttachment type and the run block
    # only reaches it for a file attachment, so a successful read without contentBytes cannot happen. It
    # would hand the runbook an empty file and raise nothing anywhere.
    it 'raises when the content read carries no contentBytes' do
      expect { call_helper(:attachment_content, { 'id' => 'AAMkAGQz=' }) }
        .to raise_error(IPaaS::Error, /attachment 'AAMkAGQz=' with no contentBytes/)
    end
  end

  describe 'ATTACHMENT_CONTENT_SELECT' do
    # contentBytes lives on microsoft.graph.fileAttachment and not on the attachment type every row shares,
    # so asking for it by its plain name answers HTTP 400 on every read. The derived type path is the only
    # spelling Graph accepts, and no stubbed response would ever show that.
    it 'asks for the bytes through the file attachment type' do
      expect(MicrosoftOutlookConnector::ATTACHMENT_CONTENT_SELECT)
        .to eq(%w[id name contentType microsoft.graph.fileAttachment/contentBytes])
    end
  end

  describe 'graph_get' do
    let(:messages_url) { "https://graph.microsoft.com/v1.0/users/#{mailbox}/messages" }

    it 'sends the query and returns the parsed object Graph answered' do
      stub_request(:get, messages_url).with(query: { '$top' => '5' })
                                      .to_return(status: 200, body: { value: [] }.to_json)
      expect(call_helper(:graph_get, messages_url, { '$top': '5' })).to eq({ 'value' => [] })
    end

    it 'asks for a retry when Microsoft throttles the tenant' do
      stub_request(:get, messages_url)
        .to_return(status: 429, headers: { 'Retry-After' => '30' },
                   body: { error: { code: 'TooManyRequests' } }.to_json)
      expect_reschedule_after(30) { call_helper(:graph_get, messages_url) }
    end

    it 'names the mailbox it was given when Microsoft refuses the caller' do
      stub_request(:get, messages_url)
        .to_return(status: 403, body: { error: { code: 'ErrorAccessDenied', message: 'Access is denied.' } }.to_json)
      expect { call_helper(:graph_get, messages_url, nil, mailbox) }
        .to raise_error(IPaaS::Job::FailJob, /while reading mailbox '#{mailbox}'/)
    end
  end

  describe 'parse_graph' do
    it 'returns the parsed object of a successful answer' do
      expect(call_helper(:parse_graph, graph_response(200, { value: [] }.to_json))).to eq({ 'value' => [] })
    end

    # Four actions share this message, so the mailbox is named only when Microsoft refused the caller.
    it 'names the mailbox when Microsoft refused the caller' do
      body = { error: { code: 'ErrorAccessDenied', message: 'Access is denied.' } }.to_json
      expect { call_helper(:parse_graph, graph_response(403, body), 'adele@contoso.com') }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 403 ErrorAccessDenied while reading mailbox ' \
                        "'adele@contoso.com': Access is denied.")
    end

    # A malformed folder id is a 400, and the mailbox it was read through is working. Naming it there
    # sends the builder to check a field that has nothing wrong with it.
    it 'says nothing about the mailbox when the failure is not a refusal' do
      body = { error: { code: 'ErrorInvalidIdMalformed', message: 'Id is malformed.' } }.to_json
      expect { call_helper(:parse_graph, graph_response(400, body), 'adele@contoso.com') }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 400 ErrorInvalidIdMalformed: Id is malformed.')
    end

    it 'says nothing about a mailbox when the caller gives none' do
      body = { error: { code: 'ErrorItemNotFound', message: 'Not found.' } }.to_json
      expect { call_helper(:parse_graph, graph_response(404, body)) }
        .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph returned HTTP 404 ErrorItemNotFound: Not found.')
    end

    # The assertion: Graph answers this collection with an object, so a bare array on a 200 is a state that
    # cannot happen while Graph keeps its contract.
    it 'raises when a successful answer is not an object' do
      expect { call_helper(:parse_graph, graph_response(200, [1, 2].to_json)) }
        .to raise_error(IPaaS::Error, 'Microsoft Graph returned a value that is not an object')
    end

    it 'fails the job with Microsoft own words on any other status' do
      body = { error: { code: 'ErrorItemNotFound', message: 'The specified object was not found.' } }.to_json
      expect { call_helper(:parse_graph, graph_response(404, body)) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 404 ErrorItemNotFound: The specified object was not found.')
    end

    # The body is parsed before the status is read, so a body that is not JSON is reported as that, whatever
    # the status was. config_tester takes the other route and quotes the raw body through describe_graph_failure.
    it 'names the status, not the parse, when a failure answers with something that is not JSON' do
      expect { call_helper(:parse_graph, graph_response(503, 'service unavailable')) }
        .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph returned HTTP 503 : service unavailable')
    end
  end
  describe 'the folder list behind the Folder field' do
    let(:delta_url) { "https://graph.microsoft.com/v1.0/users/#{mailbox}/mailFolders/delta" }
    let(:second_page_url) { "#{delta_url}?$skiptoken=page-two" }
    let(:other_mailbox) { 'other@contoso.com' }
    let(:other_delta_url) { "https://graph.microsoft.com/v1.0/users/#{other_mailbox}/mailFolders/delta" }

    def folder_row(id, display_name, parent: nil, well_known: nil)
      { 'id' => id, 'displayName' => display_name, 'parentFolderId' => parent, 'wellKnownName' => well_known }
    end

    def stub_folder_page(url, rows, next_link: nil)
      body = { value: rows }
      body[:'@odata.nextLink'] = next_link if next_link
      stub_request(:get, url).to_return(status: 200, body: body.to_json)
    end

    describe 'folders_url' do
      it 'asks the delta collection, the one read that also answers with the folders below the root' do
        expect(call_helper(:folders_url, mailbox)).to eq(delta_url)
      end

      # The assertion: mailbox_for has already refused an empty mailbox, so an empty one reaching the URL
      # is a state that cannot happen while the connector is correct.
      it 'raises when it is asked for a mailbox that is empty' do
        expect { call_helper(:folders_url, '   ') }
          .to raise_error(IPaaS::Error, 'folders_url was asked for an empty mailbox')
      end
    end

    describe 'folder_page' do
      # The assertion: Graph answers this collection with a list under 'value', so anything else on a 200 is
      # a state that cannot happen while Graph keeps its contract.
      it 'raises when a folder page answers with a value that is not a list' do
        stub_request(:get, delta_url).to_return(status: 200, body: { value: { id: 'inbox' } }.to_json)
        expect { call_helper(:folder_page, delta_url) }
          .to raise_error(IPaaS::Error, 'Microsoft Graph returned a folder page whose value is not a list')
      end

      # 429 is handled by backoff_if_needed itself, whatever server_error_statuses holds, so the dropdown
      # shows "the connector asked to try again shortly" instead of Microsoft's own throttling text.
      it 'asks for a retry when Microsoft throttles the tenant' do
        stub_request(:get, delta_url)
          .to_return(status: 429, headers: { 'Retry-After' => '30' },
                     body: { error: { code: 'ApplicationThrottled' } }.to_json)
        expect_reschedule_after(30, /rate limit/) { call_helper(:folder_page, delta_url) }
      end
    end

    describe 'folder_rows' do
      it 'follows the delta next link and returns the folders of every page' do
        stub_folder_page(delta_url, [folder_row('id-inbox', 'Inbox')], next_link: second_page_url)
        stub_folder_page(second_page_url, [folder_row('id-sales', 'Sales')])
        expect(call_helper(:folder_rows, mailbox).map { |row| row['displayName'] }).to eq(%w[Inbox Sales])
        expect(a_request(:get, delta_url)
                 .with(query: hash_including({ '$skiptoken' => 'page-two' }),
                       headers: { 'Authorization' => 'Bearer outlook-token' }))
          .to have_been_requested
      end

      # The guard: the delta collection pages at ten rows and refuses $top, so a large mailbox runs out of
      # requests before it runs out of folders. A short list that looks whole is the state this refuses.
      it 'fails the job and says to type the id when the mailbox needs more requests than the budget' do
        stub_folder_page(delta_url, [folder_row('id-inbox', 'Inbox')], next_link: second_page_url)
        stub_folder_page(second_page_url, [folder_row('id-sales', 'Sales')], next_link: second_page_url)
        expect { call_helper(:folder_rows, mailbox) }
          .to raise_error(IPaaS::Job::FailJob, /more folders than the list reads in 12 requests.*Type the folder id/m)
      end

      it 'refuses a delta next link on another host, so the token never leaves the Graph host' do
        stub_folder_page(delta_url, [folder_row('id-inbox', 'Inbox')],
                         next_link: 'https://evil.example.com/v1.0/users/x/mailFolders/delta')
        expect { call_helper(:folder_rows, mailbox) }
          .to raise_error(IPaaS::Error, %r{next page link that is not on https://graph\.microsoft\.com})
      end
    end

    describe 'folder_option_id' do
      it 'prefers the well-known name, which names the same folder in every mailbox' do
        expect(call_helper(:folder_option_id, folder_row('id-inbox', 'Inbox', well_known: 'inbox'))).to eq('inbox')
      end

      it 'takes the folder id when the folder has no well-known name' do
        expect(call_helper(:folder_option_id, folder_row('id-sales', 'Sales'))).to eq('id-sales')
      end

      # The assertion: every row of this collection carries an id, so a row without one cannot happen while
      # Graph keeps its contract.
      it 'raises when Graph returns a folder with no id' do
        expect { call_helper(:folder_option_id, folder_row(nil, 'Sales')) }
          .to raise_error(IPaaS::Error, 'Microsoft Graph returned a folder with no id')
      end

      # The assertion: the picker and folder_for share one idea of what an id looks like, so an offered id
      # that folder_for would refuse is a state that cannot happen while both stay in step.
      it 'raises when it built an id that the Folder field itself would refuse' do
        expect { call_helper(:folder_option_id, folder_row('id/with/slashes', 'Sales')) }
          .to raise_error(IPaaS::Error,
                          "the folder list built the id 'id/with/slashes', which the Folder field refuses")
      end
    end

    describe 'folder_label' do
      let(:rows) do
        [folder_row('id-inbox', 'Inbox'),
         folder_row('id-sales', 'Sales', parent: 'id-inbox'),
         folder_row('id-emea', 'EMEA', parent: 'id-sales'),]
      end

      it 'names every parent before the folder itself' do
        rows_by_id = rows.index_by { |row| row['id'] }
        expect(call_helper(:folder_label, rows[2], rows_by_id)).to eq('Inbox / Sales / EMEA')
      end

      # The assertion: a mailbox's folders form a tree, so a chain of parents that never reaches the top is a
      # state that cannot happen. Without the bound the walk never ends and the dropdown hangs to its deadline.
      it 'raises when the chain of parents never reaches the top of the mailbox' do
        looping = [folder_row('id-a', 'A', parent: 'id-b'), folder_row('id-b', 'B', parent: 'id-a')]
        rows_by_id = looping.index_by { |row| row['id'] }
        expect { call_helper(:folder_label, looping[0], rows_by_id) }
          .to raise_error(IPaaS::Error, /folder 'id-a' sits under more than 32 parents/)
      end
    end

    describe 'folder_options_from' do
      it 'offers one option per folder, the id to store and the path to read' do
        rows = [folder_row('id-inbox', 'Inbox', well_known: 'inbox'),
                folder_row('id-sales', 'Sales', parent: 'id-inbox'),]
        expect(call_helper(:folder_options_from, rows))
          .to eq([{ id: 'inbox', label: 'Inbox' }, { id: 'id-sales', label: 'Inbox / Sales' }])
      end

      # The assertion: a folder id and a well-known name are each unique inside one mailbox, so two options
      # carrying one id is a state that cannot happen. It would make the stored value mean two folders.
      it 'raises when two folders would offer the same id' do
        rows = [folder_row('id-inbox', 'Inbox', well_known: 'archive'), folder_row('archive', 'Archive')]
        expect { call_helper(:folder_options_from, rows) }
          .to raise_error(IPaaS::Error, 'the folder list offers the same id twice')
      end
    end

    describe 'fetch_folder_options' do
      it 'reads the mailbox the step names, not the default mailbox of the connection' do
        stub_folder_page(other_delta_url, [folder_row('id-inbox', 'Inbox', well_known: 'inbox')])
        expect(call_helper(:fetch_folder_options, mailbox: other_mailbox)).to eq([{ id: 'inbox', label: 'Inbox' }])
        expect(a_request(:get, other_delta_url)
                 .with(query: hash_including({}), headers: { 'Authorization' => 'Bearer outlook-token' }))
          .to have_been_requested
        expect(a_request(:get, delta_url).with(query: hash_including({}))).not_to have_been_requested
      end

      it 'reads the default mailbox of the connection when the step names no mailbox' do
        stub_folder_page(delta_url, [folder_row('id-inbox', 'Inbox', well_known: 'inbox')])
        expect(call_helper(:fetch_folder_options, mailbox: nil)).to eq([{ id: 'inbox', label: 'Inbox' }])
      end

      # The assertion: every mailbox holds at least an inbox, so an empty folder list is a state that cannot
      # happen. An empty dropdown says nothing, while this says what went wrong.
      it 'raises when Graph answers with no folders at all' do
        stub_folder_page(delta_url, [])
        expect { call_helper(:fetch_folder_options, mailbox: nil) }
          .to raise_error(IPaaS::Error, "Microsoft Graph returned no folders at all for mailbox '#{mailbox}'")
      end
    end

    # Loading the connector proves only that the options block parses. These drive the real field, so the
    # keyword the block declares has to line up with the keyword the helper takes.
    describe 'the options block the Folder field carries' do
      let(:folder_field) do
        action = connector.actions.detect { |candidate| candidate.name == 'List Emails' }
        action.input_schema.fields.detect { |field| field.id == :folder }
      end

      # Mailbox is a dependency the field can do without: an empty Mailbox reads the connection's Default
      # mailbox, which the connector documents as a working step. A required keyword would answer
      # "Select Mailbox first." and take that step away.
      it 'depends on Mailbox without requiring it, so an empty Mailbox still lists the default mailbox' do
        stub_folder_page(delta_url, [folder_row('id-inbox', 'Inbox', well_known: 'inbox')])
        expect(folder_field.option_dependencies).to eq([:mailbox])
        expect(folder_field.required_option_dependencies).to eq([])
        expect(folder_field.call_function(:options, outbound_connection)).to eq([{ id: 'inbox', label: 'Inbox' }])
      end

      it 'reaches the helper with the mailbox the sibling field holds' do
        stub_folder_page(other_delta_url, [folder_row('id-inbox', 'Inbox', well_known: 'inbox')])
        expect(folder_field.call_function(:options, outbound_connection, mailbox: other_mailbox))
          .to eq([{ id: 'inbox', label: 'Inbox' }])
      end

      # The well-known name is what makes this hold: a folder id names a folder in one mailbox only, so a
      # list built from ids alone would not carry the field's own default and the field would open on a
      # value missing from its own list.
      it 'offers the default the field itself declares' do
        stub_folder_page(delta_url, [folder_row('id-inbox', 'Inbox', well_known: 'inbox'),
                                     folder_row('id-sales', 'Sales', parent: 'id-inbox'),])
        options = folder_field.call_function(:options, outbound_connection)
        expect(options.map { |option| option[:id] }).to include(folder_field.default)
      end
    end
  end

  describe 'search_folder_for' do
    it 'leaves a blank folder blank, so the search reads the whole mailbox' do
      expect(call_helper(:search_folder_for, '   ')).to eq('')
    end

    it 'keeps the folder the step supplied for a search' do
      expect(call_helper(:search_folder_for, ' drafts ')).to eq('drafts')
    end

    it 'refuses a display name in a search folder too' do
      expect { call_helper(:search_folder_for, 'Sent Items') }
        .to raise_error(IPaaS::Job::FailJob, /A display name such as Sent Items is not accepted/)
    end
  end

  describe 'search_messages_url' do
    it 'reads the whole mailbox when the search names no folder' do
      expect(call_helper(:search_messages_url, mailbox, ''))
        .to eq("https://graph.microsoft.com/v1.0/users/#{mailbox}/messages")
    end

    it 'reads one folder when the search names one' do
      expect(call_helper(:search_messages_url, mailbox, 'drafts'))
        .to eq("https://graph.microsoft.com/v1.0/users/#{mailbox}/mailFolders/drafts/messages")
    end

    # The assertion: mailbox_for fails the job before this is reached, so a search URL with no mailbox is a
    # state that cannot happen while the action is correct.
    it 'raises when a search URL is built without a mailbox' do
      expect { call_helper(:search_messages_url, '   ', '') }
        .to raise_error(IPaaS::Error, /a Search Emails URL was built without a mailbox/)
    end
  end

  describe 'integer_or_default' do
    it 'uses the default when the step leaves the field unmapped' do
      expect(call_helper(:integer_or_default, nil, 100)).to eq(100)
    end

    it 'uses the default when the step maps the field to an empty value' do
      expect(call_helper(:integer_or_default, '  ', 25)).to eq(25)
    end

    it 'takes the number the step supplied' do
      expect(call_helper(:integer_or_default, 250, 100)).to eq(250)
    end

    it 'reads a number that reaches the field as digits' do
      expect(call_helper(:integer_or_default, '5', 25)).to eq(5)
    end
  end

  describe 'odata_literal and odata_time' do
    it 'wraps a criterion value in the quote OData expects' do
      expect(call_helper(:odata_literal, 'adele@contoso.com')).to eq("'adele@contoso.com'")
    end

    # Graph answers HTTP 400 BadRequest, "unterminated literal", for contains(subject,'it's'), so the
    # doubling is what makes the request legal and not a cosmetic choice.
    it 'doubles a quote inside the value, which Graph reads back as one quote' do
      expect(call_helper(:odata_literal, "it's")).to eq("'it''s'")
    end

    it 'writes a moment as the UTC literal Graph compares receivedDateTime against' do
      expect(call_helper(:odata_time, DateTime.parse('2026-01-02T03:04:05+02:00')))
        .to eq('2026-01-02T01:04:05Z')
    end

    # The assertion: a date clause is built only for a criterion the step filled, so an empty moment here
    # is a state that cannot happen while the action is correct.
    it 'raises when a date clause is built from an empty moment' do
      expect { call_helper(:odata_time, nil) }
        .to raise_error(IPaaS::Error, /a Search Emails date clause was built from an empty moment/)
    end
  end

  describe 'search_query' do
    it 'wraps the search text in the double quote a free-text search expects' do
      expect(call_helper(:search_query, ' invoice ')).to eq('"invoice"')
    end

    it 'keeps a single quote, which a free-text search accepts' do
      expect(call_helper(:search_query, "it's")).to eq(%q("it's"))
    end

    it 'answers empty when the step filled no search text' do
      expect(call_helper(:search_query, nil)).to eq('')
    end

    # Graph answers HTTP 400 BadRequest, "character '\"' is not valid at position 8", and SEARCH_QUOTE has no
    # escaped partner the way ODATA_QUOTE has, so the text cannot be repaired here.
    it 'fails the job when the search text holds a double quote' do
      expect { call_helper(:search_query, 'say "hi"') }
        .to raise_error(IPaaS::Job::FailJob, /Search text holds a double quote/)
    end
  end

  describe 'search_select and matches_to_address' do
    def recipient(address)
      { 'emailAddress' => { 'name' => 'Adele', 'address' => address } }
    end

    it 'asks for the summary fields when no To address narrows the search' do
      expect(call_helper(:search_select, nil))
        .to eq('id,subject,from,receivedDateTime,hasAttachments,isRead,importance,bodyPreview')
    end

    # Measured against the live tenant: with the field list as MESSAGE_SELECT declares it, a To address that
    # genuinely has six messages matched none of them, because Graph sends toRecipients only when asked.
    it 'asks for toRecipients as well when a To address narrows the search' do
      expect(call_helper(:search_select, 'adele@contoso.com')).to end_with(',toRecipients')
    end

    it 'matches a recipient whatever case either side was written in' do
      message = { 'toRecipients' => [recipient('Adele@Contoso.com')] }
      expect(call_helper(:matches_to_address, message, ' adele@contoso.com ')).to be(true)
    end

    it 'does not match a message addressed to somebody else' do
      message = { 'toRecipients' => [recipient('other@contoso.com')] }
      expect(call_helper(:matches_to_address, message, 'adele@contoso.com')).to be(false)
    end

    it 'keeps every message when the step filled no To address' do
      expect(call_helper(:matches_to_address, { 'id' => 'AAMkAGQz=' }, '  ')).to be(true)
    end

    it 'does not match a message that lists no recipient at all' do
      expect(call_helper(:matches_to_address, { 'toRecipients' => [] }, 'adele@contoso.com')).to be(false)
    end

    # The assertion: search_select asks for toRecipients whenever a To address was filled, so a message
    # without the key means the request did not, and every message would be dropped without a word.
    it 'raises when it must match a To address on a message that carries no toRecipients' do
      expect { call_helper(:matches_to_address, { 'id' => 'AAMkAGQz=' }, 'adele@contoso.com') }
        .to raise_error(IPaaS::Error, /carries no toRecipients/)
    end
  end

  describe 'search_filter' do
    it 'writes one clause per criterion Graph can filter on, joined with and' do
      filter = call_helper(:search_filter,
                           { from_address: 'postmaster@contoso.com', subject_contains: 'Testing',
                             received_after: DateTime.parse('2026-01-01T00:00:00Z'),
                             received_before: DateTime.parse('2026-02-01T00:00:00Z'),
                             has_attachments: true, is_unread: true, })
      expect(filter).to eq("from/emailAddress/address eq 'postmaster@contoso.com' and " \
                           "contains(subject,'Testing') and " \
                           'receivedDateTime ge 2026-01-01T00:00:00Z and ' \
                           'receivedDateTime le 2026-02-01T00:00:00Z and ' \
                           'hasAttachments eq true and isRead eq false')
    end

    # Graph answers HTTP 400 ErrorInvalidUrlQueryFilter for toRecipients/any(...), so To address is never a
    # clause. matches_to_address applies it to the messages that come back instead.
    it 'leaves To address out, because Graph refuses to filter on recipients' do
      expect(call_helper(:search_filter, { from_address: 'x@contoso.com', to_address: 'adele@contoso.com' }))
        .to eq("from/emailAddress/address eq 'x@contoso.com'")
    end

    it 'answers empty when the step filled nothing Graph can filter on' do
      expect(call_helper(:search_filter, { search_text: 'invoice' })).to eq('')
    end

    it 'asks for read messages when Is unread is off, which is not the same as leaving it empty' do
      expect(call_helper(:search_filter, { is_unread: false })).to eq('isRead eq true')
    end

    it 'asks for messages without an attachment when Has attachments is off' do
      expect(call_helper(:search_filter, { has_attachments: false })).to eq('hasAttachments eq false')
    end

    it 'escapes a quote typed into Subject contains' do
      expect(call_helper(:search_filter, { subject_contains: "it's" })).to eq("contains(subject,'it''s')")
    end
  end

  describe 'search_params' do
    it 'sends the free-text search with the field list and the page size' do
      expect(call_helper(:search_params, '"invoice"', '', { select: 'id,subject', page_size: 25 }))
        .to eq({ '$select': 'id,subject', '$top': '25', '$search': '"invoice"' })
    end

    it 'sends the filter when the step filled no search text' do
      expect(call_helper(:search_params, '', 'isRead eq false', { select: 'id,subject', page_size: 25 }))
        .to eq({ '$select': 'id,subject', '$top': '25', '$filter': 'isRead eq false' })
    end

    # A query value must be a String, a Symbol or raw-marked; an Integer raises inside the HTTP layer.
    it 'sends the page size as a string, because that is what a query value must be' do
      expect(call_helper(:search_params, '', '', { select: 'id', page_size: 1000 })[:$top]).to eq('1000')
    end

    # Graph answers HTTP 400 SearchWithOrderBy for $search with $orderby, and HTTP 400 InefficientFilter for
    # contains(subject,...) with $orderby, so this action asks for no order on either path.
    it 'asks for no order, which neither path of this action is allowed to have' do
      expect(call_helper(:search_params, '"invoice"', '', { select: 'id', page_size: 25 })).not_to have_key(:$orderby)
    end

    # The assertion: Graph answers HTTP 400 SearchWithFilter when the two travel together, so a request
    # carrying both is a state that cannot happen while the run block is correct.
    it 'raises when a request would carry a free-text search and a filter at once' do
      expect { call_helper(:search_params, '"invoice"', 'isRead eq false', { select: 'id', page_size: 25 }) }
        .to raise_error(IPaaS::Error, /SearchWithFilter/)
    end
  end

  describe 'next_page_link' do
    it 'answers empty when Graph reported no further page' do
      expect(call_helper(:next_page_link, { 'value' => [] })).to eq('')
    end

    # Graph writes the folder back as an OData key, mailFolders('drafts'), so the link is taken as given:
    # a check on the path would refuse every real second page.
    it 'takes the link as given, with the folder rewritten as an OData key' do
      link = "https://graph.microsoft.com/v1.0/users/#{mailbox}/mailFolders('drafts')/messages?%24skiptoken=MSZ"
      expect(call_helper(:next_page_link, { '@odata.nextLink' => link })).to eq(link)
    end

    # The assertion: the link comes from the Graph host this connection signed in to, so a link anywhere
    # else is a state that cannot happen while Graph keeps its contract.
    it 'raises when the next page link points somewhere other than the Graph host' do
      expect { call_helper(:next_page_link, { '@odata.nextLink' => 'https://evil.example.com/v1.0/users/x' }) }
        .to raise_error(IPaaS::Error, %r{not on https://graph\.microsoft\.com})
    end
  end

  describe 'intersect_search_and_filter' do
    let(:messages_url) { "https://graph.microsoft.com/v1.0/users/#{mailbox}/messages" }
    let(:filter) { "from/emailAddress/address eq 'billing@vendor.com'" }
    let(:rules) { { select: 'id', page_size: 25, to_address: nil, limit: 1, mailbox: mailbox } }

    def stub_leg(parameter, body)
      stub_request(:get, messages_url).with(query: hash_including(parameter))
                                      .to_return(status: 200, body: body.to_json)
    end

    it 'keeps only the messages that both the search and the filter answered' do
      stub_leg({ '$search' => '"invoice"' }, { value: [{ id: 'text-only' }, { id: 'in-both' }] })
      stub_leg({ '$filter' => filter }, { value: [{ id: 'in-both' }, { id: 'sender-only' }] })
      result = call_helper(:intersect_search_and_filter, messages_url, '"invoice"', filter, rules)
      expect(result).to eq({ messages: [{ 'id' => 'in-both' }], left_unread: false })
    end

    # Result limit counts matches, and a message the search found is only a match once the filter agrees, so
    # the search reads every page it can before the filter narrows it down.
    it 'reads every page of the search, whatever Result limit says' do
      second_page = "#{messages_url}?%24skiptoken=page-two"
      stub_leg({ '$search' => '"invoice"' },
               { value: [{ id: 'first' }, { id: 'second' }], '@odata.nextLink': second_page })
      stub_request(:get, messages_url).with(query: { '$skiptoken' => 'page-two' })
                                      .to_return(status: 200, body: { value: [{ id: 'third' }] }.to_json)
      stub_leg({ '$filter' => filter }, { value: [{ id: 'third' }] })
      result = call_helper(:intersect_search_and_filter, messages_url, '"invoice"', filter, rules)
      expect(result[:messages]).to eq([{ 'id' => 'third' }])
    end

    describe 'the filter pages after the search' do
      let(:filter_second_page) { "#{messages_url}?%24skiptoken=filter-two" }

      before(:each) do
        stub_request(:get, messages_url).with(query: { '$skiptoken' => 'filter-two' })
                                        .to_return(status: 200, body: { value: [{ id: 'second' }] }.to_json)
      end

      it 'stops reading once it has seen every id the search found, and reports nothing left behind' do
        stub_leg({ '$search' => '"invoice"' }, { value: [{ id: 'first' }] })
        stub_leg({ '$filter' => filter }, { value: [{ id: 'first' }], '@odata.nextLink': filter_second_page })
        result = call_helper(:intersect_search_and_filter, messages_url, '"invoice"', filter, rules)
        expect(result).to eq({ messages: [{ 'id' => 'first' }], left_unread: false })
        expect(a_request(:get, messages_url).with(query: { '$skiptoken' => 'filter-two' })).not_to have_been_made
      end

      it 'reads on to the page where the last id turns up, and not one page further' do
        filter_third_page = "#{messages_url}?%24skiptoken=filter-three"
        stub_leg({ '$search' => '"invoice"' }, { value: [{ id: 'first' }, { id: 'second' }] })
        stub_leg({ '$filter' => filter }, { value: [{ id: 'first' }], '@odata.nextLink': filter_second_page })
        stub_request(:get, messages_url).with(query: { '$skiptoken' => 'filter-two' })
                                        .to_return(status: 200, body: { value: [{ id: 'second' }],
                                                                        '@odata.nextLink': filter_third_page, }.to_json)
        result = call_helper(:intersect_search_and_filter, messages_url, '"invoice"', filter, rules)
        expect(result).to eq({ messages: [{ 'id' => 'first' }, { 'id' => 'second' }], left_unread: false })
        expect(a_request(:get, messages_url).with(query: { '$skiptoken' => 'filter-three' })).not_to have_been_made
      end
    end
  end

  describe 'read_search_pages' do
    let(:messages_url) { "https://graph.microsoft.com/v1.0/users/#{mailbox}/messages" }

    def stub_search_page(token, rows, next_token: nil)
      body = { value: rows.map { |id| { id: id } } }
      body[:'@odata.nextLink'] = "#{messages_url}?%24skiptoken=#{next_token}" if next_token
      stub_request(:get, messages_url).with(query: { '$skiptoken' => token }).to_return(status: 200, body: body.to_json)
    end

    # Graph pages a filtered query with $skip, so mail that arrives during the read shifts the window and a
    # page can repeat rows the one before it held. Result limit counts messages, not rows.
    it 'counts a message seen on two pages once against Result limit' do
      first_page = { value: [{ id: 'a' }, { id: 'b' }], '@odata.nextLink': "#{messages_url}?%24skiptoken=two" }
      stub_request(:get, messages_url).with(query: hash_including('$filter' => 'isRead eq false'))
                                      .to_return(status: 200, body: first_page.to_json)
      stub_search_page('two', %w[a b], next_token: 'three')
      stub_search_page('three', %w[c])
      result = call_helper(:read_search_pages, messages_url, { '$filter': 'isRead eq false' }, 10,
                           { limit: 3, ids: nil, to_address: nil, mailbox: mailbox })
      expect(result).to eq({ messages: [{ 'id' => 'a' }, { 'id' => 'b' }, { 'id' => 'c' }], requests: 3,
                             left_unread: false, })
    end
  end

  describe 'send_mail_url' do
    it 'builds the send mail endpoint of a mailbox' do
      expect(call_helper(:send_mail_url, mailbox))
        .to eq("https://graph.microsoft.com/v1.0/users/#{mailbox}/sendMail")
    end

    it 'keeps an external user principal name in one segment of the send mail path' do
      expect(call_helper(:send_mail_url, 'guest_gmail.com#EXT#@contoso.com'))
        .to eq('https://graph.microsoft.com/v1.0/users/guest_gmail.com%23EXT%23@contoso.com/sendMail')
    end

    # The assertion: mailbox_for fails the job before this helper is reached, so a blank mailbox here is a
    # state that cannot happen while the connector is correct.
    it 'raises when it is asked to build a send mail URL with no mailbox' do
      expect { call_helper(:send_mail_url, '   ') }
        .to raise_error(IPaaS::Error, 'send mail URL was built without a mailbox')
    end
  end

  describe 'recipients_for' do
    it 'builds one Graph recipient per address' do
      expect(call_helper(:recipients_for, ['adele@contoso.com', 'alex@contoso.com'], 'To'))
        .to eq([{ emailAddress: { address: 'adele@contoso.com' } },
                { emailAddress: { address: 'alex@contoso.com' } },])
    end

    it 'drops a mailto prefix and the whitespace around a recipient' do
      expect(call_helper(:recipients_for, ['  MAILTO:adele@contoso.com '], 'To'))
        .to eq([{ emailAddress: { address: 'adele@contoso.com' } }])
    end

    it 'returns an empty list when the step mapped no address at all' do
      expect(call_helper(:recipients_for, nil, 'Cc')).to eq([])
    end

    # Send Email sends every To, Cc and Bcc address through the same helper the Mailbox field uses.
    # Without the label the builder is told to fix Mailbox when the bad value is in Cc.
    it 'names the recipient field, not Mailbox, when a Cc address holds a slash' do
      expect { call_helper(:recipients_for, ['contoso/adele'], 'Cc recipients') }
        .to raise_error(IPaaS::Job::FailJob,
                        %r{\ACc recipients 'contoso/adele' holds a slash, a backslash or a percent sign})
    end

    # The input mapping only checks that a required list holds a value, so a list holding one empty string
    # passes it and arrives here.
    it 'fails the job and names the field when one address is empty' do
      expect { call_helper(:recipients_for, ['adele@contoso.com', '  '], 'Cc') }
        .to raise_error(IPaaS::Job::FailJob, /Cc holds an empty address/)
    end

    it 'fails the job and quotes the value when an address has nothing after the at sign' do
      expect { call_helper(:recipients_for, ['not-an-email@'], 'To') }
        .to raise_error(IPaaS::Job::FailJob, /To holds 'not-an-email@', which is not an email address/)
    end

    it 'refuses a display name wrapped around an address' do
      expect { call_helper(:recipients_for, ['"Adele V" <adele@contoso.com>'], 'Bcc') }
        .to raise_error(IPaaS::Job::FailJob, /Bcc holds .*Write the address on its own/)
    end
  end

  describe 'body_type_for' do
    it 'takes the body type the step supplied' do
      expect(call_helper(:body_type_for, 'html')).to eq('html')
    end

    it 'falls back to text when the step left the body type empty' do
      expect(call_helper(:body_type_for, nil)).to eq('text')
    end
  end

  describe 'message_ids_for' do
    # The shape a live mailbox returns: base64url, no character outside the pattern, about 150 long.
    let(:graph_message_id) do
      'AAMkAGQzOGVlNTJkLWMzMzYtNDgzNi04ZWQyLWZhMDc5YmJmNzY4NQBGAAAAAACNg_CfyiTySaMnuVjjxVl2BwBIzshfbRZ8SaUL' \
        'yxi-fjtsAAAAAAEMAABIzshfbRZ8SaULyxi-fjtsAACBu30fAAA='
    end

    def batch_of(size)
      (1..size).map { |number| "AAMkAGQzOGVlNTJkLWMzMzYtNDgzNi04ZWQyLWZhMDc5YmJmNzY4NQBGAAAAAAB#{number}" }
    end

    it 'strips each id and drops the entries that carry nothing' do
      expect(call_helper(:message_ids_for, ["  #{graph_message_id}  ", '', '   ', nil])).to eq([graph_message_id])
    end

    # Microsoft runs the requests inside one batch in an order of its own, so the same id sent twice races
    # itself: one copy moves the message and the other answers 404 for a message that did move.
    it 'sends a message named twice only once' do
      expect(call_helper(:message_ids_for, [graph_message_id, graph_message_id])).to eq([graph_message_id])
    end

    # An empty list is refused by the input mapping before the run block, because Message IDs is required and
    # [] is blank. A list holding only empty entries is not blank, so it arrives here and has to be refused.
    it 'fails the job when every entry carries nothing' do
      expect { call_helper(:message_ids_for, ['  ', '']) }
        .to raise_error(IPaaS::Job::FailJob, /No message ids to move/)
    end

    it 'fails the job when more ids are passed than one batch holds' do
      expect { call_helper(:message_ids_for, batch_of(MicrosoftOutlookConnector::BATCH_REQUEST_LIMIT + 1)) }
        .to raise_error(IPaaS::Job::FailJob,
                        /Microsoft moves at most #{MicrosoftOutlookConnector::BATCH_REQUEST_LIMIT} messages/o)
    end

    it 'admits exactly as many ids as one batch holds' do
      exactly_enough = batch_of(MicrosoftOutlookConnector::BATCH_REQUEST_LIMIT)
      expect(call_helper(:message_ids_for, exactly_enough)).to eq(exactly_enough)
    end

    it 'fails the job on an id copied from a browser address bar' do
      expect { call_helper(:message_ids_for, ['AAMkAGQzOGVlNTJk%2FyiTySaMn%2BuVjjxVl2']) }
        .to raise_error(IPaaS::Job::FailJob, /is not a Microsoft Graph message id/)
    end
  end

  describe 'move_request_url' do
    # The url of a request inside a batch is read from the version root. graph_url would prepend /v1.0, and
    # Microsoft then answers 400 'Resource not found for the segment v1.0' on every row inside an outer 200.
    it 'names the message without the API version a Graph URL carries' do
      expect(call_helper(:move_request_url, mailbox, 'AAMkAGQz='))
        .to eq("/users/#{mailbox}/messages/AAMkAGQz=/move")
    end

    it 'escapes the mailbox, so an external user principal name stays one segment' do
      expect(call_helper(:move_request_url, 'guest_gmail.com#EXT#@contoso.com', 'AAMkAGQz='))
        .to eq('/users/guest_gmail.com%23EXT%23@contoso.com/messages/AAMkAGQz=/move')
    end
  end

  describe 'move_batch_body' do
    def requests_in(body)
      JSON.parse(body)['requests']
    end

    def body_for(message_ids, folder = 'archive')
      call_helper(:move_batch_body, mailbox, message_ids, folder)
    end

    it 'hands over a string, because http_post refuses a hash body' do
      expect(body_for(['AAMkAGQz='])).to be_a(String)
    end

    it 'numbers the sub-requests from zero and names one message in each' do
      expect(requests_in(body_for(%w[AAMkAGQz= AAMkAGQ0=])).map { |request| [request['id'], request['url']] })
        .to eq([['0', "/users/#{mailbox}/messages/AAMkAGQz=/move"],
                ['1', "/users/#{mailbox}/messages/AAMkAGQ0=/move"],])
    end

    # A sub-request with no Content-Type fails the WHOLE batch with an outer 400, so no message moves at all.
    it 'marks every sub-request as JSON' do
      expect(requests_in(body_for(%w[AAMkAGQz= AAMkAGQ0=])).map { |request| request['headers'] })
        .to eq([{ 'Content-Type' => 'application/json' }, { 'Content-Type' => 'application/json' }])
    end

    it 'posts the destination folder as the destinationId of every sub-request' do
      requests = requests_in(body_for(%w[AAMkAGQz= AAMkAGQ0=], 'deleteditems'))
      expect(requests.map { |request| [request['method'], request['body']] })
        .to eq([['POST', { 'destinationId' => 'deleteditems' }],
                ['POST', { 'destinationId' => 'deleteditems' }],])
    end
  end

  describe 'move_results' do
    def answer(id, status, body)
      { 'id' => id, 'status' => status, 'body' => body }
    end

    def moved(id, new_message_id)
      answer(id, 201, { 'id' => new_message_id })
    end

    let(:not_found) do
      { 'error' => { 'code' => 'ErrorItemNotFound',
                     'message' => 'The specified object was not found in the store.', } }
    end

    # Microsoft answers the rows in an order of its own. Twelve sub-requests sent as '1' to '12' came back
    # as 12, 3, 1, 2, 4 and the rest, so a positional read blames the wrong message for a failure.
    it 'reads each answer by the sub-request it belongs to, whatever order they arrive in' do
      rows = [moved('1', 'NEW-B'), moved('0', 'NEW-A')]
      expect(call_helper(:move_results, %w[A B], { 'responses' => rows }))
        .to eq([{ message_id: 'A', new_message_id: 'NEW-A', moved: true, error: nil },
                { message_id: 'B', new_message_id: 'NEW-B', moved: true, error: nil },])
    end

    it 'fails one row and moves the rest when Microsoft refuses one message' do
      rows = [answer('1', 404, not_found), moved('0', 'NEW-A')]
      expect(call_helper(:move_results, %w[A B], { 'responses' => rows }))
        .to eq([{ message_id: 'A', new_message_id: 'NEW-A', moved: true, error: nil },
                { message_id: 'B', new_message_id: nil, moved: false,
                  error: 'Microsoft Graph returned HTTP 404 ErrorItemNotFound: The specified object was not ' \
                         'found in the store.', },])
    end

    it 'reports a message Microsoft answered nothing for as not moved' do
      expect(call_helper(:move_results, ['A'], { 'responses' => [] }))
        .to eq([{ message_id: 'A', new_message_id: nil, moved: false,
                  error: 'Microsoft Graph returned no answer for this request.', }])
    end

    # The assertion: the ids that built the batch are the ids the answers are read back with, so an answer
    # naming a sub-request this batch never sent means the two lists are not the same list.
    it 'raises when an answer names a sub-request the batch never sent' do
      rows = [moved('0', 'NEW-A'), moved('7', 'NEW-H')]
      expect { call_helper(:move_results, ['A'], { 'responses' => rows }) }
        .to raise_error(IPaaS::Error, /answered request '7', which this batch never sent/)
    end

    # The assertion: a move answers with the moved message itself, so a success that names no new id is a
    # state that cannot happen while Graph keeps its contract. The new id is the only way a later step
    # reaches the message again, so a nil would travel into the runbook with nothing anywhere erroring.
    it 'raises when a moved message comes back without its new id' do
      expect { call_helper(:move_results, ['A'], { 'responses' => [answer('0', 201, {})] }) }
        .to raise_error(IPaaS::Error, /moved message 'A' without naming its new id/)
    end

    # The assertion: Graph answers a batch with a list of rows, so anything else is a state that cannot
    # happen while Graph keeps its contract.
    it 'raises when the batch answer carries no list of responses' do
      expect { call_helper(:move_results, ['A'], { 'responses' => nil }) }
        .to raise_error(IPaaS::Error, 'Microsoft Graph returned a batch answer whose responses are not a list')
    end
  end

  describe 'describe_batch_failure' do
    it 'quotes the status, the code and the message of one refused row' do
      refused = { 'status' => 400,
                  'body' => { 'error' => { 'code' => 'ErrorInvalidIdMalformed',
                                           'message' => 'Id is malformed.', } }, }
      expect(call_helper(:describe_batch_failure, refused))
        .to eq('Microsoft Graph returned HTTP 400 ErrorInvalidIdMalformed: Id is malformed.')
    end

    it 'names the status when a refused row carries no error object' do
      expect(call_helper(:describe_batch_failure, { 'status' => 500, 'body' => {} }))
        .to eq('Microsoft Graph returned HTTP 500 : no error details')
    end
  end

  describe 'subscription_resource' do
    it 'names the mailbox and the folder the subscription will watch' do
      expect(call_helper(:subscription_resource, mailbox, 'archive'))
        .to eq("users/#{mailbox}/mailFolders/archive/messages")
    end

    it 'watches the inbox when the trigger leaves the folder empty' do
      expect(call_helper(:subscription_resource, mailbox, nil))
        .to eq("users/#{mailbox}/mailFolders/inbox/messages")
    end

    # The guard: Microsoft checks the notification endpoint before it checks the mailbox, so it answers a
    # wrong mailbox, a wrong folder and an iPaaS it cannot reach with the same words. A mailbox the
    # connector can see is empty is one fault it can still name. The trigger field is required, and
    # runbooks_controller.rb:236 calls provision! on the trigger without asking whether it is configured.
    it 'fails the job when the trigger carries no mailbox' do
      expect { call_helper(:subscription_resource, '   ', 'inbox') }
        .to raise_error(IPaaS::Job::FailJob, /has no mailbox to watch/)
    end
  end

  describe 'notifications' do
    let(:notification) do
      { 'subscriptionId' => 'sub-1', 'clientState' => 'state-1', 'resourceData' => { 'id' => 'AAMk-1' } }
    end

    # Microsoft batches notifications into one request, and the caller decides what to do with each.
    it 'reads every notification of the batch, not only the first' do
      second = notification.merge('resourceData' => { 'id' => 'AAMk-2' })
      expect(call_helper(:notifications, { value: [notification, second] }.to_json))
        .to eq([notification, second])
    end

    # A body that parses to nothing is Microsoft asking about a resource this trigger does not care
    # about, which is ordinary and is discarded below. A body that does not parse at all is something
    # other than Microsoft calling the endpoint, and the job log is where that belongs.
    it 'fails the job, naming the reason, when the body is not JSON' do
      expect { call_helper(:notifications, 'not json at all') }
        .to raise_error(IPaaS::Job::FailJob, /This endpoint answers Microsoft Graph, which sends JSON/)
    end

    # The guard: an empty batch is well formed, so it is discarded rather than failed. A discard
    # answers 200 and starts no job, where a failure would be a job nobody asked for.
    it 'discards a request whose batch holds nothing' do
      expect { call_helper(:notifications, { value: [] }.to_json) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent, /carried no Microsoft change notification/)
    end

    # A mixed batch, not one bad entry on its own: a guard that read only the first entry would let
    # this straight through, so the example would pass without the thing it is named for.
    it 'discards a batch that mixes a notification with something that is not one' do
      expect { call_helper(:notifications, { value: [notification, 'not a notification'] }.to_json) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent, /carried no Microsoft change notification/)
    end
  end

  describe 'trusted_notifications' do
    let(:notification) { { 'clientState' => 'state-1', 'resourceData' => { 'id' => 'AAMk-1' } } }

    it 'lets through a batch whose notifications all carry the client state this trigger set' do
      batch = [notification, notification]
      expect(call_helper(:trusted_notifications, batch, 'state-1')).to eq(batch)
    end

    # The guard: anyone can post to the endpoint, and the client state is the only proof a request came
    # from the subscription this trigger created.
    it 'discards a notification whose client state is not the one this trigger set' do
      expect { call_helper(:trusted_notifications, [notification], 'state-2') }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent, /client state this trigger did not set/)
    end

    # Checking one notification and trusting the batch around it would let a forged one ride in behind
    # a signed one, which is the whole point of putting the secret on every notification.
    it 'discards the whole batch when only one notification carries the wrong client state' do
      forged = notification.merge('clientState' => 'state-2')
      expect { call_helper(:trusted_notifications, [notification, forged], 'state-1') }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent, /client state this trigger did not set/)
    end

    it 'discards every notification while the stored row carries no client state' do
      expect { call_helper(:trusted_notifications, [notification], nil) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent, /client state this trigger did not set/)
    end
  end

  describe 'notification_message_id' do
    it 'reads the message id out of the resource data' do
      expect(call_helper(:notification_message_id, { 'resourceData' => { 'id' => 'AAMk-1' } })).to eq('AAMk-1')
    end

    # The assertion: a notification of a created message names the message, so one without an id is a
    # state that cannot happen while Graph keeps its contract. Without it the output schema refuses the
    # row afterwards with 'Output invalid', which names no cause.
    it 'raises when a notification carries no message id' do
      expect { call_helper(:notification_message_id, { 'resourceData' => {} }) }
        .to raise_error(IPaaS::Error, 'Microsoft Graph sent a change notification with no message id')
    end

    # Digging into a String raises TypeError, which is neither a failure nor a discard and would leave
    # the endpoint answering 500.
    it 'raises when the resource data is not an object' do
      expect { call_helper(:notification_message_id, { 'resourceData' => 'AAMk-1' }) }
        .to raise_error(IPaaS::Error, 'Microsoft Graph sent a change notification with no message id')
    end
  end

  describe 'created_subscription' do
    it 'reads the subscription out of the 201 a create is answered with, which parse_graph would refuse' do
      answer = graph_response(201, { id: subscription_id, expirationDateTime: '2026-09-28T07:56:02Z' }.to_json)
      expect(call_helper(:created_subscription, answer)['id']).to eq(subscription_id)
    end

    it 'takes a 200 carrying a subscription as a create that worked too' do
      answer = graph_response(200, { id: subscription_id }.to_json)
      expect(call_helper(:created_subscription, answer)['id']).to eq(subscription_id)
    end

    it 'fails the row when Microsoft answers a create with no subscription id, so no unusable id reaches the store' do
      answer = graph_response(201, { expirationDateTime: '2026-09-28T07:56:02Z' }.to_json)
      expect { call_helper(:created_subscription, answer) }
        .to raise_error(IPaaS::Job::FailJob, /created a subscription with no subscription id. The next run removes it/)
    end

    it 'fails the row when the id Microsoft answers with is not a subscription id, which could never be renewed' do
      answer = graph_response(201, { id: 'not-a-subscription-id' }.to_json)
      expect { call_helper(:created_subscription, answer) }
        .to raise_error(IPaaS::Job::FailJob, /created a subscription with no subscription id/)
    end

    it 'fails the job and names the endpoint check when Microsoft refuses the create' do
      body = { error: { code: 'ValidationError',
                        message: 'Subscription validation request failed.', } }.to_json
      expect { call_helper(:created_subscription, graph_response(400, body)) }
        .to raise_error(IPaaS::Job::FailJob, /checks that it can reach the trigger before it checks anything else/)
    end

    it 'fails the job when a create is answered with no body at all' do
      expect { call_helper(:created_subscription, graph_response(201, nil)) }
        .to raise_error(IPaaS::Job::FailJob, /returned a subscription that is not JSON/)
    end
  end

  describe 'stored_subscription_id and delete_subscription' do
    let(:delete_url) { "https://graph.microsoft.com/v1.0/subscriptions/#{subscription_id}" }

    before(:each) do
      stub_request(:post, token_url)
        .to_return(status: 200, body: { access_token: 'outlook-token', expires_in: 3599 }.to_json)
    end

    it 'reads the id out of the row the store gives back' do
      expect(call_helper(:stored_subscription_id, { 'id' => subscription_id })).to eq(subscription_id)
    end

    # The guard: Microsoft answers a delete of an id that is not a GUID with 400 InvalidRequest, not 404,
    # so a corrupted row would fail deprovision every time and the solution could never be removed.
    it 'reads no id out of a row whose id is not a subscription id' do
      expect(call_helper(:stored_subscription_id, { 'id' => 'sub-123' })).to be_nil
    end

    it 'asks Microsoft to delete the subscription the row names' do
      stub_request(:delete, delete_url).to_return(status: 204, body: '')
      expect(call_helper(:delete_subscription, { 'id' => subscription_id })).to eq(subscription_id)
      expect(a_request(:delete, delete_url)).to have_been_requested
    end

    it 'takes a subscription Microsoft no longer has as already gone' do
      body = { error: { code: 'ResourceNotFound', message: 'The object was not found.' } }.to_json
      stub_request(:delete, delete_url).to_return(status: 404, body: body)
      expect(call_helper(:delete_subscription, { 'id' => subscription_id })).to eq(subscription_id)
    end

    it 'sends no delete for a stored id that is not a subscription id' do
      expect(call_helper(:delete_subscription, { 'id' => 'sub-123' })).to be_nil
      expect(a_request(:delete, /graph\.microsoft\.com/)).not_to have_been_requested
    end

    it 'fails the job when Microsoft refuses the delete' do
      body = { error: { code: 'ErrorAccessDenied', message: 'Access is denied.' } }.to_json
      stub_request(:delete, delete_url).to_return(status: 403, body: body)
      expect { call_helper(:delete_subscription, { 'id' => subscription_id }) }
        .to raise_error(IPaaS::Job::FailJob, /HTTP 403 ErrorAccessDenied/)
    end

    # A failure here would leave the subscription behind for good, so a Microsoft that is briefly away
    # asks for another round instead, as List Emails does.
    it 'asks for another round when Microsoft is briefly away' do
      stub_request(:delete, delete_url).to_return(status: 503, body: 'service unavailable')
      expect { call_helper(:delete_subscription, { 'id' => subscription_id }) }
        .to raise_error(IPaaS::Job::RescheduleJob, /Microsoft API not available/)
    end
  end

  describe 'authenticate' do
    let(:request) do
      Faraday::Request.create(:get) { |built| built.headers = {} }
    end

    it 'puts a bearer token from the tenant token endpoint on the request' do
      stub_request(:post, token_url)
        .with(body: hash_including('client_id' => 'client-abc', 'client_secret' => 'secret-def',
                                   'grant_type' => 'client_credentials',
                                   'scope' => 'https://graph.microsoft.com/.default'))
        .to_return(status: 200, body: { access_token: 'outlook-token', token_type: 'Bearer',
                                        expires_in: 3599, }.to_json)
      outbound_connection.authenticate_request(request)
      expect(request.headers['Authorization']).to eq('Bearer outlook-token')
    end

    it 'asks the China login host when China is selected' do
      outbound_connection.config[:cloud] = 'China'
      china_url = "https://login.chinacloudapi.cn/#{tenant_id}/oauth2/v2.0/token"
      stub_request(:post, china_url)
        .with(body: hash_including('scope' => 'https://microsoftgraph.chinacloudapi.cn/.default'))
        .to_return(status: 200, body: { access_token: 'china-token', expires_in: 3599 }.to_json)
      outbound_connection.authenticate_request(request)
      expect(request.headers['Authorization']).to eq('Bearer china-token')
    end

    it 'reports a customer credentials error when Microsoft refuses the secret' do
      stub_request(:post, token_url)
        .to_return(status: 401, body: { error: 'invalid_client',
                                        error_description: 'AADSTS7000215', }.to_json)
      expect { outbound_connection.authenticate_request(request) }
        .to raise_error(IPaaS::Job::Outbound::CustomerCredentialsError, /invalid_client/)
    end
  end

  describe 'config_tester' do
    it 'reads the inbox of the default mailbox and says so' do
      stub_request(:get, inbox_url).to_return(status: 200, body: { id: 'inbox-id' }.to_json)
      expect(outbound_connection.config_tester)
        .to eq({ status: :success, message: "Connection successful. Read the inbox of #{mailbox}." })
    end

    # config_tester resolves the connection config again before it runs, so a value set on the resolved
    # hash inside an example is discarded. These two cases build the connection they need instead.
    context 'when the connection carries no default mailbox' do
      let(:outbound_connection_config) { { credentials: credentials_for, cloud: 'Global' } }

      it 'only fetches a token, and says that a mailbox would be checked too' do
        no_mailbox = 'Microsoft accepted the credentials. Set a Default mailbox to also check mailbox access.'
        expect(outbound_connection.config_tester).to eq({ status: :success, message: no_mailbox })
        expect(a_request(:get, inbox_url)).not_to have_been_requested
      end
    end

    it 'reports failed with Microsoft own words when the mailbox does not exist' do
      stub_request(:get, inbox_url)
        .to_return(status: 404,
                   body: { error: { code: 'ErrorInvalidUser',
                                    message: "The requested user '#{mailbox}' is invalid.", } }.to_json)
      expect(outbound_connection.config_tester)
        .to eq({ status: :failed,
                 message: "Microsoft Graph returned HTTP 404 ErrorInvalidUser: The requested user '#{mailbox}' " \
                          'is invalid.', })
    end

    it 'reports failed when the application has no permission on the mailbox' do
      stub_request(:get, inbox_url)
        .to_return(status: 403, body: { error: { code: 'ErrorAccessDenied', message: 'Access is denied.' } }.to_json)
      expect(outbound_connection.config_tester)
        .to eq({ status: :failed, message: 'Microsoft Graph returned HTTP 403 ErrorAccessDenied: Access is denied.' })
    end

    it 'reports error on a status we did not plan for' do
      stub_request(:get, inbox_url).to_return(status: 500, body: 'boom')
      expect(outbound_connection.config_tester).to eq({ status: :error,
                                                        message: 'Microsoft Graph returned HTTP 500 : boom', })
    end

    it 'reports failed with Microsoft own words when it refuses the client secret' do
      stub_request(:post, token_url)
        .to_return(status: 401, body: { error: 'invalid_client', error_description: 'AADSTS7000215' }.to_json)
      answer = outbound_connection.config_tester
      expect(answer[:status]).to eq(:failed)
      expect(answer[:message]).to match(/invalid_client/)
    end

    context 'when the tenant is a sign-in placeholder' do
      let(:outbound_connection_config) do
        { credentials: credentials_for('common'), cloud: 'Global', default_mailbox: mailbox }
      end

      it 'refuses before it calls Microsoft' do
        expect(outbound_connection.config_tester[:message]).to match(/sign-in placeholder/)
        expect(a_request(:post, token_url)).not_to have_been_requested
      end
    end
  end
  describe 'message_id_for' do
    it 'hands back an id an earlier step returned' do
      expect(call_helper(:message_id_for, '  AAMkAGQz=  ')).to eq('AAMkAGQz=')
    end

    # The assertion: an id carrying percent escapes was copied from somewhere that had already
    # encoded it. Encoding it again turns %2F into %252F and Graph answers 404 for a real message.
    it 'refuses an id that is already percent encoded' do
      expect { call_helper(:message_id_for, 'AAMk%2Ffake') }
        .to raise_error(IPaaS::Job::FailJob, /already URL encoded/)
    end
  end

  describe 'body_preference' do
    it 'turns the name the builder picked into the header value Microsoft reads' do
      expect(call_helper(:body_preference, 'Plain text')).to eq('outlook.body-content-type="text"')
      expect(call_helper(:body_preference, 'HTML')).to eq('outlook.body-content-type="html"')
    end

    # The field offers a fixed list, so only a blank value can reach here. A blank one must not build
    # a header with nothing after the equals sign: the platform refuses a header value that is nil.
    it 'falls back to the default when the format arrives blank' do
      expect(call_helper(:body_preference, '')).to eq('outlook.body-content-type="html"')
    end

    it 'refuses a format that is not one of the offered values' do
      expect { call_helper(:body_preference, 'Markdown') }
        .to raise_error(IPaaS::Job::FailJob, /is not one of HTML, Plain text/)
    end
  end

  describe 'message_url' do
    it 'names the message directly, with no folder in the path' do
      expect(call_helper(:message_url, 'adele@contoso.com', 'AAMkAGQz='))
        .to eq('https://graph.microsoft.com/v1.0/users/adele@contoso.com/messages/AAMkAGQz=')
    end

    it 'escapes a character in the id that would otherwise change the path' do
      expect(call_helper(:message_url, 'adele@contoso.com', 'AA/BB')).to end_with('messages/AA%2FBB')
    end
  end

  describe 'message_detail' do
    it 'adds the body and the format Microsoft used to everything the summary already carries' do
      detail = call_helper(:message_detail,
                           { 'id' => 'AAMkAGQz=', 'subject' => 'Hello',
                             'body' => { 'content' => '<p>hi</p>', 'contentType' => 'html' }, })
      expect(detail[:message_id]).to eq('AAMkAGQz=')
      expect(detail[:subject]).to eq('Hello')
      expect(detail[:body]).to eq('<p>hi</p>')
      expect(detail[:body_format]).to eq('html')
    end

    # Graph sends no body object at all on some messages, and a null content on others.
    it 'answers with an empty body rather than dying when Graph sends no body' do
      detail = call_helper(:message_detail, { 'id' => 'AAMkAGQz=' })
      expect(detail[:body]).to eq('')
      expect(detail[:body_format]).to eq('')
    end

    # The assertion lives in message_summary and must survive the wider mapping.
    it 'still refuses a message with no id' do
      expect { call_helper(:message_detail, { 'subject' => 'Hello' }) }
        .to raise_error(IPaaS::Error, 'Microsoft Graph returned a message with no id')
    end
  end
end

require 'spec_helper'

describe 'Microsoft Outlook Folder options', :action, :microsoft_outlook do
  let(:action_template_id) { '01a0d336-be94-7be9-9d8b-3bd3998d055b' }
  let(:delta_url) { "https://graph.microsoft.com/v1.0/users/#{mailbox}/mailFolders/delta" }
  let(:next_page_url) { "#{delta_url}?$skiptoken=page-two" }

  def folder_row(id, display_name, parent: nil, well_known: nil)
    { id: id, displayName: display_name, parentFolderId: parent, wellKnownName: well_known }
  end

  # The delta collection answers a bare URL, so these stubs carry no query either. A stub registered on
  # a bare URL matches only a request that carries no query, which is what the first example rests on.
  def stub_folders(rows, url: delta_url, next_link: nil)
    body = { value: rows }
    body[:'@odata.nextLink'] = next_link if next_link
    stub_request(:get, url).to_return(status: 200, body: body.to_json,
                                      headers: { 'Content-Type' => 'application/json' })
  end

  def folder_field
    action_template.input_schema.fields.detect { |field| field.id == :folder }
  end

  def offered(**dependencies)
    folder_field.call_function(:options, outbound_connection, **dependencies)
  end

  # An unmapped field is filled from the schema's generated example, so a run example names every field
  # (connector-sdk/AGENTS.md, "run_action with no argument does not mean 'no input'").
  def input(**overrides)
    { mailbox: nil, folder: nil, page_size: nil, page_limit: 1, all_pages: false }.merge(overrides)
  end

  def messages_url(folder)
    "https://graph.microsoft.com/v1.0/users/#{mailbox}/mailFolders/#{folder}/messages"
  end

  describe 'what the list asks Microsoft for' do
    # Graph refuses both halves of a query on this collection. `$top` answers HTTP 400
    # ErrorInvalidUrlQuery: "The following parameters are not supported with change tracking over the
    # 'Folders' resource", and naming wellKnownName in `$select` answers HTTP 400 BadRequest: "Could not
    # find a property named 'wellKnownName'". A bare URL matcher does not match a request carrying a
    # query, so this goes red the moment a select or a page size is added back.
    it 'asks the delta collection with no query at all, because Graph refuses $top and $select on it' do
      stub_folders([folder_row('id-inbox', 'Inbox', well_known: 'inbox')])

      expect(offered).to eq([{ id: 'inbox', label: 'Inbox' }])
      expect(a_request(:get, delta_url)).to have_been_made.once
      expect(a_request(:get, %r{mailFolders/delta\?})).not_to have_been_made
    end

    # An exact query, not a subset: the point is that nothing of the connector's own is appended to the
    # link Graph wrote, and a subset match would still pass with a select and a page size added.
    it 'follows the delta next link exactly as Graph wrote it' do
      stub_folders([folder_row('id-inbox', 'Inbox', well_known: 'inbox')], next_link: next_page_url)
      stub_folders([folder_row('id-sales', 'Sales', parent: 'id-inbox')], url: next_page_url)

      expect(offered.map { |option| option[:id] }).to eq(%w[inbox id-sales])
      expect(a_request(:get, delta_url).with(query: { '$skiptoken' => 'page-two' })).to have_been_made
    end
  end

  describe 'the mailbox the list reads' do
    # A Mailbox that carries a value from another step reaches the block as an empty string: the designer
    # sends the literal alone and turns anything else into one, and the platform then drops it. The hint
    # on the field promises the connection's Default mailbox in that case, and this is that promise.
    it 'reads the connection default mailbox when Mailbox arrives as an empty string' do
      stub_folders([folder_row('id-inbox', 'Inbox', well_known: 'inbox')])

      expect(offered(mailbox: '')).to eq([{ id: 'inbox', label: 'Inbox' }])
      expect(a_request(:get, delta_url)).to have_been_made.once
    end

    it 'says what Microsoft said when the mailbox does not exist' do
      stub_request(:get, delta_url)
        .to_return(status: 404,
                   body: { error: { code: 'ErrorInvalidUser',
                                    message: "The requested user 'adele@contoso.com' is invalid.", } }.to_json)

      expect { offered }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 404 ErrorInvalidUser: ' \
                        "The requested user 'adele@contoso.com' is invalid.")
    end

    it 'says what Microsoft said, and names the mailbox, when the app may not read it' do
      stub_request(:get, delta_url)
        .to_return(status: 403,
                   body: { error: { code: 'ErrorAccessDenied',
                                    message: 'Access is denied. Check credentials and try again.', } }.to_json)

      expect { offered }
        .to raise_error(IPaaS::Job::FailJob,
                        "Microsoft Graph returned HTTP 403 ErrorAccessDenied while reading mailbox '#{mailbox}': " \
                        'Access is denied. Check credentials and try again.')
    end
  end

  describe 'what the builder picks and what the step then reads' do
    # The picker and the Folder field share one idea of what a folder id is, and nothing else holds them
    # together: the list builds an id, the field validates it, and the run block puts it in a URL. This
    # takes an id straight off the list and drives it through both.
    it 'offers an id the Folder field accepts and the run block reads that folder with' do
      folder_id = 'AAMkAGQzLTIxNzgtNDc1YS1iYTU5LTA0NGRmMzE4MTAtQUFBPQ=='
      stub_folders([folder_row('id-inbox', 'Inbox', well_known: 'inbox'),
                    folder_row(folder_id, 'Sales', parent: 'id-inbox'),])
      chosen = offered.detect { |option| option[:label] == 'Inbox / Sales' }
      stub_request(:get, messages_url(chosen[:id])).with(query: hash_including({}))
                                                   .to_return(status: 200, body: { value: [] }.to_json)

      expect(run_action(input(folder: chosen[:id]))[:messages]).to eq([])
      expect(a_request(:get, messages_url(folder_id)).with(query: hash_including({}))).to have_been_made
    end
  end

  describe 'display names Outlook allows and a label cannot tame' do
    # Graph accepted every one of these in a real mailbox: a 200-character name, a name holding a tab and
    # a run of spaces, and a name starting with an emoji. The label is the display name as Graph spelled
    # it, so none of them is shortened, escaped or trimmed on the way to the dropdown.
    it 'puts an awkward display name into the label exactly as Graph spelled it' do
      long_name = 'L' * 200
      stub_folders([folder_row('id-inbox', 'Inbox', well_known: 'inbox'),
                    folder_row('id-long', long_name, parent: 'id-inbox'),
                    folder_row('id-tabs', "Tabs\tand  spaces", parent: 'id-inbox'),
                    folder_row('id-triage', '📬 Triage', parent: 'id-inbox'),])

      expect(offered.map { |option| option[:label] })
        .to contain_exactly('Inbox', "Inbox / #{long_name}", "Inbox / Tabs\tand  spaces", 'Inbox / 📬 Triage')
    end

    # A forward slash is legal inside a display name, so the separator between two names also occurs
    # inside one. A real mailbox took a folder named "Sales / EMEA" beside a folder named "Sales" holding
    # a folder named "EMEA", and both read as "Inbox / Sales / EMEA". The label is ambiguous. What the
    # step stores is not: the ids stay apart, so the folder the runbook reads is still exactly one.
    it 'shows two different folders under one label and still offers each its own id' do
      stub_folders([folder_row('id-inbox', 'Inbox', well_known: 'inbox'),
                    folder_row('id-sales', 'Sales', parent: 'id-inbox'),
                    folder_row('id-emea', 'EMEA', parent: 'id-sales'),
                    folder_row('id-sales-emea', 'Sales / EMEA', parent: 'id-inbox'),])

      collided = offered.select { |option| option[:label] == 'Inbox / Sales / EMEA' }

      expect(collided.map { |option| option[:id] }).to contain_exactly('id-emea', 'id-sales-emea')
    end
  end
end

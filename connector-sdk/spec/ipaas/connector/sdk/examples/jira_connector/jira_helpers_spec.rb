require 'spec_helper'
require_relative 'jira_context'

describe 'Jira connector helpers', :jira, :outbound_connection do
  let(:connector_id) { '01a13f2d-b655-7332-952d-145b7c29f5c3' }
  let(:bound_helpers) { connector.outbound_connection.helpers_definition.copy_for(outbound_connection) }
  let!(:tenant_info) do
    stub_request(:get, 'https://acme.atlassian.net/_edge/tenant_info')
      .to_return(status: 200, body: { cloudId: 'cloud-1' }.to_json)
  end

  before do
    helpers_proxy = bound_helpers.for_proc
    outbound_connection.define_singleton_method(:helpers) { helpers_proxy }
  end

  def call_helper(name, ...)
    bound_helpers.registered_helper(name).execute(...)
  end

  def text_node(text, mark = nil)
    node = { type: 'text', text: text }
    mark ? node.merge(marks: [{ type: mark }]) : node
  end

  def adf_doc(*content)
    { type: 'doc', content: content }
  end

  def paragraph(*content)
    { type: 'paragraph', content: content }
  end

  describe 'cloud id' do
    it 'looks the cloud id up once and reuses it for every later call' do
      expect(call_helper(:jira_url, 'myself')).to eq("#{api}/myself")
      expect(call_helper(:jira_url, 'field')).to eq("#{api}/field")
      expect(tenant_info).to have_been_requested.once
    end

    it 'looks the cloud id up again when the site changes' do
      call_helper(:jira_url, 'myself')
      stub_request(:get, 'https://other.atlassian.net/_edge/tenant_info')
        .to_return(status: 200, body: { cloudId: 'cloud-2' }.to_json)
      outbound_connection.config[:site] = 'other.atlassian.net'
      expect(call_helper(:jira_url, 'myself')).to eq('https://api.atlassian.com/ex/jira/cloud-2/rest/api/3/myself')
    end

    it 'gives the site the time of an action to answer when an action looks the cloud id up' do
      allow(outbound_connection).to receive(:http_get).and_call_original
      call_helper(:jira_url, 'myself')
      expect(outbound_connection).to have_received(:http_get)
        .with(tenant_info_url, nil, nil, skip_authentication: true, open_timeout: nil,
                                         timeout: JiraConnector::ACTION_TIMEOUT)
    end

    it 'tries again when the site answers the cloud id lookup with 429, rather than calling the site unknown' do
      stub_request(:get, tenant_info_url).to_return(status: 429, headers: { 'Retry-After' => '30' }, body: '')
      expect_reschedule_after(30) { call_helper(:jira_url, 'myself') }
    end

    it 'tries the action again later when the site does not answer the cloud id lookup' do
      stub_request(:get, tenant_info_url).to_timeout
      expect_reschedule_after(60, /Jira did not answer/) { call_helper(:jira_url, 'myself') }
    end

    it 'gives the site a short time to answer when the connection test looks the cloud id up' do
      allow(outbound_connection).to receive(:http_get).and_call_original
      call_helper(:store_cloud_id, 'acme.atlassian.net')
      expect(outbound_connection).to have_received(:http_get)
        .with(tenant_info_url, nil, nil, skip_authentication: true, open_timeout: JiraConnector::SHORT_OPEN_TIMEOUT,
                                         timeout: JiraConnector::SHORT_TIMEOUT)
    end

    it 'refuses a cloud id that would change the request path' do
      stub_request(:get, 'https://acme.atlassian.net/_edge/tenant_info')
        .to_return(status: 200, body: { cloudId: '../admin' }.to_json)
      expect { call_helper(:jira_url, 'myself') }
        .to raise_error(IPaaS::Job::FailJob, /No Jira Cloud site answers at acme\.atlassian\.net/)
    end
  end

  describe 'option helpers' do
    it 'lists the projects on every page by key and name' do
      stub_request(:get, "#{api}/project/search").with(query: hash_including('startAt' => '0'))
                                                 .to_return(status: 200, body: {
                                                   values: [{ key: 'KAN', name: 'Kanban' }], isLast: false,
                                                 }.to_json)
      stub_request(:get, "#{api}/project/search").with(query: hash_including('startAt' => '1'))
                                                 .to_return(status: 200, body: {
                                                   values: [{ key: 'OPS', name: 'Operations' }], isLast: true,
                                                 }.to_json)
      expect(call_helper(:fetch_project_options))
        .to eq([{ id: 'KAN', label: 'Kanban (KAN)' }, { id: 'OPS', label: 'Operations (OPS)' }])
    end

    it 'stops after the page cap when Jira never reports the last page' do
      stub = stub_request(:get, "#{api}/project/search")
             .with(query: hash_including({}))
             .to_return(status: 200, body: { values: [{ key: 'KAN', name: 'Kanban' }], isLast: false }.to_json)
      expect(call_helper(:fetch_project_options).size).to eq(JiraConnector::MAX_OPTION_PAGES)
      expect(stub).to have_been_requested.times(JiraConnector::MAX_OPTION_PAGES)
    end

    it 'lists the issue types the account can create in the chosen project' do
      stub_creatable_types('KAN', [{ id: '10001', name: 'Task' }])
      expect(call_helper(:fetch_issue_type_options, project_key: 'kan')).to eq([{ id: '10001', label: 'Task' }])
    end

    context 'when the connection has a default project' do
      let(:default_project) { 'OPS' }

      it 'lists the issue types of the default project when no project is chosen' do
        stub_creatable_types('OPS', [{ id: '10002', name: 'Bug' }])
        expect(call_helper(:fetch_issue_type_options, project_key: nil)).to eq([{ id: '10002', label: 'Bug' }])
      end
    end

    it 'lists the priorities of the site' do
      stub_request(:get, "#{api}/priority/search")
        .with(query: hash_including({}))
        .to_return(status: 200, body: { values: [{ id: '2', name: 'High' }], isLast: true }.to_json)
      expect(call_helper(:fetch_priority_options)).to eq([{ id: '2', label: 'High' }])
    end

    it 'lists the transitions available on the issue' do
      stub_request(:get, "#{api}/issue/KAN-1/transitions")
        .to_return(status: 200, body: { transitions: [{ id: '31', name: 'Done' }] }.to_json)
      expect(call_helper(:fetch_transition_options, issue_id_or_key: 'kan-1')).to eq([{ id: '31', label: 'Done' }])
    end
  end

  describe 'page tokens' do
    it 'starts at the offset the token carries, or at zero without one' do
      expect([call_helper(:page_start, nil), call_helper(:page_start, '100')]).to eq([0, 100])
    end

    it 'refuses a token this action did not return' do
      expect { call_helper(:page_start, 'abc') }
        .to raise_error(IPaaS::Job::FailJob, "The page token 'abc' was not returned by this action.")
    end

    it 'returns the next offset while Jira says it is not the last page' do
      expect(call_helper(:next_offset_token, { isLast: false }, 2, 0, 2)).to eq('2')
    end

    it 'returns no token on the last page' do
      expect(call_helper(:next_offset_token, { isLast: true }, 2, 0, 2)).to be_nil
    end

    it 'follows the total when Jira sends no last page flag' do
      expect(call_helper(:next_offset_token, { total: 5 }, 2, 2, 2)).to eq('4')
    end

    it 'treats a full page of a bare list as a sign of more' do
      expect([call_helper(:next_offset_token, nil, 2, 0, 2), call_helper(:next_offset_token, nil, 1, 0, 2)])
        .to eq(['2', nil])
    end
  end

  describe 'output builders' do
    it 'builds an account with a nullable email' do
      expect(call_helper(:account_output, { accountId: 'a1', displayName: 'Bot' }))
        .to eq({ account_id: 'a1', display_name: 'Bot', email_address: nil })
    end

    it 'builds the comment visibility, or nothing when the comment is open' do
      visibility = { type: 'role', value: 'Administrators', identifier: '10002' }
      expect([call_helper(:visibility_output, visibility), call_helper(:visibility_output, nil)])
        .to eq([{ type: 'role', value: 'Administrators', identifier: '10002' }, nil])
    end
  end

  describe 'markdown_to_adf' do
    def convert(text)
      call_helper(:markdown_to_adf, text)[:content]
    end

    it 'starts a new paragraph after a blank line' do
      expect(convert("one\n\ntwo")).to eq([paragraph(text_node('one')), paragraph(text_node('two'))])
    end

    it 'turns a single line break into a hard break' do
      expect(convert("one\ntwo")).to eq([paragraph(text_node('one'), { type: 'hardBreak' }, text_node('two'))])
    end

    it 'marks *bold* text as strong' do
      expect(convert('a *b* c')).to eq([paragraph(text_node('a '), text_node('b', 'strong'), text_node(' c'))])
    end

    it 'marks _italic_ text as emphasis' do
      expect(convert('_b_')).to eq([paragraph(text_node('b', 'em'))])
    end

    it 'leaves underscores inside a word alone' do
      expect(convert('snake_case_name')).to eq([paragraph(text_node('snake_case_name'))])
    end

    it 'leaves the underscores of a file name alone' do
      expect(convert('__init__.py')).to eq([paragraph(text_node('__init__.py'))])
    end

    it 'opens a marker only after a space or an opening bracket' do
      expect(convert('see /_path_ now')).to eq([paragraph(text_node('see /_path_ now'))])
    end

    it 'closes a marker only before a space or punctuation' do
      expect(convert('see _path_/ now')).to eq([paragraph(text_node('see _path_/ now'))])
    end

    it 'starts one paragraph after several blank lines' do
      expect(convert("a\n\n\nb")).to eq([paragraph(text_node('a')), paragraph(text_node('b'))])
    end

    it 'turns lines starting with a dash into one bulleted list' do
      expect(convert("Steps:\n- one\n- two")).to eq([
        paragraph(text_node('Steps:')),
        { type: 'bulletList', content: [
          { type: 'listItem', content: [paragraph(text_node('one'))] },
          { type: 'listItem', content: [paragraph(text_node('two'))] },
        ], },
      ])
    end
  end

  describe 'payload_text' do
    it 'turns the wiki markup of a webhook payload into plain text' do
      markup = "h2. Steps\n* first *bold* step\n# second _quiet_ step\n{code}x = 1{code}\n" \
               'See [the runbook|https://example.com/r] for [~accountid:acc-3]'
      expect(call_helper(:payload_text, markup))
        .to eq("Steps\n- first bold step\n- second quiet step\nx = 1\n" \
               'See the runbook (https://example.com/r) for @acc-3')
    end

    it 'leaves a snake_case word and a lone asterisk as they are' do
      expect(call_helper(:payload_text, 'set max_page_size to 5 * 2')).to eq('set max_page_size to 5 * 2')
    end

    it 'reads a payload text that is Atlassian Document Format the way the actions do' do
      expect(call_helper(:payload_text, adf_doc(paragraph(text_node('plain'))))).to eq('plain')
    end
  end

  describe 'adf_to_text' do
    def flatten(*content)
      call_helper(:adf_to_text, adf_doc(*content))
    end

    it 'keeps the address of a link after its text' do
      link = { type: 'text', text: 'the runbook', marks: [{ type: 'link', attrs: { href: 'https://example.com/r' } }] }
      expect(flatten(paragraph(text_node('See '), link))).to eq('See the runbook (https://example.com/r)')
    end

    it 'writes the address of a link once when the text is the address' do
      url = 'https://example.com/r'
      expect(flatten(paragraph({ type: 'text', text: url, marks: [{ type: 'link', attrs: { href: url } }] })))
        .to eq(url)
    end

    it 'reads the text of a status' do
      expect(flatten(paragraph({ type: 'status', attrs: { text: 'IN REVIEW' } }))).to eq('IN REVIEW')
    end

    it 'reads a date given in milliseconds or in seconds' do
      expect([flatten({ type: 'date', attrs: { timestamp: '1792000000000' } }),
              flatten({ type: 'date', attrs: { timestamp: '1792000000' } }),])
        .to eq(%w[2026-10-14 2026-10-14])
    end

    it 'reads a date before 2001 given in milliseconds' do
      expect(flatten({ type: 'date', attrs: { timestamp: '631152000000' } })).to eq('1990-01-01')
    end

    it 'names the account of a mention that carries no text' do
      expect(flatten(paragraph({ type: 'mention', attrs: { id: 'acc-1' } }))).to eq('@acc-1')
    end

    it 'reads the link of a card that carries its data instead of a url' do
      card = { type: 'inlineCard', attrs: { data: { url: 'https://example.com/a' } } }
      expect(flatten(paragraph(card))).to eq('https://example.com/a')
    end

    it 'ends a code block on its own line' do
      expect(flatten({ type: 'codeBlock', content: [text_node('x = 1')] }, paragraph(text_node('after'))))
        .to eq("x = 1\n\nafter")
    end

    it 'prefixes bulleted and numbered list items' do
      item = ->(value) { { type: 'listItem', content: [paragraph(text_node(value))] } }
      expect(flatten({ type: 'bulletList', content: [item.call('a')] },
                     { type: 'orderedList', attrs: { order: 3 }, content: [item.call('b'), item.call('c')] }))
        .to eq("- a\n\n3. b\n4. c")
    end

    it 'leaves one blank line where an image or an empty paragraph sits between two paragraphs' do
      image = { type: 'mediaSingle', content: [{ type: 'media', attrs: { id: 'file-1', type: 'file' } }] }
      expect(flatten(paragraph(text_node('a')), image, paragraph(text_node('b')))).to eq("a\n\nb")
      expect(flatten(paragraph(text_node('a')), paragraph, paragraph(text_node('b')))).to eq("a\n\nb")
    end

    it 'keeps a blank line between paragraphs, so text written with them reads back as written' do
      text = "First line\nSecond line\n\nAfter an empty line"
      expect(call_helper(:adf_to_text, call_helper(:markdown_to_adf, text))).to eq(text)
    end
  end
end

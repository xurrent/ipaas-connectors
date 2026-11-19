require 'spec_helper'

describe 'Microsoft Entra Search Users Action', :action, :ms_entra do
  let(:action_template_id) { '01a1a1c8-debd-79fc-b010-425e03d4e3bd' }
  let(:users_url) { "#{graph}/users" }
  let(:next_link) { "#{graph}/users?$skiptoken=page-two" }
  let(:foreign_link) { 'https://evil.example.com/v1.0/users?$skiptoken=page-two' }

  def stub_users(body = { value: [{ id: user_id, displayName: 'Adele Vance' }] }, url: users_url, status: 200)
    stub_request(:get, url).with(query: hash_including({}))
                           .to_return(status: status, body: body.to_json,
                                      headers: { 'Content-Type' => 'application/json' })
  end

  def store_next_link(link, input = {})
    action(input).send(:iteration_state_value=, { odata_nextLink: link })
  end

  describe 'input_schema' do
    it 'defines optional filter and search strings' do
      expect(action.input_schema.field(:filter).type).to eq(:string)
      expect(action.input_schema.field(:filter).required).to be_falsey
      expect(action.input_schema.field(:search).type).to eq(:string)
      expect(action.input_schema.field(:search).required).to be_falsey
    end

    it 'defines an optional page size from 1 to 999 that defaults to 100' do
      action.input_schema.field(:page_size).tap do |field|
        expect(field.type).to eq(:integer)
        expect(field.required).to be_falsey
        expect(field.min).to eq(1)
        expect(field.max).to eq(999)
        expect(field.default).to eq(100)
      end
    end
  end

  describe 'output_schema' do
    it 'defines a page with a count, a required has next page flag and a users array' do
      page = action.output_schema.first
      expect(page.reference).to eq('page')
      expect(page.field(:odata_count).type).to eq(:integer)
      expect(page.field(:has_next_page).required).to be_truthy
      expect(page.field(:users).type).to eq(:nested)
      expect(page.field(:users).array).to eq(true)
      expect(page.field(:users).field(:user_id).required).to be_truthy
    end

    it 'defines a required next link in the iteration state' do
      expect(action.iteration_state_schema.field(:odata_nextLink).required).to be_truthy
    end
  end

  describe 'the first page' do
    it 'sends the eventual consistency header and asks for a count' do
      stub_users
      run_action({})
      expect(a_request(:get, users_url)
        .with(headers: { 'ConsistencyLevel' => 'eventual' }, query: hash_including('$count' => 'true')))
        .to have_been_made.once
    end

    it 'asks for the user select list and the default page size of 100 when no page size is set' do
      stub_users
      run_action({})
      expect(a_request(:get, users_url)
        .with(query: { '$select' => MsEntraConnector::USER_SELECT, '$top' => '100', '$count' => 'true' }))
        .to have_been_made.once
    end

    it 'passes the filter through' do
      stub_users
      run_action({ filter: "department eq 'Sales'" })
      expect(a_request(:get, users_url).with(query: hash_including('$filter' => "department eq 'Sales'")))
        .to have_been_made.once
    end

    it 'turns the search text into a quoted display name search without the quotes it held' do
      stub_users
      run_action({ search: 'ad"ele' })
      expect(a_request(:get, users_url).with(query: hash_including('$search' => '"displayName:adele"')))
        .to have_been_made.once
    end

    it 'sends the largest page size of 999 as it is' do
      stub_users
      run_action({ page_size: 999 })
      expect(a_request(:get, users_url).with(query: hash_including('$top' => '999'))).to have_been_made.once
    end

    it 'refuses a page size above 999 before any request' do
      expect { run_action({ page_size: 5000 }) }.to raise_error(IPaaS::Error, /'page_size' should be at most 999/)
      expect(a_request(:get, users_url).with(query: hash_including({}))).not_to have_been_made
    end

    it 'maps each Graph user onto a snake case user' do
      stub_users({ '@odata.count': 1, value: [{ id: user_id, displayName: 'Adele Vance', accountEnabled: false }] })
      output = run_action({})
      expect(output['odata_count']).to eq(1)
      expect(output['users'].first).to include('user_id' => user_id, 'display_name' => 'Adele Vance',
                                               'account_enabled' => false)
    end
  end

  describe 'paging' do
    it 'stores a next link on the Graph host and reports a next page' do
      stub_users({ '@odata.nextLink': next_link, value: [{ id: user_id }] })
      expect(action({})).to receive(:iteration_state_value=).with({ odata_nextLink: next_link }).and_call_original
      expect(run_action({})['has_next_page']).to eq(true)
    end

    it 'follows the stored next link on the next run' do
      stub_request(:get, next_link).to_return(status: 200, body: { value: [{ id: user_id }] }.to_json)
      store_next_link(next_link)
      expect(run_action({})['has_next_page']).to eq(false)
      expect(a_request(:get, next_link).with(headers: { 'ConsistencyLevel' => 'eventual' })).to have_been_made.once
    end

    it 'fails the job when Graph answers with a next link on another host' do
      stub_users({ '@odata.nextLink': foreign_link, value: [{ id: user_id }] })
      expect { run_action({}) }
        .to raise_error(IPaaS::Job::FailJob, %r{next page link that is not on https://graph\.microsoft\.com/v1\.0})
    end

    it 'fails the job and sends nothing to the other host when the stored next link is on another host' do
      foreign = stub_request(:get, /evil\.example\.com/)
      store_next_link(foreign_link)
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, /next page link that is not on/)
      expect(foreign).not_to have_been_requested
    end
  end

  describe 'errors' do
    it 'reschedules the job when Graph answers 429' do
      stub_users({}, status: 429)
      expect { run_action({}) }.to raise_error(IPaaS::Job::RescheduleJob, /Microsoft API rate limit hit/)
    end

    it 'fails naming User.Read.All when Graph answers 403' do
      stub_users(access_denied, status: 403)
      expect { run_action({}) }
        .to raise_error(IPaaS::Job::FailJob,
                        include('Permission this action needs: User.Read.All. Admin consent is required.'))
    end
  end
end

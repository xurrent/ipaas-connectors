require 'spec_helper'
require_relative 'jira_context'

describe 'Jira user actions', :action, :jira do
  let(:jira_user) do
    { accountId: 'acc-1', displayName: 'Jo Smith', emailAddress: 'jo@example.com', active: true,
      accountType: 'atlassian', timeZone: 'Europe/Amsterdam', self: "#{api}/user?accountId=acc-1", }
  end

  describe 'Get User Details' do
    let(:action_template_id) { '01a13f2d-b655-7b18-9252-e50c6296560a' }

    def stub_user_search(users, query: 'jo')
      stub_request(:get, "#{api}/user/search")
        .with(query: { 'query' => query, 'maxResults' => JiraConnector::MAX_PAGE_SIZE.to_s })
        .to_return(status: 200, body: users.to_json)
    end

    def user_named(account_id, display_name, email_address = '')
      jira_user.merge(accountId: account_id, displayName: display_name, emailAddress: email_address)
    end

    def john_does(count)
      (1..count).map { |number| user_named("acc-doe-#{number}", "John Doe#{number}") }
    end

    let(:chat_app) do
      { accountId: 'app-1', displayName: 'Chat Notifications', emailAddress: '', active: true, accountType: 'app' }
    end

    it 'reads one user by account ID' do
      stub_request(:get, "#{api}/user").with(query: { 'accountId' => 'acc-1' })
                                       .to_return(status: 200, body: jira_user.to_json)
      expect(run_action({ account_id: 'acc-1' }))
        .to include(account_id: 'acc-1', display_name: 'Jo Smith', email_address: 'jo@example.com', active: true,
                    account_type: 'atlassian', time_zone: 'Europe/Amsterdam')
    end

    it 'names the user that was not found' do
      stub_request(:get, "#{api}/user").with(query: hash_including({}))
                                       .to_return(status: 404, body: { errorMessages: ['No user'] }.to_json)
      expect { run_action({ account_id: 'acc-9' }) }.to raise_error(
        IPaaS::Job::FailJob, 'User acc-9 was not found, or this account cannot see it (HTTP 404): No user'
      )
    end

    it 'names the Browse users and groups permission when Jira refuses the lookup' do
      stub_request(:get, "#{api}/user").with(query: hash_including({}))
                                       .to_return(status: 403, body: { errorMessages: ['Forbidden'] }.to_json)
      expect { run_action({ account_id: 'acc-1' }) }
        .to raise_error(IPaaS::Job::FailJob, /needs the Browse users and groups permission/)
    end

    it 'refuses an account ID and a query together before calling Jira' do
      expect { run_action({ account_id: 'acc-1', query: 'jo' }) }
        .to raise_error(IPaaS::Job::FailJob, 'Get User Details needs an account ID or a query, not both.')
      expect(a_request(:get, %r{/user})).not_to have_been_made
    end

    it 'refuses to run with neither an account ID nor a query' do
      expect { run_action({ query: '  ' }) }
        .to raise_error(IPaaS::Job::FailJob, 'Get User Details needs an account ID or a query, not both.')
    end

    it 'takes the only user a query finds' do
      stub_user_search([user_named('acc-1', 'jo.smith')], query: 'jo.smith@example.com')
      expect(run_action({ query: 'jo.smith@example.com' })).to include(account_id: 'acc-1')
    end

    it 'takes the one user who has a word starting with each word of the query' do
      stub_user_search([user_named('acc-2', 'Joan Baker', 'joan@example.com'), jira_user], query: 'jo smi')
      expect(run_action({ query: 'jo smi' })).to include(account_id: 'acc-1')
    end

    it 'splits the query into words at punctuation as well as at spaces' do
      stub_user_search([jira_user, user_named('acc-2', 'Smith Baker')], query: 'jo.smith')
      expect(run_action({ query: 'jo.smith' })).to include(account_id: 'acc-1')
    end

    it 'matches the words of the query against the shown email address as well as the display name' do
      stub_user_search([jira_user, user_named('acc-2', 'Joan Baker', 'joan@other.org')], query: 'jo example')
      expect(run_action({ query: 'jo example' })).to include(account_id: 'acc-1')
    end

    it 'matches a name with a dotted capital I to a query typed with a plain i' do
      stub_user_search([user_named('acc-2', 'İlkay Gündoğan'), chat_app], query: 'ilkay')
      expect(run_action({ query: 'ilkay' })).to include(account_id: 'acc-2')
    end

    it 'matches a query typed without accents to a name that has them' do
      stub_user_search([user_named('acc-2', 'José García'), chat_app], query: 'jose garcia')
      expect(run_action({ query: 'jose garcia' })).to include(account_id: 'acc-2')
    end

    it 'checks every word of a query that holds an @ but is not one email address' do
      stub_user_search([chat_app], query: 'no such@xurrent.com')
      expect { run_action({ query: 'no such@xurrent.com' }) }
        .to raise_error(IPaaS::Job::FailJob, /\ANo active Jira user matches 'no such@xurrent\.com'\./)
    end

    it 'fails when the only user Jira finds does not match every word of the query' do
      stub_user_search([chat_app], query: 'no-such-user')
      expect { run_action({ query: 'no-such-user' }) }
        .to raise_error(IPaaS::Job::FailJob, /\ANo active Jira user matches 'no-such-user'\./)
    end

    it 'fails when the query holds no letter or digit, rather than take the user Jira finds' do
      stub_user_search([chat_app], query: '--')
      expect { run_action({ query: '--' }) }
        .to raise_error(IPaaS::Job::FailJob, /\ANo active Jira user matches '--'\./)
    end

    it 'counts only the users who match every word when several match' do
      stub_user_search([jira_user, user_named('acc-2', 'Jo Smithers'), user_named('acc-3', 'Joan Baker')],
                       query: 'jo smi')
      expect { run_action({ query: 'jo smi' }) }.to raise_error(
        IPaaS::Job::FailJob, "2 Jira users match 'jo smi'. Give the account ID or the full email address."
      )
    end

    it 'does not take the one matching user from a full page, because Jira may list more after it' do
      stub_user_search(john_does(JiraConnector::MAX_PAGE_SIZE - 1) + [user_named('acc-2', 'John Smithers')],
                       query: 'john smith')
      expect { run_action({ query: 'john smith' }) }.to raise_error(
        IPaaS::Job::FailJob,
        "Jira finds #{JiraConnector::MAX_PAGE_SIZE} or more users for 'john smith'. " \
        'Give the account ID or the full email address.'
      )
    end

    it 'does not say nobody matches when a full page holds no matching user, because Jira may list one after it' do
      stub_user_search(john_does(JiraConnector::MAX_PAGE_SIZE), query: 'john smith')
      expect { run_action({ query: 'john smith' }) }.to raise_error(
        IPaaS::Job::FailJob,
        "Jira finds #{JiraConnector::MAX_PAGE_SIZE} or more users for 'john smith'. " \
        'Give the account ID or the full email address.'
      )
    end

    it 'takes the user whose email address equals the query when the query finds several' do
      stub_user_search([{ accountId: 'acc-2', emailAddress: 'jo@example.com.au' },
                        jira_user.merge(emailAddress: 'JO@example.com'),], query: 'jo@example.com')
      expect(run_action({ query: 'jo@example.com' })).to include(account_id: 'acc-1')
    end

    it 'refuses the one user Jira finds when the shown email address only starts with the email query' do
      stub_user_search([user_named('acc-2', 'Jo Smith', 'jo@example.com.au')], query: 'jo@example.com')
      expect { run_action({ query: 'jo@example.com' }) }
        .to raise_error(IPaaS::Job::FailJob, /\ANo active Jira user matches 'jo@example\.com'\./)
    end

    it 'takes the one user whose email address is hidden, because Jira matches a hidden address only in full' do
      stub_user_search([user_named('acc-2', 'Jo Smith', ''), user_named('acc-3', 'Joan', 'jo@example.com.au')],
                       query: 'jo@example.com')
      expect(run_action({ query: 'jo@example.com' })).to include(account_id: 'acc-2')
    end

    it 'takes a user whose email is hidden and whose display name is the email query itself' do
      stub_user_search([user_named('acc-2', 'jo@example.com', '')], query: 'jo@example.com')
      expect(run_action({ query: 'jo@example.com' })).to include(account_id: 'acc-2')
    end

    it 'does not take a user whose email is hidden when the display name holds the email query' do
      stub_user_search([user_named('acc-2', 'jo@example.com support', '')], query: 'jo@example.com')
      expect { run_action({ query: 'jo@example.com' }) }
        .to raise_error(IPaaS::Job::FailJob, /\ANo active Jira user matches 'jo@example\.com'\./)
    end

    it 'takes the user whose display name equals the query when the query finds several' do
      stub_user_search([{ accountId: 'acc-2', displayName: 'Jo Smithers' },
                        jira_user.merge(displayName: 'jo smith', emailAddress: nil),], query: 'Jo Smith')
      expect(run_action({ query: 'Jo Smith' })).to include(account_id: 'acc-1')
    end

    it 'fails when a query finds several users and none of them equals it' do
      stub_user_search([jira_user, jira_user.merge(accountId: 'acc-2', displayName: 'Joan')])
      expect { run_action({ query: 'jo' }) }
        .to raise_error(IPaaS::Job::FailJob, "2 Jira users match 'jo'. Give the account ID or the full email address.")
    end

    it 'fails when a query finds nobody, naming what can hide a user' do
      stub_user_search([])
      expect { run_action({ query: 'jo' }) }.to raise_error(
        IPaaS::Job::FailJob,
        "No active Jira user matches 'jo'. The search finds active users only, and finds nobody when the account " \
        'lacks the Browse users and groups permission.'
      )
    end
  end

  describe 'Create User' do
    let(:action_template_id) { '01a13f2d-b655-7b0d-baf8-36b28915899b' }

    it 'sends the email address and the chosen products' do
      stub = stub_request(:post, "#{api}/user")
             .with(body: { emailAddress: 'jo@example.com', products: ['jira-software'] }.to_json)
             .to_return(status: 201, body: jira_user.to_json)
      output = run_action({ email_address: ' jo@example.com ', products: ['jira-software'] })
      expect(stub).to have_been_requested.once
      expect(output).to include(account_id: 'acc-1', self: "#{api}/user?accountId=acc-1")
    end

    it 'sends an empty product list when no product is chosen' do
      stub = stub_request(:post, "#{api}/user")
             .with(body: { emailAddress: 'jo@example.com', products: [] }.to_json)
             .to_return(status: 201, body: jira_user.to_json)
      run_action({ email_address: 'jo@example.com' })
      expect(stub).to have_been_requested.once
    end

    it 'succeeds when Jira answers 200 for a user that already has the access' do
      stub_request(:post, "#{api}/user").to_return(status: 200, body: jira_user.to_json)
      expect(run_action({ email_address: 'jo@example.com' })).to include(account_id: 'acc-1')
    end

    it 'explains a refusal with the organization admin rule and the licence seat' do
      stub_request(:post, "#{api}/user").to_return(status: 403, body: { errorMessages: ['Forbidden.'] }.to_json)
      expect { run_action({ email_address: 'jo@example.com' }) }.to raise_error(
        IPaaS::Job::FailJob,
        'Jira refused to create the user (HTTP 403): Forbidden. The connection account must be an organization ' \
        'admin and have the Administer Jira permission. Each new user takes a paid licence seat.'
      )
    end

    it 'fails rather than creating the user twice when Jira answers 503' do
      stub_request(:post, "#{api}/user").to_return(status: 503, body: '')
      expect { run_action({ email_address: 'jo@example.com' }) }.to raise_error(IPaaS::Job::FailJob, /HTTP 503/)
    end

    it 'says the user may have been created when Jira does not answer' do
      stub_request(:post, "#{api}/user").to_timeout
      expect { run_action({ email_address: 'jo@example.com' }) }
        .to raise_error(IPaaS::Job::FailJob, /\AJira did not answer \(.*\)\. The change may have been made/)
    end
  end
end

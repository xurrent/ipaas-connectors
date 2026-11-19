require 'spec_helper'

describe 'Microsoft Entra Restore Deleted User Action', :action, :ms_entra do
  let(:action_template_id) { '01a1c8f4-eb48-7ece-bfbe-8fb53da0c7fe' }
  let(:deleted_url) { "#{graph}/directory/deletedItems/#{user_id}" }
  let(:restore_url) { "#{deleted_url}/restore" }
  let(:active_url) { "#{graph}/users/#{user_id}" }

  let(:restored_user) do
    {
      '@odata.context' => "#{graph}/$metadata#users/$entity", '@odata.type' => '#microsoft.graph.user',
      id: user_id, businessPhones: [], displayName: 'Adele Vance', givenName: 'Adele', surname: 'Vance',
      mail: 'adele.vance@contoso.com', userPrincipalName: 'adele.vance@contoso.com',
    }
  end

  def stub_deleted(status: 200, body: restored_user.to_json)
    stub_request(:get, deleted_url)
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  def stub_restore(status: 200, body: restored_user.to_json)
    stub_request(:post, restore_url)
      .with { |request| @sent = request.body }
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  def stub_active(status: 200, body: restored_user.to_json)
    stub_request(:get, active_url)
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'input_schema' do
    it 'requires the deleted user id and leaves the restore options optional' do
      schema = action.input_schema
      expect(schema.field(:user_id).required).to be_truthy
      expect(schema.field(:new_user_principal_name).required).to be_falsey
      expect(schema.field(:auto_reconcile_proxy_conflict).type).to eq(:boolean)
    end
  end

  describe 'output_schema' do
    it 'returns the user with a required user id, and whether it was already restored' do
      schema = action.output_schema.first
      expect(schema.field(:user).type).to eq(:nested)
      expect(schema.field(:user).field(:user_id).required).to be_truthy
      expect(schema.field(:already_restored).type).to eq(:boolean)
    end
  end

  describe 'a deleted user' do
    it 'posts no body when no option is set and maps the default fields of the restored user on 200' do
      stub_deleted
      stub_restore(body: restored_user.merge(accountEnabled: true, department: 'Sales').to_json)
      output = run_action({ user_id: user_id })
      expect(@sent).to be_blank
      expect(output).to eq(
        'already_restored' => false,
        'user' => {
          'user_id' => user_id, 'display_name' => 'Adele Vance', 'given_name' => 'Adele', 'surname' => 'Vance',
          'user_principal_name' => 'adele.vance@contoso.com', 'mail' => 'adele.vance@contoso.com',
          'job_title' => nil, 'office_location' => nil, 'mobile_phone' => nil, 'business_phones' => [],
        }
      )
    end

    it 'sends the new user principal name and the proxy conflict flag when they are set' do
      stub_deleted
      stub_restore
      run_action({ user_id: user_id, new_user_principal_name: ' adele.v2@contoso.com ',
                   auto_reconcile_proxy_conflict: 'true', })
      expect(JSON.parse(@sent)).to eq('newUserPrincipalName' => 'adele.v2@contoso.com',
                                      'autoReconcileProxyConflict' => true)
    end

    it 'fails with the Graph message when the restore answers 404' do
      stub_deleted
      stub_restore(status: 404, body: graph_error('Request_ResourceNotFound', 'Resource does not exist.'))
      expect { run_action({ user_id: user_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 404 Request_ResourceNotFound: Resource does not exist.')
    end

    it 'names User.DeleteRestore.All when the restore answers 403' do
      stub_deleted
      stub_restore(status: 403, body: access_denied.to_json)
      expect { run_action({ user_id: user_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        include('Permission this action needs: User.DeleteRestore.All (restoring a user who holds a ' \
                                'privileged administrator role also needs User.ReadWrite.All and an administrator ' \
                                'role on the app). Admin consent is required.'))
    end
  end

  describe 'a deleted item that is not a user' do
    it 'refuses a deleted group with no restore' do
      stub_deleted(body: { '@odata.type' => '#microsoft.graph.group', id: user_id }.to_json)
      expect { run_action({ user_id: user_id }) }
        .to raise_error(IPaaS::Job::FailJob, "Deleted item '#{user_id}' is #microsoft.graph.group, not " \
                                             '#microsoft.graph.user. Nothing was restored.')
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'refuses a deleted item whose type Microsoft Graph does not state, with no restore' do
      stub_deleted(body: { id: user_id }.to_json)
      expect { run_action({ user_id: user_id }) }
        .to raise_error(IPaaS::Job::FailJob, "Deleted item '#{user_id}' is of no stated type, not " \
                                             '#microsoft.graph.user. Nothing was restored.')
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end
  end

  describe 'an ID that is not in the deleted items' do
    it 'returns the active user as already restored with no restore, so a rerun succeeds' do
      stub_deleted(status: 404, body: graph_error('Request_ResourceNotFound', 'Resource does not exist.'))
      stub_active
      output = run_action({ user_id: user_id })
      expect(output['already_restored']).to eq(true)
      expect(output['user']).to include('user_id' => user_id, 'user_principal_name' => 'adele.vance@contoso.com')
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'fails saying the ID is not a deleted user when no active user has it either' do
      stub_deleted(status: 404, body: graph_error('Request_ResourceNotFound', 'Resource does not exist.'))
      stub_active(status: 404, body: graph_error('Request_ResourceNotFound', 'Resource does not exist.'))
      expect { run_action({ user_id: user_id }) }
        .to raise_error(IPaaS::Job::FailJob, "Deleted user ID '#{user_id}' is not a deleted user, and no active " \
                                             'user has this ID. Nothing was restored.')
    end

    it 'names User.Read.All when the active user lookup answers 403' do
      stub_deleted(status: 404, body: graph_error('Request_ResourceNotFound', 'Resource does not exist.'))
      stub_active(status: 403, body: access_denied.to_json)
      expect { run_action({ user_id: user_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        include('Permission this action needs: User.Read.All. Admin consent is required.'))
    end
  end

  describe 'the deleted item lookup' do
    it 'fails with no request when the user id is a user principal name' do
      expect { run_action({ user_id: 'adele.vance@contoso.com' }) }
        .to raise_error(IPaaS::Job::FailJob,
                        "Deleted user ID 'adele.vance@contoso.com' is not a Microsoft Entra object id (a GUID).")
      expect(a_request(:any, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'names User.Read.All when the deleted item lookup answers 403' do
      stub_deleted(status: 403, body: access_denied.to_json)
      expect { run_action({ user_id: user_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        include('Permission this action needs: User.Read.All. Admin consent is required.'))
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end
  end
end

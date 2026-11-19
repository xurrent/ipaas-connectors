require 'spec_helper'

describe 'IPaaS.solution_directory' do
  after(:each) { IPaaS.solution_directory = nil }

  it 'answers the assigned directory once one is set' do
    IPaaS.solution_directory = '/srv/solutions'

    expect(IPaaS.solution_directory).to eq('/srv/solutions')
    expect(MethodSource.use_uuid_cache?('/srv/solutions/accounts/1/connectors/a.rb')).to be(true)
  end

  it 'falls back to the default directory when none is set' do
    expect(IPaaS.solution_directory).to eq('tmp/solutions')
    expect(MethodSource.use_uuid_cache?('/srv/solutions/accounts/1/connectors/a.rb')).to be(false)
  end
end

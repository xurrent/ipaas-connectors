require 'spec_helper'

describe IPaaS::Job::Outbound::CustomerCredentialsError do
  subject(:error) { described_class.new(host: 'idp.example.com', reason: 'invalid_grant') }

  it 'is a kind of FailJob so existing rescues keep working' do
    expect(error).to be_a(IPaaS::Job::FailJob)
  end

  it 'exposes the host' do
    expect(error.host).to eq('idp.example.com')
  end

  it 'exposes the reason' do
    expect(error.reason).to eq('invalid_grant')
  end

  it 'builds a sanitized message from host and reason' do
    expect(error.message).to eq('Authentication to idp.example.com failed: invalid_grant')
  end
end

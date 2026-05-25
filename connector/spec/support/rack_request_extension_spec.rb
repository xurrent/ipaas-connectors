require 'spec_helper'

describe IPaaS::Connector::RackRequestExtension do
  let(:request) do
    headers = { 'HTTP_CHOCOLATECHIP' => 'My Favorite!' }
    Rack::Request.new(Rack::MockRequest.env_for('https://ipaas.xurrent.com/example?foo=bar&baz=bie', headers))
  end

  context 'headers' do
    it 'should define the headers' do
      expect(request.headers['ChocolateChip']).to eq('My Favorite!')
    end
  end
end

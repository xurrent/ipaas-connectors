require 'spec_helper'

describe IPaaS::Encryption::CryptoKey do
  it 'does not show the secret' do
    expect(IPaaS::Encryption::CryptoKey.generate.inspect).to_not include('@secret')
  end
end

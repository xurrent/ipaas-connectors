require 'spec_helper'

describe IPaaS::Encryption::StoredCryptoKey do
  it 'handles incorrectly stored timestamps' do
    store = double
    allow(store).to receive(:read) {
      { identifier: 'foo', revoked_at: 'foo' }
    }

    result = described_class.load(store, 'foo')
    expect(result.revoked_at).to be_nil
  end
end

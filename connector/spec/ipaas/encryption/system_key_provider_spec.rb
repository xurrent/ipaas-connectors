require 'spec_helper'

describe IPaaS::Encryption::SystemKeyProvider do
  let(:kms) { IPaaS::Encryption::TestKms.new }
  let(:store) { ActiveSupport::Cache::MemoryStore.new }
  let(:system_id) { '3fd5eb25-0896-4b85-a807-01509558fe12' }
  let(:kms_key_arn) { 'Foo:Bar:Baz' }
  let(:provider) { IPaaS::Encryption::SystemKeyProvider.new(store, kms, system_id, kms_key_arn) }

  it 'provides an encryption key' do
    result = provider.encryption_key
    expect(result.identifier).not_to be_empty
    expect(result.revoked_at).to be_nil
    expect(result.created_at).to be_within(1.second).of(Time.now.utc)
    expect(result.kms_key_arn).to eq(kms_key_arn)
    expect(result.parent_key_identifier).to be_nil
    expect(kms.decrypt(result.encrypted_key, result.kms_key_arn)).to eq(result.secret)

    stored_result = result.class.load(store, result.identifier)
    expect(stored_result.identifier).to eq(result.identifier)
    expect(stored_result.revoked_at).to eq(result.revoked_at)
    expect(stored_result.created_at).to be_within(1.second).of(result.created_at)
    expect(stored_result.kms_key_arn).to eq(result.kms_key_arn)
    expect(stored_result.parent_key_identifier).to eq(result.parent_key_identifier)
    expect(stored_result.encrypted_key).to eq(result.encrypted_key)
    expect(stored_result.secret).to be_nil
  end

  it 'caches the latest encryption key until it expires' do
    key1 = provider.encryption_key
    Timecop.travel(89.days.from_now)
    key2 = provider.encryption_key
    expect(key2.identifier).to eq(key1.identifier)
    expect(key2.encrypted_key).to eq(key1.encrypted_key)

    Timecop.travel(2.days.from_now)
    key3 = provider.encryption_key
    expect(key3.identifier).not_to eq(key1.identifier)
    expect(key3.encrypted_key).not_to eq(key1.encrypted_key)

    Timecop.travel(2.days.from_now)
    key4 = provider.encryption_key
    expect(key4.identifier).to eq(key3.identifier)
    expect(key4.encrypted_key).to eq(key3.encrypted_key)
  end

  it 'provides a decryption key' do
    encryption_key = provider.encryption_key

    result = provider.decryption_key(encryption_key.identifier)
    expect(kms.decrypt(result.encrypted_key, result.kms_key_arn)).to eq(result.secret)

    Timecop.travel(91.days.from_now)
    result = provider.decryption_key(encryption_key.identifier)
    expect(kms.decrypt(result.encrypted_key, result.kms_key_arn)).to eq(result.secret)
  end

  it 'does not provide a decryption key that does not exist' do
    expect { provider.decryption_key('Foo') }.to raise_error(IPaaS::Encryption::Errors::Decryption)
  end

  it 'does not provide a revoked decryption key' do
    key = provider.encryption_key
    expect { provider.decryption_key(key.identifier) }.not_to raise_error

    provider.revoke(key.identifier)
    expect { provider.decryption_key(key.identifier) }.to raise_error(IPaaS::Encryption::Errors::Decryption)
  end
end

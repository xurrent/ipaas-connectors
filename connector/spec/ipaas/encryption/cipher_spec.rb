require 'spec_helper'

describe IPaaS::Encryption::Cipher do
  before(:each) do
    @secret = IPaaS::Encryption::Cipher.generate_random_key
    @cipher = IPaaS::Encryption::Cipher.new(@secret)
  end

  it 'key_length' do
    expect(IPaaS::Encryption::Cipher.key_length).to eq(32)
  end

  it 'iv_length' do
    expect(IPaaS::Encryption::Cipher.iv_length).to eq(12)
  end

  it 'encrypts strings' do
    encrypted_data = @cipher.encrypt('Hello')
    expect(encrypted_data).to_not eq('Hello')
    expect(@cipher.decrypt(encrypted_data)).to eq('Hello')
  end

  it 'encrypts bytes' do
    encrypted_data = @cipher.encrypt(@secret)
    expect(encrypted_data).to_not eq(@secret)
    expect(@cipher.decrypt(encrypted_data)).to eq(@secret)
  end

  it 'works with blanks' do
    encrypted_data = @cipher.encrypt('')
    expect(encrypted_data).to_not eq('')
    expect(@cipher.decrypt(encrypted_data)).to eq('')
  end

  it 'uses non-deterministic encryption' do
    expect(@cipher.encrypt('Hello')).to_not eq(@cipher.encrypt('Hello'))
  end

  it 'does not show the secret' do
    expect(@cipher.inspect).to_not include('@secret')
  end
end

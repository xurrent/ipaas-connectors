require 'spec_helper'

describe IPaaS::Encryption::Encryptor do
  it 'encrypts and decrypts' do
    encrypted = subject.encrypt('hello world')
    expect(encrypted).to_not eq('hello world')
    expect(subject.decrypt(encrypted)).to eq('hello world')
  end

  it 'reflects blank when encrypting blanks' do
    expect(subject.encrypt('')).to eq('')
    expect(subject.encrypt(' ')).to eq(' ')
    expect(subject.encrypt(nil)).to eq(nil)
  end

  it 'reflects blank when decrypting blanks' do
    expect(subject.decrypt('')).to eq('')
    expect(subject.decrypt(' ')).to eq(' ')
    expect(subject.decrypt(nil)).to eq(nil)
  end

  it 'two calls with the same argument produce different outputs' do
    secret_string1 = subject.encrypt('123')
    secret_string2 = subject.encrypt('123')
    expect(secret_string1).not_to be(secret_string2)
    expect(secret_string1).not_to eq(secret_string2)
    expect(secret_string1.to_s).not_to eq(secret_string2.to_s)
    expect(secret_string1.eql?(secret_string2)).to eq(false)
  end
end

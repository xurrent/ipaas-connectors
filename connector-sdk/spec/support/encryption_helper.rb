def new_secret_string(encrypted)
  IPaaS::Encryption::SecretString.new(encrypted, encryptor)
end

def make_secret_string(plain)
  IPaaS::Encryption::SecretString.encrypt(encryptor, plain)
end

def encryptor
  @encryptor ||= IPaaS::Encryption::Encryptor.new
end

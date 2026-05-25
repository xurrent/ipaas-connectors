def make_secret_string(plain)
  IPaaS::Encryption::SecretString.encrypt(encryptor, plain)
end

def encryptor
  @encryptor ||= IPaaS::Encryption::Encryptor.new
end

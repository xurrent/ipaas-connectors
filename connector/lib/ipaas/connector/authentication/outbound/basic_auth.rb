module IPaaS
  module Connector
    module Authentication
      module Outbound
        module BasicAuth
          include IPaaS::Connector::Schema::Extension
          include IPaaS::Connector::Authentication::Outbound::Extension

          schema do
            field :basic_auth, 'Basic authentication', :nested,
                  hint: 'Fill out these details in case all communication must contain basic authentication.',
                  visibility: 'optional' do
              field :username, 'Username', :string,
                    required: true
              field :password, 'Password', :secret_string,
                    required: true
            end
          end

          authenticate do |request|
            basic_auth = config[:basic_auth]
            next if basic_auth.blank?

            decrypted_password = decrypt_secret_string(basic_auth[:password])
            encoded_auth = Base64.strict_encode64("#{basic_auth[:username]}:#{decrypted_password}")
            request.headers['Authorization'] = "Basic #{encoded_auth}"
          end
        end

        register(:basic_auth, BasicAuth)
      end
    end
  end
end

module IPaaS
  module Connector
    module Authentication
      module Inbound
        module BasicAuth
          include IPaaS::Connector::Schema::Extension
          include IPaaS::Connector::Authentication::Inbound::Extension

          schema do
            field :basic_auth, 'Basic authentication', :nested,
                  hint: 'Fill out these details to verify the inbound request.',
                  visibility: 'optional' do
              field :username, 'Username', :string,
                    required: true
              field :password, 'Password', :secret_string,
                    required: true
            end
          end

          validate do |request|
            basic_auth_config = config[:basic_auth]
            next if basic_auth_config.blank?

            username, password = basic_auth_credentials(request.headers, strict: true)
            decrypted_password = decrypt_secret_string(basic_auth_config[:password])
            unless username == basic_auth_config[:username] && password == decrypted_password
              fail_job!('Invalid basic authentication header.')
            end
          end
        end

        register(:basic_auth, BasicAuth)
      end
    end
  end
end

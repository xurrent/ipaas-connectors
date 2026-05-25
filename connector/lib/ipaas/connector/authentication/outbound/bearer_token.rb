module IPaaS
  module Connector
    module Authentication
      module Outbound
        module BearerToken
          include IPaaS::Connector::Schema::Extension
          include IPaaS::Connector::Authentication::Outbound::Extension

          schema do
            field :bearer, 'Bearer token authentication', :nested,
                  hint: 'Fill out these details in case all communication must contain bearer token authentication.',
                  visibility: 'optional' do
              field :bearer_token, 'Bearer token', :secret_string,
                    required: true
            end
          end

          authenticate do |request|
            bearer = config[:bearer]
            next if bearer.blank?

            decrypted_token = decrypt_secret_string(bearer[:bearer_token])
            request.headers['Authorization'] = "Bearer #{decrypted_token}"
          end
        end

        register(:bearer, BearerToken)
      end
    end
  end
end

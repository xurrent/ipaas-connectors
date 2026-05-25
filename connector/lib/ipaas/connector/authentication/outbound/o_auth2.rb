module IPaaS
  module Connector
    module Authentication
      module Outbound
        module OAuth2
          include IPaaS::Connector::Schema::Extension
          include IPaaS::Connector::Authentication::Outbound::Extension

          schema do
            field :oauth2, 'OAuth 2', :nested,
                  hint: 'Fill out these details in case all communication uses OAuth 2.',
                  visibility: 'optional' do
              field :grant_type, 'Grant type', :string,
                    required: true,
                    enumeration: ['Client Credentials', 'Refresh Token']
              field :authorization_url, 'Authorization URL', :uri,
                    required: true
              field :client_id, 'Client ID', :string,
                    required: true
              field :client_secret, 'Client secret', :secret_string,
                    required: true
              field :refresh_token, 'Refresh token', :string
            end

            after_update do |fields, new_values|
              if new_values.key?(:oauth2)
                oauth2_field = fields.detect { |field| field.id == :oauth2 }
                requires_refresh_token = new_values[:oauth2][:grant_type] == 'Refresh Token'
                oauth2_field.field(:refresh_token).required = requires_refresh_token
              end
              fields
            end
          end

          authenticate do |request|
            oauth2_config = config[:oauth2]
            next if oauth2_config.blank?

            grant_type = oauth2_config[:grant_type]
            body = case grant_type
                   when 'Client Credentials'
                     oauth2_client_credentials_body(oauth2_config[:client_id],
                                                    decrypt_secret_string(oauth2_config[:client_secret]))
                   when 'Refresh Token'
                     oauth2_refresh_body(oauth2_config[:client_id],
                                         decrypt_secret_string(oauth2_config[:client_secret]),
                                         oauth2_config[:refresh_token])
                   else
                     raise IPaaS::Error, "Unknown grant_type: #{grant_type}"
                   end
            request.headers['Authorization'] = oauth2_authorization_header(oauth2_config[:authorization_url], body)
          end
        end

        register(:oauth2, OAuth2)
      end
    end
  end
end

module IPaaS
  module Connector
    module Authentication
      module Outbound
        module ApiKey
          include IPaaS::Connector::Schema::Extension
          include IPaaS::Connector::Authentication::Outbound::Extension

          schema do
            field :api_key, 'API key', :nested,
                  hint: 'Fill out these details in case all communication uses an API key.',
                  visibility: 'optional' do
              field :key, 'Key', :string,
                    required: true
              field :value, 'Value', :secret_string,
                    required: true
              field :placement, 'Placement', :string,
                    enumeration: ['Header', 'Query params'], # TODO: 'Cookie'
                    default: 'Header'
            end
          end

          authenticate do |request|
            api_key_config = config[:api_key]
            next if api_key_config.blank?

            container = case api_key_config[:placement]
                        when 'Header'
                          request.headers
                        else
                          request.params
                        end
            container[api_key_config[:key]] = decrypt_secret_string(api_key_config[:value])
          end
        end

        register(:api_key, ApiKey)
      end
    end
  end
end

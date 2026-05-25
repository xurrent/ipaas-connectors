module IPaaS
  module Connector
    module Authentication
      module Inbound
        module ApiKey
          include IPaaS::Connector::Schema::Extension
          include IPaaS::Connector::Authentication::Inbound::Extension

          schema do
            field :api_key, 'API key', :nested,
                  hint: 'Fill out these details to verify the inbound request.',
                  visibility: 'optional' do
              field :key, 'Key', :string,
                    required: true
              field :value, 'Value', :string,
                    required: true
              field :placement, 'Placement', :string,
                    enumeration: ['Header', 'Query params'], # TODO: 'Cookie'
                    default: 'Header'
            end
          end

          validate do |request|
            api_key_config = config[:api_key]
            next if api_key_config.blank?

            container = case api_key_config[:placement]
                        when 'Header'
                          request.headers
                        else
                          request.params
                        end
            secret = container[api_key_config[:key]]
            fail_job!('Invalid or missing API key.') unless api_key_config[:value] == secret
          end
        end

        register(:api_key, ApiKey)
      end
    end
  end
end

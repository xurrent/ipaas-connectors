module IPaaS
  module Connector
    module Authentication
      module Outbound
        module ProxyServer
          include IPaaS::Connector::Schema::Extension

          schema do
            field :proxy_server, 'Proxy server', :nested,
                  hint: 'Fill out these details in case all communication has to pass though a specific gateway.',
                  visibility: 'optional' do
              field :host, 'Host', :uri,
                    required: true,
                    pattern: /[^?]*/
              field :username, 'Username', :string
              field :password, 'Password', :secret_string
            end
          end
        end
      end
    end
  end
end

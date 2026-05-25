class MinimalConnector < IPaaS::Connector::Definition
  connector 'uuid-connector' do
    name 'Foo Connector'

    inbound_connection do
      api_key_validator
    end

    outbound_connection do
      oauth2_authenticator
    end

    trigger 'uuid-trigger' do
      name 'Foo Trigger'

      config_schema do
        field :foo,
              'Foo',
              :string
      end

      output_schema do
        field :bar,
              'Bar',
              :integer
      end

      parse do
        { bar: 42 }
      end
    end

    action 'uuid-action' do
      name 'Foo Action'

      input_schema do
        field :foo,
              'Foo',
              :string
      end

      output_schema 'minimal-output' do
        field :bar,
              'Bar',
              :integer
      end

      run do
        { schema_reference: 'minimal-output', output: { bar: 42 } }
      end
    end
  end
end

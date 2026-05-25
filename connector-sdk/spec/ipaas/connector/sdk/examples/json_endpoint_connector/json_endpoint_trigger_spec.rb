require 'spec_helper'

describe 'JSON Endpoint Trigger', :trigger do
  let(:trigger_template_id) { 'c23047dd-eb10-42b4-a67d-6ea6c58e3958' }

  let(:required_pet_schema) do
    [
      { id: 'pet', label: 'Pet', type: 'string', required: true },
    ]
  end

  let(:trigger_config) do
    {
      body_schema: required_pet_schema.dup,
    }
  end

  context 'validation' do
    context 'header without name' do
      let(:trigger_config) do
        {
          headers: [
            { name: nil },
          ],
          body_schema: required_pet_schema.dup,
        }
      end

      it 'is not valid' do
        message = "Config mapping invalid: Nested field 'headers[0]' invalid: Field 'name' is required."
        expect(trigger).not_to be_valid
        expect(trigger.full_error_messages).to eq(message)
      end
    end
  end

  context 'inbound connection' do
    context 'config' do
      it 'should allow API key validation' do
        expect(connector.inbound_connection.validators).to include(:api_key)
      end

      it 'should allow basic auth validation' do
        expect(connector.inbound_connection.validators).to include(:basic_auth)
      end
    end

    # The following API key specs are typically skipped for the provided validations.
    # When using a custom validation it is required to write specs like these though to
    # test the custom code.
    context 'api key' do
      let(:inbound_connection_config) do
        {
          api_key: {
            key: 'secret',
            value: 'boo',
            placement: 'Query params',
          },
        }
      end

      it 'should accept valid API key' do
        output = post_trigger({ pet: 'zuzu' }, params: { secret: 'boo' })
        expect(output).to eq({ body: { pet: 'zuzu' }, query_params: { secret: 'boo' }, url_postfix: nil })
      end

      it 'should validate the API key' do
        output = post_trigger({ pet: 'zuzu' }, params: { secret: 'incorrect' })
        expect(output).to eq({ error: 'Invalid or missing API key.' })
      end

      it 'should validate the API key is present' do
        output = post_trigger({ pet: 'zuzu' })
        expect(output).to eq({ error: 'Invalid or missing API key.' })
      end
    end

    # The following Basic Auth key specs are typically skipped for the provided validations.
    # When using a custom validation it is required to write specs like these though to
    # test the custom code.
    context 'basic auth' do
      let(:inbound_connection_config) do
        {
          basic_auth: {
            username: 'admin',
            password: make_secret_string('12345'),
          },
        }
      end

      it 'should accept valid basic auth request' do
        output = post_trigger({ pet: 'zuzu' }, basic_auth: %w[admin 12345])
        expect(output).to eq({ body: { pet: 'zuzu' }, query_params: {}, url_postfix: nil })
      end

      it 'should validate basic auth is provided' do
        output = post_trigger({ pet: 'zuzu' })
        expect(output).to eq({ error: 'Missing basic authentication header.' })
      end

      it 'should validate basic auth is correct' do
        output = post_trigger({ pet: 'zuzu' }, basic_auth: %w[admin 54321])
        expect(output).to eq({ error: 'Invalid basic authentication header.' })
      end
    end
  end

  context 'config_schema' do
    it 'should require a body schema' do
      expect(trigger.config_schema.field(:body_schema).required).to be_truthy
    end

    it 'should keep headers optional' do
      expect(trigger.config_schema.field(:headers).required).to be_falsey
    end

    it 'should require a header name in case a header is added' do
      expect(trigger.config_schema.field(:headers).field(:name).required).to be_truthy
    end

    it 'should validate the pattern of the header name' do
      expect(trigger.config_schema.field(:headers).field(:name).pattern).to eq(/[A-Za-z0-9\-_]+/)
    end
  end

  context 'parse request' do
    context 'body schema' do
      let(:trigger_config) do
        {
          body_schema: [
            { id: 'cars', label: 'Cars', type: 'nested', array: true, fields: [
              { id: 'nr', label: 'Nr', type: 'integer', min: 1, max: 99 },
              { id: 'driver', label: 'Driver', type: 'string' },
            ], },
            { id: 'pet', label: 'Pet', type: 'string', required: true },
          ],
        }
      end

      it 'should return the incoming request when it is valid' do
        cars = [{ nr: 33, driver: 'MV' }, { nr: 44, driver: 'LH' }]
        output = post_trigger({ pet: 'Zuzu', cars: cars })
        expect(output).to eq({ body: { pet: 'Zuzu', cars: cars }, query_params: {}, url_postfix: nil })
      end

      it 'should handle get' do
        output = get_trigger
        # NOTE: the body field of the output schema is not required
        expect(output).to eq({ body: '', query_params: {}, url_postfix: nil })
      end

      it 'should complain when required param is missing' do
        output = post_trigger({ cars: { nr: 33, driver: 'MV' } })
        expect(output).to eq({ error: "Output invalid: Nested field 'body' invalid: Field 'pet' is required." })
      end

      it 'should ensure the type check is performed' do
        output = post_trigger({ pet: { nr: 33, driver: 'MV' } })
        msg = "Output invalid: Nested field 'body' invalid: Type of field 'pet' invalid, expected String found Hash."
        expect(output).to eq({ error: msg })
      end

      it 'should complain when value is out of range' do
        output = post_trigger({ pet: 'Zuzu', cars: { nr: 333, driver: 'MV' } })
        nr_error_message = "Field 'nr' should be at most 99."
        expect(output).to eq({
          error: "Output invalid: Nested field 'body' invalid: Nested field 'cars[0]' invalid: #{nr_error_message}",
        })
      end

      it 'should encrypt secret strings in the output' do
        trigger_config[:body_schema].last[:type] = 'secret_string'

        cars = [{ nr: 33, driver: 'MV' }, { nr: 44, driver: 'LH' }]
        output = post_trigger({ pet: 'Zuzu', cars: cars })
        expect(encryptor.decrypt(output[:body][:pet])).to eq('Zuzu')
      end

      it 'should encrypt secret strings in nested fields in the output' do
        trigger_config[:body_schema].first[:fields].last[:type] = 'secret_string'

        cars = [{ nr: 33, driver: 'MV' }, { nr: 44, driver: 'LH' }]
        output = post_trigger({ pet: 'Zuzu', cars: cars })
        expect(output[:body][:cars]
          .pluck(:driver)
          .map { |s| encryptor.decrypt(s) }).to eq(%w[MV LH])
      end
    end

    context 'headers' do
      context 'optional header' do
        let(:trigger_config) do
          {
            headers: [
              { name: 'optional-header' },
            ],
            body_schema: required_pet_schema.dup,
          }
        end

        it 'should return the incoming request when it is valid and we send name as symbol' do
          output = post_trigger({ pet: 'zuzu' }, headers: { optional_header: 'foo' })
          expect(output).to eq({ body: { pet: 'zuzu' }, headers: { 'optional-header': 'foo' }, query_params: {},
                                 url_postfix: nil, })
        end

        it 'should return the incoming request when it is valid and we send name as string' do
          output = post_trigger({ pet: 'zuzu' }, headers: { 'optional-header' => 'foo' })
          expect(output).to eq({ body: { pet: 'zuzu' }, headers: { 'optional-header': 'foo' }, query_params: {},
                                 url_postfix: nil, })
        end

        it 'should return the incoming request when no headers are provided' do
          output = post_trigger({ pet: 'zuzu' })
          expect(output).to eq({ body: { pet: 'zuzu' }, headers: {}, query_params: {}, url_postfix: nil })
        end
      end

      context 'required header' do
        let(:trigger_config) do
          {
            headers: [
              { name: 'optional-header' },
              { name: 'required-header', required: true },
            ],
            body_schema: required_pet_schema.dup,
          }
        end

        it 'should return the incoming request when it is valid' do
          output = post_trigger({ pet: 'zuzu' }, headers: { required_header: 'foo' })
          expect(output).to eq({ body: { pet: 'zuzu' }, headers: { 'required-header': 'foo' }, query_params: {},
                                 url_postfix: nil, })
        end

        it 'should complain when required header is missing' do
          output = post_trigger({ pet: 'zuzu' }, headers: { optional_header: 'foo' })
          expect(output).to eq({
            error: "Output invalid: Nested field 'headers' invalid: Field 'required-header' is required.",
          })
        end

        it 'should complain when no headers are provided' do
          output = post_trigger({ pet: 'zuzu' })
          expect(output).to eq({
            error: "Output invalid: Field 'headers' is required.",
          })
        end
      end

      context 'array header' do
        let(:trigger_config) do
          {
            headers: [
              { name: 'array-header', array: true },
            ],
            body_schema: required_pet_schema.dup,
          }
        end

        it 'should return the incoming request when it is valid' do
          output = post_trigger({ pet: 'zuzu' }, headers: { array_header: %w[foo bar] })
          expect(output).to eq({ body: { pet: 'zuzu' }, headers: { 'array-header': %w[foo bar] }, query_params: {},
                                 url_postfix: nil, })
        end

        it 'should convert single value to array' do
          output = post_trigger({ pet: 'zuzu' }, headers: { array_header: 'foo' })
          expect(output).to eq({ body: { pet: 'zuzu' }, headers: { 'array-header': ['foo'] }, query_params: {},
                                 url_postfix: nil, })
        end

        it 'should return the incoming request when no headers are provided' do
          output = post_trigger({ pet: 'zuzu' })
          expect(output).to eq({ body: { pet: 'zuzu' }, headers: {}, query_params: {}, url_postfix: nil })
        end
      end

      context 'job context identifier header' do
        it 'should return the incoming request when it is valid' do
          expect(runbook).to receive(:store_job_context_identifier).with('foo')
          output = post_trigger({ pet: 'zuzu' }, headers: { 'x-job-context-identifier': 'foo' })
          expect(output).to eq({ body: { pet: 'zuzu' }, query_params: {}, url_postfix: nil })
        end
      end
    end

    context 'url_postfix' do
      it 'should extract url_postfix from request params' do
        output = post_trigger({ pet: 'zuzu' }, params: { url_postfix: '/my/custom/path' })
        expect(output[:url_postfix]).to eq('/my/custom/path')
      end

      it 'should return nil when url_postfix is not provided' do
        output = post_trigger({ pet: 'zuzu' })
        expect(output[:url_postfix]).to be_nil
      end

      it 'should handle empty url_postfix' do
        output = post_trigger({ pet: 'zuzu' }, params: { url_postfix: '' })
        expect(output[:url_postfix]).to eq('')
      end
    end

    context 'query_params' do
      it 'should extract query parameters from request params' do
        output = post_trigger({ pet: 'zuzu' }, params: { foo: 'bar', baz: 'qux' })
        expect(output[:query_params]).to eq({ foo: 'bar', baz: 'qux' })
      end

      it 'should return empty hash when no query parameters are provided' do
        output = post_trigger({ pet: 'zuzu' })
        expect(output[:query_params]).to eq({})
      end
    end

    context 'url_postfix and query_params with headers' do
      let(:trigger_config) do
        {
          headers: [
            { name: 'custom-header' },
          ],
          body_schema: required_pet_schema.dup,
        }
      end

      it 'should return all three: url_postfix, query_params, headers, and body' do
        output = post_trigger(
          { pet: 'zuzu' },
          params: { foo: 'bar' },
          headers: { custom_header: 'header-value' }
        )
        expect(output).to eq({
          url_postfix: nil,
          query_params: { foo: 'bar' },
          headers: { 'custom-header': 'header-value' },
          body: { pet: 'zuzu' },
        })
      end
    end
  end
end

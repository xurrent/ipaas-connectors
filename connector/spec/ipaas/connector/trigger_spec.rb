require 'spec_helper'

describe IPaaS::Connector::Trigger do
  def request_double(params: {}, body: '')
    double(params: params, body: StringIO.new(body.to_s))
  end

  let(:runbook) do
    IPaaS::Connector::Runbook.new('runbook_uuid').tap do |runbook|
      allow(runbook).to receive(:account_id) { 5 } # TODO: solution is unknown in the connector gem...
    end
  end

  context 'parsing' do
    it 'should validate a runbook is provided' do
      expect do
        IPaaS::Connector::Trigger.parse(nil, {})
      end.to raise_error('Trigger must have a runbook with uuid.')
    end

    it 'should validate the runbook has a uuid' do
      expect do
        IPaaS::Connector::Trigger.parse({}, {})
      end.to raise_error('Trigger must have a runbook with uuid.')
    end

    it 'should validate the given value is a hash' do
      expect do
        IPaaS::Connector::Trigger.parse(runbook, [1, 2])
      end.to raise_error('Trigger must be a hash.')
    end
  end

  context 'when updating output fields in config after_update hook' do
    let(:connector) do
      IPaaS::Connector::Connector.new('unique-connector-id') do
        inbound_connection do
          config_schema do
            field :foo, 'Foo', :string
          end
          validate do |request|
            unless request.params[:foo] == config[:foo]
              discard_trigger_event!("Request param 'foo' should equal '#{config[:foo]}'")
            end
          end
        end

        trigger 'unique-trigger-id' do
          name 'JSON'

          config_schema do
            field :root_key,
                  'Root key',
                  :string,
                  required: true

            after_update do |_fields|
              root_key = trigger.config[:root_key]
              output_schema.fields.first&.id = root_key&.to_sym unless root_key == 'skip_schema_update'
              output_schema.fields.first&.type = (root_key == 'output_schema_error' ? :no_type : :hash)
            end
          end

          output_schema 'unique-output-id' do
            field :root, 'Root', :hash
            field :expanded, 'Expanded', :string if trigger.config[:root_key] == 'expand_output'
          end

          helper :my_object_id do
            object_id
          end

          parse do |request|
            raise IPaaS::Job::DiscardTriggerEvent if request.params.key?(:discard_me)

            log("Parse called with #{job_context_identifier}")
            self.job_context_identifier = '1'
            root_key = config[:root_key]
            p = request.params
            p[:object_id] = helpers.my_object_id if request.params.key?(:object_id)
            { root_key.to_sym => p }
          end

          respond_with do |context, response|
            root_key = config[:root_key]
            log("trigger template respond_with: #{root_key}")
            custom_body = JSON.parse(response[:body])
            custom_body['req_params'] = context[:request].params
            custom_body[root_key] = context[:trigger_output]
            custom_body["x-#{root_key}-job-uuid"] = context[:job_uuid]
            response[:body] = custom_body.to_json
            response[:headers]['x-myheader'] = 'foo'
            response[:headers].delete('header-to-remove')
            response[:status] = 202
            response
          end

          provision do
            log("trigger template after create: #{config[:root_key]}")
          end

          deprovision do
            log("trigger template after destroy: #{config[:root_key]}")
          end
        end
      end
    end

    let(:inbound_connection) do
      IPaaS::Connector::Connection.parse(
        {
          uuid: 'inbound_connection_uuid',
          direction: 'inbound',
          name: 'test inbound connection',
          description: 'Test description',
          connector: {
            uuid: connector.uuid,
          },
          config_mapping: [
            { field_id: 'foo', fixed: 'barbie' },
          ],
        },
      )
    end

    let(:trigger) do
      @root_key ||= 'beetroot'

      IPaaS::Connector::Trigger.parse(
        runbook,
        {
          description: 'Test description',
          inbound_connection: {
            uuid: inbound_connection.uuid,
          },
          trigger_template: {
            uuid: connector.trigger('unique-trigger-id').uuid,
          },
          config_mapping: [
            { field_id: 'root_key', fixed: @root_key },
          ],
        },
      )
    end

    context 'validation' do
      it 'should be valid' do
        expect(trigger).to be_valid
      end

      it 'should validate connection is required' do
        expect(trigger.inbound_connection.uuid).to eq('inbound_connection_uuid')
        trigger.inbound_connection = nil
        expect(trigger).not_to be_valid
        expect(trigger.errors[:inbound_connection]).to eq(["can't be blank."])
      end

      it 'should validate trigger template is required' do
        expect(trigger.trigger_template.uuid).to eq('unique-trigger-id')
        trigger.trigger_template = nil
        expect(trigger).not_to be_valid
        expect(trigger.errors[:trigger_template]).to eq(["can't be blank."])
      end

      it 'should validate the config' do
        invalid_trigger = IPaaS::Connector::Trigger.parse(
          runbook,
          {
            description: 'Test description',
            connector: {
              uuid: connector.uuid,
            },
            trigger_template: {
              uuid: connector.trigger('unique-trigger-id').uuid,
            },
          }.to_yaml
        )
        expect(invalid_trigger).not_to be_valid
        expect(invalid_trigger.errors[:config_mapping]).to include("invalid: Field 'root_key' is required.")
      end

      it 'should validate the config mapping' do
        invalid_trigger = IPaaS::Connector::Trigger.parse(
          runbook,
          {
            description: 'Test description',
            connector: {
              uuid: connector.uuid,
            },
            trigger_template: {
              uuid: connector.trigger('unique-trigger-id').uuid,
            },
            config_mapping: [
              { field_id: 'root_key', proc: 'unknown(3)' },
            ],
          }.to_yaml
        )
        expect(invalid_trigger).not_to be_valid
        message = "(root_key) invalid: Proc invalid: Method 'unknown' not allowed."
        expect(invalid_trigger.errors[:config_mapping]).to include(message)
      end

      it 'should validate the generated output schema' do
        @root_key = 'output_schema_error'
        expect(trigger).not_to be_valid
        message = 'Schema (unique-output-id) invalid: Field (output_schema_error) invalid: Type should be one of'
        expect(trigger.errors[:output_schema].first).to start_with(message)

        # also invalid when validated for second time
        expect(trigger).not_to be_valid

        # fix the config
        trigger.config_mapping.first.fixed = 'ok'
        trigger.config(resolve: true)
        expect(trigger).to be_valid

        # remains valid when validated again
        expect(trigger).to be_valid

        trigger.config_mapping.first.fixed = 'output_schema_error'
        trigger.config(resolve: true)
        expect(trigger).not_to be_valid
      end

      it 'should ignore output schema validation when missing' do
        trigger.output_schema.valid?
        expect(trigger).to be_valid

        allow(trigger.output_schema).to receive(:errors) { [] }
        expect(trigger).to be_valid

        allow(trigger).to receive(:output_schema) { nil }
        expect(trigger).to be_valid
      end
    end

    context 'uuid' do
      it 'delegates uuid to runbook' do
        expect(trigger.uuid).to eq(runbook.uuid)
      end
    end

    it 'should define a self reference' do
      expect(trigger.trigger).to eq(trigger)
    end

    context 'parse_request' do
      it 'should validate the request using the inbound connection template' do
        request = request_double(params: { foo: 'not barbie' })
        expect do
          trigger.parse_request(request)
        end.to raise_error(IPaaS::Job::DiscardTriggerEvent, "Request param 'foo' should equal 'barbie'")
      end

      it 'should return the output' do
        request = request_double(params: { foo: 'barbie', bar: { baz: 'qux' } })
        result = trigger.parse_request(request)
        expect(result).to eq({ 'beetroot' => { 'bar' => { 'baz' => 'qux' }, 'foo' => 'barbie' } })
      end

      it 'raises discard trigger event error' do
        request = request_double(params: { foo: 'barbie', discard_me: true })
        expect(runbook).not_to receive(:store_trigger_output)
        expect { trigger.parse_request(request) }.to raise_error(IPaaS::Job::DiscardTriggerEvent)
      end

      it 'has helpers with trigger as context' do
        request = request_double(params: { foo: 'barbie', bar: { baz: 'qux' }, object_id: 'a' })
        result = trigger.parse_request(request)
        expect(result).to eq({ 'beetroot' => { 'bar' => { 'baz' => 'qux' }, 'foo' => 'barbie',
                                               'object_id' => trigger.object_id, } })
      end

      context 'job context identifier' do
        it 'should store job context in runbook job state' do
          logs = []
          allow(trigger).to receive(:log) { |msg| logs << msg }

          request1 = request_double(params: { foo: 'barbie', bar: { baz: 'qux' }, object_id: 'a' })
          trigger.parse_request(request1)
          expect(runbook.job_context_identifier).to eq('1')

          runbook.job_state.store.clear
          expect(runbook.job_context_identifier).to be_nil

          # next request does not see identifier from previous request but starts with nil again
          request2 = request_double(params: { foo: 'barbie', bar: { baz: 'foo' }, object_id: 'b' })
          trigger.parse_request(request2)

          expect(logs).to contain_exactly('Parse called with ',
                                          'Parse called with ',)
        end
      end
    end

    context 'prepare_default_response' do
      it 'creates JSON response with job id' do
        job_uuid = SecureRandom.uuid_v7
        result = trigger.prepare_default_response({ job_uuid: job_uuid }, {})
        expect(result).to eq({
          status: 200,
          body: %({"job_uuid":"#{job_uuid}"}),
          headers: { 'content-type': 'application/json; charset=utf-8',
                     'x-job-uuid': job_uuid, }.with_indifferent_access,
        })
      end

      it 'keeps default headers with job' do
        result = trigger.prepare_default_response({ job_uuid: '3' }, { 'X-b': 8 })
        expect(result).to eq({
          status: 200,
          body: '{"job_uuid":"3"}',
          headers: { 'X-b': 8, 'content-type': 'application/json; charset=utf-8',
                     'x-job-uuid': '3', }.with_indifferent_access,
        })
      end

      it 'keeps default headers without job' do
        result = trigger.prepare_default_response({}, { a: 'h' })
        expect(result).to eq({
          status: 200,
          body: ' ',
          headers: { a: 'h', 'content-type': 'text/plain; charset=utf-8' }.with_indifferent_access,
        })
      end

      it 'handles no job value' do
        result = trigger.prepare_default_response({}, {})
        expect(result).to eq({
          status: 200,
          body: ' ',
          headers: { 'content-type': 'text/plain; charset=utf-8' }.with_indifferent_access,
        })
      end

      it 'handles no job id' do
        result = trigger.prepare_default_response({ job_uuid: nil }, {})
        expect(result).to eq({
          status: 200,
          body: ' ',
          headers: { 'content-type': 'text/plain; charset=utf-8' }.with_indifferent_access,
        })
      end
    end

    context 'respond_with' do
      it 'should delegate respond_with to the trigger template' do
        logs = []
        allow(trigger).to receive(:log) { |msg| logs << msg }
        request = request_double(params: { foo: 'not barbie' })
        job = double(uuid: 2)
        trigger.runbook.store_trigger_output({ abc: :foo })
        default_headers = { 'default-header': 'my default value', 'header-to-remove': 'please remove me' }

        result = trigger.respond_with(request, job, default_headers)

        expect(logs.last).to eq('trigger template respond_with: beetroot')
        expect(result[:status]).to eq(202)
        expect(result[:body]).to eq(<<~JSON.strip)
          {"job_uuid":"2","req_params":{"foo":"not barbie"},"beetroot":{"abc":"foo"},"x-beetroot-job-uuid":"2"}
        JSON
        expect(result[:headers]).to eq({
          'default-header': 'my default value',
          'x-job-uuid': '2',
          'x-myheader': 'foo',
          'content-type': 'application/json; charset=utf-8',
        }.with_indifferent_access)
      end
    end

    context 'provision' do
      it 'should delegate provision to the trigger template' do
        logs = []
        allow(trigger).to receive(:log) { |msg| logs << msg }
        trigger.provision
        expect(logs.first).to eq('trigger template after create: beetroot')
      end
    end

    context 'deprovision' do
      it 'should delegate deprovision to the trigger template' do
        logs = []
        allow(trigger).to receive(:log) { |msg| logs << msg }
        trigger.deprovision
        expect(logs.first).to eq('trigger template after destroy: beetroot')
      end
    end

    context 'successor' do
      it 'should find the runbook action without predecessor action' do
        trigger.runbook.actions = [IPaaS::Connector::Action.new('empty-action')]
        expect(trigger.successor.reference).to eq('empty-action')
      end

      it 'should not find runbook action with predecessor action' do
        trigger.runbook.actions = [IPaaS::Connector::Action.new('empty-action')]
        trigger.runbook.actions.first.predecessor_action_reference = 'foo'
        expect(trigger.successor).to be_nil
      end

      it 'should return nil when there is no runbook' do
        trigger.runbook = nil
        expect(trigger.successor).to be_nil
      end

      it 'should return nil when the runbook has no actions' do
        trigger.runbook.actions = nil
        expect(trigger.successor).to be_nil
      end
    end
  end

  context 'when regenerating output fields from config after_update hook' do
    let(:connector) do
      IPaaS::Connector::Connector.new('unique-connector-id') do
        trigger 'unique-trigger-id' do
          name 'JSON'

          config_schema do
            field :root_key,
                  'Root key',
                  :string,
                  required: true

            after_update do |_fields|
              regenerate_schema(output_schema)
            end
          end

          output_schema 'unique-output-id' do
            field trigger.config[:root_key], 'Root', :hash
            field :expanded, 'Expanded', :string if trigger.config[:root_key] == 'expand_output'
          end

          parse do |request|
            root_key = config[:root_key]
            { root_key.to_sym => request.params }.tap do |h|
              h[:expanded] = 'more data' if root_key == 'expand_output'
            end
          end
        end
      end
    end

    let(:inbound_connection) do
      IPaaS::Connector::Connection.parse(
        {
          uuid: 'inbound_connection_uuid',
          direction: 'inbound',
          name: 'test inbound connection',
          description: 'Test description',
          connector: {
            uuid: connector.uuid,
          },
        },
      )
    end

    let(:trigger) do
      @root_key ||= 'beetroot'

      IPaaS::Connector::Trigger.parse(
        runbook,
        {
          description: 'Test description',
          inbound_connection: {
            uuid: inbound_connection.uuid,
          },
          trigger_template: {
            uuid: connector.trigger('unique-trigger-id').uuid,
          },
          config_mapping: [
            { field_id: 'root_key', fixed: @root_key },
            { field_id: 'url_postfix', fixed: 'some/url/path?with=some&query=params' },
          ],
        },
      )
    end

    context 'parse_request' do
      it 'should return the output' do
        request = request_double(params: { foo: 'barbie', bar: { baz: 'qux' } })
        result = trigger.parse_request(request)
        expect(result).to eq({ 'beetroot' => { 'bar' => { 'baz' => 'qux' }, 'foo' => 'barbie' } })
      end

      it 'should expand the output schema' do
        @root_key = 'expand_output'
        request = request_double(params: { foo: 'barbie' })
        result = trigger.parse_request(request)
        expect(result).to eq({ 'expand_output' => { 'foo' => 'barbie' }, 'expanded' => 'more data' })
      end
    end

    context 'endpoint' do
      it 'should return the trigger end point with URL postfix' do
        expect(trigger.endpoint).to eq('https://ipaas.com/inbound/5/runbook_uuid/some/url/path?with=some&query=params')
      end

      it 'should return the trigger end point without URL postfix' do
        trigger.config[:url_postfix] = nil
        expect(trigger.endpoint).to eq('https://ipaas.com/inbound/5/runbook_uuid')
      end

      it 'should include solution uuid when present' do
        solution = double
        expect(solution).to receive(:uuid).and_return('solution_uuid')
        allow(trigger.runbook).to receive(:solution).and_return(solution)

        expect(trigger.endpoint).to eq('https://ipaas.com/inbound/5/solution_uuid/runbook_uuid/some/url/path?with=some&query=params')
      end

      it 'should generate endpoint without account_id' do
        allow(runbook).to receive(:account_id) { nil }
        trigger.config[:url_postfix] = nil
        expect(trigger.endpoint).to eq('https://ipaas.com/inbound/runbook_uuid')
      end

      it 'should generate endpoint without runbook' do
        trigger.runbook = nil
        trigger.config[:url_postfix] = nil
        expect(trigger.endpoint).to eq('https://ipaas.com/inbound')
      end

      it 'should generate endpoint without runbook uuid' do
        trigger.runbook.uuid = nil
        trigger.config[:url_postfix] = nil
        expect(trigger.endpoint).to eq('https://ipaas.com/inbound/5')
      end
    end

    context 'respond_with' do
      it 'default response handles no job and no trigger output' do
        default_headers = { 'default-header': 'my default value' }

        result = trigger.respond_with(double, nil, default_headers)

        expect(default_headers.object_id).not_to eq(result.object_id)
        expect(result[:status]).to eq(200)
        expect(result[:body]).to eq(' ')
        expect(result[:headers]).to eq({
          'default-header': 'my default value',
          'content-type': 'text/plain; charset=utf-8',
        }.with_indifferent_access)
      end
    end
  end

  context 'when sending outbound http requests from the trigger' do
    let(:connector) do
      IPaaS::Connector::Connector.new('unique-connector-id') do
        outbound_connection do
          config_schema do
            field :installation,
                  'Installation',
                  :string,
                  required: true,
                  enumeration: [
                    { id: 'com', label: 'EU Production' },
                    { id: 'qa', label: 'EU QA' },
                  ]
          end
        end

        trigger 'unique-trigger-id' do
          name 'JSON'
          outbound_traffic true

          config_schema do
            field :path,
                  'Path',
                  :string,
                  required: true
          end

          output_schema 'unique-output-id' do
            field :result, 'Result', :string
          end

          parse do |request|
            response = http_post("https://example.#{outbound_connection.config[:installation]}/#{config[:path]}",
                                 request.params.to_json)
            { result: response.body }
          end
        end
      end
    end

    let(:inbound_connection) do
      IPaaS::Connector::Connection.parse(
        {
          uuid: 'inbound_connection_uuid',
          direction: 'inbound',
          name: 'test inbound connection',
          description: 'Test description',
          connector: {
            uuid: connector.uuid,
          },
        },
      )
    end

    let(:outbound_connection) do
      IPaaS::Connector::Connection.parse(
        {
          uuid: 'outbound_connection_uuid',
          direction: 'outbound',
          name: 'test outbound connection',
          description: 'Test description',
          connector: {
            uuid: connector.uuid,
          },
          config_mapping: [
            { field_id: 'installation', fixed: 'qa' },
          ],
        },
      )
    end

    let(:trigger) do
      @root_key ||= 'beetroot'

      IPaaS::Connector::Trigger.parse(
        runbook,
        {
          description: 'Test description',
          inbound_connection: {
            uuid: inbound_connection.uuid,
          },
          outbound_connection: {
            uuid: outbound_connection.uuid,
          },
          trigger_template: {
            uuid: connector.trigger('unique-trigger-id').uuid,
          },
          config_mapping: [
            { field_id: 'path', fixed: 'my/path' },
          ],
        },
      )
    end

    it 'should parse the description' do
      expect(trigger.description).to eq('Test description')
    end

    context 'validation' do
      it 'should validate the outbound connection is present when outbound_traffic is true' do
        expect(trigger).to be_valid
        trigger.outbound_connection = nil
        expect(trigger).not_to be_valid
        expect(trigger.errors[:outbound_connection]).to eq(["can't be blank."])
      end
    end

    context 'parse_request' do
      it 'should call the external server using the outbound connection' do
        stub_request(:post, 'https://example.qa/my/path')
          .with(
            body: '{"foo":"barbie","bar":{"baz":"qux"}}',
            headers: {
              'User-Agent' => 'Xurrent iPaaS',
            }
          )
          .to_return(status: 200, body: 'response ID', headers: {})

        request = request_double(params: { foo: 'barbie', bar: { baz: 'qux' } })
        result = trigger.parse_request(request)
        expect(result).to eq({ 'result' => 'response ID' })
      end
    end

    context 'blueprint' do
      let(:blueprint_connector) do
        IPaaS::Connector::Connector.new('blueprint-connector-id') do
          inbound_connection do
            config_schema do
              field :foo, 'Foo', :string
            end
          end

          outbound_connection do
            config_schema do
              field :installation, 'Installation', :string
            end
          end

          trigger 'blueprint-trigger-id' do
            name 'Painting'
            outbound_traffic true
            blueprint_filenames %w[default_palette.txt shape_palette.json]

            config_schema do
              field :shape, 'Shape', :string
            end

            output_schema do
              field :shape, 'Shape', :string
              field :color, 'Color', :string
            end

            helper :my_object_id do
              object_id
            end

            parse do |request|
              p = request.params
              { shape: config[:shape], color: p[:color] }
            end

            extract_blueprint do
              installation = outbound_connection.config[:installation]
              blueprint_store.write('default_palette.txt', 'pink,blue,red')
              blueprint_store.write('shape_palette.json', "#{trigger.config[:shape]}-colors-#{installation}")
            end

            provision do
              trigger.store.write('default', blueprint_store.read('default_palette.txt'))
              trigger.store.write('shape', blueprint_store.read('shape_palette.json'))
            end
          end
        end
      end

      let(:blueprint_trigger) do
        IPaaS::Connector::Trigger.parse(
          runbook,
          {
            description: 'Test description',
            inbound_connection: {
              uuid: inbound_connection.uuid,
            },
            outbound_connection: {
              uuid: outbound_connection.uuid,
              config_mapping: [
                { field_id: 'installation', fixed: 'QA' },
              ],
            },
            trigger_template: {
              uuid: blueprint_connector.trigger('blueprint-trigger-id').uuid,
            },
            config_mapping: [
              { field_id: 'shape', fixed: 'circle' },
            ],
            blueprint_checksum: '0195f101',
          },
        )
      end

      it 'should be valid' do
        expect(blueprint_trigger).to be_valid
      end

      it 'should validate blueprint_checksum is set when blueprint is required' do
        blueprint_trigger.blueprint_checksum = nil
        expect(blueprint_trigger).not_to be_valid
        expect(blueprint_trigger.errors[:blueprint_checksum]).to eq([
          'Blueprint files must be extracted to support provisioning.',
        ])

        blueprint_trigger.extract_blueprint
        expect(blueprint_trigger).to be_valid
      end

      describe 'extract_blueprint' do
        it 'should extract' do
          blueprint_trigger.blueprint_checksum = nil
          expect(blueprint_trigger.blueprint_store.read('default_palette.txt')).to be_nil
          expect(blueprint_trigger.blueprint_store.read('shape_palette.json')).to be_nil

          blueprint_trigger.extract_blueprint
          expect(blueprint_trigger.blueprint_store.read('default_palette.txt')).to eq('pink,blue,red')
          expect(blueprint_trigger.blueprint_store.read('shape_palette.json')).to eq('circle-colors-qa')
          expect(blueprint_trigger.blueprint_checksum).not_to be_nil
        end

        it 'should not fail when no blueprint is present' do
          expect(trigger.extract_blueprint).to be_nil
        end

        it 'should update the checksum when the blueprint changes' do
          blueprint_trigger.extract_blueprint
          checksum = blueprint_trigger.blueprint_checksum

          blueprint_trigger.config[:shape] = 'rectangle'
          blueprint_trigger.extract_blueprint
          expect(checksum).not_to eq(blueprint_trigger.blueprint_checksum)

          blueprint_trigger.config[:shape] = 'circle' # back to original
          blueprint_trigger.extract_blueprint
          expect(checksum).to eq(blueprint_trigger.blueprint_checksum)
        end

        it 'should clear the blueprint files before extracting' do
          blueprint_trigger.extract_blueprint
          expect(blueprint_trigger.blueprint_store.read('default_palette.txt')).to eq('pink,blue,red')
          expect(blueprint_trigger.blueprint_store.read('shape_palette.json')).to eq('circle-colors-qa')
          expect(blueprint_trigger.blueprint_checksum).not_to be_nil

          # fake an error during extraction
          expect(blueprint_trigger.trigger_template).to receive(:call_function).and_raise('Noop')
          expect do
            blueprint_trigger.extract_blueprint
          end.to raise_error('Noop')

          expect(blueprint_trigger.blueprint_checksum).to be_nil
          expect(blueprint_trigger.blueprint_store.read('default_palette.txt')).to be_nil
          expect(blueprint_trigger.blueprint_store.read('shape_palette.json')).to be_nil
        end
      end

      describe 'provision' do
        it 'should be able to access the blueprint files during provisioning' do
          blueprint_trigger.blueprint_store.write('default_palette.txt', 'foo-colors')
          blueprint_trigger.blueprint_store.write('shape_palette.json', 'foo-shape-json')
          expect(blueprint_trigger.store.read('default')).to be_nil
          expect(blueprint_trigger.store.read('shape')).to be_nil

          blueprint_trigger.provision
          expect(blueprint_trigger.store.read('default')).to eq('foo-colors')
          expect(blueprint_trigger.store.read('shape')).to eq('foo-shape-json')
        end
      end
    end
  end
end

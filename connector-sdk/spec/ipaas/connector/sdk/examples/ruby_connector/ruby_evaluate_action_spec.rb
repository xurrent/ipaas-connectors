require 'spec_helper'

describe 'Ruby Eval Action', :action do
  let(:action_template_id) { 'da0f63d9-5281-4919-8613-3ec5554505ab' }

  context 'input_schema' do
    it 'should require ruby proc' do
      expect(action.input_schema.field(:proc).required).to be_truthy
    end

    it 'should not require input_schema' do
      expect(action.input_schema.field(:input_schema).required).to be_falsey
    end

    it 'should not require output_schema' do
      expect(action.input_schema.field(:output_schema).required).to be_falsey
    end

    it 'should not require input' do
      expect(action.input_schema.field(:input).required).to be_falsey
    end

    it 'makes input required when there is a required field in the input schema' do
      input_schema = [
        { id: 'i', label: 'Number', type: 'integer', required: true },
      ]
      input = { input_schema: input_schema, proc: 'a = 1' }
      result = action(input)
      expect(result.errors.map(&:message)).to eq(["invalid: Field 'input' is required."])
    end

    it 'adds fields defined in the input_schema to the input field' do
      input_schema = [
        { id: 'i', label: 'Number', type: 'integer', required: true },
        { id: 'a', label: 'First string', type: 'string', required: true },
        { id: 'b', label: 'Second string', type: 'string', required: true },
      ]
      input = { input_schema: input_schema, proc: 'a=1', input: { i: 1, a: 'a', b: 'b' } }
      result = action(input)
      expect(result.errors).to be_empty
      expect(result.input_schema.fields.length).to eq(4)
      expect(result.input_schema.fields.last.id).to eq(:input)
      expect(result.input_schema.fields.last.fields.map(&:id)).to eq([:i, :a, :b])
      expect(result.input_schema.fields.last.fields.map(&:type)).to eq([:integer, :string, :string])
    end

    it 'validates proc field' do
      input_schema = [
        { id: 'i', label: 'Number', type: 'integer', required: true },
      ]
      input = {
        input_schema: input_schema,
        proc: 'action_output("bad_action") + i + action_output("good") + action_output("bad_action2")',
        input: { i: 1 },
      }
      MockedAction = Struct.new(:reference)
      expect_any_instance_of(IPaaS::Connector::Action)
        .to receive(:other_actions)
        .and_return([MockedAction.new(reference: 'good')])
      result = action(input)
      expect(result.errors.map(&:message)).to eq(
        ["(proc) invalid action references: 'bad_action', 'bad_action2'"]
      )
    end

    it 'validates input fields' do
      input_schema = [
        { id: 'i', label: 'Number', type: 'integer', required: true },
        { id: 'a', label: 'First string', type: 'string', required: true },
        { id: 'b', label: 'Second string', type: 'string', required: true },
      ]
      input = { input_schema: input_schema, proc: 'a=1', input: { i: 'wrong', a: Date.current, c: 42 } }
      result = action(input)
      expect(result.errors.map(&:message)).to eq(
        ['invalid: ' \
         "Nested field 'input' invalid: Type of field 'i' invalid, expected Integer found String. " \
         "Nested field 'input' invalid: Type of field 'a' invalid, expected String found Date. " \
         "Nested field 'input' invalid: Field 'b' is required."]
      )
    end

    it 'adds fields defined in the output_schema to the output field' do
      output_schema = [
        { id: 'i', label: 'Number', type: 'integer', required: true },
        { id: 'a', label: 'First string', type: 'string', required: true },
        { id: 'b', label: 'Second string', type: 'string', required: true },
      ]
      input = { output_schema: output_schema, proc: 'a=1' }
      result = action(input)
      expect(result.errors).to be_empty
      expect(result.output_schema.first.fields.last.id).to eq(:results)
      expect(result.output_schema.first.fields.last.fields.map(&:id)).to eq([:i, :a, :b])
      expect(result.output_schema.first.fields.last.fields.map(&:type)).to eq([:integer, :string, :string])
    end

    it 'validates output fields' do
      output_schema = [
        { id: 'i', label: 'Number', type: 'integer', required: true },
        { id: 'a', label: 'First string', type: 'string', required: true },
        { id: 'b', label: 'Second string', type: 'string', required: true },
      ]
      proc = <<~RUBY
        output[:i] = "wrong"
        output[:a] = Date.current
        output[:c] = 42
      RUBY
      input = { output_schema: output_schema, proc: proc }
      expect { action(input).run }.to raise_error(
        IPaaS::Job::FailJob,
        'Output [] invalid: ' \
        "Nested field 'results' invalid: Type of field 'i' invalid, expected Integer found String. " \
        "Nested field 'results' invalid: Type of field 'a' invalid, expected String found Date. " \
        "Nested field 'results' invalid: Field 'b' is required."
      )
    end
  end

  context 'run' do
    [
      [{ i: 3, a: 'hello', b: 'world' }, { greeting: 'bye world' }],
      [{ i: 4, a: 'hello', b: 'world' }, { greeting: 'hello moon' }],
    ].each do |(input, expected_result)|
      it "should evaluate Ruby proc with input #{input}" do
        proc = <<~RUBY
          if input['i'] > 3
            output['greeting'] = input['a'] + " moon"
          else
            output['greeting'] = "bye " + input['b']
          end
        RUBY

        input_schema = [
          { id: 'i', label: 'Number', type: 'integer', required: true },
          { id: 'a', label: 'First string', type: 'string', required: true },
          { id: 'b', label: 'Second string', type: 'string', required: true },
        ]
        output_schema = [
          { id: 'greeting', label: 'Greeting', type: 'string', required: true },
        ]
        input = { input_schema: input_schema, output_schema: output_schema, proc: proc, input: input }
        results = action(input).run
        expect(results.pluck(:output).pluck(:results)).to eq([expected_result.with_indifferent_access])
      end
    end

    it 'should evaluate Ruby proc without parameters' do
      proc = <<~RUBY
        i = 45
        output[:o] = i * i
      RUBY
      output_schema = [
        { id: 'o', label: 'Output', type: 'integer', required: true },
      ]
      input = { output_schema: output_schema, proc: proc }
      results = action(input).run
      expect(results.pluck(:output).pluck(:results)).to eq([{ o: 2025 }.with_indifferent_access])
    end

    it 'does not evaluate unallowed methods' do
      proc = <<~RUBY
        unknown_method
      RUBY
      input = { proc: proc }
      expect do
        action(input).run
      end.to raise_error("Input invalid: Field 'proc' is invalid. Method 'unknown_method' not allowed.")
    end

    it 'evaluates with secret strings in the input' do
      proc = <<~RUBY
        if input['i'] > 3
          output['greeting'] = decrypt_secret_string(input['a']) + " moon"
        else
          output['greeting'] = "bye " + input['b']
        end
      RUBY

      input_schema = [
        { id: 'i', label: 'Number', type: 'integer', required: true },
        { id: 'a', label: 'First string', type: 'secret_string', required: true },
        { id: 'b', label: 'Second string', type: 'string', required: true },
      ]
      output_schema = [
        { id: 'greeting', label: 'Greeting', type: 'string', required: true },
      ]
      input_values = { i: 4, a: make_secret_string('hello'), b: 'world' }
      input = { input_schema: input_schema, output_schema: output_schema, proc: proc, input: input_values }
      results = action(input).run
      expect(results.pluck(:output).pluck(:results)).to eq([{ greeting: 'hello moon' }.with_indifferent_access])
    end

    it 'evaluates with secret strings in the output' do
      proc = <<~RUBY
        if input['i'] > 3
          output['greeting'] = input['a'] + " moon"
        else
          output['greeting'] = "bye " + input['b']
        end
      RUBY

      input_schema = [
        { id: 'i', label: 'Number', type: 'integer', required: true },
        { id: 'a', label: 'First string', type: 'string', required: true },
        { id: 'b', label: 'Second string', type: 'string', required: true },
      ]
      output_schema = [
        { id: 'greeting', label: 'Greeting', type: 'secret_string', required: true },
      ]
      input_values = { i: 4, a: 'hello', b: 'world' }
      input = { input_schema: input_schema, output_schema: output_schema, proc: proc, input: input_values }
      results = action(input).run
      result = results.pluck(:output).pluck(:results).first
      expect(encryptor.decrypt(result[:greeting])).to eq('hello moon')
    end
  end
end

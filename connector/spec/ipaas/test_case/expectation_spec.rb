require 'spec_helper'

RSpec.describe IPaaS::TestCase::Expectation do
  context 'validation' do
    it 'validates proc' do
      hash = { matcher: :equals, proc: '"foo".squash' }
      obj = IPaaS::TestCase::Expectation.parse(hash)
      expect(obj).not_to be_valid
      expect(obj.errors[:proc]).to eq(["Method 'squash' not allowed."])
    end

    it 'requires proc when using custom matcher' do
      hash = { matcher: :custom, fixed: 'Foo' }
      obj = IPaaS::TestCase::Expectation.parse(hash)
      expect(obj).not_to be_valid
      expect(obj.errors[:proc]).to eq(['Custom matcher requires proc.'])
    end

    it 'validates the matcher type' do
      obj = IPaaS::TestCase::Expectation.parse({ matcher: :foo, fixed: 'Foo' })
      expect(obj).not_to be_valid
      expect(obj.errors[:matcher])
        .to eq(['must be one of: ' \
                'equals, contains, includes, starts_with, ends_with, is_present, nested, custom.'])
    end

    it 'fails when evaluating with unknown matcher' do
      obj = IPaaS::TestCase::Expectation.parse({ matcher: :foo, fixed: 'Foo' })
      expect(obj.match(nil, 'Foo')).to be_present
    end
  end

  describe '#match_custom?' do
    it 'evaluates the custom matcher' do
      hash = { matcher: :custom, proc: 'actual_value > 3' }
      expectation = IPaaS::TestCase::Expectation.parse(hash)

      context = Object.new
      expect(context).not_to respond_to(:actual_value)
      errors = expectation.match(context, 6)
      expect(errors).to be_empty
      expect(context).not_to respond_to(:actual_value)

      errors = expectation.match(context, 2)
      expect(errors).to contain_exactly("Expectation failed with custom matcher.\nActual value: '2'\n" \
                                        "Matcher: 'actual_value > 3'")
      expect(context).not_to respond_to(:actual_value)

      hash = { matcher: :custom, proc: 'actual_value > 3', negated: true }
      expectation = IPaaS::TestCase::Expectation.parse(hash)
      expect(expectation.match(context, 2)).to be_empty
      expect(expectation.match(context, 6)).to contain_exactly(
        "Expectation failed with negated custom matcher.\nActual value: '6'\n" \
        "Matcher: 'actual_value > 3'"
      )
    end

    it 'restores the original "actual_value" method of the context after evaluation' do
      hash = { matcher: :custom, proc: 'actual_value > 3' }
      expectation = IPaaS::TestCase::Expectation.parse(hash)

      context = Object.new
      def context.actual_value
        1
      end

      expect(expectation.match(context, 6)).to be_empty
      expect(expectation.match(context, 2)).not_to be_empty
      expect(context.actual_value).to eq(1)
    end
  end

  describe '#match_standard?' do
    it 'evaluates the standard matchers' do
      [
        [:equals, 'foo', 'foo', true],
        [:equals, 'foo', 'fool', false],
        [:equals, '', '', true],
        [:equals, '', ' ', false],
        [:equals, ' ', '', false],
        [:equals, '427', '427', true],
        [:equals, 427, 427, true],
        [:equals, '427', 427, false],
        [:equals, 427, '427', false],
        [:equals, 0, 0, true],
        [:equals, 0, 0.0, true],
        [:equals, 0, 0.1, false],
        [:equals, %w[a b], %w[a b], true],
        [:equals, %w[a b], %w[a], false],
        [:equals, %w[a b], %w[b a], false],
        [:equals, [], [], true],
        [:equals, {}, {}, true],
        [:equals, { foo: 'bar', baz: 'quux' }, { foo: 'bar', baz: 'quux' }, true],
        [:equals, { foo: 'bar', baz: 'quux' }, { baz: 'quux', foo: 'bar' }, true],
        [:equals, { foo: 'bar', baz: 'quux' }, { foo: 'bar', quux: 'quux' }, false],
        [:equals, nil, nil, true],
        [:equals, nil, 0, false],
        [:equals, 0, nil, false],
        [:equals, '', 0, false],

        [:includes, %w[a b], %w[a b], true],
        [:includes, %w[a b], %w[b a], true],
        [:includes, %w[a b], %w[a], true],
        [:includes, %w[a b], %w[b], true],
        [:includes, %w[a b], %w[], true],
        [:includes, %w[a b], %w[a b c], false],
        [:includes, %w[a b], %w[a c], false],
        [:includes, %w[a b], %w[c], false],
        [:includes, { foo: 'bar', baz: 'quux' }, { foo: 'bar', baz: 'quux' }, true],
        [:includes, { foo: 'bar', baz: 'quux' }, { foo: 'bar' }, true],
        [:includes, { foo: 'bar', baz: 'quux' }, { baz: 'quux' }, true],
        [:includes, { foo: 'bar', baz: 'quux' }, { 'baz' => 'quux' }, true],
        [:includes, { 'foo' => 'bar', 'baz' => 'quux' }, { baz: 'quux' }, true],
        [:includes, { foo: 'bar', baz: 'quux' }, { foo: 'bar', baz: 'quux', hoo: 'bie' }, false],
        [:includes, { foo: 'bar', baz: 'quux' }, { foo: 'bar', hoo: 'bie' }, false],
        [:includes, { foo: 'bar', baz: 'quux' }, { hoo: 'bie' }, false],
        [:includes, '427', '42', true],
        [:includes, '427', '47', false],
        [:includes, '427', '7', true],
        [:includes, 427, 42, false],
        [:includes, %w[a b], 'a', true],
        [:includes, %w[a b], 'c', false],
        [:includes, nil, 'c', false],

        [:contains, 'snafoo', 'foo', true],
        [:contains, 'hello world', 'foo', false],
        [:contains, '427', '2', true],
        [:contains, '427', 2, false],
        [:contains, 427, 2, false],
        [:contains, 427, '2', false],
        [:contains, { foo: 'bar' }, { foo: 'bar' }, false],
        [:contains, { foo: 'bar' }, :foo, false],
        [:contains, %w[a b], %w[a b], false],
        [:contains, %w[a b], %w[a], false],

        [:starts_with, 'fool', 'foo', true],
        [:starts_with, 'fool', '', true],
        [:starts_with, 'foo', 'fool', false],
        [:starts_with, '427', '4', true],
        [:starts_with, '427', 4, false],
        [:starts_with, 427, 4, false],
        [:starts_with, 427, '4', false],
        [:starts_with, %w[a b], %w[a b], false],
        [:starts_with, %w[a b], %w[a], false],
        [:starts_with, { foo: 'bar' }, { foo: 'bar' }, false],
        [:starts_with, { foo: 'bar' }, :foo, false],

        [:ends_with, 'snafoo', 'foo', true],
        [:ends_with, 'fool', 'foo', false],
        [:ends_with, 'fool', 'foo', false],
        [:ends_with, 'fool', '', true],
        [:ends_with, '427', '7', true],
        [:ends_with, '427', 7, false],
        [:ends_with, 427, 7, false],
        [:ends_with, 427, '7', false],
        [:ends_with, %w[a b], %w[a b], false],
        [:ends_with, %w[a b], %w[a], false],
        [:ends_with, { foo: 'bar' }, { foo: 'bar' }, false],
        [:ends_with, { foo: 'bar' }, :foo, false],

        [:is_present, 'fool', nil, true],
        [:is_present, 0, nil, true],
        [:is_present, '', nil, false],
        [:is_present, ' ', nil, false],
        [:is_present, [], nil, false],
        [:is_present, ['foo'], nil, true],
        [:is_present, {}, nil, false],
        [:is_present, { foo: 'bar' }, nil, true],
      ].each do |matcher, actual, expected, pass|
        negations = [false, true]
        negations.each do |negated|
          pass = !pass if negated
          hash = { matcher: matcher, fixed: expected, negated: negated }
          expectation = IPaaS::TestCase::Expectation.parse(hash)

          errors = expectation.match(Object.new, actual)
          if pass
            expect(errors).to be_empty, "'#{actual}' #{'NOT ' if negated}#{matcher} '#{expected}' should pass"

          else
            expect(errors).not_to be_empty, "'#{actual}' #{'!' if negated}#{matcher} '#{expected}' should NOT pass"
            expect(errors).to contain_exactly(
              "Expectation failed with #{'negated ' if negated}#{matcher} matcher.\n" \
              "Actual value: '#{actual}'\n" \
              "Expected value: '#{expected}'"
            )
          end
        end
      end
    end
  end

  it 'evaluates the expectation as a proc' do
    hash = { matcher: :equals, proc: 'trigger_output&.dig(:foo)' }
    expectation = IPaaS::TestCase::Expectation.parse(hash)

    context = Object.new
    allow(context).to receive(:trigger_output) { { foo: 'Bar' } }
    errors = expectation.match(context, 'Bar')
    expect(errors).to be_empty

    errors = expectation.match(context, 'Baz')
    expect(errors).to contain_exactly("Expectation failed with equals matcher.\n" \
                                      "Actual value: 'Baz'\nExpected value: 'Bar'")
  end

  it 'fails if proc expectation is invalid' do
    hash = { matcher: :equals, proc: '"foo".squash' }
    expectation = IPaaS::TestCase::Expectation.parse(hash)

    context = Object.new
    errors = expectation.match(context, 'Baz')
    expect(errors).to contain_exactly("Invalid expectation.\nproc: 'Method 'squash' not allowed.'\nActual value: 'Baz'")
  end

  it 'evaluates a fixed expectation using the field type' do
    hash = { field_id: 'runbook1', matcher: :equals, fixed: { uuid: 'xyz' } }
    expectation = IPaaS::TestCase::Expectation.parse(hash)

    field = IPaaS::Connector::Schema::Field.new(id: :runbook1, type: :runbook)
    schema = double(:schema)
    allow(schema).to receive(:field).with(:runbook1).and_return(field)

    runbook = double(:runbook)
    allow(IPaaS::Connector::Runbook).to receive(:by_uuid).with('xyz').and_return(runbook)

    context = double(:context)

    errors = expectation.match(context, { runbook1: runbook }, schema: schema)
    expect(errors).to be_empty

    other_runbook = double(:other_runbook)
    errors = expectation.match(context, { runbook1: other_runbook }, schema: schema)
    expect(errors).to contain_exactly("Expectation failed for field 'runbook1' with equals matcher.\n" \
                                      "Actual value: '#[Double :other_runbook]'\nExpected value: '#[Double :runbook]'")
  end

  it 'evaluates a fixed array expectation using the field type' do
    hash = { field_id: 'runbooks', matcher: :equals, fixed: [{ uuid: 'xyz' }, { uuid: 'abc' }] }
    expectation = IPaaS::TestCase::Expectation.parse(hash)

    field = IPaaS::Connector::Schema::Field.new(id: :runbooks, type: :runbook, array: true)
    schema = double(:schema)
    allow(schema).to receive(:field).with(:runbooks).and_return(field)

    runbook_xyz = double(:runbook_xyz)
    runbook_abc = double(:runbook_abc)
    allow(IPaaS::Connector::Runbook).to receive(:by_uuid).with('xyz').and_return(runbook_xyz)
    allow(IPaaS::Connector::Runbook).to receive(:by_uuid).with('abc').and_return(runbook_abc)

    context = double(:context)

    errors = expectation.match(context, { runbooks: [runbook_xyz, runbook_abc] }, schema: schema)
    expect(errors).to be_empty

    other_runbook = double(:other_runbook)
    errors = expectation.match(context, { runbooks: [runbook_xyz, other_runbook] }, schema: schema)
    expect(errors).to contain_exactly("Expectation failed for field 'runbooks' with equals matcher.\n" \
                                      "Actual value: '[#<Double :runbook_xyz>, #<Double :other_runbook>]'\n" \
                                      "Expected value: '[#<Double :runbook_xyz>, #<Double :runbook_abc>]'")
  end

  it 'uses the custom failure message' do
    hash = { matcher: :equals, fixed: 'Bar', failure_message: 'Oops!' }
    expectation = IPaaS::TestCase::Expectation.parse(hash)

    errors = expectation.match(nil, 'Baz')
    expect(errors).to contain_exactly("Expectation failed with equals matcher.\n" \
                                      "Actual value: 'Baz'\nFailure message: Oops!")
  end

  it 'references the field in the failure message' do
    hash = { field_id: :foo, matcher: :equals, fixed: 'Bar', failure_message: 'Oops!' }
    expectation = IPaaS::TestCase::Expectation.parse(hash)

    errors = expectation.match(nil, { foo: 'Baz' })
    expect(errors).to contain_exactly("Expectation failed for field 'foo' with equals matcher.\n" \
                                      "Actual value: 'Baz'\nFailure message: Oops!")

    hash = { field_id: :foo, matcher: :equals, fixed: 'Bar' }
    expectation = IPaaS::TestCase::Expectation.parse(hash)

    errors = expectation.match(nil, { foo: 'Baz' })
    expect(errors).to contain_exactly("Expectation failed for field 'foo' with equals matcher.\n" \
                                      "Actual value: 'Baz'\nExpected value: 'Bar'")
  end

  it 'defaults to the equals matcher' do
    hash = { fixed: 'Bar' }
    expectation = IPaaS::TestCase::Expectation.parse(hash)

    expect(expectation.match(nil, 'Bar')).to be_empty
    expect(expectation.match(nil, 'Baz')).not_to be_empty
  end

  describe '#update_runbook_variable' do
    it 'updates runbook variable in proc and nested expectations' do
      hash = {
        field_id: :foo,
        matcher: :nested,
        proc: 'runbook.read_variable("old-id") + runbook&.write_variable("old-id", x)',
        nested: [
          { field_id: :bar, proc: 'runbook.variable_field("old-id")' },
        ],
      }
      obj = IPaaS::TestCase::Expectation.parse(hash)
      updated = obj.update_runbook_variable('old-id', 'new-id')

      expect(updated).to be_truthy
      expect(obj.proc).to eq('runbook.read_variable("new-id") + runbook&.write_variable("new-id", x)')
      expect(obj.nested.first.proc).to eq('runbook.variable_field("new-id")')
    end

    it 'returns false when nothing is updated' do
      hash = { matcher: :equals, fixed: 'other-value' }
      obj = IPaaS::TestCase::Expectation.parse(hash)
      expect(obj.update_runbook_variable('old-id', 'new-id')).to be_falsey
    end
  end
end

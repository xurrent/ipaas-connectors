require 'spec_helper'

describe IPaaS::Connector::Types::RubyType do
  before(:each) { IPaaS::Connector::Common::ProcHelper.validated_before.clear }

  it 'should define the ruby class' do
    expect(subject.ruby_class).to eq(String)
  end

  it 'should return false for nested?' do
    expect(subject.nested?).to be_falsey
  end

  describe 'resolve' do
    it 'should leave nils untouched' do
      expect(subject.resolve(nil)).to be_nil
    end

    it 'should return strings' do
      expect(subject.resolve('Hello Moon!')).to eq('Hello Moon!')
    end

    it 'should auto-convert other types' do
      expect(subject.resolve(12)).to eq('12')
    end
  end

  describe 'valid?' do
    it 'should return true for nil' do
      expect(subject.valid?(nil)).to eq(true)
    end

    it 'should return true for empty string' do
      expect(subject.valid?(' ')).to eq(true)
    end

    it 'should return true for allowed proc content' do
      expect(subject.valid?('output[:discard] = input.dig(:webhook) == "a"')).to eq(true)

      errors = []
      expect(subject.valid?('output[:discard] = input.dig(:webhook) == "a"', errors))
        .to eq(true)
      expect(errors).to be_empty
    end

    it 'should return false for proc with not-allowed content' do
      expect(subject.valid?('output[:discard] = ENV["a"] == "a"')).to eq(false)

      errors = []
      expect(subject.valid?('output[:discard] = ENV["a"] == "a"', errors)).to eq(false)
      expect(errors).to contain_exactly(
        "Access to 'ENV' is not allowed in expressions; only an approved set of classes is available. " \
        'Please file a request if access is needed.',
      )
    end

    it 'should return false naming the problem when the proc exhausts the stack' do
      # Injected rather than performed: overflowing for real costs a deep stack and the memory to
      # unwind it. What matters here is that the message reaches this surface either way.
      allow_any_instance_of(IPaaS::Connector::Common::ProcHelper)
        .to receive(:parse_ast).and_raise(SystemStackError)

      errors = []
      expect(subject.valid?('1 + 1', errors)).to eq(false)
      expect(errors).to contain_exactly(IPaaS::Connector::Common::ProcHelper::TOO_COMPLEX_MESSAGE)
    end

    it 'should return false for proc with invalid ruby' do
      expect(subject.valid?('(a')).to eq(false)

      errors = []
      expect(subject.valid?('(a', errors)).to eq(false)
      expect(errors.first).to include('unexpected end-of-input')
      expect(errors.length).to eq(1)
    end
  end

  it 'should provide an example' do
    field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :ruby)
    expect(subject.example(field)).to eq('(1..10).to_a.join(", ")')
  end
end

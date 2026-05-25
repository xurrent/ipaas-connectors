require 'spec_helper'

describe IPaaS::Connector::Types::RubyType do
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
      expect(errors).to contain_exactly("Access to 'ENV' not allowed.")
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

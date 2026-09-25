require 'spec_helper'

describe IPaaS::Connector::Common::ProcRules::NodeValidator do
  let(:rules) { IPaaS::Connector::Common::ProcRules }

  def validator(**)
    described_class.new(context: nil, on_invalid: ->(_message) {}, field: nil, **)
  end

  it 'builds exactly the registered rules, in order, whether or not a procedure is given' do
    expected = rules::BASIC_RULES + rules::FIELD_RULES

    expect(expected).not_to be_empty
    expect(validator.rules.map(&:class)).to eq(expected)
    expect(validator(procedure: proc { 1 }).rules.map(&:class)).to eq(expected)
  end

  it 'holds the procedure it was given, and nil when it was given none' do
    procedure = proc { 1 }

    expect(validator(procedure: procedure).procedure).to be(procedure)
    expect(validator.procedure).to be_nil
  end

  it 'hands the procedure to the constants rule and to no other' do
    procedure = proc { 1 }
    (rules::BASIC_RULES + rules::FIELD_RULES - [rules::ValidConstantsRule]).each do |rule|
      expect(rule).to receive(:new).with(nil, hash_excluding(:procedure)).and_call_original
    end
    expect(rules::ValidConstantsRule).to receive(:new).with(nil, hash_including(procedure: procedure)).and_call_original

    validator(procedure: procedure)
  end
end

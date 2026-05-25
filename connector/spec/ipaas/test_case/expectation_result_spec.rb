require 'spec_helper'

RSpec.describe IPaaS::TestCase::ExpectationResult do
  it 'passes when there are no errors' do
    obj = IPaaS::TestCase::ExpectationResult.new
    obj.errors = ['Oops', 'Oh no']
    expect(obj.passed?).to be_falsey
    expect(obj.failed?).to be_truthy

    obj.errors = []
    expect(obj.passed?).to be_truthy
    expect(obj.failed?).to be_falsey
  end

  describe '#to_h' do
    it 'serializes the result' do
      obj = IPaaS::TestCase::ExpectationResult.new
      obj.errors = ['Oops', 'Oh no']

      expect(obj.to_h).to eq({
        errors: ['Oops', 'Oh no'],
      })
    end
  end
end

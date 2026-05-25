require 'spec_helper'

describe IPaaS::Connector::Common::ProcRules::NoSafePresentRule do
  let(:context) { Object.new }

  describe 'with required boolean field' do
    let(:field) { double(required: true, type: :boolean) }

    # Test that all forbidden methods are actually blocked (one comprehensive test)
    it 'should block all forbidden methods' do
      IPaaS::Connector::Common::ProcRules::NoSafePresentRule::FORBIDDEN_METHODS.each do |method|
        proc = "value&.#{method}"
        helper = IPaaS::Connector::Common::ProcHelper.new(context, proc, field: field)

        expect(helper.valid?).to be_falsey, "Expected &.#{method} to be blocked"
        expect(helper.errors).to include(
          "Safe navigation with &.#{method} is not allowed for required boolean fields. " \
          'Use explicit nil checking instead.'
        )
      end
    end

    it 'should allow regular .present? calls' do
      proc = 'value.present?'
      helper = IPaaS::Connector::Common::ProcHelper.new(context, proc, field: field)

      expect(helper.valid?).to be_truthy
      expect(helper.errors).to be_empty
    end

    it 'should allow safe navigation with other methods' do
      proc = 'value&.to_s'
      helper = IPaaS::Connector::Common::ProcHelper.new(context, proc, field: field)

      expect(helper.valid?).to be_truthy
      expect(helper.errors).to be_empty
    end

    it 'should allow safe navigation with other boolean methods' do
      proc = 'value&.nil?'
      helper = IPaaS::Connector::Common::ProcHelper.new(context, proc, field: field)

      expect(helper.valid?).to be_truthy
      expect(helper.errors).to be_empty
    end

    it 'should only report error once per method' do
      proc = 'value&.present? && value&.present?'
      helper = IPaaS::Connector::Common::ProcHelper.new(context, proc, field: field)

      expect(helper.valid?).to be_falsey
      present_errors = helper.errors.select { |e| e.include?('Safe navigation with &.present?') }
      expect(present_errors.length).to eq(1)
    end

    it 'should report multiple errors for the same field with mixed forbidden methods' do
      methods = IPaaS::Connector::Common::ProcRules::NoSafePresentRule::FORBIDDEN_METHODS
      proc = methods.map { |m| "value&.#{m}" }.join(' && ')
      helper = IPaaS::Connector::Common::ProcHelper.new(context, proc, field: field)

      expect(helper.valid?).to be_falsey
      safe_nav_errors = helper.errors.select { |e| e.include?('Safe navigation with') }
      expect(safe_nav_errors.length).to eq(methods.count)
    end
  end

  describe 'with non-required boolean field' do
    let(:field) { double(required: false, type: :boolean) }

    # Test that all forbidden methods are allowed (one comprehensive test)
    it 'should allow safe navigation with ' do
      IPaaS::Connector::Common::ProcRules::NoSafePresentRule::FORBIDDEN_METHODS.each do |method|
        proc = "value&.#{method}"
        helper = IPaaS::Connector::Common::ProcHelper.new(context, proc, field: field)

        expect(helper.valid?).to be_truthy
        expect(helper.errors).to be_empty
      end
    end
  end

  describe 'with required non-boolean field' do
    let(:field) { double(required: true, type: :string) }

    it 'should allow safe navigation with &.present?' do
      proc = 'value&.present?'
      helper = IPaaS::Connector::Common::ProcHelper.new(context, proc, field: field)

      expect(helper.valid?).to be_truthy
      expect(helper.errors).to be_empty
    end
  end

  describe 'with non-required non-boolean field' do
    let(:field) { double(required: false, type: :string) }

    it 'should allow safe navigation with &.present?' do
      proc = 'value&.present?'
      helper = IPaaS::Connector::Common::ProcHelper.new(context, proc, field: field)

      expect(helper.valid?).to be_truthy
      expect(helper.errors).to be_empty
    end
  end

  describe 'with no field provided' do
    it 'should allow safe navigation with &.present?' do
      proc = 'value&.present?'
      helper = IPaaS::Connector::Common::ProcHelper.new(context, proc)

      expect(helper.valid?).to be_truthy
      expect(helper.errors).to be_empty
    end
  end

  describe 'with nil field' do
    it 'should allow safe navigation with &.present?' do
      proc = 'value&.present?'
      helper = IPaaS::Connector::Common::ProcHelper.new(context, proc, field: nil)

      expect(helper.valid?).to be_truthy
      expect(helper.errors).to be_empty
    end
  end

  describe 'with field that does not respond to required' do
    let(:field) { double(type: :boolean) }

    it 'should allow safe navigation with &.present?' do
      proc = 'value&.present?'
      helper = IPaaS::Connector::Common::ProcHelper.new(context, proc, field: field)

      expect(helper.valid?).to be_truthy
      expect(helper.errors).to be_empty
    end
  end

  describe 'with field that does not respond to type' do
    let(:field) { double(required: true) }

    it 'should allow safe navigation with &.present?' do
      proc = 'value&.present?'
      helper = IPaaS::Connector::Common::ProcHelper.new(context, proc, field: field)

      expect(helper.valid?).to be_truthy
      expect(helper.errors).to be_empty
    end
  end

  describe 'integration with other rules' do
    let(:field) { double(required: true, type: :boolean) }

    # Test integration with one method (present?) - others follow same pattern
    it 'should work with other validation rules' do
      proc = 'ENV["TEST"] && value&.present?'
      helper = IPaaS::Connector::Common::ProcHelper.new(context, proc, field: field)

      expect(helper.valid?).to be_falsey
      expect(helper.errors).to include(
        'Safe navigation with &.present? is not allowed for required boolean fields. Use explicit nil checking instead.'
      )
      expect(helper.errors).to include("Calling methods on 'ENV' not allowed.")
    end

    it 'should work with method definition rules' do
      proc = 'def some_method; value&.present?; end'
      helper = IPaaS::Connector::Common::ProcHelper.new(context, proc, field: field)

      expect(helper.valid?).to be_falsey
      expect(helper.errors).to include(
        'Safe navigation with &.present? is not allowed for required boolean fields. Use explicit nil checking instead.'
      )
      expect(helper.errors).to include("Method definition 'some_method' not allowed.")
    end
  end
end

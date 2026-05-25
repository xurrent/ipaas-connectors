require 'spec_helper'

describe IPaaS::Connector::Common::ProcRules::ValidMethodsRule do
  let(:rule) do
    IPaaS::Connector::Common::ProcRules::ValidMethodsRule.new(
      ->(msg) { raise "Unexpected error: #{msg}" }
    )
  end

  [
    :method,
    :Method,
    :UnboundMethod,
    :define_method,
    :method_missing,
    :respond_to_missing?,
    :instance_method,
    :to_proc,
  ].each do |unsafe_method|
    it "does not allow #{unsafe_method}" do
      expect(IPaaS::Connector::Common::ProcRules::ValidMethodsRule::RUBY_METHODS).not_to include(unsafe_method)
      expect(IPaaS::Connector::Common::ProcRules::ValidMethodsRule::ADDITIONAL_METHODS).not_to include(unsafe_method)
      expect(IPaaS::Connector::Common::ProcRules::ProcSafe.registry).not_to include(unsafe_method)
    end
  end

  [
    :number_to_human_size,
    :finish_job!,
    :backoff_if_needed,
    :parse_json_response,
    :psa_validate_secret,
    :psa_extract_basic_auth,
    :psa_generate_secret_for,
    :psa_secret_for,
    :psa_delete_secret_for,
    :secure_compare,
  ].each do |allowed_method|
    it "allows #{allowed_method}" do
      expect { rule.validate_method(allowed_method) }.not_to raise_error
    end
  end

  describe 'method constants' do
    method_constants = [
      :BASE_METHODS, :COMPARISON_METHODS, :STRING_METHODS, :NUMBER_METHODS,
      :HASH_METHODS, :ARRAY_METHODS, :BASE64_METHODS, :TIME_METHODS,
      :URI_METHODS, :CRYPTO_METHODS, :ERROR_METHODS, :XML_METHODS, :DEBUG_METHODS,
    ].freeze

    method_constants.each do |const|
      it "has no duplicates within #{const}" do
        methods = described_class.const_get(const).to_a
        duplicates = methods.group_by(&:itself).select { |_, v| v.size > 1 }.keys
        expect(duplicates).to be_empty, "Duplicate methods in #{const}: #{duplicates.join(', ')}"
      end
    end
  end
end

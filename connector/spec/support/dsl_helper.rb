class DslTester
  include IPaaS::Connector::Common::Model # includes AttributeMixin
  def self.model_name
    ActiveModel::Name.new(self, nil, 'Tester')
  end
  attribute :dynamic_field, type: Symbol, default: :bar
end

def skip_function_capture_validation
  # since spec examples are defined in a block any functions defined there report all their local variables
  # as being captured. This would raise an error normally, but to keep specs for other functionality simple
  # we can disable the check.
  allow(IPaaS::Connector::Dsl::FunctionMixin).to receive(:validate_variable_capture)
end

def enable_function_capture_validation
  expect(IPaaS::Connector::Dsl::FunctionMixin).to receive(:validate_variable_capture).and_call_original
end

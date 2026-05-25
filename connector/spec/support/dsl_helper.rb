class DslTester
  include IPaaS::Connector::Common::Model # includes AttributeMixin
  def self.model_name
    ActiveModel::Name.new(self, nil, 'Tester')
  end
  attribute :dynamic_field, type: Symbol, default: :bar
end

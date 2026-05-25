module IPaaS
  module Connector
    module Common
      module Model
        extend ActiveSupport::Concern

        included do
          include ActiveModel::API
          include ActiveModel::Validations::Callbacks
          include IPaaS::Connector::Dsl::AttrAccessorMixin
          include IPaaS::Connector::Dsl::AttributeMixin
          include IPaaS::Connector::Dsl::SchemaMixin
          include IPaaS::Connector::Dsl::FunctionMixin

          def full_error_messages
            errors.full_messages.join(' ')
          end

          def full_error_messages_for(attribute)
            errors.full_messages_for(attribute)
          end
        end
      end
    end
  end
end

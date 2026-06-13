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

          # Set when the backing file could not be parsed; the record becomes a quarantined
          # placeholder (uuid + message only) so one bad file doesn't fail the whole set.
          attr_accessor :load_error

          # Surface the load error so every `valid?`-based check treats a broken record as invalid.
          validate { errors.add(:base, load_error) if load_error.present? }

          def broken?
            load_error.present?
          end

          def full_error_messages
            errors.full_messages.join(' ')
          end

          def full_error_messages_for(attribute)
            errors.full_messages_for(attribute)
          end
        end

        class_methods do
          # Build (or mark) a broken record. Idempotent: parsing can fail after
          # the record self-registered (e.g. bad actions), if so: reuse it.
          def broken(uuid:, load_error:)
            existing = try(:find, uuid)
            (existing || new(uuid)).tap { |record| record.load_error = load_error }
          end
        end
      end
    end
  end
end

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

          attr_accessor :unresolved_error

          def unresolved?
            unresolved_error.present?
          end

          def own_connector
            connector if respond_to?(:connector)
          end

          def full_error_messages
            errors.full_messages.join(' ')
          end

          def full_error_messages_for(attribute)
            errors.full_messages_for(attribute)
          end
        end

        def resolve_error
          ResolveScope.read(@resolve_error_entry)
        end

        def resolve_error=(message)
          @resolve_error_entry = ResolveScope.stamp(message)
        end

        def report_mapping_validity(attribute, resolved, owner = self)
          return if resolved&.valid?

          if resolved.nil?
            return if owner&.unresolved?
            return errors.add(attribute, "could not be validated, the field logic raised: #{resolve_error}") if
              resolve_error.present?

            return errors.add(attribute, 'could not be validated because the field logic did not resolve.')
          end

          errors.add(attribute, "invalid: #{resolved.full_error_messages}")
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

module IPaaS
  module Connector
    module Authentication
      module Inbound
        class << self
          def register(key, module_klass)
            helper = module_klass.validate_request_helper(nil)
            unless helper.valid? & module_klass.helpers.valid?
              errors = helper.errors
              errors += module_klass.helpers.errors if module_klass.helpers.errors.present?
              raise ArgumentError, "#{module_klass} is not valid. Errors: #{errors}"
            end

            (@validators ||= {})[key] = module_klass
          end

          def keys
            @validators.keys
          end

          def module(key)
            @validators[key]
          end
        end

        module Extension
          extend ActiveSupport::Concern

          class_methods do
            def helpers
              @helpers ||= IPaaS::Connector::Common::Helpers.new
            end

            def helper(name, &block)
              helpers.define_helper(name, &block)
            end

            def validate(&block)
              @validator = block
            end

            def validate_request_helper(binding)
              return unless @validator

              IPaaS::Connector::Common::ProcHelper.new(binding, @validator)
            end

            def validate_request(binding, request)
              validate_request_helper(binding).tap do |top_level_helper|
                next unless top_level_helper

                helpers.copy_to(binding)
                top_level_helper.execute(request)
              end
            end
          end
        end
      end
    end
  end
end

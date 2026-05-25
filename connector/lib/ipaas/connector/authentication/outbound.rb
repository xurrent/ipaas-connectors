module IPaaS
  module Connector
    module Authentication
      module Outbound
        class << self
          def register(key, module_klass)
            helper = module_klass.authenticate_request_helper(nil)
            unless helper.valid? & module_klass.helpers.valid?
              errors = helper.errors
              errors += module_klass.helpers.errors if module_klass.helpers.errors.present?
              raise ArgumentError, "#{module_klass} is not valid. Errors: #{errors}"
            end
            (@authentications ||= {})[key] = module_klass
          end

          def keys
            @authentications.keys
          end

          def module(key)
            @authentications[key]
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

            def authenticate(&block)
              @authenticator = block
            end

            def authenticate_request_helper(binding)
              return unless @authenticator

              IPaaS::Connector::Common::ProcHelper.new(binding, @authenticator)
            end

            def authenticate_request(binding, request)
              authenticate_request_helper(binding).tap do |top_level_helper|
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

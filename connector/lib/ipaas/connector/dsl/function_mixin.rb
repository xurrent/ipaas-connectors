module IPaaS
  module Connector
    module Dsl
      # The FunctionMixin module provides a DSL for defining and validating
      # functions in a class. It allows specifying required functions and
      # ensures that each function is defined only once.
      module FunctionMixin
        extend ActiveSupport::Concern

        class << self
          def validate_variable_capture(name, block)
            values = IPaaS::Connector::Common::ProcHelper.captured_variables(block)
            # captured local variables in block: possible memory leak as these will not be garbage collected
            return unless values.any?

            message = "Function '#{name}' captures local variables: #{values.keys}."
            # only raise in the test environment until existing runbooks no longer capture local variables
            raise ArgumentError, message if IPaaS.env == 'test'

            Rails.logger.warn(message) if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          end
        end

        included do
          def self.function(name, required: false)
            ivar = :"@#{name}"
            raise IPaaS::Error, "Function '#{name}' is already defined." if instance_variable_defined?(ivar)

            define_method(name) do |&block|
              next instance_variable_get(ivar) unless block

              IPaaS::Connector::Dsl::FunctionMixin.validate_variable_capture(name, block)

              instance_variable_set(ivar, block)
            end

            validate do |record|
              record.function_valid?(name, ivar)
              record.function_present?(name, ivar) if required
            end

            # Call a function if defined, and execute it within the given context with the given parameters
            return if respond_to?(:call_function)
            define_method(:call_function) do |attribute, context, *params|
              if !self.valid? && self.errors[attribute].present?
                raise IPaaS::Error, "Function '#{attribute}' invalid: #{self.errors[attribute].join(', ')}"
              end
              proc = send(attribute)
              return unless proc

              IPaaS::Connector::Common::ProcHelper.new(context, proc).execute(*params)
            end
          end

          def function_valid?(name, ivar)
            proc = instance_variable_get(ivar)
            return unless proc

            helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, proc)
            return if helper.valid?

            self.errors.add(name, "invalid: #{helper.errors.join(' ')}")
          end

          def function_present?(name, ivar)
            return if instance_variable_defined?(ivar)

            self.errors.add(name, "function is required, define '#{name} do ... end'.")
          end
        end
      end
    end
  end
end

module IPaaS
  module Connector
    class Schema
      module Extension
        extend ActiveSupport::Concern

        included do
          def self.schema(&block)
            @schema = block
          end

          def self.apply_schema(binding)
            binding.instance_eval(&@schema) if @schema
          end
        end
      end
    end
  end
end

module IPaaS
  module Connector
    module Common
      module ProcContainer
        extend ActiveSupport::Concern

        included do
          attribute :proc, type: String

          def visit_procs(memo = nil, path = [], &block)
            next_path = path + [self.field_id]
            memo = yield(next_path, self, memo, self.proc) if self.proc
            try(:nested)&.each do |mapping|
              memo = mapping.visit_procs(memo, next_path, &block)
            end
            memo
          end
        end
      end
    end
  end
end

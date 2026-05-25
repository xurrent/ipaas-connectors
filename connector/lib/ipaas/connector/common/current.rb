module IPaaS
  module Connector
    module Common
      class Current < ActiveSupport::CurrentAttributes
        attribute :uuid_scope

        self.defaults = {
          uuid_scope: -> { UuidMixin::DEFAULT_SCOPE },
        }
      end
    end
  end
end

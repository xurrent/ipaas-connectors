# A constant on `valid_constants_rule_spec`'s owner module assigned somewhere else, so an example
# can tell a module a file assigns from the constants under it that the file did not write. It is a
# fixture because its path is the point: the rule compares it against the proc's own file. That spec
# requires it after the module exists, or the module itself would belong here.
module IPaaS
  module Connector
    module Common
      module ProcRules
        module ValidConstantsRuleSpecOwner
          ELSEWHERE = 'y'.freeze
        end
      end
    end
  end
end

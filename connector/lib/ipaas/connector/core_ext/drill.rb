module IPaaS
  module Connector
    module CoreExt
      # Shared recursion for Hash#drill and Array#drill: descends into +value+
      # with the remaining +keys+, mirroring #dig's nil and TypeError behavior.
      module Drill
        module_function

        def drill_into(value, keys)
          return value if keys.empty?
          return nil if value.nil?
          raise TypeError, "#{value.class} does not have #drill method" unless value.respond_to?(:drill)

          value.drill(*keys)
        end
      end
    end
  end
end

class Hash
  # Like #dig, but nested arrays map the remaining key path over their elements.
  def drill(key, *rest)
    IPaaS::Connector::CoreExt::Drill.drill_into(self[key], rest)
  end
end

class Array
  # Like #dig for Integer keys; for other keys the full remaining key path is
  # applied to each element, returning the array of results (nils preserved).
  def drill(key, *rest)
    if key.is_a?(Integer)
      IPaaS::Connector::CoreExt::Drill.drill_into(self[key], rest)
    else
      map { |element| IPaaS::Connector::CoreExt::Drill.drill_into(element, [key, *rest]) }
    end
  end
end

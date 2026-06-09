module IPaaS
  module Job
    module GraphQL
      # Processes parsed GraphQL response data so it matches the generated
      # iPaaS schema, which represents a connection field as a plain array of
      # the node type (see FieldBuilder.add_connection_output).
      module Result
        extend IPaaS::Connector::Common::ProcRules::ProcSafe

        proc_safe :gql_flatten_nodes

        class << self
          # Deep-walks the value and replaces every hash of the form
          # { 'nodes' => [...] } (a nodes key as the only key, with an array
          # value) with that array. Recurses into the replaced array so
          # connections nested inside the records of another connection are
          # flattened too. Keys are compared as strings: the input is
          # JSON-parsed response data.
          def gql_flatten_nodes(value)
            case value
            when Hash
              flatten_hash(value)
            when Array
              value.map { |element| gql_flatten_nodes(element) }
            else
              value
            end
          end

          private

          # Hashes with more keys than nodes (e.g. a user-queried totalCount
          # next to nodes) are left untouched.
          def flatten_hash(hash)
            if hash.keys == ['nodes'] && hash['nodes'].is_a?(Array)
              gql_flatten_nodes(hash['nodes'])
            else
              hash.transform_values { |nested| gql_flatten_nodes(nested) }
            end
          end
        end
      end
    end
  end
end

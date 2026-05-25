module IPaaS
  module Connector
    class Schema
      # Generates field definitions from one or more JSON samples.
      class Generator
        def self.dsl_lines(*json_samples)
          new(*json_samples).dsl_lines
        end

        # @param json_samples [Array<String, Hash>] one or more JSON strings or parsed hashes
        def initialize(*json_samples)
          @json_samples = json_samples
        end

        # Returns DSL lines built from the JSON samples.
        #
        # @return [String] DSL for the inferred fields
        def dsl_lines
          @dsl_lines ||= DslBuilder.build(structure)
        end

        # Returns the inferred structure from the JSON samples.
        #
        # @return [Hash] the merged structure hash
        def structure
          @structure ||= StructureInferrer.new(*@json_samples).infer
        end

        # Returns {Schema::Field} instances built from the JSON samples.
        #
        # @return [Array<Schema::Field>] the inferred fields
        def fields
          @fields ||= FieldBuilder.build(structure)
        end
      end
    end
  end
end

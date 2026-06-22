module IPaaS
  module Connector
    # Instance of an action template.
    #
    # One is created by parsing a (JSON) hash where the `input_mapping` will be resolved
    # and used as the input for the action.
    class Action
      extend IPaaS::Connector::Common::ProcRules::ProcSafe

      proc_safe :input, :nested, :iteration_state, :iteration_state_value, :iteration_state_value=,
                :action_template, :step, :completed?, :steps

      include IPaaS::Connector::Common::Model
      include IPaaS::Job::Context

      EXCLUDED_REFERENCE_CHARACTER = '♦'.freeze
      REFERENCE_WITH_INVALID_CHARS = /['"#{EXCLUDED_REFERENCE_CHARACTER}\\]/

      attr_accessor :runbook
      delegate :version, :solution, :trigger_output, :action_output, to: :runbook
      delegate :connector, to: :action_template, allow_nil: true

      attribute :reference
      attribute :description
      attribute :outbound_connection, type: Connection
      attribute :action_template, type: ActionTemplate
      attribute :input_mapping, type: [IPaaS::Connector::Mapping::FieldMapping]
      attribute :output_schema_name_mapping, type: [IPaaS::Connector::Mapping::SchemaNameMapping]
      attribute :predecessor_action_reference # not predecessor_action to keep flexible load order of actions
      attribute :predecessor_output_schema_reference

      schema :input_schema # deep copy of connection template config schema
      schema :output_schema, array: true # deep copy of connection template config schema
      schema :iteration_state_schema # deep copy of connection template iteration state schema

      validates :action_template, presence: { message: "can't be blank." }
      validate :predecessor_action_reference_valid?
      validate :predecessor_output_schema_reference_valid?
      validate :input_mapping_valid?
      validate :outbound_connection_valid?

      class << self
        def parse(runbook, action)
          raise IPaaS::Error, 'Action must have a runbook.' unless runbook
          hash = IPaaS::Connector::Common::Serializer.parse(action)
          raise IPaaS::Error, 'Action must be a hash.' unless hash.is_a?(Hash)
          hash = hash.deep_symbolize_keys
          hash[:reference] = generate_reference(runbook) unless hash.key?(:reference)

          Action.new(hash[:reference]).tap do |new_action|
            copy_action_values(new_action, hash)
            new_action.runbook = runbook
            new_action.valid? # triggers resolve
          end
        end

        def generate_reference(runbook)
          existing_references = (runbook.actions || []).map(&:reference)

          loop do
            reference = SecureRandom.hex(5) # Has ~1M possibilities, plenty for even the largest runbooks
            return reference unless existing_references.include?(reference)
          end
        end

        def generate_output(action)
          action.action_template.call_function(:run, action)
        end

        private

        def copy_action_values(action, hash)
          copy_basic_attributes(action, hash)
          copy_connections_and_templates(action, hash)
          copy_mappings(action, hash)
        end

        def copy_basic_attributes(action, hash)
          action.description = hash[:description]
          action.predecessor_action_reference = hash[:predecessor_action_reference]
          action.predecessor_output_schema_reference = hash[:predecessor_output_schema_reference]
        end

        def copy_connections_and_templates(action, hash)
          action.outbound_connection = IPaaS::Connector::Connection.by_uuid(hash.dig(:outbound_connection, :uuid))
          action.action_template = IPaaS::Connector::ActionTemplate.by_uuid(hash.dig(:action_template, :uuid))
        end

        def copy_mappings(action, hash)
          action.input_mapping = Array(hash[:input_mapping]).map do |m|
            IPaaS::Connector::Mapping::FieldMapping.parse(m)
          end
          action.output_schema_name_mapping = Array(hash[:output_schema_name_mapping]).map do |m|
            IPaaS::Connector::Mapping::SchemaNameMapping.parse(m)
          end
        end
      end

      def initialize(reference = nil)
        self.reference = reference
      end

      def uuid
        "#{runbook.uuid}:#{reference}"
      end

      def to_h_ref
        IPaaS::Connector::Common::Serializer.to_h(self, :reference, :description,
                                                  :predecessor_action_reference, :predecessor_output_schema_reference,
                                                  :outbound_connection, :action_template, :input_mapping,
                                                  :output_schema_name_mapping)
      end

      def input(resolve: false)
        return @input if instance_variable_defined?(:@input) && !resolve

        @input = nil # Prevents infinite loops; see https://xurrent-support.xurrent.com/requests/64601195
        result = input_schema.resolve(self, input_mapping) do |values|
          @input = values
        end
        @input ||= result # Fallback: block is skipped when resolve raises, memoize return value
      end

      def log_input(input)
        # noop
      end

      # Run the action in a couple of steps:
      # 1. Validate the input mapping
      # 2. Call the action_template.run method to retrieve the output
      # 3. Per output in the array:
      #   3a. Resolve the output schema based on the schema_reference
      #   3b. Retrieve the raw output based on the output key
      #   3c. Raise an error in case the output is not conform the output schema
      # 5. Return an array of:
      #     { output: <mapped output> }
      #    or with schema_reference for nested actions
      #     { schema_reference: <reference>, output: <mapped output> }
      def run(output_proc = -> { self.class.generate_output(self) })
        refresh_input_mapping
        refresh_outbound_connection

        log_input(input)

        outputs = Array(output_proc.call)
        mapped_outputs = outputs.map { |output| map_output(output) }
        store_mapped_outputs(mapped_outputs)

        errors = validate_mapped_outputs(mapped_outputs)
        raise IPaaS::Job::FailJob, errors.join("\n") if errors.any?

        mapped_outputs_to_run_results(mapped_outputs)
      end

      def nested?
        action_template&.nested
      end

      def outbound?
        outbound_connection&.configurable?
      end

      def other_actions
        runbook&.actions&.excluding(self) || []
      end

      def predecessor_action
        return if predecessor_action_reference.blank?

        find_other_action(predecessor_action_reference)
      end

      def predecessor_output_schema
        return unless predecessor_action_reference

        predecessor_action&.find_output_schema(predecessor_output_schema_reference)
      end

      def find_other_action(reference)
        other_actions.detect { |a| a.reference == reference }
      end

      def find_output_schema(reference)
        output_schemas&.detect { |s| s.reference == reference }
      end

      def successor(output_schema_reference = nil)
        if output_schema_reference && !nested?
          raise ArgumentError, 'output_schema_reference only available for nested actions'
        end

        runbook&.actions&.detect do |action|
          action.predecessor_action_reference == self.reference &&
            action.predecessor_output_schema_reference == output_schema_reference
        end
      end

      def descendants
        _descendants
      end

      def action_template=(template)
        @action_template = template
        return unless template

        copy_schema_blocks_from(template, :input_schema)
        copy_schema_blocks_from(template, :output_schema, array: true)
        copy_schema_blocks_from(template, :iteration_state_schema)
      end

      def predecessor_output_schema_reference=(schema_reference)
        @predecessor_output_schema_reference = schema_reference.presence&.to_s
      end

      def iteration_state
        runbook&.action_iteration_state(reference)
      end

      def iteration_state_value(*keys)
        iteration_state&.dig(:value, *keys)
      end

      def iteration_count
        iteration_state&.dig(:count) || 0
      end

      def reference_with_update=(new_reference)
        reference_was = self.reference
        self.reference_without_update = ensure_valid_reference(new_reference)
        return if reference_was.blank?

        runbook.actions.each do |action|
          action.update_action_reference(reference_was, new_reference)
        end

        solution.test_cases_for(runbook.uuid)&.each do |test_case|
          updated = test_case.update_action_reference(reference_was, new_reference)
          test_case.save if updated
        end
      end

      alias reference_without_update= reference=
      alias reference= reference_with_update=

      def update_action_reference(reference_was, new_reference)
        updated = false
        if predecessor_action_reference == reference_was
          self.predecessor_action_reference = new_reference
          updated = true
        end
        input_mapping.each do |mapping|
          updated |= mapping.update_action_reference(reference_was, new_reference)
        end
        updated
      end

      def update_runbook_variable(id_was, new_id)
        updated = false
        input_mapping.each do |mapping|
          updated |= mapping.update_runbook_variable(id_was, new_id)
        end
        updated
      end

      def validate_duplicate_predecessor_action
        duplicate_predecessors = runbook&.actions&.excluding(self)&.select do |other_action|
          other_action.predecessor_action_reference == predecessor_action_reference &&
            other_action.predecessor_output_schema_reference == predecessor_output_schema_reference
        end
        return if duplicate_predecessors.blank?

        runbook.errors.add(:base, duplicate_predecessors_message(duplicate_predecessors))
      end

      def validate_presence_of_predecessor_action
        return unless predecessor_action_reference && !predecessor_action

        if predecessor_action_reference == self.reference
          runbook.errors.add(:base, "Action (#{reference}) invalid: cannot be its own predecessor.")
        else
          runbook.errors.add(
            :base,
            "Action (#{reference}) invalid: Predecessor action #{predecessor_action_reference} is unknown."
          )
        end
      end

      def output_schema_name_mapping_disabled
        action_template&.disable_output_schema_name_mapping
      end

      def output_schema_name(schema)
        custom_mapping = find_custom_mapping(schema.reference)
        if custom_mapping && !output_schema_name_mapping_disabled
          custom_mapping.name_mapping
        else
          schema.name
        end
      end

      private

      def find_custom_mapping(schema_reference)
        output_schema_name_mapping&.find { |m| m.schema_reference == schema_reference }
      end

      def refresh_input_mapping
        input(resolve: true)
        return if input.valid?

        raise IPaaS::Job::FailJob, "Input invalid: #{input.full_error_messages}"
      end

      def refresh_outbound_connection
        return unless outbound_connection.present?
        outbound_connection.runbook = self.runbook
        outbound_connection.config(resolve: true)
        return if outbound_connection.valid?

        raise IPaaS::Job::FailJob, "Outbound connection invalid: #{outbound_connection.full_error_messages}"
      end

      def iteration_state_value=(raw_output)
        raise IPaaS::Job::FailJob, 'Iteration state only available for nested actions.' unless nested?

        if raw_output.blank?
          runbook.store_action_iteration_state(reference, nil)
          return
        end

        resolved_mapping = store_iteration_state(raw_output)
        return if resolved_mapping.valid?

        raise IPaaS::Job::FailJob, "Iteration state content invalid: #{resolved_mapping.full_error_messages}"
      end

      def store_iteration_state(raw_output)
        unless raw_output.is_a?(Hash)
          raise IPaaS::Job::FailJob, "Expected iteration state to be a hash, got #{raw_output.class.name}."
        end

        previous_count = iteration_count
        fixed_mapping = IPaaS::Connector::Mapping::FieldMapping.fixed_mapping(raw_output)
        resolved_mapping = iteration_state_schema.resolve(self, fixed_mapping)
        runbook.store_action_iteration_state(reference, { count: previous_count + 1, value: resolved_mapping.to_hash })
        resolved_mapping
      end

      def store_mapped_outputs(mapped_outputs)
        mapped_outputs.each do |schema_reference, resolved_mapping|
          next unless resolved_mapping.present?

          runbook.store_action_output(reference, resolved_mapping.to_hash, output_schema_reference: schema_reference)
        end
      end

      def validate_mapped_outputs(mapped_outputs)
        errors = []
        mapped_outputs.each do |schema_reference, resolved_mapping|
          unless resolved_mapping.valid?
            errors << "Output [#{schema_reference}] invalid: #{resolved_mapping.full_error_messages}"
          end
        end
        errors
      end

      def mapped_outputs_to_run_results(mapped_outputs)
        mapped_outputs.map do |schema_reference, output|
          { output: output }.tap do |nested_outputs|
            nested_outputs[:schema_reference] = schema_reference if self.nested?
          end
        end
      end

      def _descendants(ancestors = [])
        return [] if self.output_schemas.nil?

        successors = []
        successors += self.output_schemas.map(&:reference).map { |schema_ref| successor(schema_ref) } if nested?
        successors << self.successor
        successors.compact!
        successors + (successors - ancestors).flat_map { |s| s.send(:_descendants, ancestors + successors) }
      end

      def predecessor_action_reference_valid?
        errors.add(:predecessor_action, 'cannot be a descendant.') if descendants.include?(predecessor_action)
      end

      def duplicate_predecessors_message(duplicate_predecessors)
        predecessor_name = if predecessor_action
                             "Predecessor action #{predecessor_action.action_template.name} " \
                               "(#{predecessor_action.reference}"
                           else
                             'Predecessor (trigger'
                           end
        predecessor_name += " - #{predecessor_output_schema.reference}" if predecessor_output_schema
        "Action (#{reference}) invalid: #{predecessor_name}) also connected to: " \
          "#{duplicate_predecessors.map(&:reference).join(', ')}."
      end

      def predecessor_output_schema_reference_valid?
        return if predecessor_output_schema_reference.blank?

        unless predecessor_output_schema
          errors.add(:predecessor_output_schema, "#{predecessor_output_schema_reference} is unknown.")
        end
        return unless predecessor_action && !predecessor_action.nested?

        errors.add(:predecessor_output_schema, 'is only available for nested actions.')
      end

      def input_mapping_valid?
        return unless action_template
        return if IPaaS::Connector::Mapping.invalid_mapping?(self, :input_mapping)

        # Trust an already-resolved input when it validates: re-resolving here can
        # be expensive (dynamic schemas re-introspect a potentially multi-MB schema)
        # and #run re-resolves regardless, so the gate only resolves when no valid
        # memo exists yet. Reading @input directly keeps this a pure check (no
        # resolve); it is nil before the first resolve and if a prior resolve raised.
        return if @input&.valid?

        # In execution mode the parse-time memo may have frozen a degraded dynamic
        # schema (e.g. introspection unavailable at parse time), so re-resolve
        # against the live schema before rejecting. Designer mode keeps the memo to
        # avoid eager introspection in the builder.
        resolved = execution_mode? ? input(resolve: true) : input
        return if resolved.valid?

        errors.add(:input_mapping, "invalid: #{resolved.full_error_messages}")
      end

      def execution_mode?
        runbook.present? && !runbook.designer_mode?
      end

      def outbound_connection_valid?
        return unless outbound_connection
        return if outbound_connection.valid?

        errors.add(:outbound_connection, "invalid: #{outbound_connection.full_error_messages}")
      end

      def ensure_valid_reference(new_reference)
        return new_reference if runbook.nil?
        if new_reference.match?(REFERENCE_WITH_INVALID_CHARS)
          raise IPaaS::Error,
                "Action reference cannot contain ', \", #{EXCLUDED_REFERENCE_CHARACTER} or \\: #{new_reference}"
        end

        reference_was = self.reference
        exists = runbook.actions.map(&:reference).excluding(reference_was).include?(new_reference)
        raise IPaaS::Error, "Action reference is not unique: #{new_reference}" if exists

        new_reference.presence || reference_was || self.class.generate_reference(runbook)
      end

      def map_output(output)
        raise IPaaS::Job::FailJob, "Expected output to be a hash, got #{output.class.name}." unless output.is_a?(Hash)

        output_schema = extract_output_schema(output)
        reference = self.nested? ? output_schema.reference : nil
        raw_output = hash_with_encrypted_secrets(output[:output], output_schema)

        fixed_mapping = IPaaS::Connector::Mapping::FieldMapping.fixed_mapping(raw_output)
        mapped_output = output_schema.resolve(self, fixed_mapping)
        [reference, mapped_output]
      end

      def extract_output_schema(output)
        return self.output_schemas.first unless self.nested?

        schema_reference = output[:schema_reference]
        if schema_reference.blank?
          raise IPaaS::Job::FailJob, "Missing schema_reference, found keys: #{output.keys.join(', ')}."
        end

        output_schema = output_schema(schema_reference)
        raise IPaaS::Job::FailJob, "Output schema '#{schema_reference}' not found." unless output_schema

        output_schema
      end
    end
  end
end

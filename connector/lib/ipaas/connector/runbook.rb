module IPaaS
  module Connector
    # Instance of a runbook which consists of a single trigger and multiple actions.
    #
    # One is created by parsing a (JSON) hash.
    class Runbook
      extend IPaaS::Connector::Common::ProcRules::ProcSafe

      proc_safe :trigger_output, :action_output, :write_variable, :read_variable,
                :variable_field, :account_id, :runbook

      include IPaaS::Connector::Common::Model
      include IPaaS::Connector::Common::UuidMixin
      include IPaaS::Job::Store
      include IPaaS::Job::Environment
      include IPaaS::Job::Encryption

      ACTION_STORE_KEY_SEPARATOR = IPaaS::Connector::Action::EXCLUDED_REFERENCE_CHARACTER

      attr_accessor :solution
      delegate :account_id, :version, to: :solution, allow_nil: true
      delegate :endpoint, to: :trigger, allow_nil: true
      attr_writer :job_state

      attribute :name
      attribute :description
      SUPPORTED_CONCURRENCY_TYPES = [:per_runbook, :per_job_context_identifier].freeze
      attribute :concurrency, type: Hash

      attribute :trigger, type: Trigger
      attribute :actions, type: [Action]

      attribute :runbook_variables, type: [IPaaS::Connector::Schema::Field]

      validates :name, :trigger, :actions, presence: { message: "can't be blank." }
      validate :concurrency_valid?
      validate :trigger_valid?
      validate :actions_valid?
      validate :runbook_variables_valid?

      class << self
        def parse(runbook)
          hash = IPaaS::Connector::Common::Serializer.parse(runbook, with_uuid: true)
          raise IPaaS::Error, 'Runbook must be a hash.' unless hash.is_a?(Hash)
          hash = hash.deep_symbolize_keys

          Runbook.new(hash[:uuid]).tap do |new_runbook|
            parse_concurrency(new_runbook, hash[:concurrency])
            parse_runbook_variables(new_runbook, hash.fetch(:runbook_variables, []))
            copy_runbook_values(new_runbook, hash)
            new_runbook.valid? # triggers resolve
          end
        end

        def parse_concurrency(runbook, concurrency)
          return unless concurrency.present?
          unless concurrency.is_a?(Hash) && concurrency[:type].present?
            raise IPaaS::Error, 'Concurrency must indicate type.'
          end
          type_value = concurrency[:type].to_s.to_sym

          runbook.concurrency = { type: type_value }
        end

        def parse_runbook_variables(runbook, vars)
          runbook.runbook_variables = vars.map do |var|
            IPaaS::Connector::Types::SchemaFieldType.resolve(var)
          end
        end

        private

        def copy_runbook_values(runbook, hash)
          runbook.name = hash[:name]
          runbook.description = hash[:description]
          runbook.trigger = IPaaS::Connector::Trigger.parse(runbook, hash[:trigger]) if hash.key?(:trigger)
          copy_actions(runbook, hash)
        end

        def copy_actions(runbook, hash)
          runbook.actions = Array(hash[:actions]).map do |action|
            IPaaS::Connector::Action.parse(runbook, action)
          end
          # re-evaluate as runbook variables may depend on variables defined in outbound connections related
          # to successor actions
          runbook.actions.map { |action| action.input(resolve: true) }
        end
      end

      def to_h
        IPaaS::Connector::Common::Serializer.to_h(self,
                                                  :uuid, :name, :description,
                                                  :concurrency, :runbook_variables, :trigger, :actions,)
      end

      def to_json(_options = nil)
        {
          uuid: uuid,
          name: name,
        }.to_json
      end

      def in_designer_mode
        execution_mode_was = @execution_mode
        @execution_mode = false
        yield
      ensure
        @execution_mode = execution_mode_was
      end

      def in_execution_mode
        execution_mode_was = @execution_mode
        @execution_mode = true
        yield
      ensure
        @execution_mode = execution_mode_was
      end

      def designer_mode?
        !@execution_mode
      end

      def job_state
        @job_state ||= IPaaS::Job::MemoryStore.new
      end

      def trigger_output
        job_state.read('trigger_output')
      end

      def store_trigger_output(value)
        job_state.write('trigger_output', value)
      end

      def job_context_identifier
        job_state.read('job_context_identifier')
      end

      def store_job_context_identifier(value)
        job_state.write('job_context_identifier', value)
      end

      def action_output(action_reference, output_schema_reference: nil)
        output_schema_reference = resolve_output_schema_reference(action_reference, output_schema_reference)
        stored_value = job_state.read(action_store_key(action_reference, output_schema_reference))
        return stored_value if stored_value.blank?

        action = actions&.detect { |action| action.reference == action_reference }
        return stored_value unless action

        output_schema = find_output_schema(action, output_schema_reference)
        return stored_value unless output_schema

        reconstruct_secret_strings(stored_value, output_schema)
      end

      def store_action_output(action_reference, value, output_schema_reference: nil)
        output_schema_reference = resolve_output_schema_reference(action_reference, output_schema_reference)
        job_state.write(action_store_key(action_reference, output_schema_reference), value)
      end

      def action_iteration_state(action_reference)
        job_state.read(action_iteration_state_key(action_reference))
      end

      def rename_runbook_variable(id_was, new_id)
        update_actions_runbook_variable(id_was, new_id)
        update_connections_runbook_variable(id_was, new_id)
        update_test_cases_runbook_variable(id_was, new_id)
      end

      def store_action_iteration_state(action_reference, value)
        job_state.write(action_iteration_state_key(action_reference), value)
      end

      def write_variable(id, value)
        variable = IPaaS::Connector::RunbookVariable.new(id, variable_field(id), value)
        raise IPaaS::Job::FailJob, "Runbook variable '#{id}': #{variable.full_error_messages}" if variable.invalid?

        job_state.write("variable:#{variable.id}", value)
      end

      def read_variable(id)
        job_state.read("variable:#{id}")
      end

      def variable_field(id)
        runbook_variables.detect { |variable| variable.id.to_s == id.to_s }&.deep_dup
      end

      def add_action_errors
        errors.add(:base, 'No actions are connected to the trigger.') if trigger && !trigger.successor

        validate_unreachable_actions

        @action_set = Set.new
        actions.each do |action|
          validate_action(action)
          next if action.valid?
          errors.add(:actions, "(#{action.reference}) invalid: #{action.full_error_messages}")
        end
      end

      def validate_unreachable_actions
        return if actions.blank?
        return unless trigger&.successor

        reachable_references = Set.new(ordered_reachable_actions.map(&:reference))
        unreachable_actions = actions.reject { |action| reachable_references.include?(action.reference) }

        unreachable_actions.each do |action|
          errors.add(:base, "Action (#{action.reference}) is unreachable")
        end
      end

      def ordered_reachable_actions
        # also includes orphaned output schemas
        lookup = actions&.index_by(&:reference) || {}
        sorted_actions = []
        children_by_parent = (actions || []).group_by(&:predecessor_action_reference)
        visited = Set.new
        traverse_chain(first_action, sorted_actions, lookup, children_by_parent, visited)
        sorted_actions
      end

      def first_action
        trigger&.successor || actions&.find { |action| action.predecessor_action_reference.nil? }
      end

      private

      def update_actions_runbook_variable(id_was, new_id)
        actions.each do |action|
          action.update_runbook_variable(id_was, new_id)
        end
      end

      def update_connections_runbook_variable(id_was, new_id)
        Solution.as_current(solution) do
          IPaaS::Connector::Connection.all.each do |connection|
            updated = connection.update_runbook_variable(id_was, new_id)
            connection.save(validate: false) if updated
          end
        end
      end

      def update_test_cases_runbook_variable(id_was, new_id)
        solution.test_cases_for(self.uuid)&.each do |test_case|
          updated = test_case.update_runbook_variable(id_was, new_id)
          test_case.save(validate: false) if updated
        end
      end

      def reconstruct_secret_strings(value, schema)
        value.each_with_object(value.class.new) do |(key, val), result|
          field = schema.field_definition(key)
          result[key] = reconstruct_field_value(val, field)
        end
      end

      def reconstruct_field_value(value, field)
        return reconstruct_nested_array_fields(value, field) if nested_array_field?(field, value)
        return reconstruct_nested_hash_fields(value, field) if nested_hash_field?(field, value)
        return reconstruct_array_fields(value, field) if array_field?(field, value)
        return convert_string_to_secret_string(value) if secret_string_field?(field)

        value
      end

      def nested_array_field?(field, value)
        field.type == :nested && field.array && value.is_a?(Array)
      end

      def nested_hash_field?(field, value)
        field.type == :nested && value.is_a?(Hash)
      end

      def array_field?(field, value)
        field.array && value.is_a?(Array)
      end

      def secret_string_field?(field)
        field.type == :secret_string
      end

      def reconstruct_array_fields(value, field)
        value.map { |element| reconstruct_field_value(element, field) }
      end

      def reconstruct_nested_hash_fields(hash, parent_field)
        hash.each_with_object(hash.class.new) do |(key, val), result|
          nested_field = parent_field.field_definition(key)
          result[key] = reconstruct_field_value(val, nested_field)
        end
      end

      def reconstruct_nested_array_fields(value, parent_field)
        value.map { |element| reconstruct_nested_hash_fields(element, parent_field) }
      end

      def find_output_schema(action, output_schema_reference)
        if output_schema_reference.present? && action.nested?
          action.find_output_schema(output_schema_reference)
        else
          action.output_schemas&.first
        end
      end

      def convert_string_to_secret_string(value)
        return nil if value.nil?
        new_secret_string(value.to_s)
      end

      def traverse_chain(action, sorted, lookup, children_by_parent, visited)
        while action
          append_action_and_nested(action, sorted, lookup, children_by_parent, visited)
          action = action.successor
        end
      end

      def append_action_and_nested(action, sorted, lookup, children_by_parent, visited)
        return if visited.include?(action.reference)
        visited.add(action.reference)
        sorted << lookup[action.reference]

        return unless action.nested?

        action.output_schemas.each do |schema|
          nested = action.successor(schema.reference)
          traverse_chain(nested, sorted, lookup, children_by_parent, visited)
        end

        traverse_orphan_nested_branches(action, sorted, lookup, children_by_parent, visited)
      end

      def traverse_orphan_nested_branches(action, sorted, lookup, children_by_parent, visited)
        children = Array(children_by_parent[action.reference])
        known_schema_refs = Set.new(action.output_schemas&.map(&:reference))
        orphan_children = children.select do |child|
          child.predecessor_output_schema_reference.present? &&
            !known_schema_refs.include?(child.predecessor_output_schema_reference)
        end
        orphan_children.each do |orphan|
          traverse_chain(orphan, sorted, lookup, children_by_parent, visited)
        end
      end

      def action_iteration_state_key(action_reference)
        "action_iteration_state_#{action_reference}"
      end

      def action_store_key(action_reference, output_schema_reference)
        key = "action_output_#{action_reference}"
        key += "#{ACTION_STORE_KEY_SEPARATOR}#{output_schema_reference}" if output_schema_reference
        key
      end

      def resolve_output_schema_reference(action_reference, output_schema_reference)
        return output_schema_reference if output_schema_reference.present?

        action = actions&.detect { |a| a.reference == action_reference }
        output_schemas = action&.output_schemas || []
        return output_schemas.first.reference if output_schemas.one?

        nil
      end

      def concurrency_valid?
        return unless concurrency.present?

        type_value = concurrency[:type]
        return if type_value.in?(SUPPORTED_CONCURRENCY_TYPES)

        errors.add(:concurrency, "Concurrency type must be one of: [#{SUPPORTED_CONCURRENCY_TYPES.join(', ')}]")
      end

      def trigger_valid?
        return unless trigger
        return if trigger.valid?

        errors.add(:trigger, "invalid: #{trigger.full_error_messages}")
      end

      def actions_valid?
        return true if actions.blank?

        add_action_errors
        errors[:actions].none?
      end

      def validate_action(action)
        action.validate_presence_of_predecessor_action
        connection_key = {
          predecessor: action.predecessor_action_reference,
          output_schema: action.predecessor_output_schema_reference,
        }
        if @action_set.include?(connection_key)
          action.validate_duplicate_predecessor_action
        else
          @action_set.add(connection_key)
        end
      end

      def runbook_variables_valid?
        return true if runbook_variables.blank?
        ids = runbook_variables.map { |x| x.id.to_s }
        return unless ids.size != ids.uniq.size
        duplicate = ids.detect { |id| ids.count(id) > 1 }
        errors.add(:runbook_variables, "Runbook variable '#{duplicate}' is defined more than once")
      end
    end
  end
end

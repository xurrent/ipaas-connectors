require 'digest'
require 'method_source'

module IPaaS
  module Connector
    module Common
      class ProcHelper
        ACTION_OUTPUT_REGEX = /action_output\('([^']+)'|action_output\("([^"]+)"/

        # Field attributes any FIELD_RULES rule may consult to decide
        # validity. Today only `NoSafePresentRule` reads the field, and it
        # branches on `(required && type == :boolean)`. If a future rule
        # reads a different attribute, widen `field_validation_class` AND
        # this list. The contract-guard spec enforces this stays in sync.
        FIELD_VALIDATION_ATTRIBUTES = [:required, :type].freeze

        class InvalidProcCalled < IPaaS::Error
        end

        class ProcSourceError < IPaaS::Error
          attr_reader :context

          def initialize(message = nil, context: nil)
            super(message)
            @context = context
          end
        end

        class << self
          def action_references(proc)
            proc.scan(ACTION_OUTPUT_REGEX)
                .map(&:compact)
                .flatten
          end

          def create_action_ref_replacer(reference_was, new_reference)
            replace_regex = /action_output\((["'])#{Regexp.escape(reference_was)}\1/
            ->(proc) do
              proc.gsub(replace_regex) do
                quote = ::Regexp.last_match(1)
                "action_output(#{quote}#{new_reference}#{quote}"
              end
            end
          end

          def create_runbook_variable_replacer(id_was, new_id)
            methods = 'read_variable|write_variable|variable_field'
            pattern = /(runbook&?\.)(#{methods})\s*\(\s*(["'])#{Regexp.escape(id_was)}\3/
            ->(proc) do
              proc.gsub(pattern) do
                receiver = ::Regexp.last_match(1)
                method = ::Regexp.last_match(2)
                quote = ::Regexp.last_match(3)
                "#{receiver}#{method}(#{quote}#{new_id}#{quote}"
              end
            end
          end

          def proc_source(procedure)
            procedure.source.strip
          rescue StandardError => e
            context = proc_debug_context(procedure, e)
            raise ProcSourceError.new("Error retrieving proc source #{e.class}: '#{e.message}'",
                                      context: context)
          end

          def proc_debug_context(procedure, exception = nil)
            context = { source_location: procedure.source_location }
            context = add_proc_source(context)
            add_uuid_scope(context)
          rescue StandardError => e
            msg = "Unable to get debug context: #{e.class}: '#{e.message}'."
            msg += " Original exception: #{exception.class}: '#{exception.message}'." if exception
            raise ProcSourceError.new(msg, context: context)
          end

          def add_proc_source(context)
            file_name, proc_start_line = context[:source_location]
            file_content = MethodSource.lines_for(file_name)
            context.merge!({
              line_content: file_content[proc_start_line - 1].rstrip,
              file_content: file_content.join,
            })
          end

          def add_uuid_scope(context)
            file_name, = context[:source_location]
            if MethodSource.use_uuid_cache?(file_name)
              context[:cache_postfix] = SolutionFileCache.uuid_scope_postfix_for_error_msg
            end
            context
          end

          def captured_variables(proc, seen: Set.new)
            seen << proc
            proc.binding.local_variables.each_with_object({}) do |bound_local_var, acc|
              value = proc.binding.local_variable_get(bound_local_var)
              if value.is_a?(Proc)
                captured_variables(value, seen: seen).each { |k, v| acc[k] = v } unless seen.include?(value)
              else
                acc[bound_local_var] = value
              end
              acc
            end
          end
        end

        cattr_accessor :validated_before do
          Set.new
        end
        attr_accessor :context, :procedure, :source, :on_invalid, :errors

        def initialize(context, procedure, on_invalid: nil, field: nil)
          @context = context
          @procedure = procedure
          @source = procedure.is_a?(String) ? procedure : self.class.proc_source(procedure)
          @on_invalid = on_invalid
          @field = field
        end

        def valid?
          self.errors = []
          return true if validated_before.include?(validation_cache_key)

          validate_nodes(parse_ast)
          self.errors.none?.tap do |valid|
            validated_before.add(validation_cache_key) if valid
          end
        end

        def execute_if_valid(...)
          return nil unless valid?

          execute(...)
        end

        def execute(*params, **kwargs)
          raise InvalidProcCalled, errors.to_s unless valid?

          executing do
            if params.empty? && kwargs.empty?
              run_proc
            else
              run_proc_with_params(*params, **kwargs)
            end
          end
        end

        private

        def executing
          old_context = self.context
          self.context = executing_procs.first.context if context.nil? && executing_procs.any?
          executing_procs.push(self)
          yield
        ensure
          self.context = old_context
          executing_procs.pop
        end

        def executing_procs
          Thread.current[:executing_procs] ||= []
        end

        def run_proc
          if procedure.is_a?(String)
            # As there are no parameters provided a string can simply be evaluated and will
            # directly result in the value, e.g. '["Hello", " ", "World!"].join()'
            context.instance_eval(procedure, __FILE__, __LINE__)
          else
            context.instance_exec(&procedure)
          end
        end

        def run_proc_with_params(*params, **)
          proc = if procedure.is_a?(String)
                   # As parameters provided the string should be evaluated to a
                   # procedure e.g. '->(value) { value.starts_with?("Hello") }'.
                   # The next step is then to execute the proc with the given params.
                   context.instance_eval(procedure, __FILE__, __LINE__)
                 else
                   procedure
                 end
          context.instance_exec(*params, **, &proc)
        end

        def validate_nodes(ast)
          node_validator = ProcRules::NodeValidator.new(context: context,
                                                        on_invalid: ->(message) { validation_error(message) },
                                                        field: @field)
          ast&.each_node { |node| node_validator.validate(node) }
        end

        def validation_error(message)
          (self.errors ||= []) << message
          on_invalid&.call(message)
        end

        def parse_ast
          rubocop_source = RuboCop::AST::ProcessedSource.new(source, 3.4)
          validation_error(rubocop_source.diagnostics.map(&:render).join("\n")) if rubocop_source.ast.nil?
          rubocop_source.ast
        end

        def validation_cache_key
          @validation_cache_key ||= "#{Digest::SHA256.hexdigest(source)}:#{field_validation_class}".freeze
        end

        # Rule behavior may depend on field attributes. If so, those must be used in key otherwise
        # only source needs to be used to determine whether proc is safe.
        def field_validation_class
          # At the moment only NoSafePresentRule reads the field,
          # and it branches on `(required && type == :boolean)`.

          return :other unless @field
          return :required_boolean if @field.try(:required) && @field.try(:type) == :boolean

          :other
        end
      end
    end
  end
end

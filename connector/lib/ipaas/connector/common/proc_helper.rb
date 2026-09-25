require 'digest'
require 'method_source'

module IPaaS
  module Connector
    module Common
      class ProcHelper
        ACTION_OUTPUT_REGEX = /action_output\('([^']+)'|action_output\("([^"]+)"/

        # This version is used as a baseline for allowed constructs/methods.
        # Change it only after a thorough review of its impact.
        TARGET_RUBY_VERSION = 3.4

        # Upper bound on how deeply procs may nest during a single resolution.
        # A proc whose value depends on itself (e.g. a config field that reads
        # `config`) re-enters proc execution without bound and, uncapped, exhausts
        # the Ruby stack (SystemStackError) which 500s the page. 100 is far above
        # anything an authored solution nests; the nesting of the file itself is
        # bounded separately, by YamlLimits::MAX_DEPTH.
        MAX_PROC_DEPTH = 100

        # The maximum size iPaaS allows for an expression, above this value it is not validated.
        MAX_SOURCE_BYTES = 64.kilobytes

        # The maximum nesting depth iPaaS allows in an expression, above this value it is
        # rejected. A best-effort ceiling: some expressions are refused by the guard below
        # instead. Changing this needs explicit security approval.
        MAX_NESTING_DEPTH = 400

        TOO_LARGE_MESSAGE = "Expression is larger than #{MAX_SOURCE_BYTES / 1.kilobyte} KB. Split " \
                            'it into separate expressions.'.freeze

        TOO_COMPLEX_MESSAGE = 'This expression is too complex to validate. Simplify it, for ' \
                              'example by splitting it into separate expressions.'.freeze

        SYNTAX_ERROR_MESSAGE = 'Expression is not supported Ruby.'.freeze

        # The guards below cover cases no source is known to reach. They log under this prefix so
        # whether they are reachable is answered by scanning logs rather than by argument. Source
        # text is never logged, only its size.
        UNEXPECTED_PREFIX = 'ProcHelper unexpected'.freeze

        BARE_DATA_PILL_MESSAGE = 'A data pill was used outside a string, where Ruby treats it as ' \
                                 "a comment and ignores it. Remove the surrounding \#{} so the " \
                                 'pill is used directly in code, or place the pill inside a ' \
                                 'double-quoted string.'.freeze

        UNATTRIBUTED_BLOCK_MESSAGE = 'A block defined inside an expression cannot be validated. ' \
                                     'Define it in the connector instead.'.freeze

        # Field attributes any FIELD_RULES rule may consult to decide
        # validity. Today only `NoSafePresentRule` reads the field, and it
        # branches on `(required && type == :boolean)`. If a future rule
        # reads a different attribute, widen `field_validation_class` AND
        # this list. The contract-guard spec enforces this stays in sync.
        FIELD_VALIDATION_ATTRIBUTES = [:required, :type].freeze

        # A block from one of this gem's own files is ours whichever connector runs it, so its verdict
        # is process-wide. Spelled the way Ruby reports source_location, not through __dir__, which
        # resolves symlinks that a loaded file's path keeps.
        GEM_LIB = "#{File.expand_path('../../..', File.dirname(__FILE__))}/".freeze

        # Where a String proc's lambdas are born. Such a block has no connector to answer for it and
        # is not the gem's either, so it is refused rather than judged.
        STRING_PROC_FILE = File.expand_path(__FILE__).freeze

        class InvalidProcCalled < IPaaS::Error
        end

        class MissingValidationStore < IPaaS::Error
        end

        class RecursiveProcError < IPaaS::Error
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

          # The methods through which procs access runbook variables; shared by the
          # replacer and the usage detector so they cannot drift apart.
          RUNBOOK_VARIABLE_METHODS = /read_variable|write_variable|variable_field/
          RUNBOOK_VARIABLE_USAGE = /runbook&?\.(?:#{RUNBOOK_VARIABLE_METHODS})\b/

          def runbook_variables_used?(proc)
            RUNBOOK_VARIABLE_USAGE.match?(proc.to_s)
          end

          def create_runbook_variable_replacer(id_was, new_id)
            pattern = /(runbook&?\.)(#{RUNBOOK_VARIABLE_METHODS})\s*\(\s*(["'])#{Regexp.escape(id_was)}\3/
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

          def read_source(source)
            SourceParser.read(source)
          end

          def gem_file?(file)
            file&.start_with?(GEM_LIB) || false
          end

          # Why a source must not be evaluated, or nil when it may be. One that will not parse is
          # refused rather than evaluated to find out why: it can never run, and evaluating it
          # requires much more work than parsing it does before reaching the same conclusion.
          def unevaluable_reason(source)
            unevaluable_reason_of(read_source(source))
          end

          def unevaluable_reason_of(parsed)
            return :unparseable if parsed.tree.nil?

            :too_deeply_nested if depth_exceeded?(parsed.tree)
          end

          def depth_exceeded?(sexp)
            stack = [[sexp, 1]]
            until stack.empty?
              node, depth = stack.pop
              return true if depth > MAX_NESTING_DEPTH

              node.each { |child| stack.push([child, depth + 1]) if child.is_a?(Array) }
            end
            false
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

        private_class_method :depth_exceeded?

        cattr_accessor :validated_before do
          Set.new
        end
        attr_reader :declared_context
        attr_accessor :procedure, :source, :on_invalid

        def initialize(context, procedure, on_invalid: nil, field: nil, connector: nil)
          @declared_context = context
          @procedure = procedure
          @source = procedure.is_a?(String) ? procedure : self.class.proc_source(procedure)
          @on_invalid = on_invalid
          @field = field
          @connector = connector
        end

        def errors
          errors_by_helper[self] ||= []
        end

        # The default inspect would print the whole connector graph through @connector, once per
        # helper, wherever a template or trigger is inspected.
        def inspect
          "ProcHelper (#{source_origin})"
        end

        def errors=(value)
          errors_by_helper[self] = value
        end

        def valid?
          self.errors = []
          judged_valid?(validation_store)
        rescue SystemStackError
          refuse_stack_exhausted
          false
        end

        def execute_if_valid(...)
          return nil unless valid?

          execute(...)
        end

        def execute(*params, **kwargs)
          raise InvalidProcCalled, errors.to_s unless valid?

          executing do |ctx|
            if params.empty? && kwargs.empty?
              run_proc(ctx)
            else
              run_proc_with_params(ctx, *params, **kwargs)
            end
          end
        end

        private

        def judged_valid?(store)
          return false if store.nil?
          return true if store.include?(validation_cache_key)

          validate_before_parsing
          return false if errors.any?

          validate_nodes(parse_ast)
          self.errors.none?.tap { |valid| store.add(validation_cache_key) if valid }
        end

        # Which store may answer for this block is decided by where the block was written, never by
        # who runs it: a connector-scoped verdict must not land in the process-wide set.
        def validation_store
          case block_origin
          when :global then validated_before
          when :string_born
            refuse_unattributed_block
            nil
          else connector_store
          end
        end

        def block_origin
          return :global if procedure.is_a?(String)

          file = procedure.source_location&.first
          return :string_born if file == STRING_PROC_FILE
          return :global if self.class.gem_file?(file)

          :connector
        end

        def connector_store
          # Our class is the receiver so the judged object never gets to answer the check.
          return @connector.proc_validations if IPaaS::Connector::Connector === @connector # rubocop:disable Style/CaseEquality

          # No owner is a programming error rather than authored input, so it raises where a block born inside an
          # expression falls closed: a field error here would silently blank whatever it mapped.
          log_unexpected('no connector owns the block')
          raise MissingValidationStore, 'No connector owns this block, so its validation cannot be recorded.'
        end

        def refuse_unattributed_block
          # Raising would turn one planted block into a 500 on every later render of the shared graph.
          # Logged first: `validation_error` reaches an `on_invalid` that may raise.
          log_unexpected('block born inside an expression')
          validation_error(UNATTRIBUTED_BLOCK_MESSAGE)
        end

        def executing
          guard_against_recursion!
          ctx = effective_context
          executing_procs.push([self, ctx])
          begin
            yield ctx
          ensure
            executing_procs.pop
          end
        end

        def effective_context
          declared_context || executing_procs.first&.last
        end

        def errors_by_helper
          Thread.current[:proc_helper_errors] ||= ObjectSpace::WeakKeyMap.new
        end

        # Raised before pushing, so a self-referential/too-deep proc is stopped as an
        # ordinary (catchable) error instead of exhausting the stack. Kept outside the
        # push/pop begin/ensure above so it never pops a frame it did not push.
        def guard_against_recursion!
          return if executing_procs.size < MAX_PROC_DEPTH

          raise RecursiveProcError,
                "Expression is nested too deeply or refers back to itself (over #{MAX_PROC_DEPTH} levels of " \
                'evaluation). Check for an expression whose value depends on itself, for example a config field ' \
                'that reads `config`.'
        end

        def executing_procs
          Thread.current[:executing_procs] ||= []
        end

        def run_proc(ctx)
          if procedure.is_a?(String)
            # As there are no parameters provided a string can simply be evaluated and will
            # directly result in the value, e.g. '["Hello", " ", "World!"].join()'
            ctx.instance_eval(procedure, __FILE__, __LINE__)
          else
            ctx.instance_exec(&procedure)
          end
        end

        def run_proc_with_params(ctx, *params, **)
          proc = if procedure.is_a?(String)
                   # As parameters provided the string should be evaluated to a
                   # procedure e.g. '->(value) { value.starts_with?("Hello") }'.
                   # The next step is then to execute the proc with the given params.
                   ctx.instance_eval(procedure, __FILE__, __LINE__)
                 else
                   procedure
                 end
          ctx.instance_exec(*params, **, &proc)
        end

        def validate_nodes(ast)
          node_validator = ProcRules::NodeValidator.new(context: effective_context,
                                                        on_invalid: ->(message) { validation_error(message) },
                                                        field: @field, procedure: procedure)
          ast&.each_node { |node| node_validator.validate(node) }
        end

        def validation_error(message)
          (self.errors ||= []) << message
          on_invalid&.call(message)
        end

        # Ordered so the most actionable message wins, and so an oversized source is refused before
        # either of the two parses below reads it.
        def validate_before_parsing
          validate_source_size
          return if errors.any?

          parsed = self.class.read_source(source)
          reason = self.class.unevaluable_reason_of(parsed)
          # Too deep needs a restructure whatever else is wrong with it, so it is reported first: a
          # pill fixed on the way to that restructure was never the thing standing in the way. An
          # unparseable source is the other way around, since a bare pill is usually why it will not
          # parse, and its own message says so where a syntax error does not.
          if reason == :too_deeply_nested
            validation_error(TOO_COMPLEX_MESSAGE)
            return
          end

          validate_no_bare_interpolation(parsed)
          validate_unparseable(parsed) if reason == :unparseable
        end

        def validate_source_size
          return if source.bytesize <= MAX_SOURCE_BYTES

          validation_error(TOO_LARGE_MESSAGE)
        end

        def validate_unparseable(parsed)
          return if errors.any?

          validation_error(parsed.diagnostic || SYNTAX_ERROR_MESSAGE)
        end

        # SystemStackError is not a StandardError, so it escapes validation unless named. The bounds
        # refuse every shape known to reach this, which is not the same as making it unreachable;
        # keep this so a shape they miss still becomes a field error.
        def refuse_stack_exhausted
          validation_error(TOO_COMPLEX_MESSAGE)
          log_unexpected("stack exhausted validating #{source.bytesize} bytes")
        end

        def log_unexpected(detail)
          IPaaS.default_logger.warn("#{UNEXPECTED_PREFIX}: #{detail} from #{source_origin}")
        end

        # Where the source came from, so a log line is actionable on its own. Never raises: one
        # caller is the stack-overflow rescue, where losing the field error to fetch a log detail
        # would be a poor trade.
        def source_origin
          return "field '#{@field.id}'" if @field.try(:id)
          return 'an expression field' if procedure.is_a?(String)

          file, line = procedure.source_location
          file ? "#{file}:#{line}" : 'an unknown location'
        rescue StandardError => e
          "an origin that could not be read (#{e.class})"
        end

        def parse_ast
          rubocop_source = RuboCop::AST::ProcessedSource.new(source, TARGET_RUBY_VERSION)
          return rubocop_source.ast unless rubocop_source.ast.nil?

          # Unparseable source is refused before this, so reaching here means the two parsers
          # disagree. No such source is known; report the diagnostic rather than accept it
          # silently. No diagnostic means nothing to parse, which an empty expression is allowed.
          diagnostics = rubocop_source.diagnostics.map(&:render).join("\n")
          if diagnostics.present?
            log_unexpected("parsers disagree on #{source.bytesize} bytes")
            validation_error(diagnostics)
          end
          nil
        end

        # A data pill written outside a string (e.g. `mapping[#{pill}]`) lexes as a Ruby comment,
        # silently discarding the rest of the line, so it reads as one however the source parses.
        # Reading the comments rather than the tree keeps this actionable message available for a
        # source that will not parse at all. The lexer never treats a real string's `#{...}` as a
        # comment, so scanning comments avoids false positives on legitimate procs. A hand-written
        # comment starting with `#{` (no space after #) is technically a false positive but that
        # style is never used in practice.
        def validate_no_bare_interpolation(parsed)
          return unless parsed.comments.any? { |text| text.start_with?('#{') }

          validation_error(BARE_DATA_PILL_MESSAGE)
        end

        # A gem block is exempt from the class allow-list, and an expression of the same text shares
        # its store, so the two verdicts are kept apart.
        def validation_cache_key
          @validation_cache_key ||= [Digest::SHA256.hexdigest(source), field_validation_class,
                                     *(:gem if gem_block?),].join(':').freeze
        end

        def gem_block?
          !procedure.is_a?(String) && block_origin == :global
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

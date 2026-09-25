module IPaaS
  module Connector
    module Common
      module LoadRules
        # Judges a connector definition against a declared shape without evaluating it, so that a
        # body which is not a connector definition is refused before it can run. Bodies of
        # proc-bearing blocks are not walked: those are expressions, governed by the proc rules.
        class ConnectorShape
          # Not pinned to a receiver type, because it is meaningful on every literal. Its receiver is
          # still gated: `literal?` or `const_expr_receiver?`. We do not allow it on a bare const node.
          ANY_RECEIVER_METHODS = [:freeze].to_set.freeze

          # Pinned to the receiver types the method is defined on. Naming a method without its
          # receiver would accept it on any value, and a core extension adding the same name to
          # another type would then widen the accepted shape with nobody reviewing it.
          TYPED_RECEIVER_METHODS = {
            strip: [:str, :dstr].to_set.freeze,
            chomp: [:str, :dstr].to_set.freeze,
            minutes: [:int, :float].to_set.freeze,
            seconds: [:int, :float].to_set.freeze,
          }.freeze

          LITERAL_METHODS = (ANY_RECEIVER_METHODS + TYPED_RECEIVER_METHODS.keys).freeze

          PERMITTED_PATHS = [
            [:IPaaS, :Job, :CompactHash].freeze,
            [:IPaaS, :Job, :Humanize].freeze,
            [:IPaaS, :Job, :GraphQL, :ArtifactCache].freeze,
            [:IPaaS, :Job, :GraphQL, :FieldBuilder].freeze,
            [:IPaaS, :Job, :GraphQL, :QueryBuilder].freeze,
            [:IPaaS, :Job, :GraphQL, :Result].freeze,
            [:IPaaS, :Job, :GraphQL, :Schema].freeze,
          ].to_set.freeze

          # A constant assignment naming one of these would shadow the root of a permitted path for
          # every proc in the file, which run after the body and so cannot be judged positionally.
          ROOT_SEGMENTS = PERMITTED_PATHS.to_set(&:first).freeze

          SUPERCLASS_PATH = [:IPaaS, :Connector, :Definition].freeze

          POSITIONS = [:connector, :action, :trigger, :inbound_connection, :outbound_connection].to_set.freeze

          PROC_BEARING = [
            :authenticate, :config_schema, :config_tester, :deprovision, :extract_blueprint,
            :helper, :input_schema, :iteration_state_schema, :output_schema, :parse, :provision,
            :respond_with, :run, :setup_info, :validate,
          ].to_set.freeze

          VERBS = {
            connector: [:action, :avatar, :description, :helper, :inbound_connection, :name, :outbound_connection,
                        :trigger,],
            action: [:avatar, :description, :disable_output_schema_name_mapping, :helper, :input_schema,
                     :iteration_state_schema, :name, :nested, :output_schema, :run,],
            trigger: [:avatar, :blueprint_filenames, :config_schema, :deprovision, :description,
                      :extract_blueprint, :helper, :internal_only, :name, :outbound_traffic,
                      :output_schema, :parse, :provision, :respond_with,],
            inbound_connection: [:api_key_validator, :basic_auth_validator, :config_schema, :helper,
                                 :oauth2_client_credentials_validator, :setup_info, :validate,],
            outbound_connection: [:api_key_authenticator, :authenticate, :basic_auth_authenticator,
                                  :bearer_authenticator, :config_schema, :config_tester,
                                  :deprovision, :helper, :oauth2_authenticator, :provision,
                                  :setup_info,],
          }.transform_values { |v| v.to_set.freeze }.freeze

          SCALAR_LITERAL_TYPES = [:str, :sym, :int, :float].to_set.freeze

          LITERAL_HANDLERS = {
            array: :literal_array?, hash: :literal_pairs?, dstr: :literal_interpolation?,
            send: :literal_send?,
          }.freeze

          CONST_EXPR_HANDLERS = {
            const: :permitted_const?, regexp: :plain_regexp?, array: :const_expr_array?,
            hash: :const_expr_pairs?, dstr: :const_expr_interpolation?, send: :const_expr_send?,
          }.freeze

          Outcome = Struct.new(:label, :findings, :uncheckable) do
            def checked? = uncheckable.nil?
            def in_shape? = checked? && findings.empty?
          end

          class << self
            def check(source, label = nil)
              new(source, label).check
            end
          end

          def initialize(source, label = nil)
            @source = source
            @label = label
            @findings = []
            @assigned = Set.new
            @assigned_lines = Set.new
          end

          def check
            reason = uncheckable_reason
            return Outcome.new(@label, [], reason) if reason

            # Two different nils: a source the parser rejected, and one it accepted that holds no
            # code. The bound above consults a different parser, which accepts bytes this one
            # refuses, so the distinction has to be made here or a rejected source is reported as
            # holding no definition.
            parsed = RuboCop::AST::ProcessedSource.new(@source, ProcHelper::TARGET_RUBY_VERSION)
            return Outcome.new(@label, [], :unparseable) unless parsed.valid_syntax?

            ast = parsed.ast
            return Outcome.new(@label, [], :no_definition) if ast.nil?

            walk_file(ast)
            Outcome.new(@label, @findings, nil)
          end

          private

          # Only sources that pass basic constraints will be evaluated, only for those a shape check
          # adds value.
          def uncheckable_reason
            return :too_large if @source.bytesize > IPaaS::Connector::Connector::MAX_SOURCE_FILE_BYTES

            ProcHelper.unevaluable_reason(@source)
          end

          def refuse(message)
            @findings << message
            nil
          end

          def walk_file(ast)
            return refuse('holds more than one top-level expression') if ast.begin_type?
            return refuse('does not define a class') unless ast.class_type?

            name, superclass, body = *ast
            return unless walk_class_name(name)
            unless const_path(superclass) == SUPERCLASS_PATH
              return refuse("does not subclass #{SUPERCLASS_PATH.join('::')}")
            end

            walk_class_body(body)
          end

          # The class name binds in the same scope as a class-body constant and reaches as far, so it
          # shadows a permitted root the same way one does.
          def walk_class_name(node)
            return refuse('defines a namespaced class') unless node.const_type? && node.namespace.nil?

            name = node.children[1]
            return true unless ROOT_SEGMENTS.include?(name)

            refuse("names the class '#{name}', which shadows a permitted constant path")
          end

          def walk_class_body(body)
            statements = statements_of(body)
            declaration = statements.select(&:block_type?)
            return refuse('does not hold exactly one connector declaration') unless declaration.one?

            statements.each { |statement| walk_class_body_statement(statement, declaration.first) }
          end

          def walk_class_body_statement(statement, declaration)
            return walk_constant(statement) if statement.casgn_type?
            return walk_connector_declaration(statement) if statement.equal?(declaration)

            refuse("holds #{statement.type} where only constants and the connector declaration are allowed")
          end

          def walk_connector_declaration(node)
            send_node = node.send_node
            unless send_node.receiver.nil? && send_node.method_name == :connector &&
                   send_node.arguments.one? && send_node.arguments.first.str_type?
              return refuse('declares the connector with something other than a single literal uuid')
            end

            walk_structural_block(node, :connector)
          end

          def walk_structural_block(node, position)
            return refuse("#{position} block takes parameters") unless node.arguments.empty?

            statements_of(node.body).each { |statement| walk_statement(statement, position) }
          end

          def walk_statement(statement, position)
            case statement.type
            when :casgn then walk_constant(statement)
            when :send then walk_verb(statement, position)
            when :block then walk_block(statement, position)
            else refuse("holds #{statement.type} in the #{position} block")
            end
          end

          # Arguments are literals only.
          # This is a deliberate conservatism: no known connector needs it.
          # Allowing constants opens up complexity which is not warranted.
          def walk_verb(node, position)
            return refuse("calls a method on a receiver in the #{position} block") unless node.receiver.nil?
            unless VERBS.fetch(position).include?(node.method_name)
              return refuse("uses '#{node.method_name}', which is not part of the #{position} vocabulary")
            end
            unless node.arguments.all? { |argument| literal?(argument) }
              return refuse("passes a non-literal argument to '#{node.method_name}'")
            end

            true
          end

          def walk_block(node, position)
            return unless walk_verb(node.send_node, position)

            name = node.send_node.method_name
            return if PROC_BEARING.include?(name)
            return walk_structural_block(node, name) if POSITIONS.include?(name)

            refuse("opens a block on '#{name}', which is neither an expression nor a structural position")
          end

          def walk_constant(node)
            namespace, name, value = *node
            return refuse('assigns a namespaced constant') unless namespace.nil?
            return refuse("assigns '#{name}', which shadows a permitted constant path") if ROOT_SEGMENTS.include?(name)
            unless @assigned_lines.add?(node.loc.line)
              # freezing the constants needs unique line numbers per constant, we enforce that here
              return refuse("assigns '#{name}' on a line that already assigns a constant")
            end
            return refuse("assigns '#{name}' a value that is not a constant expression") unless const_expr?(value)

            @assigned << name
            true
          end

          def statements_of(node)
            return [] if node.nil?

            node.begin_type? ? node.children : [node]
          end

          # Both predicates dispatch through a closed table: a node type absent from it is refused,
          # so a construct nobody enumerated cannot fall through as permitted.
          def literal?(node)
            return false if node.nil?
            return true if scalar_literal?(node)

            handler = LITERAL_HANDLERS[node.type]
            handler ? send(handler, node) : false
          end

          def const_expr?(node)
            return false if node.nil?
            return true if literal?(node)

            handler = CONST_EXPR_HANDLERS[node.type]
            handler ? send(handler, node) : false
          end

          def scalar_literal?(node)
            SCALAR_LITERAL_TYPES.include?(node.type) ||
              node.true_type? || node.false_type? || node.nil_type?
          end

          def literal_array?(node)
            node.children.all? { |child| literal?(child) }
          end

          def const_expr_array?(node)
            node.children.all? { |child| const_expr?(child) }
          end

          def plain_regexp?(node)
            node.children.all? { |child| child.str_type? || child.regopt_type? }
          end

          def literal_pairs?(node)
            node.children.all? { |pair| pair.pair_type? && literal?(pair.key) && literal?(pair.value) }
          end

          def const_expr_pairs?(node)
            node.children.all? { |pair| pair.pair_type? && const_expr?(pair.key) && const_expr?(pair.value) }
          end

          def literal_interpolation?(node)
            node.children.all? do |child|
              child.str_type? || (child.begin_type? && child.children.all? { |part| literal?(part) })
            end
          end

          def const_expr_interpolation?(node)
            node.children.all? do |child|
              child.str_type? || (child.begin_type? && child.children.all? { |part| const_expr?(part) })
            end
          end

          def literal_send?(node)
            node.arguments.empty? && node.block_node.nil? &&
              permitted_method?(node) && literal?(node.receiver)
          end

          def const_expr_send?(node)
            return false unless node.block_node.nil?
            return repeated_literal?(node) if node.method_name == :*

            node.arguments.empty? && permitted_method?(node) && const_expr_receiver?(node.receiver)
          end

          def permitted_method?(node)
            return true if ANY_RECEIVER_METHODS.include?(node.method_name)

            receivers = TYPED_RECEIVER_METHODS[node.method_name]
            !receivers.nil? && receivers.include?(node.receiver&.type)
          end

          def const_expr_receiver?(node)
            literal?(node) || (node&.dstr_type? && const_expr?(node))
          end

          def repeated_literal?(node)
            node.receiver&.int_type? && node.arguments.one? && node.arguments.first.int_type?
          end

          # Judged on the outermost node of the path: an inner node is a shorter path matching no
          # entry, which would refuse every permitted reference. Dormant today, because every
          # handler passes down a whole sub-expression and the path walk never re-enters here — it
          # goes live if anything visits every `const` node in a subtree, or recurses into one.
          def permitted_const?(node)
            path, absolute = const_path_and_scope(outermost_const(node))
            return false if path.nil?
            # An absolute path resolves at top level whatever this file assigned, so it is only ever
            # a permitted entry — never a local back-reference, however the file shadows the name.
            return PERMITTED_PATHS.include?(path) if absolute
            return @assigned.include?(path.first) if path.one?

            PERMITTED_PATHS.include?(path)
          end

          # Kept apart from the proc rules' copy: this gate runs before any evaluation, and a change to a
          # proc-rule helper must not be able to change what the loader refuses.
          def outermost_const(node)
            node = node.parent while node.parent&.const_type? && node.parent.children.first.equal?(node)
            node
          end

          def const_path(node)
            const_path_and_scope(node).first
          end

          # The path as symbols, root-first, and whether it was written absolutely. A `::`-prefixed
          # path bottoms out in a `cbase` rather than nil and names the same constant, so both forms
          # yield the same path — but the caller has to know which it was.
          def const_path_and_scope(node)
            parts = []
            while node.is_a?(RuboCop::AST::Node) && node.const_type?
              parts.unshift(node.children[1])
              node = node.children.first
            end
            return [nil, false] unless node.nil? || node.cbase_type?

            [parts, !node.nil?]
          end
        end
      end
    end
  end
end

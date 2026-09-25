module IPaaS
  module Connector
    module Common
      module ProcRules
        class ValidConstantsRule < ProcRule
          include ConstPaths

          def self.under(prefix, rows)
            rows.to_h { |path, methods| [prefix + path, methods] }
          end
          private_class_method :under

          CORE = IPaaS.make_shareable({
            [:Time] => [:now, :current, :parse, :at],
            [:DateTime] => [:parse, :current],
            [:Date] => [:parse, :today, :current],
            [:Hash] => [],
            [:Array] => [],
            [:String] => [],
            [:Integer] => [],
            [:Float] => [],
            [:Regexp] => [:last_match],
            [:JSON] => [:parse, :pretty_generate, :[]], # `[]` parses a String, generates anything else
            [:JSON, :ParserError] => [],
            [:URI] => [:parse, :encode_www_form, :join],
            [:URI, :InvalidURIError] => [],
            [:URI, :Error] => [],
            [:URI, :HTTPS] => [],
            [:Base64] => [
              :encode64, :decode64, :strict_encode64, :strict_decode64, :urlsafe_encode64, :urlsafe_decode64,
            ],
            [:SecureRandom] => [:uuid],
            [:Digest, :SHA256] => [:hexdigest, :digest],
            [:OpenSSL] => [:secure_compare],
            [:OpenSSL, :HMAC] => [:hexdigest, :digest],
            [:OpenSSL, :Digest, :SHA256] => [:hexdigest],
            [:StandardError] => [],
            [:ArgumentError] => [],
            [:TypeError] => [],
            [:KeyError] => [],
            [:IndexError] => [],
            [:RuntimeError] => [],
          })

          GEMS = IPaaS.make_shareable({
            [:Rack, :Utils] => [:parse_query],
            [:Rack, :QueryParser, :InvalidParameterError] => [],
            [:ActiveSupport, :SecurityUtils] => [:secure_compare],
          })

          JWT = IPaaS.make_shareable(under([:IPaaS, :Job, :JWT], {
            [] => [:pem_valid?, :jwk_to_pem, :assert_no_oidc_redirect!],
            [:MAX_TOKEN_BYTES] => [],
            [:ASYMMETRIC_JWK_KTYS] => [:include?],
            [:MAX_OIDC_RESPONSE_BYTES] => [],
            [:OIDC_HTTP_OPTS] => [],
            [:SUPPORTED_ALGORITHMS] => [],
          }))

          GRAPHQL = IPaaS.make_shareable(under([:IPaaS, :Job, :GraphQL], {
            [:Schema] => [
              :gql_collect_fields, :gql_find_root_field, :gql_find_type, :gql_list_root_fields,
              :gql_mutation_input_type_name, :gql_resolve_connection_node_type, :gql_resolve_return_type_name,
              :gql_to_ipaas_type, :gql_unwrap_type,
            ],
            [:Schema, :INTROSPECTION_QUERY] => [],
            [:FieldBuilder] => [
              :gql_add_dynamic_fields, :gql_add_dynamic_input_fields, :gql_build_order_subfields,
              :gql_collect_dynamic_descriptors, :gql_restore_fields_from_descriptors, :gql_update_include_fields_input,
            ],
            [:QueryBuilder] => [:gql_build_field_selection, :gql_type_ref_string],
            [:Result] => [:gql_flatten_nodes],
            [:ArtifactCache] => [
              :gql_cache_clear, :gql_cache_read, :gql_cache_write, :gql_clear_schema_error, :gql_invalidate,
              :gql_load_bundle, :gql_read_root_options, :gql_read_schema_error, :gql_schema_error_cause,
              :gql_seed_root_options, :gql_selector_notice, :gql_warm_for_regeneration?, :gql_write_bundle_part,
              :gql_write_root_options, :gql_write_schema_error,
            ],
          }))

          OURS = IPaaS.make_shareable(under([:IPaaS], {
            [:Error] => [],
            [:Encryption, :SecretString] => [],
            [:Connector, :Trigger] => [:trigger_server_url],
            [:Job, :ContentType] => [:detect_content_type],
            [:Job, :DiscardTriggerEvent] => [],
            [:Job, :FailJob] => [],
            [:Job, :RescheduleJob] => [],
            [:Job, :Outbound, :HTTP] => [:create_binary_part, :raw_param_value],
            [:Job, :Outbound, :CustomerCredentialsError] => [],
            [:Job, :Humanize] => [:humanize_field_name],
            [:Job, :CompactHash] => [:compact_hash],
          }).merge(JWT, GRAPHQL))

          # Root-first path => the methods that may be called on it; an empty list permits reading
          # the path and calling nothing on it directly. The groups above exist to be read; every
          # change is a change to this constant.
          ALLOWED_CONSTANTS = IPaaS.make_shareable(CORE.merge(GEMS, OURS))
          private_constant :CORE, :GEMS, :JWT, :GRAPHQL, :OURS

          # `outcome` is :allowed, :owned (the proc's own file assigns it), :gem (the proc is written in
          # this gem) or :refused; `detail` carries the exception when the reason is :error; `expression`
          # is the enclosing expression, which the path and the method between them do not spell.
          ConstantUse = Struct.new(:written, :canonical, :method_name, :outcome, :reason, :detail, :expression,
                                   :line, :column, keyword_init: true)

          REFUSED_PATH = "Access to '%s' is not allowed in expressions; only an approved set of classes is " \
                         'available. Please file a request if access is needed.'.freeze
          REFUSED_METHOD = "Calling '%s' on '%s' is not allowed in expressions; only approved methods of " \
                           'approved classes are available. Please file a request if access is needed.'.freeze
          REFUSED_REOPENING = "Reopening '%s' is not allowed in expressions.".freeze
          REFUSED_RESCUE = "'%s' is not an error class, so it cannot be rescued in expressions.".freeze
          REFUSED_BINDING = "'%s' may only be called, rescued, raised or tested in expressions, not passed on " \
                            'as a value.'.freeze
          # A fault of ours, not a verdict on what the author wrote: the path message would send them
          # looking for a policy that refused nothing.
          REFUSED_ERROR = "'%s' could not be checked in expressions, so it is not available.".freeze

          # Methods that consume a class argument without handing it on; each must be one the method lists
          # permit, and none may be a helper name (`HelpersProxy::RESERVED_NAMES`), or `helpers.raise(Time)`
          # would hand the class to the author's own block.
          READ_METHODS = [:raise, :is_a?, :kind_of?, :instance_of?].freeze

          # Pattern-only node types whose every const-bearing child is itself a pattern, so a class
          # under one needs no position. Pattern-only is not the test: `if_guard` and `pin` qualify
          # and are absent, holding an evaluated expression. `pair` a hash literal builds too.
          PATTERN_NODES = [:array_pattern, :array_pattern_with_tail, :find_pattern, :const_pattern,
                           :match_alt, :match_as,].freeze

          class Refusal < StandardError
            attr_reader :reason

            def initialize(reason)
              super(reason.to_s)
              @reason = reason
            end
          end

          class << self
            # The modules a connector body may alias, resolved once on first use: this file loads
            # before the modules it names, so they cannot be resolved while it is being defined.
            def permitted_modules
              @permitted_modules ||= IPaaS.make_shareable(
                LoadRules::ConnectorShape::PERMITTED_PATHS.each_with_object({}.compare_by_identity) do |path, modules|
                  modules[resolve_from_object(path)] = path
                end,
              )
            end

            # Segment by segment without inheritance: a multi-segment lookup would resolve a bogus
            # path such as `IPaaS::Job::JSON` to `::JSON` through `Object`.
            def resolve_from_object(path)
              path.inject(Object) { |scope, segment| const_in(scope, segment) }
            end

            # Module's own lookups, so a singleton override on the judged module answers neither.
            def const_in(mod, name)
              ::Module.instance_method(:const_get).bind_call(mod, name, false)
            end

            def const_defined_at(mod, name)
              ::Module.instance_method(:const_source_location).bind_call(mod, name, false)&.first
            end
          end

          attr_writer :on_use

          def initialize(context, on_invalid: nil, procedure: nil, on_use: nil)
            super(context, on_invalid: on_invalid)
            @procedure = procedure
            @on_use = on_use
            @judged = {}.compare_by_identity
            @reported = []
          end

          def on_const(node)
            outer = outermost_const(node)
            return unless outer.equal?(node) && @judged[node].nil?

            @judged[node] = true
            judge(node)
          end

          private

          def judge(node)
            path, absolute = const_path_and_scope(node)
            expression = (node.parent || node).source
            dispatched_methods(node).each do |method_name|
              judge_dispatch(node, method_name, path, absolute, expression)
            end
          end

          def judge_dispatch(node, method_name, path, absolute, expression)
            use = ConstantUse.new(written: path || [node.children[1]], method_name: method_name,
                                  expression: expression, line: node.loc.line, column: node.loc.column)
            decide(use) do
              raise Refusal, :reopened if reopened?(node)
              raise Refusal, :scope if path.nil?

              permit(use, absolute, node)
            end
            @on_use&.call(use)
          end

          def decide(use)
            yield
          rescue Refusal => e
            refuse(use, e.reason)
          rescue StandardError => e
            refuse(use, :error, "#{e.class}: #{e.message}")
          end

          # A shorthand assignment calls the writer as well, and the AST spells only the reader it
          # expands from, so the path is judged for both.
          def dispatched_methods(node)
            method_name = called_method(node)
            return [method_name] unless method_name && shorthand_assigned?(node.parent)

            [method_name, :"#{method_name}="]
          end

          def shorthand_assigned?(call)
            call.parent&.shorthand_asgn? && call.parent.children[0].equal?(call)
          end

          def called_method(node)
            parent = node.parent
            return nil unless [:send, :csend].include?(parent&.type) && parent.children[0].equal?(node)

            parent.children[1]
          end

          def permit(use, absolute, node)
            return use.outcome = :gem if gem_file?

            owner = absolute ? nil : owner_of(use.written.first)
            return permit_listed(use, use.written, node) if owner.nil?

            value, rest = resolve_owned(owner, use.written)
            return permit_owned_module(use, value, rest, node) if ::Module === value # rubocop:disable Style/CaseEquality

            raise Refusal, :path unless rest.empty?

            refuse_unrescuable(nil, node)
            use.outcome = :owned
          end

          def permit_listed(use, canonical, node)
            use.canonical = canonical
            methods = ALLOWED_CONSTANTS[canonical]
            raise Refusal, :path if methods.nil?

            refuse_unrescuable(canonical, node)

            if use.method_name
              raise Refusal, :method unless methods.include?(use.method_name)
            elsif class_path?(canonical) && !consumed_in_place?(node)
              raise Refusal, :bound
            end

            use.outcome = :allowed
          end

          # A value constant may be read anywhere; a class only where the construct consumes it.
          def class_path?(canonical)
            ::Module === self.class.resolve_from_object(canonical) # rubocop:disable Style/CaseEquality
          end

          # The exception list of a rescue, the condition of a `when`, a pattern, or an argument to a
          # method that tests or raises it — never a body.
          def consumed_in_place?(node)
            parent = node.parent
            case parent&.type
            when :when then !parent.children.last.equal?(node)
            when :array then rescued_list?(parent)
            when :send, :csend then READ_METHODS.include?(parent.children[1])
            else matched_in_pattern?(node, parent)
            end
          end

          # A deadline interrupt is not a StandardError, so only a StandardError class may be rescued. A
          # non-class clause is worse than a wrong one: Ruby answers it with a TypeError, which an outer
          # StandardError rescue catches, swallowing the interrupt that reached the clause.
          def refuse_unrescuable(canonical, node)
            raise Refusal, :rescued if rescued?(node) && !(canonical && error_class?(canonical))
          end

          def error_class?(canonical)
            value = self.class.resolve_from_object(canonical)
            ::Class === value && ::Module.instance_method(:<=).bind_call(value, ::StandardError) == true # rubocop:disable Style/CaseEquality
          end

          def rescued?(node)
            node.parent&.type == :array && rescued_list?(node.parent)
          end

          def rescued_list?(array)
            array.parent&.type == :resbody && array.parent.children[0].equal?(array)
          end

          # The position test is inverted between the two families: in `Array => a` the class is the
          # operand being bound rather than the pattern, so accepting the first child there would
          # hand it to the author. `in_pattern` is `[pattern, guard, body]`; the guard is refused by
          # its own `if_guard` node, and naming the first child states that rather than relying on it.
          def matched_in_pattern?(node, parent)
            case parent&.type
            when :in_pattern then parent.children.first.equal?(node)
            when :match_pattern, :match_pattern_p then parent.children.last.equal?(node)
            when :pair then parent.parent&.type == :hash_pattern
            else PATTERN_NODES.include?(parent&.type)
            end
          end

          def permit_owned_module(use, value, rest, node)
            path = self.class.permitted_modules[value]
            raise Refusal, :path if path.nil?

            permit_listed(use, path + rest, node)
          end

          def resolve_owned(owner, written)
            value = self.class.const_in(owner, written.first)
            rest = written.drop(1)
            while nesting.any? { |m| m.equal?(value) }
              raise Refusal, :path if rest.empty?

              segment = rest.first
              raise Refusal, :path unless defined_in_own_file?(value, segment)

              value = self.class.const_in(value, segment)
              rest = rest.drop(1)
            end
            [value, rest]
          end

          # A connector file evaluated at the top level defines its class on Object, so Object is the
          # last place a root can be owned.
          def owner_of(root)
            (nesting + [::Object]).find { |m| defined_in_own_file?(m, root) }
          end

          # Owned means assigned in the proc's own file: the nesting also holds whatever evaluated
          # that file, whose constants the author did not write.
          def defined_in_own_file?(mod, name)
            file = own_file
            return false if file.nil?

            self.class.const_defined_at(mod, name) == file
          end

          def own_file
            return nil if @procedure.is_a?(String) || @procedure.nil?

            @procedure.source_location&.first
          end

          # A block the DSL hands over at load from one of this gem's own files is ours. The one gem
          # file an author's code is evaluated in is where String procs run, so it does not count.
          def gem_file?
            return @gem_file if defined?(@gem_file)

            file = own_file
            @gem_file = file != ProcHelper::STRING_PROC_FILE && ProcHelper.gem_file?(file)
          end

          # A String proc and a proc without a binding own nothing: neither has a lexical scope.
          def nesting
            return @nesting if defined?(@nesting)

            @nesting = own_file.nil? ? [] : @procedure.binding.eval('::Module.nesting')
          rescue ArgumentError
            @nesting = []
          end

          def refuse(use, reason, detail = nil)
            use.outcome = :refused
            use.reason = reason
            use.detail = detail
            report(message_for(use))
          end

          def message_for(use)
            name = use.written.join('::')
            case use.reason
            when :method then format(REFUSED_METHOD, use.method_name, name)
            when :reopened then format(REFUSED_REOPENING, name)
            when :rescued then format(REFUSED_RESCUE, name)
            when :bound then format(REFUSED_BINDING, name)
            when :error then format(REFUSED_ERROR, name)
            else format(REFUSED_PATH, name)
            end
          end

          def report(message)
            return if @reported.include?(message)

            @reported << message
            on_invalid&.call(message)
          end
        end
      end
    end
  end
end

module IPaaS
  module Connector
    module Common
      module ProcRules
        class ValidMethodsRule < ProcRule
          BASE_METHODS = [
            :lambda,
            :call,
            :class,
            :raise,
            :blank?,
            :empty?,
            :nil?,
            :present?,
            :presence,
            :tap,
            :itself,
            :is_a?,
            :kind_of?,
            :instance_of?,
            :to_json,
            :pretty_generate,
            :Float,
          ].freeze

          DEBUG_METHODS = [
            :puts,
            :object_id,
            :foo,
            :foo_tester,
            :caller,
          ].freeze

          COMPARISON_METHODS = [
            :!,
            :<,
            :<=,
            :>,
            :>=,
            :==,
            :!=,
          ].freeze

          STRING_METHODS = [
            :split,
            :gsub,
            :tr,
            :contains,
            :starts_with?,
            :start_with?,
            :ends_with?,
            :end_with?,
            :index,
            :rindex,
            :reverse,
            :center,
            :ljust,
            :lstrip,
            :lstrip!,
            :rjust,
            :rstrip,
            :rstrip!,
            :strip,
            :strip!,
            :to_f,
            :to_i,
            :match,
            :to_sym,
            :downcase,
            :downcase!,
            :upcase,
            :upcase!,
            :titleize,
            :camelcase,
            :underscore,
            :capitalize,
            :capitalize!,
            :swapcase,
            :swapcase!,
            :match?,
            :sub,
            :strftime,
            :captures,
            :last_match,
            :bytesize,
            :chomp,
          ].freeze

          NUMBER_METHODS = [
            :+,
            :-,
            :/,
            :%,
            :*,
            :**,
            :to_s,
            :times,
            :byte,
            :bytes,
            :day,
            :days,
            :exabyte,
            :exabytes,
            :fortnight,
            :fortnights,
            :gigabyte,
            :gigabytes,
            :hour,
            :hours,
            :kilobyte,
            :kilobytes,
            :megabyte,
            :megabytes,
            :minute,
            :minutes,
            :petabyte,
            :petabytes,
            :second,
            :seconds,
            :terabyte,
            :terabytes,
            :week,
            :weeks,
            :zettabyte,
            :zettabytes,
            :number_to_human_size,
            :ceil,
            :abs,
          ].freeze

          HASH_METHODS = [
            :[],
            :[]=,
            :dig,
            :drill,
            :fetch,
            :key?,
            :delete,
            :except,
            :except!,
            :reduce,
            :clear,
            :clear!,
            :merge,
            :merge!,
            :slice,
            :slice!,
            :to_a,
            :with_indifferent_access,
            :keys,
            :values,
            :each_value,
            :transform_keys,
            :transform_values,
            :deep_dup,
          ].freeze

          ARRAY_METHODS = [
            :Array,
            :[],
            :<<,
            :|,
            :push,
            :length,
            :size,
            :first,
            :last,
            :include?,
            :exclude?,
            :each,
            :each_with_object,
            :join,
            :all?,
            :uniq,
            :uniq!,
            :map,
            :flat_map,
            :pluck,
            :pick,
            :detect,
            :reject,
            :select,
            :sum,
            :min,
            :max,
            :clear,
            :any?,
            :none?,
            :with_index,
            :each_slice,
            :zip,
            :fill,
            :find_index,
            :each_with_index,
            :compact,
            :compact_blank,
            :flatten,
            :index_by,
            :to_h,
            :group_by,
            :filter_map,
            :sort,
            :sort_by,
            :take,
            :filter,
            :to_set,
          ].freeze

          BASE64_METHODS = [
            :encode64,
            :strict_encode64,
            :urlsafe_encode64,
            :decode64,
            :strict_decode64,
            :urlsafe_decode64,
          ].freeze

          TIME_METHODS = [
            :now,
            :current,
            :today,
            :date,
            :utc,
            :getutc,
            :in_time_zone,
            :to_date,
            :to_datetime,
            :to_fs,
            :iso8601,
            :rfc3339,
            :zone,
            :'zone=',
            :ago,
            :since,
            :from_now,
            :at,
            :year,
            :month,
            :mday,
            :wday,
            :yday,
            :sec,
            :today?,
            :monday?,
            :tuesday?,
            :wednesday?,
            :thursday?,
            :friday?,
            :saturday?,
            :sunday?,
            :beginning_of_day,
            :end_of_day,
            :beginning_of_week,
            :end_of_week,
            :beginning_of_month,
            :end_of_month,
            :beginning_of_year,
            :end_of_year,
            :noon,
            :change,
            :in_seconds,
            :in_minutes,
            :in_hours,
            :in_days,
            :in_weeks,
            :in_months,
            :in_years,
          ].freeze

          URI_METHODS = [
            :scheme,
            :host,
            :port,
            :default_port,
            :userinfo,
            :request_uri,
            :encode_www_form,
            :parse_query,
            :query,
            :url,
          ].freeze

          CRYPTO_METHODS = [
            :digest,
            :hexdigest,
            :secure_compare,
          ].freeze

          ERROR_METHODS = [
            :message,
          ].freeze

          XML_METHODS = [
            :text,
            :at_xpath,
          ].freeze

          RUBY_METHODS = Set.new(
            BASE_METHODS + COMPARISON_METHODS + BASE64_METHODS + TIME_METHODS +
            STRING_METHODS + NUMBER_METHODS + HASH_METHODS + ARRAY_METHODS + URI_METHODS +
            CRYPTO_METHODS + ERROR_METHODS + XML_METHODS
          ).freeze

          DEBUG_METHODS_SET = Set.new(DEBUG_METHODS).freeze

          # Methods without a clear owning module (Faraday HTTP attributes, generic DSL keywords, etc.).
          # Most iPaaS methods are registered via ProcSafe in the modules that define them.
          ADDITIONAL_METHODS = Set.new([
            :authenticate,
            :authenticators,
            :body,
            :config,
            :'body=',
            :headers,
            :'headers=',
            :id,
            :'id=',
            :module,
            :name,
            :params,
            :'params=',
            :path,
            :'path=', # URI::Generic#path, appended to when a connector builds a sub-path
            :property,
            :request,
            :run,
            :runbooks,
            :status,
            :template,
            :to_hash,
            :url_for,
            :setup_info,
            :validate,
            :validators,
            :value,
          ]).freeze

          # Methods dispatching a *positional* symbol as a method name; extend when allowlisting
          # another. The block-pass channel needs no list: validate_block_pass_symbols covers every method.
          REFLECTIVE_METHODS = Set[:reduce, :inject].freeze

          CLASS_CALL_MESSAGE = "'.class' is only allowed to get the class name.".freeze

          TO_JSON_MESSAGE = "'to_json' takes no arguments and cannot be passed as a symbol.".freeze

          SOLUTION_METHODS = Set[:create_schedule!, :name, :runbooks, :soft_delete_schedule, :uuid].freeze
          SOLUTION_CONTEXTS = [:receiver, :stringified].freeze
          ASSIGNMENT_NODES = [:op_asgn, :or_asgn, :and_asgn].freeze
          SOLUTION_CALL_MESSAGE = "'solution' may only be used to call #{SOLUTION_METHODS.sort.join(', ')}.".freeze

          class << self
            def solution_call_permitted?(node)
              context, method_name, holder, through_block = ClassCallContext.of(node)
              return false if through_block || !SOLUTION_CONTEXTS.include?(context)
              return false unless SOLUTION_METHODS.include?(method_name)

              !assignment_target?(holder)
            end

            # The first send off a receiverless `helpers`, with no arguments; its allowlist is skipped
            # because the names are connector-defined. Shared with the proc_scan census.
            def top_level_helper?(node)
              node&.type == :send && node.children == [nil, :helpers]
            end

            private

            def assignment_target?(holder)
              parent = holder.parent
              ASSIGNMENT_NODES.include?(parent&.type) && parent.children.first.equal?(holder)
            end
          end

          attr_writer :on_class_call, :on_solution_call

          def initialize(...)
            super
            @reported_methods = []
            @reflective_reported = []
            @block_pass_reported = false
            @class_call_reported = false
            @to_json_reported = false
            @solution_call_reported = false
          end

          def on_send(node)
            parent, method_name, *params = *node

            notify_observers(node, method_name)
            validate_block_pass_symbols(params)
            validate_reflective_dispatch(node, method_name, params) if REFLECTIVE_METHODS.include?(method_name)

            # helpers.<anything> is accepted when called from the top level
            return if top_level_helper?(parent)

            validate_named_call(node, method_name, params)
          end

          def notify_observers(node, method_name)
            @on_class_call&.call(node) if method_name == :class
            @on_solution_call&.call(node) if method_name == :solution
          end

          def validate_named_call(node, method_name, params)
            validate_to_json_call(node, params) if method_name == :to_json
            validate_class_call(node) if method_name == :class
            return validate_solution_call(node) if method_name == :solution

            validate_method(method_name)
          end
          alias on_csend on_send

          # Judges an op-assign as the explicit expansion it stands for: the operator it dispatches,
          # and the setter, which the child `send` names as the reader it expands from.
          def on_op_asgn(node)
            target = node.children[0]

            validate_method(node.children[1]) if node.op_asgn_type?

            return unless target.call_type?
            return if top_level_helper?(target.children.first)

            validate_method(:"#{target.method_name}=")
          end
          # `||=`/`&&=` dispatch no operator; their second child is the value, not a method name.
          # These must not call `super`: it resolves by the defining name, so an `or_asgn` would
          # reach `Traversal#on_op_asgn` and raise past `valid?`, which rescues only SystemStackError.
          alias on_or_asgn on_op_asgn
          alias on_and_asgn on_op_asgn

          def validate_method(method_name)
            return if RUBY_METHODS.include?(method_name)
            return if ADDITIONAL_METHODS.include?(method_name)
            return if ProcSafe.registry.include?(method_name)
            return if IPaaS.env != 'production' && DEBUG_METHODS_SET.include?(method_name)
            return if @reported_methods.include?(method_name)

            @reported_methods << method_name
            on_invalid.call("Method '#{method_name}' not allowed.")
          end

          private

          def validate_block_pass_symbols(params)
            params.select { |param| param.type == :block_pass }.each { |block_pass| validate_block_pass(block_pass) }
          end

          def validate_block_pass(block_pass)
            child = block_pass.children.first
            return report_unreadable_block_pass unless child&.type == :sym

            symbol = child.children.first
            if symbol == :class
              @on_class_call&.call(block_pass)
              validate_class_call(block_pass)
            end
            @on_solution_call&.call(block_pass) if symbol == :solution
            validate_dispatched_method(symbol)
          end

          def validate_class_call(node)
            return if @class_call_reported || ClassCallContext.permitted?(node)

            @class_call_reported = true
            on_invalid.call(CLASS_CALL_MESSAGE)
          end

          def validate_solution_call(node)
            return if @solution_call_reported || self.class.solution_call_permitted?(node)

            report_solution_dispatch
          end

          # Refuses `:solution` dispatched as a symbol (&:solution, reduce(:solution)) by name, so a
          # future `proc_safe :solution` cannot reopen the record through the block-pass or reflective
          # channel, the way to_json is refused.
          def report_solution_dispatch
            return if @solution_call_reported

            @solution_call_reported = true
            on_invalid.call(SOLUTION_CALL_MESSAGE)
          end

          def report_unreadable_block_pass
            return if @block_pass_reported

            @block_pass_reported = true
            on_invalid.call('Block argument must be a literal symbol.')
          end

          def validate_reflective_dispatch(node, method_name, params)
            arguments = params.reject { |param| param.type == :block_pass }
            return if arguments.empty?
            return report_reflective_dispatch(method_name) if splatted?(arguments)

            last_argument = arguments.last
            return validate_reflective_symbol(last_argument) if last_argument.type == :sym
            return if seed_form?(arguments, node, params)

            report_reflective_dispatch(method_name)
          end

          def validate_reflective_symbol(symbol_node)
            @on_solution_call&.call(symbol_node) if symbol_node.children.first == :solution
            validate_dispatched_method(symbol_node.children.first)
          end

          def splatted?(arguments)
            arguments.any? { |argument| argument.type == :splat }
          end

          # Ruby reads a lone argument as the seed whenever a block follows, literal or block-pass;
          # only at two arguments does it dispatch a positional symbol as a method name.
          def seed_form?(arguments, node, params)
            arguments.one? && (node.block_node || params.any? { |param| param.type == :block_pass })
          end

          def validate_dispatched_method(method_name)
            return report_to_json if method_name == :to_json
            return report_solution_dispatch if method_name == :solution

            validate_method(method_name)
          end

          def validate_to_json_call(node, params)
            report_to_json if params.any? || node.block_node
          end

          def report_to_json
            return if @to_json_reported

            @to_json_reported = true
            on_invalid.call(TO_JSON_MESSAGE)
          end

          def report_reflective_dispatch(method_name)
            return if @reflective_reported.include?(method_name)

            @reflective_reported << method_name
            on_invalid.call("Method name argument to '#{method_name}' must be a literal symbol.")
          end

          def top_level_helper?(parent)
            self.class.top_level_helper?(parent)
          end
        end
      end
    end
  end
end

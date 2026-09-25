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
            :solution,
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

          def initialize(...)
            super
            @reported_methods = []
            @reflective_reported = []
            @block_pass_reported = false
          end

          def on_send(node)
            parent, method_name, *params = *node

            validate_block_pass_symbols(params)
            validate_reflective_dispatch(node, method_name, params) if REFLECTIVE_METHODS.include?(method_name)

            # helpers.<anything> is accepted when called from the top level
            return if top_level_helper?(parent)

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
            params.select { |param| param.type == :block_pass }.map { |n| n.children.first }.each do |child|
              next validate_method(child.children.first) if child&.type == :sym

              report_unreadable_block_pass
            end
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
            return validate_method(last_argument.children.first) if last_argument.type == :sym
            return if seed_form?(arguments, node, params)

            report_reflective_dispatch(method_name)
          end

          def splatted?(arguments)
            arguments.any? { |argument| argument.type == :splat }
          end

          # Ruby reads a lone argument as the seed whenever a block follows, literal or block-pass;
          # only at two arguments does it dispatch a positional symbol as a method name.
          def seed_form?(arguments, node, params)
            arguments.one? && (node.block_node || params.any? { |param| param.type == :block_pass })
          end

          def report_reflective_dispatch(method_name)
            return if @reflective_reported.include?(method_name)

            @reflective_reported << method_name
            on_invalid.call("Method name argument to '#{method_name}' must be a literal symbol.")
          end

          def top_level_helper?(parent)
            parent&.type == :send && parent&.children == [nil, :helpers]
          end
        end
      end
    end
  end
end

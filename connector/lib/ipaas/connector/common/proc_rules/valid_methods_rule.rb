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
            :do,
            :id,
            :test,
            :blank?,
            :empty?,
            :nil?,
            :present?,
            :presence,
            :tap,
            :itself,
            :is_a?,
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
            :ˆ,
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
            :utc,
            :to_datetime,
            :iso8601,
            :zone,
            :'zone=',
            :ago,
            :at,
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
            :property,
            :request,
            :run,
            :runbooks,
            :solution,
            :status,
            :template,
            :to_hash,
            :url_for,
            :validate,
            :validators,
            :value,
          ]).freeze

          def initialize(...)
            super
            @reported_methods = []
          end

          def on_send(node)
            parent, method_name, *params = *node

            # block-pass with symbol are also method calls like `[].each(&:foo)`
            params.select { |param| param.type == :block_pass }.map { |n| n.children.first }.each do |child|
              validate_method(child.children.first) if child.type == :sym
            end

            # helpers.<anything> is accepted when called from the top level
            return if top_level_helper?(parent)

            validate_method(method_name)
          end
          alias on_csend on_send

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

          def top_level_helper?(parent)
            parent&.type == :send && parent&.children == [nil, :helpers]
          end
        end
      end
    end
  end
end

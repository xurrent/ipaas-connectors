require 'delegate'
require 'json'
require 'singleton'
require 'forwardable'
require 'base64'
require 'active_support/all'

require 'active_model'
require 'cgi'
require 'rubocop'
require 'rack'
require 'faraday'
require 'faraday/multipart'
require 'fileutils'
require 'jwt'
require 'method_source'

module IPaaS
  class Error < StandardError
  end

  class << self
    def env
      ENV['IPAAS_ENV'] || 'production'
    end

    def solution_directory
      if const_defined?(:Rails) && const_defined?(:ENVx) && Rails.root
        return @solution_directory if @solution_directory

        @solution_directory = Rails.root.join(ENVx.SOLUTION_DATA_DIR).to_s
      end
      'tmp/solutions'
    end

    # Where a component logs when nothing more specific is configured: the host's logger when
    # there is one, a file under test so log output stays out of the spec results, stdout
    # otherwise. Callers wanting a request-scoped sink resolve that themselves first.
    def default_logger
      return Rails.logger if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      @default_logger ||= env == 'test' ? test_logger : Logger.new($stdout)
    end

    # Deeply immutable, for a constant whose value is shared for the life of the process and so
    # must not be modifiable by anything that runs later. Raises on a value it cannot make
    # immutable, such as a lock, or a proc whose self or captured objects are not shareable.
    # All procs it accepts are isolated but it does not freeze them, so those still need freezing before passing.
    # @param value [Object] the value a constant is about to be bound to (any contained procs should already be frozen)
    # @return [Object] that same value, made deeply immutable
    def make_shareable(value)
      Ractor.make_shareable(value)
    end

    private

    def test_logger
      FileUtils.mkdir_p('log')
      Logger.new('log/test.log')
    end
  end
end

require 'ipaas/connector/common/proc_rules/proc_safe'
require 'ipaas/connector/core_ext/drill'
require 'ipaas/connector/core_ext/method_source_patch'
require 'ipaas/connector/dsl/boolean'
require 'ipaas/connector/dsl/attr_accessor_mixin'
require 'ipaas/connector/dsl/attribute_mixin'
require 'ipaas/connector/dsl/schema_mixin'
require 'ipaas/connector/dsl/function_mixin'
require 'ipaas/connector/dsl/helpers_mixin'
require 'ipaas/connector/common/resolve_scope'
require 'ipaas/connector/common/model'
require 'ipaas/connector/common/uuid_mixin'
require 'ipaas/connector/common/source_lines'
require 'ipaas/connector/common/solution_file_cache'
require 'ipaas/connector/common/yaml_limits'
require 'ipaas/connector/common/proc_rules/proc_rule'
require 'ipaas/connector/common/proc_rules/const_paths'
require 'ipaas/connector/common/proc_rules/no_const_def_rule'
require 'ipaas/connector/common/proc_rules/no_shared_variable_access_rule'
require 'ipaas/connector/common/proc_rules/no_method_def_rule'
require 'ipaas/connector/common/proc_rules/no_safe_present_rule'
require 'ipaas/connector/common/proc_rules/no_exec_rule'
require 'ipaas/connector/common/proc_rules/no_rescue_exception_rule'
require 'ipaas/connector/common/proc_rules/valid_methods_rule'
require 'ipaas/connector/common/proc_rules/valid_constants_rule'
require 'ipaas/connector/common/proc_rules/node_validator'
require 'ipaas/connector/common/load_rules/connector_shape'
require 'ipaas/connector/common/source_parser'
require 'ipaas/connector/common/proc_container'
require 'ipaas/connector/common/proc_helper'
require 'ipaas/connector/common/helpers'
require 'ipaas/connector/common/helpers_proxy'
require 'ipaas/connector/common/unresolved_node'
require 'ipaas/encryption/secret_string' # Serializer permits it, so it must load first
require 'ipaas/connector/common/serializer'
require 'ipaas/connector/types'
require 'ipaas/connector/types/any_type'
require 'ipaas/connector/types/string_type'
require 'ipaas/connector/types/binary_type'
require 'ipaas/connector/types/base64_type'
require 'ipaas/connector/types/integer_type'
require 'ipaas/connector/types/float_type'
require 'ipaas/connector/types/boolean_type'
require 'ipaas/connector/types/hash_type'
require 'ipaas/connector/types/uri_type'
require 'ipaas/connector/types/time_zone_type'
require 'ipaas/connector/types/date_type'
require 'ipaas/connector/types/time_type'
require 'ipaas/connector/types/time_of_day_type'
require 'ipaas/connector/types/date_time_type'
require 'ipaas/connector/types/regexp_type'
require 'ipaas/connector/types/nested_type'
require 'ipaas/connector/types/recurrence_type'
require 'ipaas/connector/types/ruby_type'
require 'ipaas/connector/types/runbook_type'
require 'ipaas/connector/types/runbook_variable_type'
require 'ipaas/connector/types/schema_field_type'
require 'ipaas/connector/types/secret_string_type'
require 'ipaas/connector/types/hashed_credential_type'
require 'ipaas/connector/schema/field'
require 'ipaas/connector/schema/extension'
require 'ipaas/connector/schema/structure_inferrer'
require 'ipaas/connector/schema/field_builder'
require 'ipaas/connector/schema/dsl_builder'
require 'ipaas/connector/schema/generator'
require 'ipaas/connector/schema/connector_generator'
require 'ipaas/job/helpers'
require 'ipaas/job/context'
require 'ipaas/job/csv'
require 'ipaas/job/delegation/inbound_connection_ref'
require 'ipaas/job/delegation/outbound_connection_ref'
require 'ipaas/job/delegation/trigger_ref'
require 'ipaas/job/delegation/action_ref'
require 'ipaas/job/delegation/helpers_ref'
require 'ipaas/job/outbound/faraday_connection_extension'
require 'ipaas/job/outbound/logging_middleware'
require 'ipaas/job/outbound/selective_params_encoder'
require 'ipaas/job/outbound/http'
require 'ipaas/job/outbound/xml'
require 'ipaas/job/outbound/json_response'
require 'ipaas/job/outbound/backoff'
require 'ipaas/job/outbound/xurrent_rate_limits'
require 'ipaas/job/outbound/scheduler'
require 'ipaas/job/store'
require 'ipaas/job/basic_auth'
require 'ipaas/job/cache'
require 'ipaas/job/jwt'
require 'ipaas/job/humanize'
require 'ipaas/job/compact_hash'
require 'ipaas/job/content_type'
require 'ipaas/job/graphql'
require 'ipaas/job/ruby'
require 'ipaas/job/memory_store'
require 'ipaas/job/memory_locker'
require 'ipaas/job/lock'
require 'ipaas/job/blueprint_store'
require 'ipaas/job/encryption'
require 'ipaas/job/environment'
require 'ipaas/job/outbound/customer_credentials_error'
require 'ipaas/job/outbound/o_auth2'
require 'ipaas/job/outbound/aws_sig_v4'
require 'ipaas/job/psa_auth'
require 'ipaas/job/inbound_oauth2_client_credentials'

require 'ipaas/connector/authentication/inbound'
require 'ipaas/connector/authentication/inbound/api_key'
require 'ipaas/connector/authentication/inbound/basic_auth'
require 'ipaas/connector/authentication/inbound/oauth2_client_credentials/connection_token'
require 'ipaas/connector/authentication/inbound/oauth2_client_credentials/verifier'
require 'ipaas/connector/authentication/inbound/oauth2_client_credentials'
require 'ipaas/connector/authentication/outbound'
require 'ipaas/connector/authentication/outbound/proxy_server'
require 'ipaas/connector/authentication/outbound/api_key'
require 'ipaas/connector/authentication/outbound/basic_auth'
require 'ipaas/connector/authentication/outbound/bearer_token'
require 'ipaas/connector/authentication/outbound/o_auth2'
require 'ipaas/connector/schema'

require 'ipaas/connector/inbound_connection_template'
require 'ipaas/connector/outbound_connection_template'
require 'ipaas/connector/trigger_template'
require 'ipaas/connector/action_template'
require 'ipaas/connector/connector'
require 'ipaas/connector/definition'
require 'ipaas/connector/mapping/field_mapping'
require 'ipaas/connector/mapping/schema_name_mapping'
require 'ipaas/connector/mapping/resolved_mapping'

require 'ipaas/connector/connection'
require 'ipaas/connector/trigger'
require 'ipaas/connector/action'
require 'ipaas/connector/runbook'
require 'ipaas/connector/runbook_variable'
require 'ipaas/connector/environment_variable'

require 'ipaas/test_case/expectation_result'
require 'ipaas/test_case/expectation'
require 'ipaas/test_case/expected_output'
require 'ipaas/test_case/mocked_output'
require 'ipaas/test_case/action_iteration'
require 'ipaas/test_case/action'
require 'ipaas/test_case/trigger'
require 'ipaas/test_case/test_case'
require 'ipaas/test_case/matchers/contains_matcher'
require 'ipaas/test_case/matchers/ends_with_matcher'
require 'ipaas/test_case/matchers/equals_matcher'
require 'ipaas/test_case/matchers/includes_matcher'
require 'ipaas/test_case/matchers/is_present_matcher'
require 'ipaas/test_case/matchers/starts_with_matcher'

require 'ipaas/encryption/cipher'
require 'ipaas/encryption/crypto_key'
require 'ipaas/encryption/data_row_record'
require 'ipaas/encryption/encryptor'
require 'ipaas/encryption/errors'
require 'ipaas/encryption/hashed_credential'
require 'ipaas/encryption/intermediate_key_provider'
require 'ipaas/encryption/system_key_provider'
require 'ipaas/encryption/stored_crypto_key'
require 'ipaas/encryption/test_key_provider'
require 'ipaas/encryption/test_kms'

class RubyConnector < IPaaS::Connector::Definition
  connector '1c9d09fa-cc75-4383-9f9f-be59761daadf' do
    name 'Ruby'
    avatar '/assets/icons/gem.svg'
    description <<~END_OF_DESCRIPTION
      ## Overview
      Runs a user-supplied Ruby script inside a sandbox. The script is validated against an allowlist of methods before execution. This connector does **not** execute arbitrary Ruby, and `eval`, `system`, `exec`, `require`, `instance_eval`, direct instance / global variables, and method / constant definitions are all rejected. Use it for in-runbook data transformation, validation, and small computations that don't justify a dedicated connector.

      ## Prerequisites
      - Familiarity with Ruby syntax and with the allowed methods listed under the **Evaluate Ruby Code** action.
      - Knowledge of the [Ruby 3.4 standard library](https://docs.ruby-lang.org/en/3.4/) and the [ActiveSupport 8.1 core extensions](https://guides.rubyonrails.org/v8.1/active_support_core_extensions.html) the allowlist draws from.

      ## Authentication
      None. This connector runs entirely in-process and requires no credentials.

      ## Triggers
      None. This connector is outbound only.

      ## Actions

      ### Evaluate Ruby Code
      Runs a Ruby script with caller-defined input and output schemas. Values assigned to `output[:field]` inside the script are returned under `results`.

      **Use case**: reshape data between actions, derive computed fields, validate an invariant and fail the job on breach, format timestamps or sizes, or decrypt secret inputs before passing them to a later step.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |-----------|------|----------|---------|-------------|
      | input_schema | SchemaField[] | No | `[]` | Field definitions for the script's inputs. Each entry has `id`, `label`, `type` (`string`, `integer`, `secret_string`, …), `required` |
      | output_schema | SchemaField[] | No | `[]` | Field definitions for the values returned under `results`. The runtime validates types and required fields after execution |
      | input | Nested | Conditional | n/a | Values that match `input_schema`. Required when any `input_schema` entry has `required: true` |
      | proc | Ruby | Yes | n/a | Ruby script to execute. Access inputs via `input[:key]` (or `input['key']`) and return data via `output[:key] = value` |

      #### Example Input

      ```json
      {
        "input_schema": [
          { "id": "i", "label": "Number", "type": "integer", "required": true },
          { "id": "a", "label": "First string", "type": "string", "required": true },
          { "id": "b", "label": "Second string", "type": "string", "required": true }
        ],
        "output_schema": [
          { "id": "greeting", "label": "Greeting", "type": "string", "required": true }
        ],
        "input": { "i": 4, "a": "hello", "b": "world" },
        "proc": "if input['i'] > 3\n  output['greeting'] = input['a'] + ' moon'\nelse\n  output['greeting'] = 'bye ' + input['b']\nend"
      }
      ```

      #### Output

      | Field Name | Type | Description |
      |---|---|---|
      | `results` | Nested | Hash populated by the script. See **Results object fields** below |

      ##### Results object fields
      Fields are defined by `output_schema`. The runtime enforces the declared types and required flags; wrong types or missing required fields raise `IPaaS::Job::FailJob` with `Nested field 'results' invalid: …`.

      #### Example Output

      ```json
      {
        "results": { "greeting": "hello moon" }
      }
      ```

      #### Allowed Ruby methods
      Every method call in the script is validated against the allowlist before execution. The groups below sample the most frequently used methods per category. For the full authoritative list, see `connector/lib/ipaas/connector/common/proc_rules/valid_methods_rule.rb`.

      | Category | Representative methods |
      |---|---|
      | Base / comparison | `present?`, `blank?`, `nil?`, `presence`, `is_a?`, `tap`, `itself`, `to_json`, `pretty_generate`, `raise`, `Float`, `lambda`, `call`, `==`, `!=`, `<`, `<=`, `>`, `>=`, `!` |
      | Strings | `split`, `gsub`, `sub`, `tr`, `strip`, `lstrip`, `rstrip`, `match`, `match?`, `captures`, `start_with?`, `end_with?`, `index`, `reverse`, `downcase`, `upcase`, `capitalize`, `swapcase`, `titleize`, `camelcase`, `underscore`, `strftime`, `to_i`, `to_f`, `to_sym`, `bytesize` |
      | Numbers | `+`, `-`, `*`, `/`, `%`, `**`, `to_s`, `to_i`, `to_f`, `abs`, `ceil`, `times`, durations (`seconds`, `minutes`, `hours`, `days`, `weeks`, `fortnights`), byte helpers (`bytes`, `kilobytes`, `megabytes`, `gigabytes`, `terabytes`, …), `number_to_human_size` |
      | Hashes | `[]`, `[]=`, `dig`, `fetch`, `key?`, `delete`, `except`, `slice`, `merge`, `reduce`, `keys`, `values`, `each_value`, `transform_keys`, `transform_values`, `with_indifferent_access`, `deep_dup`, `to_a` |
      | Arrays | `[]`, `<<`, `push`, `length`, `size`, `first`, `last`, `include?`, `exclude?`, `each`, `each_with_index`, `each_with_object`, `each_slice`, `map`, `flat_map`, `filter`, `filter_map`, `select`, `reject`, `detect`, `reduce`, `sum`, `min`, `max`, `sort`, `sort_by`, `group_by`, `index_by`, `pluck`, `pick`, `uniq`, `compact`, `compact_blank`, `flatten`, `zip`, `take`, `to_h`, `to_set`, `any?`, `all?`, `none?` |
      | Time | `Time.now`, `Time.current`, `utc`, `to_datetime`, `iso8601`, `zone`, `ago`, `at` |
      | Base64 | `encode64`, `strict_encode64`, `urlsafe_encode64`, `decode64`, `strict_decode64`, `urlsafe_decode64` |
      | URI | `scheme`, `host`, `request_uri`, `query`, `encode_www_form`, `parse_query`, `url` |
      | Crypto | `hexdigest`, `secure_compare` |
      | XML | `text`, `at_xpath` |

      Calling anything outside the allowlist (including `eval`, `system`, `exec`, `require`, `instance_eval`, method / constant definitions, direct instance / class / global variables) is rejected at validation time with `Method '<name>' not allowed.`.

      #### Available iPaaS helpers
      In addition to the allowed Ruby methods, every helper registered via `proc_safe` is callable from the script. The groups below are grouped by intended audience. The first four are what most runbook authors will ever need; the rest are primarily for connector-authoring contexts and pass validation here without being idiomatic.

      **Runbook-native (common)**

      | Helper | Purpose |
      |---|---|
      | `log(message)` | Emit a log line on the runbook run |
      | `fail_job!(message)` | Fail the action with a user-facing error. Prefer this over `raise` |
      | `finish_job!` | Exit the action successfully before the end of the script |
      | `backoff` | Signal the runbook runner to back off |
      | `input`, `nested`, `iteration_state`, `iteration_state_value`, `iteration_state_value=` | Access the inputs and iteration state of the surrounding action |
      | `action_output(ref)` | Read the output of another action in the same runbook. Validated against existing references at save time |
      | `trigger_output` | Read the runbook's trigger output |
      | `read_variable(name)`, `write_variable(name, value)` | Read / write a runbook variable |
      | `account_id`, `runbook` | Identifiers for the current run |

      **Secrets**

      | Helper | Purpose |
      |---|---|
      | `decrypt_secret_string(value)` | Decrypt a `secret_string` input into a plain string |
      | `make_secret_string(value)`, `new_secret_string(value)` | Wrap a plain value as a secret. Use when writing a `secret_string` output |

      **Cache & store**

      | Helper | Purpose |
      |---|---|
      | `cache_read(key)`, `cache_write(key, value)`, `cache_clear(key)` | Connector-scoped cache |
      | `store(key)`, `read(key)`, `write(key, value)` | Persistent store |
      | `blueprint_store` | Blueprint-scoped store |

      **Environment**

      | Helper | Purpose |
      |---|---|
      | `environment_variable(name)` | Read a named environment variable |

      **Data & name helpers**

      | Helper | Purpose |
      |---|---|
      | `compact_hash(hash)` | Remove nil / blank values from a hash |
      | `camel_to_snake(string)` | Convert camelCase → snake_case |
      | `humanize_field_name(string)` | Humanise a schema field name |
      | `keys_to_field_id(hash)` | Convert keys to field-id form |
      | `detect_content_type` | Detect a response's content type |
      | `parse_json_response(response)`, `parse_xml_response(response)` | Parse HTTP responses into hashes |

      **JWT**

      | Helper | Purpose |
      |---|---|
      | `encode_jwt(payload, …)`, `decode_jwt!(token, …)` | JWT encode / decode |
      | `make_jwt_payload(…)` | Build a JWT payload |
      | `pem_valid?(pem)` | Check PEM validity |

      **Advanced (primarily for connector authoring, available but not idiomatic here)**

      | Helper | Purpose |
      |---|---|
      | `http_send(method, url, **options)`, `http_connection`, plus method shortcuts (`get`, `post`, `put`, `delete`, `head`, `patch`, `options`, `trace`, and their `http_`-prefixed aliases), `multipart_post`, `create_text_part`, `create_binary_part` | Outbound HTTP |
      | `oauth2_client_credentials_body(…)`, `oauth2_refresh_body(…)`, `oauth2_authorization_header(…)`, `clear_oauth2_header_cache` | OAuth2 request bodies and header caching |
      | `aws_credentials_for_role`, `aws_account_id`, `build_aws_signed_headers`, `call_aws` | AWS SigV4 signing |
      | `basic_auth_credentials` | Basic auth credential lookup |
      | `psa_validate_secret`, `psa_extract_basic_auth`, `psa_generate_secret_for`, `psa_secret_for`, `psa_delete_secret_for` | PSA auth helpers |
      | `update_schedule`, `create_schedule!`, `soft_delete_schedule` | Scheduler helpers |
      | `gql_find_type`, `gql_find_root_field`, `gql_unwrap_type`, `gql_resolve_return_type_name`, `gql_resolve_connection_node_type`, `gql_collect_fields`, `gql_build_field_selection`, `gql_type_ref_string`, `gql_add_dynamic_fields`, `gql_add_dynamic_input_fields`, `gql_build_order_subfields`, `gql_update_include_fields_input`, `gql_list_root_fields`, `gql_required_args?`, `gql_to_ipaas_type`, `gql_find_nodes_field`, `gql_skip_field?`, `gql_mutation_input_type_name` | GraphQL schema / query helpers |
      | `ruby_eval(code, params)` | Recursive Ruby evaluation |

      #### Error Handling
      Errors surface at three points:

      | Stage | Trigger | Message shape |
      |---|---|---|
      | Script validation (before execution) | Disallowed method call | `Method '<name>' not allowed.` |
      | Script validation (before execution) | `action_output('<ref>')` references a step that doesn't exist | `(proc) invalid action references: '<ref>', …` |
      | Input validation (before execution) | `input` values don't match `input_schema` types / required flags | `Nested field 'input' invalid: Type of field '<x>' invalid, expected <T> found <U>.` |
      | Runtime | Any uncaught exception raised inside the script | The exception class and message propagate |
      | Runtime | Intentional failure | Call `fail_job!('<reason>')`. Produces a clean user-facing error |
      | Output validation (after execution) | `results` don't match `output_schema` types / required flags | `Output [] invalid: Nested field 'results' invalid: …` |

      #### Best Practices
      - Return data through `output[:field] = value`. The script's return value is discarded.
      - Access inputs via `input[:key]` or `input['key']`. The hash is `with_indifferent_access`.
      - Call `decrypt_secret_string(input[:x])` for any `secret_string` input; wrap outgoing secret values with `make_secret_string(value)` when the `output_schema` declares a `secret_string` field.
      - Use `fail_job!('reason')` for unrecoverable conditions instead of raising a raw exception.
      - If the validator rejects a method, pick an allowed alternative from the lists above. Never try to bypass the allowlist (any workaround involving `send`, `eval`, or constant lookup will be rejected).
      - Keep scripts small. For logic that repeats across runbooks, add a dedicated connector action instead of pasting a large script into each runbook.

      ## Execution Limits
      The Ruby connector imposes no timeout or memory cap of its own. Long-running scripts are subject to the surrounding job runner's limits.

      ## Best Practices
      - Use the Ruby connector for glue logic only. Reshape data, validate invariants, compute derived fields. Anything that calls an external API belongs in a dedicated connector.
      - Declare `input_schema` and `output_schema` up front. The surrounding runbook editor uses them to validate wiring, and the runtime uses them to type-check at the boundaries.
      - Treat the allowlist as the contract. If a method you want isn't allowed, the idiomatic path is to either rephrase the expression or add a dedicated action in a purpose-built connector.
      - Prefer `fail_job!('reason')` over `raise`. It produces a clean error on the runbook run without a Ruby stack trace leaking to the operator.
      - Protect secret inputs: decrypt with `decrypt_secret_string` only as late as needed, and never `log(...)` a decrypted value.

      ## Common Use Cases
      - **Reshape action output**: map `action_output('list_devices')` into a slimmer array of hashes before handing it to the next step.
      - **Custom validation**: assert an invariant on upstream data (`fail_job!('no users found')`) so the runbook stops before a destructive action.
      - **Derived fields**: compute a hash (`hexdigest`), build a query string (`URI.encode_www_form`), or normalise a timestamp (`1.hour.ago.iso8601`) for downstream actions.
      - **Secret handling**: call `decrypt_secret_string(input[:token])`, use the plain value in a computed header, and surface the result as a `secret_string` via `make_secret_string(...)`.
      - **Human-readable formatting**: `number_to_human_size(bytes)` or `strftime('%Y-%m-%d')` for values rendered in Xurrent records.

      ## References
      - [Ruby 3.4 standard library](https://docs.ruby-lang.org/en/3.4/)
      - [ActiveSupport 8.1 core extensions](https://guides.rubyonrails.org/v8.1/active_support_core_extensions.html)
      - [Base64](https://docs.ruby-lang.org/en/3.4/Base64.html)
      - [Time](https://docs.ruby-lang.org/en/3.4/Time.html)
      - [URI](https://docs.ruby-lang.org/en/3.4/URI.html)
    END_OF_DESCRIPTION

    action 'da0f63d9-5281-4919-8613-3ec5554505ab' do
      name 'Evaluate Ruby Code'
      avatar '/assets/icons/gem.svg'
      description <<~END_OF_DESCRIPTION
        Runs a Ruby script with caller-defined input and output schemas. Values assigned to `output[:field]` inside the script are returned under `results`. The script is validated against an allowlist of methods before execution. This action does **not** execute arbitrary Ruby.

        **Use case**: reshape data between actions, derive computed fields, validate an invariant and fail the job on breach, format timestamps or sizes, or decrypt secret inputs before passing them to a later step.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | input_schema | SchemaField[] | No | `[]` | Field definitions for the script's inputs. Each entry has `id`, `label`, `type` (`string`, `integer`, `secret_string`, …), `required` |
        | output_schema | SchemaField[] | No | `[]` | Field definitions for the values returned under `results`. The runtime validates types and required fields after execution |
        | input | Nested | Conditional | n/a | Values that match `input_schema`. Required when any `input_schema` entry has `required: true` |
        | proc | Ruby | Yes | n/a | Ruby script to execute. Access inputs via `input[:key]` (or `input['key']`) and return data via `output[:key] = value` |

        ### Example Input

        ```json
        {
          "input_schema": [
            { "id": "i", "label": "Number", "type": "integer", "required": true },
            { "id": "a", "label": "First string", "type": "string", "required": true },
            { "id": "b", "label": "Second string", "type": "string", "required": true }
          ],
          "output_schema": [
            { "id": "greeting", "label": "Greeting", "type": "string", "required": true }
          ],
          "input": { "i": 4, "a": "hello", "b": "world" },
          "proc": "if input['i'] > 3\n  output['greeting'] = input['a'] + ' moon'\nelse\n  output['greeting'] = 'bye ' + input['b']\nend"
        }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `results` | Nested | Hash populated by the script. See **Results object fields** below |

        #### Results object fields
        Fields are defined by `output_schema`. The runtime enforces the declared types and required flags; wrong types or missing required fields raise `IPaaS::Job::FailJob` with `Nested field 'results' invalid: …`.

        ### Example Output

        ```json
        {
          "results": { "greeting": "hello moon" }
        }
        ```

        ### Allowed Ruby methods
        Every method call in the script is validated against the allowlist before execution. The groups below sample the most frequently used methods per category. For the full authoritative list, see `connector/lib/ipaas/connector/common/proc_rules/valid_methods_rule.rb`.

        | Category | Representative methods |
        |---|---|
        | Base / comparison | `present?`, `blank?`, `nil?`, `presence`, `is_a?`, `tap`, `itself`, `to_json`, `pretty_generate`, `raise`, `Float`, `lambda`, `call`, `==`, `!=`, `<`, `<=`, `>`, `>=`, `!` |
        | Strings | `split`, `gsub`, `sub`, `tr`, `strip`, `lstrip`, `rstrip`, `match`, `match?`, `captures`, `start_with?`, `end_with?`, `index`, `reverse`, `downcase`, `upcase`, `capitalize`, `swapcase`, `titleize`, `camelcase`, `underscore`, `strftime`, `to_i`, `to_f`, `to_sym`, `bytesize` |
        | Numbers | `+`, `-`, `*`, `/`, `%`, `**`, `to_s`, `to_i`, `to_f`, `abs`, `ceil`, `times`, durations (`seconds`, `minutes`, `hours`, `days`, `weeks`, `fortnights`), byte helpers (`bytes`, `kilobytes`, `megabytes`, `gigabytes`, `terabytes`, …), `number_to_human_size` |
        | Hashes | `[]`, `[]=`, `dig`, `fetch`, `key?`, `delete`, `except`, `slice`, `merge`, `reduce`, `keys`, `values`, `each_value`, `transform_keys`, `transform_values`, `with_indifferent_access`, `deep_dup`, `to_a` |
        | Arrays | `[]`, `<<`, `push`, `length`, `size`, `first`, `last`, `include?`, `exclude?`, `each`, `each_with_index`, `each_with_object`, `each_slice`, `map`, `flat_map`, `filter`, `filter_map`, `select`, `reject`, `detect`, `reduce`, `sum`, `min`, `max`, `sort`, `sort_by`, `group_by`, `index_by`, `pluck`, `pick`, `uniq`, `compact`, `compact_blank`, `flatten`, `zip`, `take`, `to_h`, `to_set`, `any?`, `all?`, `none?` |
        | Time | `Time.now`, `Time.current`, `utc`, `to_datetime`, `iso8601`, `zone`, `ago`, `at` |
        | Base64 | `encode64`, `strict_encode64`, `urlsafe_encode64`, `decode64`, `strict_decode64`, `urlsafe_decode64` |
        | URI | `scheme`, `host`, `request_uri`, `query`, `encode_www_form`, `parse_query`, `url` |
        | Crypto | `hexdigest`, `secure_compare` |
        | XML | `text`, `at_xpath` |

        Calling anything outside the allowlist (including `eval`, `system`, `exec`, `require`, `instance_eval`, method / constant definitions, direct instance / class / global variables) is rejected at validation time with `Method '<name>' not allowed.`.

        ### Available iPaaS helpers
        In addition to the allowed Ruby methods, every helper registered via `proc_safe` is callable from the script. The groups below are grouped by intended audience. The first four are what most runbook authors will ever need; the rest are primarily for connector-authoring contexts and pass validation here without being idiomatic.

        **Runbook-native (common)**

        | Helper | Purpose |
        |---|---|
        | `log(message)` | Emit a log line on the runbook run |
        | `fail_job!(message)` | Fail the action with a user-facing error. Prefer this over `raise` |
        | `finish_job!` | Exit the action successfully before the end of the script |
        | `backoff` | Signal the runbook runner to back off |
        | `input`, `nested`, `iteration_state`, `iteration_state_value`, `iteration_state_value=` | Access the inputs and iteration state of the surrounding action |
        | `action_output(ref)` | Read the output of another action in the same runbook. Validated against existing references at save time |
        | `trigger_output` | Read the runbook's trigger output |
        | `read_variable(name)`, `write_variable(name, value)` | Read / write a runbook variable |
        | `account_id`, `runbook` | Identifiers for the current run |

        **Secrets**

        | Helper | Purpose |
        |---|---|
        | `decrypt_secret_string(value)` | Decrypt a `secret_string` input into a plain string |
        | `make_secret_string(value)`, `new_secret_string(value)` | Wrap a plain value as a secret. Use when writing a `secret_string` output |

        **Cache & store**

        | Helper | Purpose |
        |---|---|
        | `cache_read(key)`, `cache_write(key, value)`, `cache_clear(key)` | Connector-scoped cache |
        | `store(key)`, `read(key)`, `write(key, value)` | Persistent store |
        | `blueprint_store` | Blueprint-scoped store |

        **Environment**

        | Helper | Purpose |
        |---|---|
        | `environment_variable(name)` | Read a named environment variable |

        **Data & name helpers**

        | Helper | Purpose |
        |---|---|
        | `compact_hash(hash)` | Remove nil / blank values from a hash |
        | `camel_to_snake(string)` | Convert camelCase → snake_case |
        | `humanize_field_name(string)` | Humanise a schema field name |
        | `keys_to_field_id(hash)` | Convert keys to field-id form |
        | `detect_content_type` | Detect a response's content type |
        | `parse_json_response(response)`, `parse_xml_response(response)` | Parse HTTP responses into hashes |

        **JWT**

        | Helper | Purpose |
        |---|---|
        | `encode_jwt(payload, …)`, `decode_jwt!(token, …)` | JWT encode / decode |
        | `make_jwt_payload(…)` | Build a JWT payload |
        | `pem_valid?(pem)` | Check PEM validity |

        **Advanced (primarily for connector authoring, available but not idiomatic here)**

        | Helper | Purpose |
        |---|---|
        | `http_send(method, url, **options)`, `http_connection`, plus method shortcuts (`get`, `post`, `put`, `delete`, `head`, `patch`, `options`, `trace`, and their `http_`-prefixed aliases), `multipart_post`, `create_text_part`, `create_binary_part` | Outbound HTTP |
        | `oauth2_client_credentials_body(…)`, `oauth2_refresh_body(…)`, `oauth2_authorization_header(…)`, `clear_oauth2_header_cache` | OAuth2 request bodies and header caching |
        | `aws_credentials_for_role`, `aws_account_id`, `build_aws_signed_headers`, `call_aws` | AWS SigV4 signing |
        | `basic_auth_credentials` | Basic auth credential lookup |
        | `psa_validate_secret`, `psa_extract_basic_auth`, `psa_generate_secret_for`, `psa_secret_for`, `psa_delete_secret_for` | PSA auth helpers |
        | `update_schedule`, `create_schedule!`, `soft_delete_schedule` | Scheduler helpers |
        | `gql_find_type`, `gql_find_root_field`, `gql_unwrap_type`, `gql_resolve_return_type_name`, `gql_resolve_connection_node_type`, `gql_collect_fields`, `gql_build_field_selection`, `gql_type_ref_string`, `gql_add_dynamic_fields`, `gql_add_dynamic_input_fields`, `gql_build_order_subfields`, `gql_update_include_fields_input`, `gql_list_root_fields`, `gql_required_args?`, `gql_to_ipaas_type`, `gql_find_nodes_field`, `gql_skip_field?`, `gql_mutation_input_type_name` | GraphQL schema / query helpers |
        | `ruby_eval(code, params)` | Recursive Ruby evaluation |

        ### Error Handling
        Errors surface at three points:

        | Stage | Trigger | Message shape |
        |---|---|---|
        | Script validation (before execution) | Disallowed method call | `Method '<name>' not allowed.` |
        | Script validation (before execution) | `action_output('<ref>')` references a step that doesn't exist | `(proc) invalid action references: '<ref>', …` |
        | Input validation (before execution) | `input` values don't match `input_schema` types / required flags | `Nested field 'input' invalid: Type of field '<x>' invalid, expected <T> found <U>.` |
        | Runtime | Any uncaught exception raised inside the script | The exception class and message propagate |
        | Runtime | Intentional failure | Call `fail_job!('<reason>')`. Produces a clean user-facing error |
        | Output validation (after execution) | `results` don't match `output_schema` types / required flags | `Output [] invalid: Nested field 'results' invalid: …` |

        ### Best Practices
        - Return data through `output[:field] = value`. The script's return value is discarded.
        - Access inputs via `input[:key]` or `input['key']`. The hash is `with_indifferent_access`.
        - Call `decrypt_secret_string(input[:x])` for any `secret_string` input; wrap outgoing secret values with `make_secret_string(value)` when the `output_schema` declares a `secret_string` field.
        - Use `fail_job!('reason')` for unrecoverable conditions instead of raising a raw exception.
        - If the validator rejects a method, pick an allowed alternative from the lists above. Never try to bypass the allowlist (any workaround involving `send`, `eval`, or constant lookup will be rejected).
        - Keep scripts small. For logic that repeats across runbooks, add a dedicated connector action instead of pasting a large script into each runbook.
      END_OF_DESCRIPTION

      input_schema do
        field :input_schema, 'Input schema', :schema_field, array: true, default: []
        field :output_schema, 'Output schema', :schema_field, array: true, default: []

        field :proc, 'Ruby code', :ruby, required: true,
                                         hint: 'Ruby code to execute',
                                         sample: "output[:greeting] = \"Hello \#{input[:name]}!\""

        after_update do |fields|
          regenerate_schema(output_schema.first) if output_schema.present?

          fields.slice!(3)
          required = action.input[:input_schema].any?(&:required)
          input_schema.field(:input, 'Input values', :nested, fields: action.input[:input_schema], required: required)
          fields
        end
      end

      output_schema do
        field :results, 'Results', :nested, fields: action.input[:output_schema]
      end

      run do
        input = action.input[:input]

        result = ruby_eval(action.input[:proc], input)

        [{ output: { results: result } }]
      end
    end
  end
end

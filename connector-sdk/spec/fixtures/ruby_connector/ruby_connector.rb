class RubyConnector < IPaaS::Connector::Definition
  connector '1c9d09fa-cc75-4383-9f9f-be59761daadf' do
    name 'Ruby'
    avatar '/assets/icons/gem.svg'
    description <<~END_OF_DESCRIPTION
      ## Overview
      Runs a user-supplied Ruby script inside a sandbox. The script is validated against an allowlist of methods, and of the classes it may name, before execution. This connector does **not** execute arbitrary Ruby, and `eval`, `system`, `exec`, `require`, `instance_eval`, direct instance / global variables, and method / constant definitions are all rejected. Use it for in-runbook data transformation, validation, and small computations that don't justify a dedicated connector.

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

      #### Common Use Cases
      - **Reshape action output**: map `action_output('list_devices')` into a slimmer array of hashes before handing it to the next step.
      - **Custom validation**: assert an invariant on upstream data (`fail_job!('no users found')`) so the runbook stops before a destructive action.
      - **Derived fields**: select the parts of an action's output that several downstream actions reuse, computing the selection once instead of repeating it in every step, or normalise a timestamp (`1.hour.ago.iso8601`) before handing it on.
      - **Secret handling**: call `decrypt_secret_string(input[:token])`, use the plain value in a computed header, and surface the result as a `secret_string` via `make_secret_string(...)`.
      - **Human-readable formatting**: `number_to_human_size(bytes)` or `strftime('%Y-%m-%d')` for values rendered in Xurrent records.

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
      | Hashes | `[]`, `[]=`, `dig`, `drill`, `fetch`, `key?`, `delete`, `except`, `slice`, `merge`, `reduce`, `keys`, `values`, `each_value`, `transform_keys`, `transform_values`, `with_indifferent_access`, `deep_dup`, `to_a` |
      | Arrays | `[]`, `<<`, `push`, `length`, `size`, `first`, `last`, `include?`, `exclude?`, `each`, `each_with_index`, `each_with_object`, `each_slice`, `map`, `flat_map`, `filter`, `filter_map`, `select`, `reject`, `detect`, `reduce`, `sum`, `min`, `max`, `sort`, `sort_by`, `group_by`, `index_by`, `pluck`, `pick`, `uniq`, `compact`, `compact_blank`, `flatten`, `zip`, `take`, `to_h`, `to_set`, `any?`, `all?`, `none?` |
      | Time | `Time.now`, `Time.current`, `Time.parse`, `utc`, `to_datetime`, `iso8601`, `zone`, `ago`, `at` |
      | XML | `text`, `at_xpath` |

      Calling anything outside the allowlist (including `eval`, `system`, `exec`, `require`, `instance_eval`, method / constant definitions, direct instance / class / global variables) is rejected at validation time with `Method '<name>' not allowed.`. The `alias` and `undef` keywords are rejected with `'alias' not allowed.` / `'undef' not allowed.`.

      `to_json` takes no arguments: call it bare (`value.to_json`). Passing options or a block, or `:to_json` as a symbol (`&:to_json`, `reduce(:to_json)`), is rejected with `'to_json' takes no arguments and cannot be passed as a symbol.`; write `map { |v| v.to_json }` instead of `map(&:to_json)`.

      #### Allowed classes
      A script may name only an approved class or module, matched by exact name (for example `Time`, `Date`, `JSON`, `URI`, `Base64`, `SecureRandom`, `Digest::SHA256`, `OpenSSL::HMAC`, `StandardError`, `ArgumentError`), and may call only the approved methods on each (`JSON.parse`, `Time.now`, `Base64.encode64`, …). A class may otherwise appear only where the construct consumes it: a `rescue` list, a `when` condition, a pattern match, or an argument to `raise`, `is_a?`, `kind_of?` or `instance_of?`. It may not be assigned to a variable, placed in a literal or passed to anything else. For the full authoritative list, see `connector/lib/ipaas/connector/common/proc_rules/valid_constants_rule.rb`.

      #### Available iPaaS helpers
      In addition to the allowed Ruby methods, the platform provides the helpers below.

      **Runbook-native (common)**

      | Helper | Purpose |
      |---|---|
      | `log(message)` | Emit a log line on the runbook run |
      | `fail_job!(message)` | Fail the action with a custom message. Prefer this over `raise` |
      | `finish_job!(message)` | Early exit: complete the job before the end of the runbook, skipping subsequent actions |
      | `backoff(message, retry_after:)` | Signal the runbook runner to wait before continuing |
      | `input` | The values mapped into this action's `input` field, with indifferent access |
      | `job_context_identifier`, `job_context_identifier=` | Read / set the run's identifier, facilitates filtering of jobs |

      **Secrets**

      | Helper | Purpose |
      |---|---|
      | `decrypt_secret_string(value)` | Decrypt a `secret_string` input into a plain string |
      | `make_secret_string(value)`, `new_secret_string(value)` | Wrap a plain value as a secret. Use when writing a `secret_string` output |

      **Data & name helpers**

      | Helper | Purpose |
      |---|---|
      | `compact_hash(hash)` | Remove nil / blank values from a hash |
      | `camel_to_snake(string)` | Convert camelCase → snake_case |
      | `humanize_field_name(string)` | Humanise a schema field name |
      | `keys_to_field_id(hash)` | Convert keys to field-id form |
      | `detect_content_type` | Detect a response's content type |
      | `parse_json_response(body)` | Parse a JSON response body into a hash or array. Fails the job when the body is not valid JSON |
      | `parse_xml_response(body)` | Parse an XML response body into a document with namespaces removed. Read values out of it with `at_xpath` and `text` |

      #### Advanced helpers

      **Available but prefer alternatives**

      Reading or updating runbook state from inside the script is possible, but hides dependencies.
      Prefer mapping values so the wiring is visible in the runbook.

      | Helper | Purpose |
      |---|---|
      | `trigger_output` | Read the runbook's trigger output. Prefer an explicit input field |
      | `action_output(ref)` | Read the output of another action in the same runbook, validated against existing references at save time. Prefer an explicit input field |
      | `read_variable(name)` | Read a runbook variable. Prefer an explicit input field |
      | `write_variable(name, value)` | Write a runbook variable. Prefer the 'Assign Runbook Variable' action |

      **Primarily for connector authoring, available but not idiomatic here**

      | Helper | Purpose |
      |---|---|
      | `http_send(method, url, **options)` | Outbound HTTP request |
      | `outbound_connection.store.read(key)`, `outbound_connection.store.write(key, value)` | Persistent store shared by every Ruby action step wired to the same Ruby connection |
      | `encode_jwt(payload, …)`, `decode_jwt!(token, …)` | JWT encode / decode |
      | `make_jwt_payload(…)` | Build a JWT payload |
      | `pem_valid?(pem)` | Check PEM validity |
      | `runbook` | The running runbook. Exposes `runbook.uuid`, `runbook.account_id` and `runbook.read_variable(name)` |
      | `account_id` | Xurrent account the run belongs to |

      #### Error Handling
      Errors surface at three points:

      | Stage | Trigger | Message shape |
      |---|---|---|
      | Script validation (before execution) | Disallowed method call | `Method '<name>' not allowed.` |
      | Script validation (before execution) | Class or module not on the approved list | `Access to '<Name>' is not allowed in expressions; only an approved set of classes is available. Please file a request if access is needed.` |
      | Script validation (before execution) | Unapproved method on an approved class | `Calling '<method>' on '<Name>' is not allowed in expressions; only approved methods of approved classes are available. Please file a request if access is needed.` |
      | Script validation (before execution) | Approved class used as a value (assigned, in a literal, passed on) | `'<Name>' may only be called, rescued, raised or tested in expressions, not passed on as a value.` |
      | Script validation (before execution) | `action_output('<ref>')` references a step that doesn't exist | `(proc) invalid action references: '<ref>', …` |
      | Input validation (before execution) | `input` values don't match `input_schema` types / required flags | `Nested field 'input' invalid: Type of field '<x>' invalid, expected <T> found <U>.` |
      | Runtime | Any uncaught exception raised inside the script | The exception class and message propagate |
      | Runtime | Intentional failure | Call `fail_job!('<reason>')`. Produces a clean error carrying that message |
      | Output validation (after execution) | `results` don't match `output_schema` types / required flags | `Output [] invalid: Nested field 'results' invalid: …` |

      #### Best Practices
      - Use the Ruby connector for glue logic only. Reshape data, validate invariants, compute derived fields. Anything that calls an external API belongs in a dedicated connector.
      - Declare `input_schema` and `output_schema` up front. The surrounding runbook editor uses them to validate wiring, and the runtime uses them to type-check at the boundaries.
      - Return data through `output[:field] = value`. The script's return value is discarded.
      - Access inputs via `input[:key]` or `input['key']`. The hash is `with_indifferent_access`.
      - Protect secrets: call `decrypt_secret_string(input[:x])` only as late as needed and never `log(...)` a decrypted value; wrap outgoing secret values with `make_secret_string(value)` when the `output_schema` declares a `secret_string` field.
      - Prefer `fail_job!('reason')` over `raise` for unrecoverable conditions. It produces a clean error on the job without a Ruby stack trace.
      - When the script needs to pause, call `backoff` and let the runbook runner reschedule the action. `sleep` is not allowed.
      - If the validator rejects a method, pick an allowed alternative from the lists above.
      - Keep scripts small. For logic that repeats across runbooks, add a dedicated connector action instead of pasting a large script into each runbook.

      ## Execution Limits
      Long-running scripts are subject to the surrounding job runner's limits. This means a Ruby action must complete within 90 seconds.

      ## References
      - [Ruby 3.4 standard library](https://docs.ruby-lang.org/en/3.4/)
      - [ActiveSupport 8.1 core extensions](https://guides.rubyonrails.org/v8.1/active_support_core_extensions.html)
      - [Time](https://docs.ruby-lang.org/en/3.4/Time.html)
    END_OF_DESCRIPTION

    action 'da0f63d9-5281-4919-8613-3ec5554505ab' do
      name 'Evaluate Ruby Code'
      avatar '/assets/icons/gem.svg'
      description <<~END_OF_DESCRIPTION
        Runs a Ruby script with caller-defined input and output schemas. Values assigned to `output[:field]` inside the script are returned under `results`. The script is validated against an allowlist of methods, and of the classes it may name, before execution. This action does **not** execute arbitrary Ruby.

        ### Common Use Cases
        - **Reshape action output**: map `action_output('list_devices')` into a slimmer array of hashes before handing it to the next step.
        - **Custom validation**: assert an invariant on upstream data (`fail_job!('no users found')`) so the runbook stops before a destructive action.
        - **Derived fields**: select the parts of an action's output that several downstream actions reuse, computing the selection once instead of repeating it in every step, or normalise a timestamp (`1.hour.ago.iso8601`) before handing it on.
        - **Secret handling**: call `decrypt_secret_string(input[:token])`, use the plain value in a computed header, and surface the result as a `secret_string` via `make_secret_string(...)`.
        - **Human-readable formatting**: `number_to_human_size(bytes)` or `strftime('%Y-%m-%d')` for values rendered in Xurrent records.

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
        | Hashes | `[]`, `[]=`, `dig`, `drill`, `fetch`, `key?`, `delete`, `except`, `slice`, `merge`, `reduce`, `keys`, `values`, `each_value`, `transform_keys`, `transform_values`, `with_indifferent_access`, `deep_dup`, `to_a` |
        | Arrays | `[]`, `<<`, `push`, `length`, `size`, `first`, `last`, `include?`, `exclude?`, `each`, `each_with_index`, `each_with_object`, `each_slice`, `map`, `flat_map`, `filter`, `filter_map`, `select`, `reject`, `detect`, `reduce`, `sum`, `min`, `max`, `sort`, `sort_by`, `group_by`, `index_by`, `pluck`, `pick`, `uniq`, `compact`, `compact_blank`, `flatten`, `zip`, `take`, `to_h`, `to_set`, `any?`, `all?`, `none?` |
        | Time | `Time.now`, `Time.current`, `Time.parse`, `utc`, `to_datetime`, `iso8601`, `zone`, `ago`, `at` |
        | XML | `text`, `at_xpath` |

        Calling anything outside the allowlist (including `eval`, `system`, `exec`, `require`, `instance_eval`, method / constant definitions, direct instance / class / global variables) is rejected at validation time with `Method '<name>' not allowed.`. The `alias` and `undef` keywords are rejected with `'alias' not allowed.` / `'undef' not allowed.`.

        `to_json` takes no arguments: call it bare (`value.to_json`). Passing options or a block, or `:to_json` as a symbol (`&:to_json`, `reduce(:to_json)`), is rejected with `'to_json' takes no arguments and cannot be passed as a symbol.`; write `map { |v| v.to_json }` instead of `map(&:to_json)`.

        #### Allowed classes
        A script may name only an approved class or module, matched by exact name (for example `Time`, `Date`, `JSON`, `URI`, `Base64`, `SecureRandom`, `Digest::SHA256`, `OpenSSL::HMAC`, `StandardError`, `ArgumentError`), and may call only the approved methods on each (`JSON.parse`, `Time.now`, `Base64.encode64`, …). A class may otherwise appear only where the construct consumes it: a `rescue` list, a `when` condition, a pattern match, or an argument to `raise`, `is_a?`, `kind_of?` or `instance_of?`. It may not be assigned to a variable, placed in a literal or passed to anything else. For the full authoritative list, see `connector/lib/ipaas/connector/common/proc_rules/valid_constants_rule.rb`.

        ### Available iPaaS helpers
        In addition to the allowed Ruby methods, the platform provides the helpers below.

        **Runbook-native (common)**

        | Helper | Purpose |
        |---|---|
        | `log(message)` | Emit a log line on the runbook run |
        | `fail_job!(message)` | Fail the action with a custom message. Prefer this over `raise` |
        | `finish_job!(message)` | Early exit: complete the job before the end of the runbook, skipping subsequent actions |
        | `backoff(message, retry_after:)` | Signal the runbook runner to wait before continuing |
        | `input` | The values mapped into this action's `input` field, with indifferent access |
        | `job_context_identifier`, `job_context_identifier=` | Read / set the run's identifier, facilitates filtering of jobs |

        **Secrets**

        | Helper | Purpose |
        |---|---|
        | `decrypt_secret_string(value)` | Decrypt a `secret_string` input into a plain string |
        | `make_secret_string(value)`, `new_secret_string(value)` | Wrap a plain value as a secret. Use when writing a `secret_string` output |

        **Data & name helpers**

        | Helper | Purpose |
        |---|---|
        | `compact_hash(hash)` | Remove nil / blank values from a hash |
        | `camel_to_snake(string)` | Convert camelCase → snake_case |
        | `humanize_field_name(string)` | Humanise a schema field name |
        | `keys_to_field_id(hash)` | Convert keys to field-id form |
        | `detect_content_type` | Detect a response's content type |
        | `parse_json_response(body)` | Parse a JSON response body into a hash or array. Fails the job when the body is not valid JSON |
        | `parse_xml_response(body)` | Parse an XML response body into a document with namespaces removed. Read values out of it with `at_xpath` and `text` |

        ### Advanced helpers

        **Available but prefer alternatives**

        Reading or updating runbook state from inside the script is possible, but hides dependencies.
        Prefer mapping values so the wiring is visible in the runbook.

        | Helper | Purpose |
        |---|---|
        | `trigger_output` | Read the runbook's trigger output. Prefer an explicit input field |
        | `action_output(ref)` | Read the output of another action in the same runbook, validated against existing references at save time. Prefer an explicit input field |
        | `read_variable(name)` | Read a runbook variable. Prefer an explicit input field |
        | `write_variable(name, value)` | Write a runbook variable. Prefer the 'Assign Runbook Variable' action |

        **Primarily for connector authoring, available but not idiomatic here**

        | Helper | Purpose |
        |---|---|
        | `http_send(method, url, **options)` | Outbound HTTP request |
        | `outbound_connection.store.read(key)`, `outbound_connection.store.write(key, value)` | Persistent store shared by every Ruby action step wired to the same Ruby connection |
        | `encode_jwt(payload, …)`, `decode_jwt!(token, …)` | JWT encode / decode |
        | `make_jwt_payload(…)` | Build a JWT payload |
        | `pem_valid?(pem)` | Check PEM validity |
        | `runbook` | The running runbook. Exposes `runbook.uuid`, `runbook.account_id` and `runbook.read_variable(name)` |
        | `account_id` | Xurrent account the run belongs to |

        ### Error Handling
        Errors surface at three points:

        | Stage | Trigger | Message shape |
        |---|---|---|
        | Script validation (before execution) | Disallowed method call | `Method '<name>' not allowed.` |
        | Script validation (before execution) | Class or module not on the approved list | `Access to '<Name>' is not allowed in expressions; only an approved set of classes is available. Please file a request if access is needed.` |
        | Script validation (before execution) | Unapproved method on an approved class | `Calling '<method>' on '<Name>' is not allowed in expressions; only approved methods of approved classes are available. Please file a request if access is needed.` |
        | Script validation (before execution) | Approved class used as a value (assigned, in a literal, passed on) | `'<Name>' may only be called, rescued, raised or tested in expressions, not passed on as a value.` |
        | Script validation (before execution) | `action_output('<ref>')` references a step that doesn't exist | `(proc) invalid action references: '<ref>', …` |
        | Input validation (before execution) | `input` values don't match `input_schema` types / required flags | `Nested field 'input' invalid: Type of field '<x>' invalid, expected <T> found <U>.` |
        | Runtime | Any uncaught exception raised inside the script | The exception class and message propagate |
        | Runtime | Intentional failure | Call `fail_job!('<reason>')`. Produces a clean error carrying that message |
        | Output validation (after execution) | `results` don't match `output_schema` types / required flags | `Output [] invalid: Nested field 'results' invalid: …` |

        ### Best Practices
        - Use the Ruby connector for glue logic only. Reshape data, validate invariants, compute derived fields. Anything that calls an external API belongs in a dedicated connector.
        - Declare `input_schema` and `output_schema` up front. The surrounding runbook editor uses them to validate wiring, and the runtime uses them to type-check at the boundaries.
        - Return data through `output[:field] = value`. The script's return value is discarded.
        - Access inputs via `input[:key]` or `input['key']`. The hash is `with_indifferent_access`.
        - Protect secrets: call `decrypt_secret_string(input[:x])` only as late as needed and never `log(...)` a decrypted value; wrap outgoing secret values with `make_secret_string(value)` when the `output_schema` declares a `secret_string` field.
        - Prefer `fail_job!('reason')` over `raise` for unrecoverable conditions. It produces a clean error on the job without a Ruby stack trace.
        - When the script needs to pause, call `backoff` and let the runbook runner reschedule the action. `sleep` is not allowed.
        - If the validator rejects a method, pick an allowed alternative from the lists above.
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

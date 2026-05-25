class RunbookVariableConnector < IPaaS::Connector::Definition
  connector '01956bca-5a4b-79fc-a3ae-61fcff121682' do
    name 'Runbook Variables'
    avatar '/assets/icons/runbook-variable.svg'
    description <<~END_OF_DESCRIPTION
      ## Overview
      Writes a value into a runbook variable so later actions in the same run can read it. Runbook variables are runtime storage scoped to a single runbook execution; they are declared on the runbook itself (id, label, type, optional constraints) and referenced by ID from any action's field mapping or outbound connection configuration.

      ## Prerequisites
      - The target runbook variable must be declared on the runbook before this action can write to it. Variables are declared on the runbook with `id`, `label`, `type`, and optional constraints (`required`, `default`, `min`, `max`, `array`, nested `fields`, etc.).
      - No external credentials. This connector runs entirely in-process against the current runbook's job state.

      ## Authentication
      None — this connector does not ask for credentials.

      ## Triggers
      None — this connector is outbound only.

      ## Actions

      ### Assign Runbook Variable
      Writes `value` into the runbook variable identified by `id`. The variable becomes readable by any later action that maps the same runbook variable. After the run, the action also returns the written value as `value` so downstream actions can chain off it without a separate read.

      The `value` input is dynamically typed: once you select an `id`, the runbook variable's declared type, required flag, and constraints become the schema for `value`. Selecting a variable declared as `integer` with `min: 1, max: 42` makes `value` an integer field with that range; selecting a required `string` makes `value` a required string; selecting `array: true` makes `value` accept an array (a single value is wrapped to a one-element array). If `id` resolves to a variable that is not declared on the runbook, the action falls back to `any_value_type` for `value`, the run block logs `Runbook variable '<id>' not in use.`, and no value is written.

      **Use case**: persist intermediate results between actions in the same run — track a started-at timestamp, accumulate a counter or batch result across iterations, copy a configuration value into a variable so a later filter or condition can reference it, or clear a previously assigned variable by writing `null`.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |---|---|---|---|---|
      | `id` | RunbookVariable | Yes | - | The runbook variable to write to. Resolved against the runbook's declared `runbook_variables` by ID. Max length 256. |
      | `value` | Dynamic | Inherited from the declared variable | Inherited from the declared variable | The value to write. Type, required flag, and constraints are taken from the declared variable. Pass `null` to clear the variable. |

      #### Example Input

      Assigning a declared `integer` variable `my-int-var` (declared with `min: 1, max: 42`):

      ```json
      {
        "id": "my-int-var",
        "value": 42
      }
      ```

      Clearing a previously assigned variable:

      ```json
      {
        "id": "my-int-var",
        "value": null
      }
      ```

      Assigning an `array: true` `hash` variable:

      ```json
      {
        "id": "my-array-of-hash-var",
        "value": [{ "one": 1 }, { "two": 2 }]
      }
      ```

      Assigning a `nested` variable with declared sub-fields:

      ```json
      {
        "id": "my-nested-var",
        "value": { "foo": "bar" }
      }
      ```

      #### Output

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `value` | Dynamic | Inherited from the declared variable | The value that was written, in the type of the declared variable. Mirrors the input `value` so downstream actions can reference `action_output(...).value` without a separate read. |

      #### Example Output

      For the integer assignment above:

      ```json
      {
        "value": 42
      }
      ```

      For the array assignment above:

      ```json
      {
        "value": [{ "one": 1 }, { "two": 2 }]
      }
      ```

      #### Error Handling
      - **Variable not declared on the runbook** — `id` cannot resolve, schema validation fails with `Input mapping invalid: Field 'id' is required.` and the action does not run. If the action is reached at runtime with an unresolved `id` (e.g. through a code path that bypassed validation), the run block logs `Runbook variable '<id>' not in use.` and writes nothing; the action still completes and returns `value: nil` in the output.
      - **Type mismatch** — passing a value that doesn't match the declared type fails with `Input mapping invalid: Type of field 'value' invalid, expected <DeclaredType> found <ActualType>.` (e.g. `expected Integer found String`). The variable is not updated.
      - **Constraint violation** — values outside declared `min`/`max`, `min_length`/`max_length`, or `pattern` constraints fail validation with the matching constraint error before the run block executes.
      - **Required value missing** — if the declared variable is `required: true`, omitting `value` (or passing `null`) fails validation. If the declared variable has a `default`, omitting `value` writes the default instead.

      #### Best Practices
      - Declare the runbook variable on the runbook first; without a declaration, the action is a no-op that only logs `not in use`.
      - Use the variable's declared type to enforce validation at the assignment boundary instead of inside Ruby blocks downstream — `min`/`max`, `required`, `array`, and nested `fields` constraints all apply to `value`.
      - Use `secret_string` for any value that should not appear in the run log (tokens, passwords, PII).
      - To clear a variable mid-run, assign `null`. To reset to a declared default, omit `value` from the mapping.
      - Use `:runbook_variable` `id` references rather than hard-coding values in field mappings whenever the same value is read in more than one place — renaming the variable on the runbook automatically updates every action and connection that maps it.

      ## Rate Limiting
      None. The action operates on in-process job state and makes no network calls.

      ## Best Practices
      - Declare every runbook variable you intend to assign before wiring **Assign Runbook Variable** into the runbook. Picking an undeclared `id` makes the action a logged no-op — useful only for debugging.
      - Keep variable IDs stable once other actions reference them. Renaming an `id` on the runbook auto-updates references, but deleting and recreating with a different ID does not.
      - Prefer typed declarations (`integer`, `time`, `boolean`, `hash` with explicit `fields`) over generic `string` so type and constraint validation runs at the assignment boundary.
      - Use `array: true` on the declaration when accumulating across iterations; the action will wrap a single value into a one-element array on assignment, so the variable's shape stays consistent across paths.
      - Initialize variables with `default` on the declaration when the runbook has a path that reads before any **Assign Runbook Variable** has run; otherwise `read_variable` returns `nil`.
      - Never log a `secret_string` variable's resolved value via the **Debug** connector or a Ruby `log(...)` call — the run log is plain text.

      ## Common Use Cases
      - **Started-at timestamp** — assign a `time` variable at the start of the runbook, then compare it against `Time.now` inside a later **Evaluate Ruby Code** action to enforce a per-run timeout.
      - **Batch result accumulator** — declare a `hash` (optionally `array: true`) variable, then call **Assign Runbook Variable** at the end of each batch with the merged result so the final action can summarise the run.
      - **Iteration counter** — declare an `integer` variable with `default: 0`, then increment via Ruby and **Assign Runbook Variable** to control loop exit conditions.
      - **Cross-action configuration copy** — pull a value out of an outbound connection's configuration once, write it to a variable, and reference the variable in every downstream field mapping instead of repeating the lookup.
      - **Clear sensitive data** — assign `null` to a `secret_string` variable after the action that needed the plaintext finishes, so subsequent actions cannot read it back.

      ## References
      - [Connector Documentation](https://www.xurrent.com/help/connector-documentation)
      - [Create Your First Runbook](https://www.xurrent.com/help/create-your-first-runbook)
    END_OF_DESCRIPTION

    action '01956bca-86a6-7996-8d96-606af5237024' do
      name 'Assign Runbook Variable'
      avatar '/assets/icons/runbook-variable.svg'
      description <<~END_OF_DESCRIPTION
        Writes `value` into the runbook variable identified by `id`. The variable becomes readable by any later action that maps the same runbook variable. After the run, the action also returns the written value as `value` so downstream actions can chain off it without a separate read.

        The `value` input is dynamically typed: once you select an `id`, the runbook variable's declared type, required flag, and constraints become the schema for `value`. Selecting a variable declared as `integer` with `min: 1, max: 42` makes `value` an integer field with that range; selecting a required `string` makes `value` a required string; selecting `array: true` makes `value` accept an array (a single value is wrapped to a one-element array). If `id` resolves to a variable that is not declared on the runbook, the action falls back to `any_value_type` for `value`, the run block logs `Runbook variable '<id>' not in use.`, and no value is written.

        **Use case**: persist intermediate results between actions in the same run — track a started-at timestamp, accumulate a counter or batch result across iterations, copy a configuration value into a variable so a later filter or condition can reference it, or clear a previously assigned variable by writing `null`.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |---|---|---|---|---|
        | `id` | RunbookVariable | Yes | - | The runbook variable to write to. Resolved against the runbook's declared `runbook_variables` by ID. Max length 256. |
        | `value` | Dynamic | Inherited from the declared variable | Inherited from the declared variable | The value to write. Type, required flag, and constraints are taken from the declared variable. Pass `null` to clear the variable. |

        ### Example Input

        Assigning a declared `integer` variable `my-int-var` (declared with `min: 1, max: 42`):

        ```json
        {
          "id": "my-int-var",
          "value": 42
        }
        ```

        Clearing a previously assigned variable:

        ```json
        {
          "id": "my-int-var",
          "value": null
        }
        ```

        Assigning an `array: true` `hash` variable:

        ```json
        {
          "id": "my-array-of-hash-var",
          "value": [{ "one": 1 }, { "two": 2 }]
        }
        ```

        Assigning a `nested` variable with declared sub-fields:

        ```json
        {
          "id": "my-nested-var",
          "value": { "foo": "bar" }
        }
        ```

        ### Output

        | Field | Type | Required | Description |
        |---|---|---|---|
        | `value` | Dynamic | Inherited from the declared variable | The value that was written, in the type of the declared variable. Mirrors the input `value` so downstream actions can reference `action_output(...).value` without a separate read. |

        ### Example Output

        For the integer assignment above:

        ```json
        {
          "value": 42
        }
        ```

        For the array assignment above:

        ```json
        {
          "value": [{ "one": 1 }, { "two": 2 }]
        }
        ```

        ### Error Handling
        - **Variable not declared on the runbook** — `id` cannot resolve, schema validation fails with `Input mapping invalid: Field 'id' is required.` and the action does not run. If the action is reached at runtime with an unresolved `id` (e.g. through a code path that bypassed validation), the run block logs `Runbook variable '<id>' not in use.` and writes nothing; the action still completes and returns `value: nil` in the output.
        - **Type mismatch** — passing a value that doesn't match the declared type fails with `Input mapping invalid: Type of field 'value' invalid, expected <DeclaredType> found <ActualType>.` (e.g. `expected Integer found String`). The variable is not updated.
        - **Constraint violation** — values outside declared `min`/`max`, `min_length`/`max_length`, or `pattern` constraints fail validation with the matching constraint error before the run block executes.
        - **Required value missing** — if the declared variable is `required: true`, omitting `value` (or passing `null`) fails validation. If the declared variable has a `default`, omitting `value` writes the default instead.

        ### Best Practices
        - Declare the runbook variable on the runbook first; without a declaration, the action is a no-op that only logs `not in use`.
        - Use the variable's declared type to enforce validation at the assignment boundary instead of inside Ruby blocks downstream — `min`/`max`, `required`, `array`, and nested `fields` constraints all apply to `value`.
        - Use `secret_string` for any value that should not appear in the run log (tokens, passwords, PII).
        - To clear a variable mid-run, assign `null`. To reset to a declared default, omit `value` from the mapping.
      END_OF_DESCRIPTION

      input_schema do
        field :id,
              'ID',
              :runbook_variable,
              required: true,
              hint: 'Use this ID to reference the variable in field mappings.',
              max_length: 256
        field :value,
              'Value',
              :any_value_type

        after_update do |fields|
          variable_field = runbook.variable_field(input[:id]&.id)
          fields.slice!(1)
          if variable_field
            variable_field.id = :value
            variable_field.label = 'Value'
            fields << variable_field
          else
            input_schema.field(:value, 'Value', :any_value_type)
          end

          regenerate_schema(output_schema.first)

          fields
        end
      end

      output_schema do
        value_field = action.input_schema.field(:value)
        field(value_field)
      end

      run do
        id = input[:id]&.id
        output = { value: nil }

        if runbook.variable_field(id)
          runbook.write_variable(id, input[:value])
          output[:value] = input[:value]
        else
          log("Runbook variable '%<id>s' not in use.", { id: id })
        end

        [{ output: output }]
      end
    end
  end
end

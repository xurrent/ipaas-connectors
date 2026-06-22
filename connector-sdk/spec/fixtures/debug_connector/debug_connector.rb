class DebugConnector < IPaaS::Connector::Definition
  connector '0192229d-bc1d-7013-a90d-0785c78c5964' do
    name 'Debug'
    avatar '/assets/icons/bug.svg'
    description <<~END_OF_DESCRIPTION
      ## Overview
      Writes a message to the runbook run log. Use it to trace execution, surface intermediate values, or confirm branch outcomes during development.

      ## Prerequisites
      This connector runs in-process and requires no credentials or external endpoints.

      ## Authentication
      This connector requires no credentials.

      ## Triggers
      This connector is outbound only.

      ## Actions

      ### Log Message
      Writes the `message` input to the runbook run log via the platform's `log` helper. Returns no output fields.

      **Use case**: emit a marker line to confirm a branch was taken, surface the value of an `action_output(...)` reference or runbook variable mid-run, or pinpoint where a runbook reached during development.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |---|---|---|---|---|
      | `message` | String | Yes | - | Text to write to the runbook run log. Reference any upstream `action_output(...)` value or runbook variable inline; the runbook builder substitutes them into the string before the action runs. |

      #### Example Input

      ```json
      {
        "message": "Created user 42"
      }
      ```

      #### Output

      This action has no output fields.

      #### Example Output

      ```json
      {}
      ```

      #### Error Handling
      Schema validation runs before the action executes. If `message` is missing or not a string, the action fails with a validation error before reaching the run block. Once validation passes, `log` always succeeds.

      #### Best Practices
      - Never put a decrypted `secret_string` value into `message`; anything passed to `log` lands in the run log in plain text.
      - Keep messages short and structured (e.g. `created user id=42`) so they're greppable in the run log.

      ## Best Practices
      - Use Debug actions for traces during development; remove or gate them before runbooks ship to production so the run log stays focused on business actions.
      - Reference upstream `action_output(...)` values or runbook variables directly in `message`; the runbook builder substitutes them before the action runs.

      ## Common Use Cases
      - **Branch confirmation**: drop a Log Message inside each branch of an `if`/`switch` to verify which path the runbook took.
      - **Mid-run inspection**: log the size or a sample field of an upstream `action_output(...)` reference to debug shape mismatches without rerunning the whole runbook.
      - **Runbook milestone markers**: emit a recognisable string at key points so log-ingestion tooling can correlate the runbook run with downstream events.

      ## References
      - For richer in-runbook logging (formatted strings, conditional logging, multiple lines), call `log(...)` inside an **Evaluate Ruby Code** action on the **Ruby** connector.
    END_OF_DESCRIPTION

    action '0192229d-fb7a-78d2-91c8-341915eb9e87' do
      name 'Log Message'
      avatar '/assets/icons/card-text.svg'
      description <<~END_OF_DESCRIPTION
        Writes the `message` input to the runbook run log via the platform's `log` helper. Returns no output fields.

        **Use case**: emit a marker line to confirm a branch was taken, surface the value of an `action_output(...)` reference or runbook variable mid-run, or pinpoint where a runbook reached during development.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |---|---|---|---|---|
        | `message` | String | Yes | - | Text to write to the runbook run log. Reference any upstream `action_output(...)` value or runbook variable inline; the runbook builder substitutes them into the string before the action runs. |

        ### Example Input

        ```json
        {
          "message": "Created user 42"
        }
        ```

        ### Output

        This action has no output fields.

        ### Example Output

        ```json
        {}
        ```

        ### Error Handling
        Schema validation runs before the action executes. If `message` is missing or not a string, the action fails with a validation error before reaching the run block. Once validation passes, `log` always succeeds.

        ### Best Practices
        - Never put a decrypted `secret_string` value into `message`; anything passed to `log` lands in the run log in plain text.
        - Keep messages short and structured (e.g. `created user id=42`) so they're greppable in the run log.
      END_OF_DESCRIPTION

      input_schema do
        field :message,
              'Message',
              :string,
              required: true
      end

      output_schema do
        name 'This action has no output'
      end

      run do
        log(action.input.fetch(:message))
        [{ output: {} }]
      end
    end
  end
end

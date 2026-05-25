class FlowConnector < IPaaS::Connector::Definition
  connector '60f87e74-8f76-4d9e-b2ca-ac976f1c4359' do
    name 'Flow'
    avatar '/assets/icons/shuffle.svg'
    description <<~END_OF_DESCRIPTION
      ## Overview
      In-process control-flow primitives — branching, looping, parallelisation, error handling, and timing — for use inside runbooks. No external service is called and no credentials are required; every action runs entirely within the Xurrent runbook engine.

      ## Prerequisites
      - Access to the Xurrent runbook builder. This connector ships pre-installed; no additional setup is needed.

      ## Authentication
      None — runs in-process. No connection needs to be configured.

      ## Triggers
      None — this connector exposes actions only.

      ## Actions

      ### If-then-else
      Branches on a boolean condition. Routes execution to the **True** sub-block when the condition is truthy and, optionally, to the **False** sub-block when it is falsy.

      **Use case**: gate a downstream action on a query result, a comparison, or any boolean-coercible value.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |---|---|---|---|---|
      | `condition` | Boolean | Yes | - | The branch selector. Strings such as `"True"`, `"true"`, `"F"`, `"false"` are coerced to booleans before evaluation. |
      | `include_false_path` | Boolean | No | `true` | When `false`, the **False** sub-block is removed from the runbook tree and a falsy `condition` produces no output. |

      #### Example Input

      ```json
      { "condition": true, "include_false_path": true }
      ```

      #### Output
      Two output schemas — `true` and `false`. Each carries a single field:

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `result` | Boolean | Yes | Mirrors the input `condition`. |

      Only the matching schema fires per run. When `include_false_path` is `false` and `condition` is falsy, no schema fires and no nested actions run.

      #### Example Output

      `true` schema:

      ```json
      { "result": true }
      ```

      `false` schema:

      ```json
      { "result": false }
      ```

      #### Error Handling
      A missing `condition` fails input validation before the action runs. Otherwise the action does not raise.

      #### Best Practices
      - Set `include_false_path` to `false` when only the True branch is meaningful — it keeps the runbook tree readable.
      - For three or more branches, use **Case** instead of chaining nested If-then-else actions.

      ### Case
      Matches a string expression against a list of candidate values; routes execution to the matching sub-block, or to the **Else** sub-block when no candidate matches.

      **Use case**: branch on a status field, an event type, or any string with more than two possible values.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |---|---|---|---|---|
      | `expression` | String | Yes | - | The value to match. |
      | `matches` | Array of String | Yes | - | Candidate values; one output schema is created per entry. Maximum 50 entries. |
      | `include_else_path` | Boolean | No | `true` | When `false`, the **Else** sub-block is removed and a non-matching `expression` produces no output. |

      #### Example Input

      ```json
      {
        "expression": "baz",
        "matches": ["foo", "bar", "baz", "boo"]
      }
      ```

      #### Output
      One output schema per `matches` entry (named after the match string), plus optionally an `else` schema. Each schema carries:

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `expression` | String | Yes | The expression that selected this branch. |

      Only the matching schema fires per run.

      #### Example Output

      `baz` schema (matched):

      ```json
      { "expression": "baz" }
      ```

      `else` schema (no match):

      ```json
      { "expression": "unknown" }
      ```

      #### Error Handling
      A missing `expression` or `matches`, or a `matches` array longer than 50 entries, fails input validation before the action runs.

      #### Best Practices
      - Output schema names cannot be remapped from the runbook builder; each branch is named after its match string, which keeps a long Case action readable.
      - For a binary branch, use **If-then-else** — its boolean coercion handles strings like `"True"` and `"F"`.

      ### Section
      A pure passthrough that groups child actions under a named section in the runbook tree. No data transformation.

      **Use case**: organise a long runbook into logical sub-blocks, or scope a sub-tree visually for readability.

      #### Input Parameters
      None.

      #### Example Input

      ```json
      {}
      ```

      #### Output
      One output schema, `nested_section`, with no fields.

      #### Example Output

      ```json
      {}
      ```

      #### Error Handling
      None — Section has no failure modes of its own.

      #### Best Practices
      - Use Section purely for organisation. Variables, retries, and error handling all live in dedicated actions; Section adds no semantics beyond grouping.

      ### Fork
      Starts N parallel sub-blocks. Each branch receives its own zero-based `index`.

      **Use case**: run independent operations in parallel — e.g. notify two chat channels simultaneously, or fan-out the same lookup to several systems.

      #### Input Parameters

      | Parameter | Type | Required | Min | Max | Description |
      |---|---|---|---|---|---|
      | `nr_of_actions` | Integer | Yes | `2` | `50` | Number of parallel branches. |

      #### Example Input

      ```json
      { "nr_of_actions": 4 }
      ```

      #### Output
      One output schema per branch (`fork-0`, `fork-1`, …, `fork-<N-1>`). Each schema carries:

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `index` | Integer | Yes | Zero-based branch position. |

      All N schemas fire per run, in parallel.

      #### Example Output

      Branch outputs for `nr_of_actions = 4`:

      ```json
      [
        { "index": 0 },
        { "index": 1 },
        { "index": 2 },
        { "index": 3 }
      ]
      ```

      #### Error Handling
      `nr_of_actions` outside `[2, 50]` fails input validation.

      #### Best Practices
      - Branch references stay stable when `nr_of_actions` shrinks back from a higher value — wiring on the first N branches is preserved across changes.
      - Use **Fork** when each branch performs a different operation. Use **Loop** when the number of branches is driven by a list of values.

      ### Loop
      Iterates over an array, running the nested sub-block once per item. Each iteration receives the current item and a zero-based index.

      **Use case**: process each row of an upstream query result, send one notification per recipient, or apply a transformation to each entry of a list.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |---|---|---|---|---|
      | `items` | Array of Any | No | - | The list to iterate. Each entry triggers one iteration. An empty array runs the nested sub-block zero times. |

      #### Example Input

      ```json
      { "items": ["foo", "bar", "baz"] }
      ```

      #### Output
      One output schema, `loop`, fired once per item:

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `item` | Any | Yes | The current entry. |
      | `index` | Integer | Yes | Zero-based position in `items`. |

      #### Example Output

      Per-iteration outputs for the input above:

      ```json
      [
        { "item": "foo", "index": 0 },
        { "item": "bar", "index": 1 },
        { "item": "baz", "index": 2 }
      ]
      ```

      #### Error Handling
      An empty or absent `items` array yields zero iterations — the nested sub-block does not run and no error is raised.

      #### Best Practices
      - Iterations run sequentially. For independent work, use **Fork** when the count is fixed.
      - When each item drives an external API call and the target API supports bulk requests, use **Batch** to amortise per-call overhead.

      ### Batch
      Splits an array into fixed-size chunks and runs the nested sub-block once per chunk. The final chunk may be smaller.

      **Use case**: feed a bulk-write endpoint that accepts an array of items per call (e.g. "update up to 100 records per request"), or amortise per-call overhead across many small items.

      #### Input Parameters

      | Parameter | Type | Required | Min | Description |
      |---|---|---|---|---|
      | `items` | Array of Any | Yes | - | The source array to chunk. |
      | `batch_size` | Integer | Yes | `2` | Items per chunk. |

      #### Example Input

      ```json
      { "items": [1, 2, 3, 4, 5], "batch_size": 2 }
      ```

      #### Output
      One output schema, `batch`, fired once per chunk:

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `items` | Array of Any | Yes | The items in this chunk. The final chunk may contain fewer than `batch_size` items. |

      #### Example Output

      Per-chunk outputs for the input above:

      ```json
      [
        { "items": [1, 2] },
        { "items": [3, 4] },
        { "items": [5] }
      ]
      ```

      #### Error Handling
      Missing `items` or `batch_size`, or `batch_size < 2`, fails input validation. An empty `items` array yields zero chunks.

      #### Best Practices
      - Match `batch_size` to the target API's bulk-endpoint maximum (e.g. 100 for many REST APIs, 25 for AWS DynamoDB `BatchWriteItem`).
      - Downstream actions should treat the per-chunk `items.size` as variable — it equals `batch_size` for every chunk except, potentially, the last.

      ### Fail
      Stops the runbook and marks the run as **Failed**, with an optional message logged to the run.

      **Use case**: assert an invariant — fail the run if upstream data is missing, malformed, or violates a business rule.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |---|---|---|---|---|
      | `message` | String | No | `Stopped` | Text logged on failure. |

      #### Example Input

      ```json
      { "message": "No matching account found for the supplied ID" }
      ```

      #### Output
      None — the action terminates the runbook and the run ends in the **Failed** state.

      #### Example Output
      Not applicable.

      #### Error Handling
      Always terminates the runbook with `message`. The run ends in the **Failed** state.

      #### Best Practices
      - Pair Fail with **If-then-else** or **Case** — branch into Fail when an invariant breaks, rather than letting an unhelpful runtime error surface later.
      - Make `message` actionable: include the failing value, not just `"validation failed"`.

      ### Finish
      Stops the runbook and marks the run as successfully **Finished** at this step. Logs `message` to the run.

      **Use case**: short-circuit out of a runbook when there is no further work to do — e.g. an early return after detecting a no-op condition.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |---|---|---|---|---|
      | `message` | String | Yes | `Runbook execution completed` | Text logged on completion. |

      #### Example Input

      ```json
      { "message": "Already up to date — nothing to do" }
      ```

      #### Output
      None — the action logs `message` and terminates the runbook. The run ends in the **Finished** state.

      #### Example Output
      Not applicable.

      #### Error Handling
      Always terminates the runbook with `message`. This is a successful exit — the run is marked Finished, not Failed.

      #### Best Practices
      - Use Finish only for clean, intentional early exits. For unexpected conditions, use **Fail** so the run is recorded as failed.
      - Make `message` describe **why** the runbook is exiting — operators see this in the run log.

      ### Try-catch
      Wraps a `Try` sub-block in error handling. If any action inside `Try` raises, the runbook engine re-runs this action and routes execution down the `Catch` sub-block, passing the error message.

      **Use case**: handle expected failures from external systems — a 4xx response, a missing record, a transient network error — without failing the whole runbook.

      #### Input Parameters
      None.

      #### Example Input

      ```json
      {}
      ```

      #### Output
      Two output schemas — `try` and `catch`. Exactly one fires per invocation.

      `try` schema — no fields.

      `catch` schema:

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `error` | String | Yes | Error message from the action that raised inside `Try`. |

      #### Example Output

      `try` schema (no error inside Try):

      ```json
      {}
      ```

      `catch` schema (an action inside Try raised):

      ```json
      { "error": "Something went wrong" }
      ```

      #### Error Handling
      Routing is automatic. On the first invocation the `Try` schema fires. If a child action of `Try` raises, the runbook engine re-invokes Try-catch with internal state set so the `Catch` schema fires next, with `error` populated from the raised exception's message. Exceptions outside the `Try` sub-block are not caught.

      #### Best Practices
      - Catch only failures you know how to handle. Letting an unrecoverable error surface is usually safer than catching it and continuing on bad data.
      - Pair Try-catch with **Retry** at the end of the `Catch` sub-block to re-run `Try` after a remediation step. Without **Retry**, execution falls through to the next sibling action after `Catch` completes.
      - The `error` field is a string — to retain structured information, encode it into the message at the source (e.g. JSON-encode a hash before raising).

      ### Retry
      Re-runs the surrounding **Try-catch** action's `Try` sub-block. Must be placed inside a `Catch` sub-block.

      **Use case**: handle transient failures by re-attempting the original operation after the catch path has logged or remediated the error.

      #### Input Parameters
      None.

      #### Example Input

      ```json
      {}
      ```

      #### Output
      A single output schema with no fields.

      #### Example Output

      ```json
      {}
      ```

      #### Error Handling
      When reached inside a `Catch` sub-block, control returns to the surrounding `Try` sub-block. Placed outside a `Catch` block, Retry has no error-handling effect — it simply exits with an empty output.

      #### Best Practices
      - The classic transient-retry pattern is: **Try-catch** with the flaky action inside `Try`; **Wait** at the start of `Catch` to back off; **Retry** at the end of `Catch` to re-attempt.
      - Guard against infinite retries: combine Retry with a counter (e.g. a runbook variable incremented in the catch path) and switch to **Fail** once a retry budget is exhausted.

      ### Wait
      Pauses the runbook for at least `seconds_to_wait` seconds before continuing. Reports the actual elapsed time.

      **Use case**: insert a deliberate delay between actions — back off before retrying, give an upstream system time to settle, or schedule the next step.

      #### Input Parameters

      | Parameter | Type | Required | Min | Description |
      |---|---|---|---|---|
      | `seconds_to_wait` | Integer | Yes | `0` | Minimum number of seconds to wait. The actual wait may be longer; never shorter. |

      #### Example Input

      ```json
      { "seconds_to_wait": 60 }
      ```

      #### Output
      One output schema, `actual`:

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `started_at` | Time | Yes | When the wait began. |
      | `requested_wait` | Integer | Yes | The configured `seconds_to_wait`. |
      | `completed_at` | Time | Yes | When the wait ended. |
      | `actual_wait` | Integer | Yes | Seconds elapsed between `started_at` and `completed_at`. Always `>= requested_wait`. |

      #### Example Output

      ```json
      {
        "started_at": "2026-04-28T09:00:00Z",
        "requested_wait": 60,
        "completed_at": "2026-04-28T09:01:02Z",
        "actual_wait": 62
      }
      ```

      #### Error Handling
      When `seconds_to_wait > 0`, the first invocation suspends the action on the queue and returns no output. The runbook engine resumes the action after the wait elapses, at which point the `actual` schema fires with the timing fields above. When `seconds_to_wait` is `0`, the action completes on the first invocation with `started_at == completed_at`.

      #### Best Practices
      - `actual_wait` can exceed `requested_wait` because the engine schedules pickup on its own queue. Branch on `actual_wait` if exact timing matters downstream.
      - For exponential backoff inside a retry loop, drive `seconds_to_wait` from a runbook variable and double it each iteration.

      ## Runbook Concepts

      The Flow connector is the most direct demonstrator of three runbook-engine concepts. They appear in the action descriptions above; this section names them once for reference.

      - **Nested actions** — actions marked `nested` in this connector (every action except **Fail**, **Finish**, and **Retry**) host child actions in the runbook tree. Each nested action emits one or more output schemas, and the runbook builder lets you wire child actions under each schema.
      - **Output schema selection** — when a nested action emits multiple output schemas (e.g. **If-then-else**'s `true`/`false`, **Case**'s per-match schemas, **Try-catch**'s `try`/`catch`), only the schemas that fire on a given run propagate to their wired child actions.
      - **Iteration** — **Loop**, **Batch**, and **Fork** fire their output schema multiple times per run, once per item / chunk / branch. **Wait** and **Try-catch** also use the iteration mechanism internally to suspend and resume.

      ## Best Practices
      - Use Flow for control flow only. Reach for the **Ruby** connector when you need to transform or compute over data — Flow has no expression evaluation of its own.
      - Keep nesting shallow. Each level (e.g. **If-then-else** inside **Loop** inside **Fork**) compounds the runbook's state space and makes failures harder to localise.
      - Branch with **If-then-else** for two paths and **Case** for many. Don't chain four **If-then-else** actions when **Case** would do.
      - Use **Fail** with a specific message when a precondition breaks; **Finish** marks the run as successful, which is wrong for a precondition violation.
      - Reach for **Try-catch** + **Retry** + **Wait** for transient failures from external connectors. For permanent failures, route into **Fail** instead — retrying a 404 doesn't help.
      - Avoid **Loop** for very large arrays — its sequential model means N items take N times longer than one. Switch to **Batch** when the downstream action has a bulk endpoint, or **Fork** when items are independent and the count is fixed.

      ## Common Use Cases
      - **Branch on a query result** — call a lookup action, then **If-then-else** on whether it returned a record. Wire the True branch to the update path and the False branch to the create path.
      - **Process a list** — chain a list-fetching action into **Loop**; nest the per-item action inside.
      - **Bulk-write items** — chain a list-fetching action into **Batch** with `batch_size` matching the target API's bulk-endpoint maximum; nest the bulk-write action inside.
      - **Fan out to parallel destinations** — chain a payload-builder action into **Fork**, with one child sub-block per destination.
      - **Retry a transient failure** — wrap the flaky action in **Try-catch**, add **Wait** at the start of `Catch` to back off, end `Catch` with **Retry**.
      - **Assert an invariant** — chain the validating action into **If-then-else**; route the failure branch to **Fail** with a descriptive message.
      - **Short-circuit on a no-op** — chain a status-check action into **If-then-else**; route the "nothing to do" branch to **Finish**.
      - **Group sub-trees** — wrap a logical sub-tree in **Section** to keep the runbook readable.

      ## References
      - For data transformation, computation, or building structured payloads — Flow has no expression evaluation; use **Evaluate Ruby Code** on the **Ruby** connector.
      - For state that persists across iterations — define a runbook variable on the **Runbook Variables** connector and update it inside **Loop**, **Batch**, or a **Try-catch** `Catch` block to track retry counts, accumulators, or progress flags.
    END_OF_DESCRIPTION

    action '3a8bb36b-863f-4b31-a677-bb9c927c9202' do
      name 'If-then-else'
      avatar '/assets/icons/signpost-split.svg'
      description <<~END_OF_DESCRIPTION
        Branches on a boolean condition. Routes execution to the **True** sub-block when the condition is truthy and, optionally, to the **False** sub-block when it is falsy.

        **Use case**: gate a downstream action on a query result, a comparison, or any boolean-coercible value.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |---|---|---|---|---|
        | `condition` | Boolean | Yes | - | The branch selector. Strings such as `"True"`, `"true"`, `"F"`, `"false"` are coerced to booleans before evaluation. |
        | `include_false_path` | Boolean | No | `true` | When `false`, the **False** sub-block is removed from the runbook tree and a falsy `condition` produces no output. |

        ### Example Input

        ```json
        { "condition": true, "include_false_path": true }
        ```

        ### Output
        Two output schemas — `true` and `false`. Each carries a single field:

        | Field | Type | Required | Description |
        |---|---|---|---|
        | `result` | Boolean | Yes | Mirrors the input `condition`. |

        Only the matching schema fires per run. When `include_false_path` is `false` and `condition` is falsy, no schema fires and no nested actions run.

        ### Example Output

        `true` schema:

        ```json
        { "result": true }
        ```

        `false` schema:

        ```json
        { "result": false }
        ```

        ### Error Handling
        A missing `condition` fails input validation before the action runs. Otherwise the action does not raise.

        ### Best Practices
        - Set `include_false_path` to `false` when only the True branch is meaningful — it keeps the runbook tree readable.
        - For three or more branches, use **Case** instead of chaining nested If-then-else actions.
      END_OF_DESCRIPTION
      nested true

      input_schema do
        field :condition,
              'Condition',
              :boolean,
              required: true
        field :include_false_path,
              'Include false path',
              :boolean,
              default: true,
              visibility: 'optional'

        after_update do
          action.output_schemas&.clear

          output_schema 'true' do
            name 'True'
            field :result,
                  'Result',
                  :boolean,
                  required: true
          end

          if action.input[:include_false_path]
            output_schema 'false' do
              name 'False'
              field :result,
                    'Result',
                    :boolean,
                    required: true
            end
          end
        end
      end

      run do
        condition = action.input.fetch(:condition)
        output = { result: condition }
        schema_reference = if condition
                             'true'
                           elsif action.input[:include_false_path]
                             'false'
                           end
        if schema_reference
          [{ schema_reference: schema_reference, output: output }]
        else
          []
        end
      end
    end

    action 'f93f2f08-c901-4655-8083-9c88e5d40761' do
      name 'Case'
      avatar '/assets/icons/list-task.svg'
      description <<~END_OF_DESCRIPTION
        Matches a string expression against a list of candidate values; routes execution to the matching sub-block, or to the **Else** sub-block when no candidate matches.

        **Use case**: branch on a status field, an event type, or any string with more than two possible values.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |---|---|---|---|---|
        | `expression` | String | Yes | - | The value to match. |
        | `matches` | Array of String | Yes | - | Candidate values; one output schema is created per entry. Maximum 50 entries. |
        | `include_else_path` | Boolean | No | `true` | When `false`, the **Else** sub-block is removed and a non-matching `expression` produces no output. |

        ### Example Input

        ```json
        {
          "expression": "baz",
          "matches": ["foo", "bar", "baz", "boo"]
        }
        ```

        ### Output
        One output schema per `matches` entry (named after the match string), plus optionally an `else` schema. Each schema carries:

        | Field | Type | Required | Description |
        |---|---|---|---|
        | `expression` | String | Yes | The expression that selected this branch. |

        Only the matching schema fires per run.

        ### Example Output

        `baz` schema (matched):

        ```json
        { "expression": "baz" }
        ```

        `else` schema (no match):

        ```json
        { "expression": "unknown" }
        ```

        ### Error Handling
        A missing `expression` or `matches`, or a `matches` array longer than 50 entries, fails input validation before the action runs.

        ### Best Practices
        - Output schema names cannot be remapped from the runbook builder; each branch is named after its match string, which keeps a long Case action readable.
        - For a binary branch, use **If-then-else** — its boolean coercion handles strings like `"True"` and `"F"`.
      END_OF_DESCRIPTION
      nested true
      disable_output_schema_name_mapping true

      input_schema do
        field :expression,
              'Expression',
              :string,
              required: true
        field :matches,
              'Matches',
              :string,
              array: true,
              required: true,
              max_length: 50
        field :include_else_path,
              'Include else path',
              :boolean,
              default: true,
              visibility: 'optional'

        after_update do
          action.output_schemas.clear

          matches = action.input[:matches]
          matches.each do |match|
            output_schema match do
              name match
              field :expression,
                    match,
                    :string,
                    required: true
            end
          end

          if action.input[:include_else_path]
            output_schema 'else' do
              name 'Else'
              field :expression,
                    'Else',
                    :string,
                    required: true
            end
          end
        end
      end

      run do
        expression = action.input[:expression]
        match = if action.input[:matches].include?(expression)
                  expression
                elsif action.input[:include_else_path]
                  'else'
                end
        if match
          [{ schema_reference: match, output: { expression: expression } }]
        else
          []
        end
      end
    end

    action '0195802a-b2da-7e8a-98e0-f235b0962e8c' do
      name 'Section'
      avatar '/assets/icons/list-nested.svg'
      description <<~END_OF_DESCRIPTION
        A pure passthrough that groups child actions under a named section in the runbook tree. No data transformation.

        **Use case**: organise a long runbook into logical sub-blocks, or scope a sub-tree visually for readability.

        ### Input Parameters
        None.

        ### Example Input

        ```json
        {}
        ```

        ### Output
        One output schema, `nested_section`, with no fields.

        ### Example Output

        ```json
        {}
        ```

        ### Error Handling
        None — Section has no failure modes of its own.

        ### Best Practices
        - Use Section purely for organisation. Variables, retries, and error handling all live in dedicated actions; Section adds no semantics beyond grouping.
      END_OF_DESCRIPTION
      nested true

      output_schema 'nested_section' do
        name ''
      end

      run do
        [{ schema_reference: 'nested_section', output: {} }]
      end
    end

    action 'a9e30a7c-3caf-4d71-b629-140e68a20748' do
      name 'Loop'
      avatar '/assets/icons/repeat.svg'
      description <<~END_OF_DESCRIPTION
        Iterates over an array, running the nested sub-block once per item. Each iteration receives the current item and a zero-based index.

        **Use case**: process each row of an upstream query result, send one notification per recipient, or apply a transformation to each entry of a list.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |---|---|---|---|---|
        | `items` | Array of Any | No | - | The list to iterate. Each entry triggers one iteration. An empty array runs the nested sub-block zero times. |

        ### Example Input

        ```json
        { "items": ["foo", "bar", "baz"] }
        ```

        ### Output
        One output schema, `loop`, fired once per item:

        | Field | Type | Required | Description |
        |---|---|---|---|
        | `item` | Any | Yes | The current entry. |
        | `index` | Integer | Yes | Zero-based position in `items`. |

        ### Example Output

        Per-iteration outputs for the input above:

        ```json
        [
          { "item": "foo", "index": 0 },
          { "item": "bar", "index": 1 },
          { "item": "baz", "index": 2 }
        ]
        ```

        ### Error Handling
        An empty or absent `items` array yields zero iterations — the nested sub-block does not run and no error is raised.

        ### Best Practices
        - Iterations run sequentially. For independent work, use **Fork** when the count is fixed.
        - When each item drives an external API call and the target API supports bulk requests, use **Batch** to amortise per-call overhead.
      END_OF_DESCRIPTION
      nested true

      input_schema do
        field :items,
              'Items',
              :any_item_type,
              array: true
      end

      output_schema 'loop' do
        name 'For each item'
        field :item,
              'Item',
              :any_item_type,
              required: true
        field :index,
              'Index',
              :integer,
              required: true,
              hint: 'Zero based index.'
      end

      run do
        items = action.input[:items]
        items.map.with_index do |item, index|
          output = { item: item, index: index }
          { schema_reference: 'loop', output: output }
        end
      end
    end

    action '7c07f696-e14a-4b18-8f39-39f01908f3f0' do
      name 'Batch'
      avatar '/assets/icons/repeat-1.svg'
      description <<~END_OF_DESCRIPTION
        Splits an array into fixed-size chunks and runs the nested sub-block once per chunk. The final chunk may be smaller.

        **Use case**: feed a bulk-write endpoint that accepts an array of items per call (e.g. "update up to 100 records per request"), or amortise per-call overhead across many small items.

        ### Input Parameters

        | Parameter | Type | Required | Min | Description |
        |---|---|---|---|---|
        | `items` | Array of Any | Yes | - | The source array to chunk. |
        | `batch_size` | Integer | Yes | `2` | Items per chunk. |

        ### Example Input

        ```json
        { "items": [1, 2, 3, 4, 5], "batch_size": 2 }
        ```

        ### Output
        One output schema, `batch`, fired once per chunk:

        | Field | Type | Required | Description |
        |---|---|---|---|
        | `items` | Array of Any | Yes | The items in this chunk. The final chunk may contain fewer than `batch_size` items. |

        ### Example Output

        Per-chunk outputs for the input above:

        ```json
        [
          { "items": [1, 2] },
          { "items": [3, 4] },
          { "items": [5] }
        ]
        ```

        ### Error Handling
        Missing `items` or `batch_size`, or `batch_size < 2`, fails input validation. An empty `items` array yields zero chunks.

        ### Best Practices
        - Match `batch_size` to the target API's bulk-endpoint maximum (e.g. 100 for many REST APIs, 25 for AWS DynamoDB `BatchWriteItem`).
        - Downstream actions should treat the per-chunk `items.size` as variable — it equals `batch_size` for every chunk except, potentially, the last.
      END_OF_DESCRIPTION
      nested true

      input_schema do
        field :items,
              'Items',
              :any_item_type,
              required: true,
              array: true
        field :batch_size,
              'Batch size',
              :integer,
              required: true,
              min: 2
      end

      output_schema 'batch' do
        name 'For each batch'
        field :items,
              'Items',
              :any_item_type,
              required: true,
              array: true
      end

      run do
        items = action.input[:items]
        result = []
        items.each_slice(action.input[:batch_size]) do |batch|
          output = { items: batch }
          result << { schema_reference: 'batch', output: output }
        end
        result
      end
    end

    action '0198371d-7927-792f-84fa-5b60337cb7e0' do
      name 'Fail'
      avatar '/assets/icons/stop-exclaim.svg'
      description <<~END_OF_DESCRIPTION
        Stops the runbook and marks the run as **Failed**, with an optional message logged to the run.

        **Use case**: assert an invariant — fail the run if upstream data is missing, malformed, or violates a business rule.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |---|---|---|---|---|
        | `message` | String | No | `Stopped` | Text logged on failure. |

        ### Example Input

        ```json
        { "message": "No matching account found for the supplied ID" }
        ```

        ### Output
        None — the action terminates the runbook and the run ends in the **Failed** state.

        ### Example Output
        Not applicable.

        ### Error Handling
        Always terminates the runbook with `message`. The run ends in the **Failed** state.

        ### Best Practices
        - Pair Fail with **If-then-else** or **Case** — branch into Fail when an invariant breaks, rather than letting an unhelpful runtime error surface later.
        - Make `message` actionable: include the failing value, not just `"validation failed"`.
      END_OF_DESCRIPTION

      input_schema do
        field :message,
              'Message',
              :string,
              hint: <<~END_OF_HINT,
                Text to log on stop.
              END_OF_HINT
              default: 'Stopped'
      end

      output_schema do
        name 'This action has no output'
      end

      run do
        fail_job!(action.input.fetch(:message, ''))
        [{ output: {} }]
      end
    end

    action '0198371e-7927-792f-84fa-5b60337cb7e0' do
      name 'Finish'
      avatar '/assets/icons/finish.svg'
      description <<~END_OF_DESCRIPTION
        Stops the runbook and marks the run as successfully **Finished** at this step. Logs `message` to the run.

        **Use case**: short-circuit out of a runbook when there is no further work to do — e.g. an early return after detecting a no-op condition.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |---|---|---|---|---|
        | `message` | String | Yes | `Runbook execution completed` | Text logged on completion. |

        ### Example Input

        ```json
        { "message": "Already up to date — nothing to do" }
        ```

        ### Output
        None — the action logs `message` and terminates the runbook. The run ends in the **Finished** state.

        ### Example Output
        Not applicable.

        ### Error Handling
        Always terminates the runbook with `message`. This is a successful exit — the run is marked Finished, not Failed.

        ### Best Practices
        - Use Finish only for clean, intentional early exits. For unexpected conditions, use **Fail** so the run is recorded as failed.
        - Make `message` describe **why** the runbook is exiting — operators see this in the run log.
      END_OF_DESCRIPTION

      input_schema do
        field :message,
              'Message',
              :string,
              hint: <<~END_OF_HINT,
                Text to log on completion.
              END_OF_HINT
              default: 'Runbook execution completed',
              required: true
      end

      output_schema do
        name 'This action has no output'
      end

      run do
        finish_job!(input[:message])
        [{ output: {} }]
      end
    end

    action '322bb36b-863f-4b31-a677-bb9c927c9202' do
      name 'try-catch'
      avatar '/assets/icons/try-catch.svg'
      description <<~END_OF_DESCRIPTION
        Wraps a `Try` sub-block in error handling. If any action inside `Try` raises, the runbook engine re-runs this action and routes execution down the `Catch` sub-block, passing the error message.

        **Use case**: handle expected failures from external systems — a 4xx response, a missing record, a transient network error — without failing the whole runbook.

        ### Input Parameters
        None.

        ### Example Input

        ```json
        {}
        ```

        ### Output
        Two output schemas — `try` and `catch`. Exactly one fires per invocation.

        `try` schema — no fields.

        `catch` schema:

        | Field | Type | Required | Description |
        |---|---|---|---|
        | `error` | String | Yes | Error message from the action that raised inside `Try`. |

        ### Example Output

        `try` schema (no error inside Try):

        ```json
        {}
        ```

        `catch` schema (an action inside Try raised):

        ```json
        { "error": "Something went wrong" }
        ```

        ### Error Handling
        Routing is automatic. On the first invocation the `Try` schema fires. If a child action of `Try` raises, the runbook engine re-invokes Try-catch with internal state set so the `Catch` schema fires next, with `error` populated from the raised exception's message. Exceptions outside the `Try` sub-block are not caught.

        ### Best Practices
        - Catch only failures you know how to handle. Letting an unrecoverable error surface is usually safer than catching it and continuing on bad data.
        - Pair Try-catch with **Retry** at the end of the `Catch` sub-block to re-run `Try` after a remediation step. Without **Retry**, execution falls through to the next sibling action after `Catch` completes.
        - The `error` field is a string — to retain structured information, encode it into the message at the source (e.g. JSON-encode a hash before raising).
      END_OF_DESCRIPTION
      nested true

      output_schema 'try' do
        name 'Try'
      end

      output_schema 'catch' do
        name 'Catch'
        field :error,
              'Error Message',
              :string,
              required: true
      end

      iteration_state_schema do
        field :condition,
              'Condition',
              :boolean,
              hint: 'Automatically set to true when the action is retried ' \
                    'due to an exception in the try block, so that the catch block will be executed.'
        field :error_message,
              'Error Message',
              :string,
              hint: 'Contains the error message when retrying with condition=true to execute catch block.'
      end

      run do
        iteration_state = self.iteration_state_value || {}
        condition = iteration_state[:condition].nil? || iteration_state[:condition] == 'false'
        error_message = iteration_state[:error_message]

        self.iteration_state_value = nil

        schema_reference = condition ? 'try' : 'catch'
        output = condition ? {} : { error: error_message.to_s }

        [{ schema_reference: schema_reference, output: output }]
      end
    end

    action '0075802a-b2da-7e8a-98e0-f235b0962e8c' do
      name 'Retry'
      avatar '/assets/icons/rescue.svg'
      description <<~END_OF_DESCRIPTION
        Re-runs the surrounding **Try-catch** action's `Try` sub-block. Must be placed inside a `Catch` sub-block.

        **Use case**: handle transient failures by re-attempting the original operation after the catch path has logged or remediated the error.

        ### Input Parameters
        None.

        ### Example Input

        ```json
        {}
        ```

        ### Output
        A single output schema with no fields.

        ### Example Output

        ```json
        {}
        ```

        ### Error Handling
        When reached inside a `Catch` sub-block, control returns to the surrounding `Try` sub-block. Placed outside a `Catch` block, Retry has no error-handling effect — it simply exits with an empty output.

        ### Best Practices
        - The classic transient-retry pattern is: **Try-catch** with the flaky action inside `Try`; **Wait** at the start of `Catch` to back off; **Retry** at the end of `Catch` to re-attempt.
        - Guard against infinite retries: combine Retry with a counter (e.g. a runbook variable incremented in the catch path) and switch to **Fail** once a retry budget is exhausted.
      END_OF_DESCRIPTION

      output_schema do
      end

      run do
        [{ output: {} }]
      end
    end

    action '019b0c4b-0789-74be-9b0e-0d8ef303746c' do
      name 'Wait'
      avatar '/assets/icons/clock.svg'
      description <<~END_OF_DESCRIPTION
        Pauses the runbook for at least `seconds_to_wait` seconds before continuing. Reports the actual elapsed time.

        **Use case**: insert a deliberate delay between actions — back off before retrying, give an upstream system time to settle, or schedule the next step.

        ### Input Parameters

        | Parameter | Type | Required | Min | Description |
        |---|---|---|---|---|
        | `seconds_to_wait` | Integer | Yes | `0` | Minimum number of seconds to wait. The actual wait may be longer; never shorter. |

        ### Example Input

        ```json
        { "seconds_to_wait": 60 }
        ```

        ### Output
        One output schema, `actual`:

        | Field | Type | Required | Description |
        |---|---|---|---|
        | `started_at` | Time | Yes | When the wait began. |
        | `requested_wait` | Integer | Yes | The configured `seconds_to_wait`. |
        | `completed_at` | Time | Yes | When the wait ended. |
        | `actual_wait` | Integer | Yes | Seconds elapsed between `started_at` and `completed_at`. Always `>= requested_wait`. |

        ### Example Output

        ```json
        {
          "started_at": "2026-04-28T09:00:00Z",
          "requested_wait": 60,
          "completed_at": "2026-04-28T09:01:02Z",
          "actual_wait": 62
        }
        ```

        ### Error Handling
        When `seconds_to_wait > 0`, the first invocation suspends the action on the queue and returns no output. The runbook engine resumes the action after the wait elapses, at which point the `actual` schema fires with the timing fields above. When `seconds_to_wait` is `0`, the action completes on the first invocation with `started_at == completed_at`.

        ### Best Practices
        - `actual_wait` can exceed `requested_wait` because the engine schedules pickup on its own queue. Branch on `actual_wait` if exact timing matters downstream.
        - For exponential backoff inside a retry loop, drive `seconds_to_wait` from a runbook variable and double it each iteration.
      END_OF_DESCRIPTION
      nested true

      input_schema do
        field :seconds_to_wait, 'Seconds to wait', :integer,
              min: 0,
              required: true,
              hint: <<~END_OF_HINT
                The minimum number of seconds to wait before the next action is executed.
                Please note the actual wait duration may be longer than this value.
              END_OF_HINT
      end

      iteration_state_schema do
        field :started_at, 'Started at', :time, required: true
      end

      output_schema 'actual' do
        field :started_at, 'Started at', :time,
              required: true,
              hint: <<~END_OF_HINT
                The time this action was started, i.e. when waiting started.
              END_OF_HINT
        field :requested_wait, 'Seconds requested to wait', :integer,
              required: true,
              hint: <<~END_OF_HINT
                The minimum number of seconds this action was configured to wait,
                i.e. the 'Seconds to wait' input value.
              END_OF_HINT
        field :completed_at, 'Completed at', :time,
              required: true,
              hint: <<~END_OF_HINT
                The time this action completed, i.e. when waiting stopped.
              END_OF_HINT
        field :actual_wait, 'Seconds waited', :integer,
              required: true,
              hint: <<~END_OF_HINT
                The actual number of seconds waited because of this action.
                This will at least be the number of seconds requested, but it can be more.
              END_OF_HINT
      end

      run do
        started_at = iteration_state_value(:started_at)
        seconds_to_wait = action.input[:seconds_to_wait]
        if started_at.nil? && seconds_to_wait > 0
          self.iteration_state_value = { started_at: Time.current }
          backoff(retry_after: seconds_to_wait.seconds)
        end

        self.iteration_state_value = nil
        completed_at = Time.current
        started_at = started_at&.to_datetime
        started_at ||= completed_at
        [{ schema_reference: 'actual',
           output: {
             started_at: started_at,
             requested_wait: seconds_to_wait,
             completed_at: completed_at,
             actual_wait: completed_at - started_at,
           }, }]
      end
    end
  end
end

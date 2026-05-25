class SchedulerConnector < IPaaS::Connector::Definition
  connector '05901261-4073-4e5b-91b2-5f533935ddae' do
    name 'Scheduler'
    avatar '/assets/icons/clock.svg'
    description <<~'END_OF_DESCRIPTION'
      ## Overview
      Runs runbooks on a recurring or one-off schedule. The connector exposes two triggers — **Scheduler** for runbooks whose schedule is configured statically on the trigger, and **Dynamic Scheduler** for runbooks whose schedules are created, updated, and deleted at runtime by other runbooks — plus three actions (**Create Schedule**, **Update Schedule**, **Delete Schedule**) that manage schedules pointing at Dynamic Scheduler runbooks. Schedules are persisted in iPaaS and dispatched by the platform's internal scheduler service; no external service is called.

      ## Prerequisites
      - Access to the Xurrent runbook builder.
      - For **Dynamic Scheduler** workflows, the runbook being scheduled must already exist in the same solution and use the **Dynamic Scheduler** trigger; the manager runbook references it by `runbook_uuid`.

      ## Authentication
      None — this connector runs in-process against the current solution's schedule store. No connection needs to be configured.

      ## Triggers

      ### Scheduler
      Triggers the runbook on the recurrence configured on the trigger itself. When the runbook is provisioned, a schedule record is created from the trigger config; when the runbook is deprovisioned, the schedule is soft-deleted. The trigger is internal — the dispatch is performed by the platform's scheduler service, not by an external HTTP caller.

      **Use case**: run a runbook every 15 minutes, every weekday at 09:00, on the first of every month, etc., where the cadence is known at design time and lives with the runbook.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |---|---|---|---|---|
      | `schedule` | Recurrence | Yes | - | Recurrence definition for the runbook. See **Schedule (Recurrence) object fields** below. |
      | `request_body` | Hash | No | - | Optional JSON body merged into the request that fires the runbook. Surfaces under `body` on each run alongside the platform-injected `schedule_reference`. |

      ##### Schedule (Recurrence) object fields

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `frequency` | String | Yes | One of `no_repeat`, `minutely`, `hourly`, `daily`, `weekly`, `monthly`, `yearly`. |
      | `disabled` | Boolean | No | When `true`, the schedule is paused — no occurrences fire until it is re-enabled. The reference is preserved. |
      | `interval` | Integer | When `frequency != no_repeat` | Cadence multiplier. `>= 1`. E.g. `frequency: weekly, interval: 2` runs every two weeks. |
      | `time_zone` | String | When `frequency != no_repeat` | IANA time zone name (e.g. `"UTC"`, `"Europe/Amsterdam"`). |
      | `time_of_day` | String / Time | When `frequency` is `daily`, `weekly`, `monthly`, or `yearly` | Local time the schedule fires (e.g. `"09:00:00"`). Interpreted in `time_zone`. Optional for `minutely`/`hourly` (defaults to current time). |
      | `start_date` | Date | No | First eligible day for the schedule. Defaults to today when `frequency != no_repeat`. |
      | `end_date` | Date | No | Last eligible day. The schedule disables itself once the next occurrence would fall after `end_date`. Must be `>= start_date`. |
      | `day` | Array of String | When `frequency = weekly` | Weekday names (`monday`…`sunday`) the schedule fires on. |
      | `day_of_week` | Boolean | No | For `monthly` / `yearly`: when `true`, switches the field set to `day_of_week_index` + `day_of_week_day`; when `false`, uses `day_of_month`. |
      | `day_of_month` | Array of Integer | When `frequency = monthly` and `day_of_week = false` | 1–31, or `-1` for the last day of the month. |
      | `day_of_week_index` / `day_of_week_day` | Integer / String | When `frequency` is `monthly` or `yearly` and `day_of_week = true` | E.g. `index: 2, day: "tuesday"` for the second Tuesday. `index` accepts `1`, `2`, `3`, `4`, or `-1` (last). |
      | `month_of_year` | Array of Integer | When `frequency = yearly` | 1–12. |

      #### Example Input

      Trigger configuration on the runbook (every other week on Saturday and Sunday at 16:55:50 UTC):

      ```json
      {
        "schedule": {
          "frequency": "weekly",
          "time_zone": "UTC",
          "interval": 2,
          "day": ["saturday", "sunday"],
          "time_of_day": "16:55:50"
        },
        "request_body": { "source": "scheduler" }
      }
      ```

      #### Output

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `body` | Hash | No | The request body the scheduler dispatched to the runbook. Includes the platform-injected `schedule_reference` and any keys from `request_body` on the trigger config. |
      | `triggered_at` | DateTime | Yes | UTC timestamp the runbook was dispatched. |

      #### Example Output

      ```json
      {
        "body": {
          "schedule_reference": "f0b5a7e9-3c52-4e7a-9b2e-2a9c1b1d6e44",
          "source": "scheduler"
        },
        "triggered_at": "2026-04-29T16:55:50Z"
      }
      ```

      #### Error Handling
      - **Provision failure** — if the schedule cannot be persisted (validation error on the recurrence, missing required fields, invalid `frequency`, etc.), provision raises `Failed to register schedule: <error>` and the runbook deployment fails.
      - **Deprovision** — silently no-ops if no `schedule_reference` is stored against the trigger; otherwise performs a soft delete (`deleted: true`).
      - **Invalid recurrence at runtime** — if `next_occurrence_at` cannot be computed (e.g. timeout while computing), the schedule disables itself and the next-occurrence error is recorded on the schedule record.
      - **Dispatch failure** — if dispatching the runbook returns a non-2xx response, the platform's scheduler service records `Runbook execution failed with status <status>` and continues to the next occurrence.

      #### Best Practices
      - Use this trigger when the cadence is owned by the runbook itself. For schedules driven by another runbook (e.g. one schedule per onboarded customer), use **Dynamic Scheduler** plus **Create Schedule**.
      - Set a `time_zone` explicitly. Defaults to the server's `Time.zone`, which is rarely what users expect when reasoning about local fire times.
      - Put run-correlation data (e.g. a tenant ID, environment marker) into `request_body`; the scheduler reference is injected for free as `schedule_reference`.

      ### Dynamic Scheduler
      Triggers a runbook when an external **Create Schedule** action fires its scheduled job. Unlike **Scheduler**, this trigger has no recurrence config of its own — the schedule lives in a separate record created by another runbook calling **Create Schedule**, and the trigger only describes how to extract a job-context identifier from the inbound request.

      **Use case**: run-per-tenant or run-per-resource schedules where the set of schedules changes at runtime — e.g. a manager runbook that creates one schedule per customer onboarded, and a worker runbook (this trigger) that fires when each schedule occurrence dispatches.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |---|---|---|---|---|
      | `job_context_identifier_path` | String | No | - | Dot-path into the inbound request used to derive the runbook's job-context identifier — e.g. `"body.tenant_id"` or `"schedule_reference"`. The path is resolved against `{ body: <parsed JSON>, triggered_at: <DateTime> }`; if the first segment is not a top-level key on that object, `body` is prepended. Resolution failures are logged and the run continues without a context identifier. Optional / hidden by default. |

      #### Example Input

      Trigger configuration on the runbook:

      ```json
      {
        "job_context_identifier_path": "body.schedule_reference"
      }
      ```

      #### Output

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `body` | Hash | No | The request body the scheduler dispatched (includes `schedule_reference` plus any `request_body` set on the originating **Create Schedule** action). |
      | `triggered_at` | DateTime | Yes | UTC timestamp the runbook was dispatched. |

      #### Example Output

      ```json
      {
        "body": {
          "schedule_reference": "tenant-42-daily",
          "tenant_id": "42"
        },
        "triggered_at": "2026-04-29T09:00:00Z"
      }
      ```

      #### Error Handling
      - **Path not present** — the path resolver walks `body` first and falls back to top-level keys; if no key matches, no context identifier is set and the run proceeds normally.
      - **Path traversal error** — if a segment is applied to a non-hash value (e.g. indexing into an array with a string key), the trigger logs `Unable to determine job context identifier. <ErrorClass>: <message>` and the run proceeds without a context identifier.
      - **Empty body** — the trigger accepts empty bodies; `body` is set to the raw value (`nil` or empty string) and `triggered_at` is still emitted.

      #### Best Practices
      - Set `job_context_identifier_path` to a value that uniquely identifies the work item driven by the schedule (e.g. `body.schedule_reference` or `body.tenant_id`); job-context identifiers are how iPaaS deduplicates and correlates concurrent runs.
      - Keep the path stable. Changing it after schedules are live retroactively changes how concurrent runs of the same worker are correlated.
      - When the manager runbook owns the lifecycle, store `schedule_reference` somewhere durable (a runbook variable, a CMDB record) so that **Update Schedule** and **Delete Schedule** can be called against it later.

      ## Actions

      ### Create Schedule
      Creates a new schedule that fires the runbook identified by `runbook_uuid`. The target runbook must be in the same solution and must use the **Dynamic Scheduler** trigger (the platform rejects the call otherwise). On success the action returns the `schedule_reference` (echoed from the input) and the computed `next_occurrence_at`.

      **Use case**: a manager runbook that creates per-tenant or per-resource schedules at runtime — for example, when a new customer is onboarded, create a daily schedule that runs the worker runbook for that customer.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |---|---|---|---|---|
      | `runbook_uuid` | String | Yes | - | UUID of the worker runbook to schedule. Must use the **Dynamic Scheduler** trigger and live in the same solution. |
      | `schedule_reference` | String | Yes | - | Caller-supplied identifier for the schedule, unique per solution. Use this same value to **Update Schedule** or **Delete Schedule** later. |
      | `schedule` | Recurrence | Yes | - | Recurrence definition. Same fields as documented under the **Scheduler** trigger's **Schedule (Recurrence) object fields**. |
      | `request_body` | Hash | No | - | Optional JSON merged into the request body the scheduler dispatches. Available on the worker runbook's `body` output alongside `schedule_reference`. |

      #### Example Input

      ```json
      {
        "runbook_uuid": "7c0d8739-5fbd-4a6f-a1b4-2991bb0e2b54",
        "schedule_reference": "tenant-42-daily",
        "schedule": {
          "frequency": "weekly",
          "time_zone": "UTC",
          "interval": 1,
          "day": ["monday", "wednesday", "friday"],
          "time_of_day": "09:00:00"
        },
        "request_body": { "tenant_id": "42" }
      }
      ```

      #### Output

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `schedule_reference` | String | Yes | Echo of the input `schedule_reference`. Use this to drive subsequent **Update Schedule** / **Delete Schedule** calls. |
      | `next_occurrence_at` | DateTime | No | UTC timestamp of the next computed firing. `null` if the schedule could not compute one (e.g. `end_date` is in the past). |
      | `next_occurrence_errors` | String | No | Human-readable message describing why `next_occurrence_at` is `null` (e.g. `"Timeout Computing next occurrence"`). |

      #### Example Output

      ```json
      {
        "schedule_reference": "tenant-42-daily",
        "next_occurrence_at": "2026-05-01T09:00:00Z",
        "next_occurrence_errors": null
      }
      ```

      #### Error Handling
      - **Unknown runbook** — if `runbook_uuid` does not match a runbook in the current solution, the action fails the job with `Failed to create schedule: No Runbook found`.
      - **Wrong trigger** — if the target runbook does not use a supported scheduler trigger template, the action fails with `Failed to create schedule: Trigger template <uuid> is not supported for scheduling.`
      - **Duplicate reference** — `schedule_reference` must be unique per solution; reusing one fails validation with `Failed to create schedule: ["Reference must be unique per solution"]`.
      - **Invalid recurrence** — missing `frequency` for a recurrent schedule, `interval < 1`, an unknown `frequency`, or invalid `day_of_week`/`month_of_year` values fail validation with the corresponding ActiveRecord error message.

      #### Best Practices
      - Generate `schedule_reference` deterministically from a stable key (e.g. `"tenant-#{id}-daily"`) so the manager runbook can recompute it later without persisting it separately.
      - Capture `next_occurrence_errors` and surface it back to the caller — a successful create with a `null` `next_occurrence_at` means the schedule was registered but will never fire as configured.
      - Pass tenant/resource identifiers through `request_body` rather than encoding them into `schedule_reference`; the worker runbook reads them from `body` directly.

      ### Update Schedule
      Replaces the recurrence on an existing schedule identified by `schedule_reference`. Pending dispatches enqueued before the update are unscheduled so the new recurrence takes effect immediately.

      **Use case**: change the cadence of a previously created schedule — e.g. shift a customer's nightly run from 02:00 to 04:00 after their time zone changes, or pause a schedule by setting `disabled: true` on the recurrence.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |---|---|---|---|---|
      | `schedule_reference` | String | Yes | - | The `schedule_reference` returned by **Create Schedule**. Scoped to the current solution. |
      | `schedule` | Recurrence | Yes | - | New recurrence definition. Treated as a full replacement — frequency-irrelevant fields are cleared (e.g. switching to `weekly` clears `day_of_month`), and `last_enqueued_for` is reset so the new recurrence fires from its own `start_date`. Same field set as **Create Schedule**. |

      #### Example Input

      ```json
      {
        "schedule_reference": "tenant-42-daily",
        "schedule": {
          "frequency": "weekly",
          "time_zone": "UTC",
          "interval": 1,
          "day": ["monday", "wednesday", "friday"],
          "time_of_day": "09:00:00"
        }
      }
      ```

      #### Output

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `success` | Boolean | Yes | `true` when the schedule was updated. The action fails the job before reaching this output if the update could not be applied. |

      #### Example Output

      ```json
      { "success": true }
      ```

      #### Error Handling
      - **Unknown reference** — `schedule_reference` not found in the current solution (or already soft-deleted) fails the job with `Failed to update schedule: Schedule not found`.
      - **Validation failure** — invalid recurrence values fail with `Failed to update schedule: Schedule update failed`. Schedule fields not provided in `schedule` are reset to their defaults during the update — pass a complete recurrence object, not a partial patch.

      #### Best Practices
      - Treat **Update Schedule** as a full replacement, not a patch. Recompute the entire recurrence from your source of truth before calling.
      - To pause a schedule without losing the reference, **Update Schedule** with `disabled: true` on the recurrence; to resume, send another **Update Schedule** with `disabled: false`.
      - For one-off changes to the next firing only, prefer creating a fresh schedule with **Create Schedule** and deleting the old one — **Update Schedule** clears the queued occurrence and recomputes from the new recurrence's `start_date`.

      ### Delete Schedule
      Soft-deletes the schedule identified by `schedule_reference`. Pending dispatches for the schedule are unscheduled.

      **Use case**: tear down per-tenant schedules when a tenant is offboarded; clean up schedules whose owning resource has been removed.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |---|---|---|---|---|
      | `schedule_reference` | String | Yes | - | The `schedule_reference` returned by **Create Schedule**. Scoped to the current solution. |

      #### Example Input

      ```json
      { "schedule_reference": "tenant-42-daily" }
      ```

      #### Output

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `success` | Boolean | Yes | Always `true` when the action returns. Deletion of a non-existent reference is treated as a no-op. |

      #### Example Output

      ```json
      { "success": true }
      ```

      #### Error Handling
      Soft-delete is idempotent — calling **Delete Schedule** with a `schedule_reference` that does not exist (or is already deleted) returns `{ "success": true }` without error. There are no validation failure modes once `schedule_reference` is provided.

      #### Best Practices
      - Pair **Delete Schedule** with the same idempotency key your manager runbook uses to **Create Schedule**, so reruns of the offboarding flow don't fail when the schedule is already gone.
      - Soft-deleted schedules are filtered out by the model's default scope (`where(deleted: false)`); callers cannot resurrect a deleted reference. To re-enable, **Create Schedule** again with a fresh recurrence.

      ## Best Practices
      - Use the **Scheduler** trigger when the cadence is owned by the runbook (one runbook → one schedule). Use **Dynamic Scheduler** + **Create / Update / Delete Schedule** when schedules are created at runtime (one runbook → many schedules).
      - Use deterministic `schedule_reference` values (e.g. `"tenant-<id>-<purpose>"`) so manager runbooks can update or delete schedules without persisting the reference separately. References must be unique per solution.
      - Always specify `time_zone` explicitly on recurrences — relying on the platform default makes runbook behaviour environment-dependent.
      - Carry tenant/resource identifiers through `request_body`. The worker runbook receives them on its `body` output alongside the platform-injected `schedule_reference`.
      - Set `job_context_identifier_path` on **Dynamic Scheduler** to the field that uniquely identifies the work item (typically `body.schedule_reference` or `body.tenant_id`). Job-context identifiers drive concurrency and correlation for runs of the same worker runbook.
      - Recurrences with `frequency: minutely` or `hourly` self-enqueue the next occurrence after each run. `daily` / `weekly` / `monthly` / `yearly` are batched by the platform's daily enqueuer; expect the first daily-or-coarser run to be dispatched directly only when its first occurrence falls before tomorrow.

      ## Common Use Cases
      - **Recurring runbook on a fixed cadence** — add the **Scheduler** trigger to the runbook, set `frequency`, `interval`, `time_of_day`, and `time_zone`, and provision the runbook. The platform creates the schedule automatically.
      - **Per-tenant scheduled work** — manager runbook calls **Create Schedule** with `schedule_reference: "tenant-<id>-<purpose>"`, `runbook_uuid` of a worker runbook (using the **Dynamic Scheduler** trigger), and `request_body` carrying the tenant ID. The worker runbook reads the tenant ID from `body` on each fire.
      - **Pause / resume an existing schedule** — manager runbook calls **Update Schedule** with the same `schedule_reference` and a recurrence carrying `disabled: true` to pause; send another **Update Schedule** with `disabled: false` to resume.
      - **Bulk teardown on offboarding** — when a tenant is removed, manager runbook iterates the tenant's known schedule references and calls **Delete Schedule** for each. Idempotent, so retries are safe.

      ## References
      - [iCalendar (RFC 5545)](https://www.rfc-editor.org/rfc/rfc5545) — recurrence semantics that the underlying recurrence engine ([ice_cube](https://github.com/seejohnrun/ice_cube)) implements.
      - [IANA Time Zone Database](https://www.iana.org/time-zones) — source of valid `time_zone` values.
    END_OF_DESCRIPTION

    trigger 'd7a8f78f-0909-4269-9473-0b3fdf6fb163' do
      name 'Scheduler'
      avatar '/assets/icons/clock.svg'
      description <<~END_OF_DESCRIPTION
        Triggers the runbook on the recurrence configured on the trigger itself. When the runbook is provisioned, a schedule record is created from the trigger config; when the runbook is deprovisioned, the schedule is soft-deleted. The trigger is internal — the dispatch is performed by the platform's scheduler service, not by an external HTTP caller.

        **Use case**: run a runbook every 15 minutes, every weekday at 09:00, on the first of every month, etc., where the cadence is known at design time and lives with the runbook.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |---|---|---|---|---|
        | `schedule` | Recurrence | Yes | - | Recurrence definition for the runbook. See **Schedule (Recurrence) object fields** below. |
        | `request_body` | Hash | No | - | Optional JSON body merged into the request that fires the runbook. Surfaces under `body` on each run alongside the platform-injected `schedule_reference`. |

        #### Schedule (Recurrence) object fields

        | Field | Type | Required | Description |
        |---|---|---|---|
        | `frequency` | String | Yes | One of `no_repeat`, `minutely`, `hourly`, `daily`, `weekly`, `monthly`, `yearly`. |
        | `disabled` | Boolean | No | When `true`, the schedule is paused — no occurrences fire until it is re-enabled. The reference is preserved. |
        | `interval` | Integer | When `frequency != no_repeat` | Cadence multiplier. `>= 1`. E.g. `frequency: weekly, interval: 2` runs every two weeks. |
        | `time_zone` | String | When `frequency != no_repeat` | IANA time zone name (e.g. `"UTC"`, `"Europe/Amsterdam"`). |
        | `time_of_day` | String / Time | When `frequency` is `daily`, `weekly`, `monthly`, or `yearly` | Local time the schedule fires (e.g. `"09:00:00"`). Interpreted in `time_zone`. Optional for `minutely`/`hourly` (defaults to current time). |
        | `start_date` | Date | No | First eligible day for the schedule. Defaults to today when `frequency != no_repeat`. |
        | `end_date` | Date | No | Last eligible day. The schedule disables itself once the next occurrence would fall after `end_date`. Must be `>= start_date`. |
        | `day` | Array of String | When `frequency = weekly` | Weekday names (`monday`…`sunday`) the schedule fires on. |
        | `day_of_week` | Boolean | No | For `monthly` / `yearly`: when `true`, switches the field set to `day_of_week_index` + `day_of_week_day`; when `false`, uses `day_of_month`. |
        | `day_of_month` | Array of Integer | When `frequency = monthly` and `day_of_week = false` | 1–31, or `-1` for the last day of the month. |
        | `day_of_week_index` / `day_of_week_day` | Integer / String | When `frequency` is `monthly` or `yearly` and `day_of_week = true` | E.g. `index: 2, day: "tuesday"` for the second Tuesday. `index` accepts `1`, `2`, `3`, `4`, or `-1` (last). |
        | `month_of_year` | Array of Integer | When `frequency = yearly` | 1–12. |

        ### Example Input

        Trigger configuration on the runbook (every other week on Saturday and Sunday at 16:55:50 UTC):

        ```json
        {
          "schedule": {
            "frequency": "weekly",
            "time_zone": "UTC",
            "interval": 2,
            "day": ["saturday", "sunday"],
            "time_of_day": "16:55:50"
          },
          "request_body": { "source": "scheduler" }
        }
        ```

        ### Output

        | Field | Type | Required | Description |
        |---|---|---|---|
        | `body` | Hash | No | The request body the scheduler dispatched to the runbook. Includes the platform-injected `schedule_reference` and any keys from `request_body` on the trigger config. |
        | `triggered_at` | DateTime | Yes | UTC timestamp the runbook was dispatched. |

        ### Example Output

        ```json
        {
          "body": {
            "schedule_reference": "f0b5a7e9-3c52-4e7a-9b2e-2a9c1b1d6e44",
            "source": "scheduler"
          },
          "triggered_at": "2026-04-29T16:55:50Z"
        }
        ```

        ### Error Handling
        - **Provision failure** — if the schedule cannot be persisted (validation error on the recurrence, missing required fields, invalid `frequency`, etc.), provision raises `Failed to register schedule: <error>` and the runbook deployment fails.
        - **Deprovision** — silently no-ops if no `schedule_reference` is stored against the trigger; otherwise performs a soft delete (`deleted: true`).
        - **Invalid recurrence at runtime** — if `next_occurrence_at` cannot be computed (e.g. timeout while computing), the schedule disables itself and the next-occurrence error is recorded on the schedule record.
        - **Dispatch failure** — if dispatching the runbook returns a non-2xx response, the platform's scheduler service records `Runbook execution failed with status <status>` and continues to the next occurrence.

        ### Best Practices
        - Use this trigger when the cadence is owned by the runbook itself. For schedules driven by another runbook (e.g. one schedule per onboarded customer), use **Dynamic Scheduler** plus **Create Schedule**.
        - Set a `time_zone` explicitly. Defaults to the server's `Time.zone`, which is rarely what users expect when reasoning about local fire times.
        - Put run-correlation data (e.g. a tenant ID, environment marker) into `request_body`; the scheduler reference is injected for free as `schedule_reference`.
      END_OF_DESCRIPTION
      internal_only true

      config_schema do
        field :schedule,
              'Schedule',
              :recurrence,
              required: true

        field :request_body, 'Request Body', :hash
      end

      output_schema do
        field :body, 'Body', :hash
        field :triggered_at, 'Triggered at', :date_time, required: true
      end

      provision do
        schedule_reference = trigger.store.read('schedule_reference')
        next if schedule_reference

        schedule_attributes = trigger.config[:schedule].to_hash.merge(
          reference: SecureRandom.uuid,
          request_body: trigger.config[:request_body]
        ).compact

        result = solution.create_schedule!(runbook.uuid, schedule_attributes)
        fail_job!("Failed to register schedule: #{result[:error]}") unless result[:success]

        schedule_reference = result[:schedule_reference]
        log('Schedule registered as %<reference>s', { reference: schedule_reference })
        trigger.store.write('schedule_reference', schedule_reference)
      end

      deprovision do
        schedule_reference = trigger.store.read('schedule_reference')
        next unless schedule_reference

        solution.soft_delete_schedule(schedule_reference)

        log('Unregistered schedule %<reference>s', { reference: schedule_reference })
        trigger.store.delete('schedule_reference')
      end

      parse do |request|
        body_content = request.body&.read
        body = body_content.present? ? JSON.parse(body_content) : body_content

        {
          body: body,
          triggered_at: DateTime.current,
        }
      end

      # protection_profile :high_volume
    end

    trigger '019898e9-8b75-7116-97a8-9630b10262c9' do
      name 'Dynamic Scheduler'
      avatar '/assets/icons/clock.svg'
      description <<~END_OF_DESCRIPTION
        Triggers a runbook when an external **Create Schedule** action fires its scheduled job. Unlike **Scheduler**, this trigger has no recurrence config of its own — the schedule lives in a separate record created by another runbook calling **Create Schedule**, and the trigger only describes how to extract a job-context identifier from the inbound request.

        **Use case**: run-per-tenant or run-per-resource schedules where the set of schedules changes at runtime — e.g. a manager runbook that creates one schedule per customer onboarded, and a worker runbook (this trigger) that fires when each schedule occurrence dispatches.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |---|---|---|---|---|
        | `job_context_identifier_path` | String | No | - | Dot-path into the inbound request used to derive the runbook's job-context identifier — e.g. `"body.tenant_id"` or `"schedule_reference"`. The path is resolved against `{ body: <parsed JSON>, triggered_at: <DateTime> }`; if the first segment is not a top-level key on that object, `body` is prepended. Resolution failures are logged and the run continues without a context identifier. Optional / hidden by default. |

        ### Example Input

        Trigger configuration on the runbook:

        ```json
        {
          "job_context_identifier_path": "body.schedule_reference"
        }
        ```

        ### Output

        | Field | Type | Required | Description |
        |---|---|---|---|
        | `body` | Hash | No | The request body the scheduler dispatched (includes `schedule_reference` plus any `request_body` set on the originating **Create Schedule** action). |
        | `triggered_at` | DateTime | Yes | UTC timestamp the runbook was dispatched. |

        ### Example Output

        ```json
        {
          "body": {
            "schedule_reference": "tenant-42-daily",
            "tenant_id": "42"
          },
          "triggered_at": "2026-04-29T09:00:00Z"
        }
        ```

        ### Error Handling
        - **Path not present** — the path resolver walks `body` first and falls back to top-level keys; if no key matches, no context identifier is set and the run proceeds normally.
        - **Path traversal error** — if a segment is applied to a non-hash value (e.g. indexing into an array with a string key), the trigger logs `Unable to determine job context identifier. <ErrorClass>: <message>` and the run proceeds without a context identifier.
        - **Empty body** — the trigger accepts empty bodies; `body` is set to the raw value (`nil` or empty string) and `triggered_at` is still emitted.

        ### Best Practices
        - Set `job_context_identifier_path` to a value that uniquely identifies the work item driven by the schedule (e.g. `body.schedule_reference` or `body.tenant_id`); job-context identifiers are how iPaaS deduplicates and correlates concurrent runs.
        - Keep the path stable. Changing it after schedules are live retroactively changes how concurrent runs of the same worker are correlated.
        - When the manager runbook owns the lifecycle, store `schedule_reference` somewhere durable (a runbook variable, a CMDB record) so that **Update Schedule** and **Delete Schedule** can be called against it later.
      END_OF_DESCRIPTION
      internal_only true

      config_schema do
        field :job_context_identifier_path, 'Job Context Identifier Path', :string,
              visibility: 'optional',
              hint: 'Path to a field inside the trigger output which will be used as job context identifier.'
      end

      output_schema do
        field :body, 'Body', :hash
        field :triggered_at, 'Triggered at', :date_time, required: true
      end

      parse do |request|
        body_content = request.body&.read
        body = body_content.present? ? JSON.parse(body_content) : body_content

        {
          body: body,
          triggered_at: DateTime.current,
        }.tap do |trigger_output|
          if config[:job_context_identifier_path].present?
            begin
              hash = trigger_output.with_indifferent_access
              path = config[:job_context_identifier_path].split('.')
              path = [:body] + path unless hash.key?(path.first)
              context_id = hash.dig(*path)
              self.job_context_identifier = context_id
            rescue StandardError => e
              log('Unable to determine job context identifier. %<error>s', { error: "#{e.class}: #{e.message}" })
            end
          end
        end
      end
    end

    action '0198990a-a98e-7cce-a3ab-7311c2a22c36' do
      name 'Create Schedule'
      avatar '/assets/icons/clock-plus.svg'
      description <<~'END_OF_DESCRIPTION'
        Creates a new schedule that fires the runbook identified by `runbook_uuid`. The target runbook must be in the same solution and must use the **Dynamic Scheduler** trigger (the platform rejects the call otherwise). On success the action returns the `schedule_reference` (echoed from the input) and the computed `next_occurrence_at`.

        **Use case**: a manager runbook that creates per-tenant or per-resource schedules at runtime — for example, when a new customer is onboarded, create a daily schedule that runs the worker runbook for that customer.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |---|---|---|---|---|
        | `runbook_uuid` | String | Yes | - | UUID of the worker runbook to schedule. Must use the **Dynamic Scheduler** trigger and live in the same solution. |
        | `schedule_reference` | String | Yes | - | Caller-supplied identifier for the schedule, unique per solution. Use this same value to **Update Schedule** or **Delete Schedule** later. |
        | `schedule` | Recurrence | Yes | - | Recurrence definition. Same fields as the **Scheduler** trigger's `schedule` config — see the connector's **Schedule (Recurrence) object fields** for the full set. |
        | `request_body` | Hash | No | - | Optional JSON merged into the request body the scheduler dispatches. Available on the worker runbook's `body` output alongside `schedule_reference`. |

        ### Example Input

        ```json
        {
          "runbook_uuid": "7c0d8739-5fbd-4a6f-a1b4-2991bb0e2b54",
          "schedule_reference": "tenant-42-daily",
          "schedule": {
            "frequency": "weekly",
            "time_zone": "UTC",
            "interval": 1,
            "day": ["monday", "wednesday", "friday"],
            "time_of_day": "09:00:00"
          },
          "request_body": { "tenant_id": "42" }
        }
        ```

        ### Output

        | Field | Type | Required | Description |
        |---|---|---|---|
        | `schedule_reference` | String | Yes | Echo of the input `schedule_reference`. Use this to drive subsequent **Update Schedule** / **Delete Schedule** calls. |
        | `next_occurrence_at` | DateTime | No | UTC timestamp of the next computed firing. `null` if the schedule could not compute one (e.g. `end_date` is in the past). |
        | `next_occurrence_errors` | String | No | Human-readable message describing why `next_occurrence_at` is `null` (e.g. `"Timeout Computing next occurrence"`). |

        ### Example Output

        ```json
        {
          "schedule_reference": "tenant-42-daily",
          "next_occurrence_at": "2026-05-01T09:00:00Z",
          "next_occurrence_errors": null
        }
        ```

        ### Error Handling
        - **Unknown runbook** — if `runbook_uuid` does not match a runbook in the current solution, the action fails the job with `Failed to create schedule: No Runbook found`.
        - **Wrong trigger** — if the target runbook does not use a supported scheduler trigger template, the action fails with `Failed to create schedule: Trigger template <uuid> is not supported for scheduling.`
        - **Duplicate reference** — `schedule_reference` must be unique per solution; reusing one fails validation with `Failed to create schedule: ["Reference must be unique per solution"]`.
        - **Invalid recurrence** — missing `frequency` for a recurrent schedule, `interval < 1`, an unknown `frequency`, or invalid `day_of_week`/`month_of_year` values fail validation with the corresponding ActiveRecord error message.

        ### Best Practices
        - Generate `schedule_reference` deterministically from a stable key (e.g. `"tenant-#{id}-daily"`) so the manager runbook can recompute it later without persisting it separately.
        - Capture `next_occurrence_errors` and surface it back to the caller — a successful create with a `null` `next_occurrence_at` means the schedule was registered but will never fire as configured.
        - Pass tenant/resource identifiers through `request_body` rather than encoding them into `schedule_reference`; the worker runbook reads them from `body` directly.
      END_OF_DESCRIPTION

      input_schema do
        field :runbook_uuid, 'Runbook UUID', :string, required: true, hint: 'The UUID of the runbook to schedule'
        field :schedule_reference,
              'Schedule Reference',
              :string,
              required: true,
              hint: 'A unique identifier for this schedule (scoped per solution)
                     which can be used in Delete Schedule action'
        field :schedule, 'Schedule', :recurrence, required: true
        field :request_body, 'Request Body', :hash
      end

      output_schema do
        field :schedule_reference, 'Schedule Reference', :string, required: true
        field :next_occurrence_at, 'Next Occurrence At', :date_time
        field :next_occurrence_errors, 'NextOccurrence Errors', :string
      end

      run do
        schedule_attributes = action.input[:schedule].to_hash.merge(
          reference: action.input[:schedule_reference],
          request_body: action.input[:request_body]
        ).compact

        result = create_schedule!(action.input[:runbook_uuid], schedule_attributes)
        fail_job!("Failed to create schedule: #{result[:error]}") unless result[:success]
        output = result.slice(:next_occurrence_at, :schedule_reference, :next_occurrence_errors)

        [{ output: output }]
      end
    end

    action '0198990a-c37a-706d-b7c4-9859f95d6685' do
      name 'Delete Schedule'
      avatar '/assets/icons/clock-cancel.svg'
      description <<~END_OF_DESCRIPTION
        Soft-deletes the schedule identified by `schedule_reference`. Pending dispatches for the schedule are unscheduled.

        **Use case**: tear down per-tenant schedules when a tenant is offboarded; clean up schedules whose owning resource has been removed.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |---|---|---|---|---|
        | `schedule_reference` | String | Yes | - | The `schedule_reference` returned by **Create Schedule**. Scoped to the current solution. |

        ### Example Input

        ```json
        { "schedule_reference": "tenant-42-daily" }
        ```

        ### Output

        | Field | Type | Required | Description |
        |---|---|---|---|
        | `success` | Boolean | Yes | Always `true` when the action returns. Deletion of a non-existent reference is treated as a no-op. |

        ### Example Output

        ```json
        { "success": true }
        ```

        ### Error Handling
        Soft-delete is idempotent — calling **Delete Schedule** with a `schedule_reference` that does not exist (or is already deleted) returns `{ "success": true }` without error. There are no validation failure modes once `schedule_reference` is provided.

        ### Best Practices
        - Pair **Delete Schedule** with the same idempotency key your manager runbook uses to **Create Schedule**, so reruns of the offboarding flow don't fail when the schedule is already gone.
        - Soft-deleted schedules are filtered out by the model's default scope (`where(deleted: false)`); callers cannot resurrect a deleted reference. To re-enable, **Create Schedule** again with a fresh recurrence.
      END_OF_DESCRIPTION

      input_schema do
        field :schedule_reference, 'Schedule Reference', :string, required: true
      end

      output_schema do
        field :success, 'Success', :boolean, required: true
      end

      run do
        soft_delete_schedule(action.input[:schedule_reference])
        [{ output: { success: true } }]
      end
    end

    action '6f498dde-8195-494b-95b3-8bb0d2b6eb68' do
      name 'Update Schedule'
      avatar '/assets/icons/clock-edit.svg'
      description <<~END_OF_DESCRIPTION
        Replaces the recurrence on an existing schedule identified by `schedule_reference`. Pending dispatches enqueued before the update are unscheduled so the new recurrence takes effect immediately.

        **Use case**: change the cadence of a previously created schedule — e.g. shift a customer's nightly run from 02:00 to 04:00 after their time zone changes, or pause a schedule by setting `disabled: true` on the recurrence.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |---|---|---|---|---|
        | `schedule_reference` | String | Yes | - | The `schedule_reference` returned by **Create Schedule**. Scoped to the current solution. |
        | `schedule` | Recurrence | Yes | - | New recurrence definition. Treated as a full replacement — frequency-irrelevant fields are cleared (e.g. switching to `weekly` clears `day_of_month`), and `last_enqueued_for` is reset so the new recurrence fires from its own `start_date`. Same field set as **Create Schedule**. |

        ### Example Input

        ```json
        {
          "schedule_reference": "tenant-42-daily",
          "schedule": {
            "frequency": "weekly",
            "time_zone": "UTC",
            "interval": 1,
            "day": ["monday", "wednesday", "friday"],
            "time_of_day": "09:00:00"
          }
        }
        ```

        ### Output

        | Field | Type | Required | Description |
        |---|---|---|---|
        | `success` | Boolean | Yes | `true` when the schedule was updated. The action fails the job before reaching this output if the update could not be applied. |

        ### Example Output

        ```json
        { "success": true }
        ```

        ### Error Handling
        - **Unknown reference** — `schedule_reference` not found in the current solution (or already soft-deleted) fails the job with `Failed to update schedule: Schedule not found`.
        - **Validation failure** — invalid recurrence values fail with `Failed to update schedule: Schedule update failed`. Frequency-irrelevant fields are cleared as part of the update (e.g. switching to `weekly` clears `day_of_month`), so pass a complete recurrence object rather than a partial patch.

        ### Best Practices
        - Treat **Update Schedule** as a full replacement, not a patch. Recompute the entire recurrence from your source of truth before calling.
        - To pause a schedule without losing the reference, **Update Schedule** with `disabled: true` on the recurrence; to resume, send another **Update Schedule** with `disabled: false`.
        - For one-off changes to the next firing only, prefer creating a fresh schedule with **Create Schedule** and deleting the old one — **Update Schedule** clears the queued occurrence and recomputes from the new recurrence's `start_date`.
      END_OF_DESCRIPTION

      input_schema do
        field :schedule_reference, 'Schedule Reference', :string, required: true
        field :schedule, 'Schedule', :recurrence, required: true
      end

      output_schema do
        field :success, 'Success', :boolean, required: true
      end

      run do
        result = update_schedule(action.input[:schedule_reference], action.input[:schedule])
        fail_job!("Failed to update schedule: #{result[:error]}") unless result[:success]

        [{ output: { success: true } }]
      end
    end
  end
end

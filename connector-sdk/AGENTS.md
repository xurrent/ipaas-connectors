# Connector SDK AGENTS.md

## Context

**Project Template for customers** to define their own connectors and test them.

## Rules

1. **Neutrality**: Decoupled from `platform/` internals.
2. **API Stability**: Do not break public API without major version increments.
3. **Docs**: Public methods must have Yard documentation.
4. **Maintenance**: Minimal dependencies.
5. **Defines standard connectors**: [spec/fixtures/**](spec/fixtures/) contains standard connectors provided by Xurrent, copied to platform and (for testing purposes) to connector projects.
6. **Global Rules**: Adhere to [../AGENTS.md](../AGENTS.md).

## Stubbing a shared function in a spec

`helpers` hands a proc a proxy that dispatches registered helper names and nothing else, so it
cannot be stubbed — `allow(trigger.helpers).to receive(:my_helper)` fails with
`Missing helper method '__id__'.` because RSpec cannot introspect it. Nor can anything behind it:
a connector is sealed once it loads, and RSpec refuses to stub a frozen object
(`Cannot proxy frozen objects`).

Stub on the trigger or action instead, which is the solution's own and never sealed: hand it a
stand-in that defines the helpers you stub as real methods and forwards everything else. A proc
resolves `helpers` on the trigger or action it runs on, so connector-level helpers are reached
through the stand-in as well. `HelpersSpy` in
`spec/ipaas/connector/sdk/examples/xurrent-app-connector/shared/app_offering_blueprint_specs.rb`
shows the pattern.

## Constraints the platform enforces before your `run` block

A guard in a `run` block or helper for any of these is dead code, because the action never reaches
it. Verified while building `jamf_connector`.

| Constraint                        | Where           | What you get instead                                                                                                                                                                                          |
| --------------------------------- | --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `min:` / `max:` on an input field | input mapping   | `Action invalid: Input mapping invalid: Field 'page_size' should be at most 100.`                                                                                                                             |
| `enumeration:` on an input field  | input mapping   | the action is invalid; an unlisted value never arrives                                                                                                                                                        |
| `:date_time` input type           | input mapping   | a parseable String is coerced to `DateTime`, an unparseable one is rejected: `Type of field 'updated_since' invalid, expected DateTime found String.`                                                         |
| `:uri` config field               | `config.valid?` | a schemeless URL fails validation, and `config_tester` short-circuits to `Connection configuration is invalid.` before your block runs. `:uri` does accept `http://`, so an https-only check still has a job. |

So clamp nothing you already declared. Supply defaults, and let the mapping reject the rest.

Two hard limits worth knowing before you generate a large schema:

- **A schema field id has a maximum length** (`connector/lib/ipaas/connector/schema/field.rb`, the
  `attribute :id` length validation). An API key whose snake_case form is longer cannot be declared
  at all, and the action fails to validate with `Id is too long`. The value is then **lost**, not
  merely undeclared: record which keys those are and why, next to the constants, and treat it as
  data the runbook cannot have. Read the current limit off that validation rather than assuming a
  number.
- **Every query parameter value must be a String, Symbol or raw-marked**
  (`connector/lib/ipaas/job/outbound/http.rb:151-157`). An Integer raises `Params must be a hash
with symbols, strings or raw-marked values`. Call `.to_s` on page numbers and sizes.

## The schema is the contract, in both directions

Only what a schema declares crosses the boundary. Nested schema fields default to
`remove_unmapped_fields: true`, and `ResolvedMapping` strips every key the schema does not name
(`connector/lib/ipaas/connector/mapping/resolved_mapping.rb:283`). So an API field your
`output_schema` omits does not reach the runbook at all, however faithfully the run block returned
it. The same applies to `input_schema`: a parameter you did not declare cannot be sent.

This is why "every field that CAN appear in ANY response MUST be in output_schema" is a correctness
rule and not a tidiness rule. A missing declaration, or a field id that does not match what
`camel_to_snake` produces, is silent data loss: the runbook reads nil and nothing anywhere errors.

Two practical consequences:

- **Verify field ids against a live response, not against the spec.** Generate them with
  ActiveSupport `#underscore` rather than a hand-rolled snake_case, then diff the ids you declared
  against the keys the API actually returned. `fileVault2Status` becomes `file_vault2_status`, not
  `file_vault_2_status`, and getting it wrong looks exactly like a field the API never sent.
- **A "keys we do not model" log line is worth its cost.** Since undeclared keys vanish, that log
  is the only signal that the API sent something the runbook will never see. Compare against the
  declared ids and log only keys carrying a value, or every top-level section the API returns
  regardless of what you requested will show up as a false positive on every run.

`config_tester` must return `{ status: :success | :failed | :error, message: ... }`
(`connector/lib/ipaas/connector/connection.rb:131-139`). It is not a logging block. `config.valid?`
is checked first and `StandardError` is rescued into `{ status: :error }`, so a `fail_job!` in a
helper it calls becomes a readable customer-facing message.

## `run_action` with no argument does not mean "no input"

`field_mapping(nil, schema:)` falls through to `fixed_mapping(schema.example)`
(`spec/support/field_mapping_helper.rb:6`), so every unmapped field is filled from the schema's
generated example. An optional `:date_time` arrives as a real timestamp and your run block builds
a filter you never asked for.

Pass an explicit hash in every run example:

```ruby
def input(**overrides)
  { sections: nil, page_size: nil, updated_since: nil }.merge(overrides)
end

run_action(input(page_size: 25))
```

Note also that the proc allowlist is only checked when a proc actually runs
(`ValidMethodsRule`), so a method like `zero?` that is not on the list raises
`InvalidProcCalled: Method 'zero?' not allowed` at runtime, not at load. A spec that exercises
every branch is the only thing that catches it.

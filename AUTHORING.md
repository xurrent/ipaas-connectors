# Authoring connectors

A connector is a Ruby file that declares how Xurrent iPaaS talks to one external system: how to authenticate (`connection`), what events the system can send in (`trigger_templates`), and what operations a runbook can invoke against it (`action_templates`).

The `ipaas-connector` gem in the [`connector/`](./connector) directory of this repository ships a small Ruby DSL for those declarations. Subclassing `IPaaS::Connector::Definition` opens up the methods you'll see throughout this guide: `connector`, `inbound_connection`, `outbound_connection`, `trigger_template`, `action_template`, `helper`, and the schema-building helpers. Everything else is plain Ruby running inside the sandbox described below. The DSL source lives under `connector/lib/ipaas/connector/`; the field types, authenticator and validator presets, and the helpers mixin are all there if you want to read along.

This guide covers how the files fit together, the constraints the runtime puts on connector code, and the conventions for tests. It assumes you've forked the public mirror (or copied the `connector-sdk/` layout into your own project) and already know basic Ruby.

## Where things live

A connector typically owns four files:

| File | Purpose |
|---|---|
| `connector-sdk/spec/fixtures/<name>_connector.rb` | The connector definition: the source of truth. The SDK loads it; the specs exercise it. |
| `connector-sdk/spec/ipaas/connector/sdk/examples/<name>_connector/<thing>_spec.rb` | One spec per trigger, action, or connection. |
| `connector-sdk/spec/support/shared_contexts/<name>_context.rb` | Shared `let` blocks (connector id, outbound config, base URL) used by every spec for this connector. |
| `connector-sdk/spec/support/shared_examples/<name>_error_examples.rb` | Reusable rate-limit and 5xx error examples. Optional, but worth adding once you have more than one action. |

UUIDs (for the connector itself, every trigger, every action) must be stable v7 UUIDs. Generate them once with `SecureRandom.uuid_v7` and leave them alone; they are the wire-level identity of the templates.

## Anatomy of a connector

```ruby
class MyConnector < IPaaS::Connector::Definition
  connector '<connector-uuid-v7>' do
    name 'My System'
    avatar '/assets/icons/my_system.svg'   # provide as part of the PR for public connectors
    description <<~END_OF_DESCRIPTION
      ## Overview
      Markdown shown to runbook authors. Cover prerequisites, authentication,
      triggers, and actions with input/output tables.
    END_OF_DESCRIPTION

    inbound_connection do
      # Either declare built-in validators…
      api_key_validator
      # …or write a custom validate block. At least one is required.
      validate { |request| request.headers['X-My-Token'] == config[:token] }
    end

    outbound_connection do
      # Built-ins handle the common patterns.
      bearer_authenticator
      # Custom authenticate blocks are for non-standard headers.
      authenticate { |request| request.headers['Authorization'] = "Token #{config[:api_key]}" }
    end

    trigger_template '<trigger-uuid-v7>' do
      name 'Event received'
      output_schema { field :event_id, type: :string }
      parse do |request|
        body = JSON.parse(request.body&.read || '{}')
        { event_id: body['id'], deduplication_id: body['id'] }
      end
    end

    action_template '<action-uuid-v7>' do
      name 'Fetch record'
      input_schema  { field :id, type: :string, required: true }
      output_schema { field :record, type: :hash }
      run do
        response = helpers.my_system_get("records/#{input[:id]}")
        [{ output: { record: response.body } }]
      end
    end

    helper :my_system_url do |path|
      "#{outbound_connection.config[:base_url]}/api/v1/#{path}"
    end

    helper :my_system_get do |path, query: {}|
      response = http_get(helpers.my_system_url(path), query: query)
      backoff_if_needed(response, api_name: 'My System')
      helpers.parse_response(response)
    end

    helper :parse_response do |response|
      fail_job!("HTTP #{response.status}: #{response.body}") unless response.status == 200
      JSON.parse(response.body).with_indifferent_access
    end
  end
end
```

A few things to notice:

- **`config`** inside `inbound_connection` or `outbound_connection` holds the resolved configuration the user supplied for that connection.
- **`input`** inside an action's `run` block holds the resolved input mapping for that step.
- **`helpers.<name>`** calls a `helper :<name> do … end` defined elsewhere in the connector. Helpers call other helpers the same way.
- Call **`backoff_if_needed`** on every HTTP response. It raises `RescheduleJob` when the API answers `429` or `503`, and the runtime retries the step after the suggested delay.
- **HMAC and signature validation** belong in the inbound connection's `validate` block. The framework rewinds the request body between `validate` and `parse`, so `parse` still sees the full body. Connector code cannot call `request.body.rewind` itself — the framework does it.

## The connector sandbox

Connector code runs in a restricted Ruby environment. The runtime parses every `validate`, `parse`, `run`, `authenticate`, and `helper` block and rejects code that does any of the following:

- **No method definitions.** The sandbox rejects `def foo` and `def self.foo`. Use helpers (`helper :foo do … end`) for reusable logic.
- **No constant definitions.** The sandbox rejects `MY_CONST = …`. Inline the value, or compute it inside a helper.
- **No global variables.** Reading `$something` raises.
- **No subprocess execution.** The sandbox rejects backticks (`` `cmd` ``) and `%x{cmd}`.
- **No arbitrary top-level constants.** A small allow-list opens up `JSON`, `YAML`, `URI`, `JWT`, `IO`, the standard Ruby value types, and a curated set of Rails and stdlib classes. Anything outside that list fails at load time.
- **Method allow-list.** Connector code can only call methods on the allow-list (`connector/lib/ipaas/connector/common/proc_rules/valid_methods_rule.rb`) and methods that iPaaS modules register via `proc_safe`. The list covers the `String`, `Integer`, `Hash`, `Array`, `Date`, `Time`, `URI`, `JSON`, and crypto methods you'll typically reach for; extend that file if you need one it's missing. For new helpers you write in `connector/lib/ipaas/job/…`, register them via `proc_safe` in the module that defines them, not in `valid_methods_rule.rb`.

Because you can't define local methods, extracting logic into helpers is often the only way to keep a `run` block readable. That constraint shapes most of the conventions below.

A custom RuboCop cop, `UnsafeGsub`, flags `String#gsub(pattern, variable)` calls. When the replacement comes from a variable, use the block form (`gsub(pattern) { variable }`) so backslashes aren't reinterpreted.

## Helpers

### Per-connector helpers

Define them inside the `connector` block:

```ruby
helper :my_system_url do |path|
  "#{outbound_connection.config[:base_url]}/api/v1/#{path}"
end
```

Call it as `helpers.my_system_url('records/123')`. Helpers take positional and keyword arguments and return whatever the rest of the connector needs.

A useful starter set for any HTTP-based connector:

- **`<name>_url(path)`**: base-URL builder.
- **`<name>_get(path, query: {})` and `<name>_post(path, body)`**: wrap `http_get` or `http_post`, then `backoff_if_needed`, then `parse_response`. Action `run` blocks shrink to one or two lines as a result.
- **`<name>_get_paginated(path)`**: for list endpoints. Read `iteration_state_value(:cursor)`, append it to the request, set the next cursor on the response, and return the collected page. The runtime drives the loop.
- **`parse_response(response)`**: JSON-parse the body, raise on non-2xx via `fail_job!`, and return `with_indifferent_access`.

### Action- and trigger-scoped helpers

If a piece of logic only matters inside one action or trigger, put the `helper` block inside that action or trigger instead of at the connector level. Connector-level helpers reach everywhere; scoped helpers stay inside their surrounding template.

### Built-in helpers provided by the runtime

Every connector can call these without any setup:

- **HTTP**: `http_get`, `http_post`, `http_put`, `http_patch`, `http_delete`. They return a response with `status`, `headers`, and `body`.
- **Flow control**: `fail_job!(message)` fails the current step, `discard_trigger_event!(message)` drops a trigger event with a 200 response, `bad_request(message)` rejects a trigger event with a 422.
- **Rate limiting**: `backoff_if_needed(response, api_name: '...')` raises `RescheduleJob` for 429 and 503.
- **Iteration state**: `iteration_state_value(:key)` reads the cursor; `iteration_state_value(:key, value)` writes it. The runtime uses this to drive cursor-based pagination across invocations.
- **Logging**: `log(message)` writes to the per-step log that appears in the runbook UI.
- **Data shaping**: `camel_to_snake(hash)` normalises external API responses; `keys_to_field_id(hash)` aligns keys with schema field IDs.

Every method marked `proc_safe` under `connector/lib/ipaas/job/` is callable. Browse that directory to discover what's available.

## Specs

Each trigger, action, and connection gets its own `_spec.rb`. The shared context keeps the boilerplate manageable:

```ruby
# spec/support/shared_contexts/my_system_context.rb
shared_context 'my_system', :my_system do
  let(:connector_id) { '<connector-uuid-v7>' }
  let(:base_url)     { 'https://api.example.com' }
  let(:outbound_connection_config) do
    { bearer: { bearer_token: make_secret_string('test-token') } }
  end
end
```

```ruby
# spec/ipaas/connector/sdk/examples/my_system_connector/fetch_record_action_spec.rb
require 'spec_helper'

describe 'My System: fetch record', :action, :my_system do
  let(:action_template_id) { '<action-uuid-v7>' }

  it 'returns the record' do
    stub_request(:get, "#{base_url}/api/v1/records/123")
      .to_return(status: 200, body: { id: '123', name: 'Widget' }.to_json)

    result = run_action(input: { id: '123' })

    expect(result).to eq([{ output: { record: { id: '123', name: 'Widget' } } }])
  end
end
```

A few rules new authors trip on:

- **`RescheduleJob` carries data.** A spec that expects a backoff must assert the `reschedule_after` value, not just the exception type.
- **Aim for full coverage.** Cover every branch in a `run`, `parse`, or helper block. The SDK's own connectors hold to that bar; yours should too.
- **Group by behaviour, not by setup.** Use `describe` for the subject, `context` for the variant, and `it` with an explicit expectation that names what each example asserts.
- **Use shared examples for repetitive error tests** (rate limit, 5xx, malformed body). See `connector-sdk/spec/support/shared_examples/` for the pattern.

## Things to keep in mind

- **Schemas drive the UI.** Every `field` in `input_schema` or `output_schema` shows up in the runbook editor. `hint`, `visibility`, and `required` shape what the runbook author sees and what they can change. `virima_connector.rb` and `xurrent_app_connector.rb` exercise the DSL most fully.
- **The `description` markdown reaches runbook authors.** Treat it as product documentation, not as a code comment. The standard layout: *Overview*, *Prerequisites*, *Authentication*, *Triggers*, and *Actions* with input/output tables.
- **`make_secret_string` in specs.** A `:secret_string` field comes back as an opaque object in production. `make_secret_string('value')` gives your tests the same wrapper, so code that reads the value behaves the same way under test.
- **Avatars.** For a private connector in your own fork, set `avatar` to any URL or asset path the runtime can resolve. For a PR contributing a new public connector, include the SVG with the PR (see [CONTRIBUTING.md](./CONTRIBUTING.md)) and reference it as `/assets/icons/<connector_name>.svg`. The platform team wires the asset in when the change is replayed internally.

## Where to look next

- **Reference connectors** in `connector-sdk/spec/fixtures/`: `virima_connector.rb` (REST + pagination), `xurrent_app_connector.rb` (OAuth + webhooks), `logic_monitor_connector.rb` (PSA-style auth), `graphql_connector.rb` (GraphQL DSL).
- **DSL surface** in `connector/lib/ipaas/connector/`: the schema field types, authenticators, validators, and the helpers mixin all live here.
- **Sandbox rules** in `connector/lib/ipaas/connector/common/proc_rules/`: the source of truth for what's allowed and what isn't.

When in doubt, copy the closest reference connector and trim it down. The DSL is small and the patterns recur.

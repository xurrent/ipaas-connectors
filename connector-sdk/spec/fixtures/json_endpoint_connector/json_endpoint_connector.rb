class JsonEndpointConnector < IPaaS::Connector::Definition
  connector 'ef6a3a61-cdd1-4ec6-9d27-cb2aa5f8427d' do
    name 'JSON Endpoint'
    avatar '/assets/icons/filetype-json.svg'
    description <<~'END_OF_DESCRIPTION'
      ## Overview
      Inbound webhook endpoint that accepts authenticated JSON `POST` requests and parses the body, headers, URL suffix, and query-string into structured trigger output for use in a runbook. Pairs with the outbound **HTTP** connector.

      ## Prerequisites
      - A Xurrent iPaaS trigger URL. The platform generates one when you install this trigger in a runbook and shows it in the install view.
      - API key or HTTP Basic Auth credentials for the caller. Populate whichever method the calling system supports. You can configure both on the same connection. Leave a method blank to disable it.
      - A caller system able to send JSON `POST` requests to the trigger URL over HTTPS.

      ## Authentication
      Every inbound request must authenticate with **API key** or **Basic Auth**. Populate whichever method the calling system supports. You can configure both on one connection; the validator skips any method you leave blank.

      ### API key

      | Field | Type | Required | Default | Description |
      |---|---|---|---|---|
      | `key` | String | Yes | - | Header or query-parameter name the caller sends the API key in (e.g. `X-API-Key`) |
      | `value` | String | Yes | - | Expected API-key value |
      | `placement` | Enum | No | `Header` | Where the caller places the key. Either `Header` or `Query params` |

      ### Basic auth

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `username` | String | Yes | Expected Basic Auth username |
      | `password` | Secret | Yes | Expected Basic Auth password. The caller sends it as `Authorization: Basic <base64(user:pass)>` per RFC 7617 |

      ## Triggers

      ### JSON Endpoint

      Exposes a single HTTPS `POST` endpoint that the caller invokes with a JSON body. The trigger parses the body against the configured `body_schema`, extracts any declared headers, reads an optional trailing path segment as `url_postfix`, captures any query-string parameters, and emits a structured payload to the runbook.

      **Use case**: receive webhook callbacks from any system that can POST JSON with an API key or Basic Auth. Common callers include monitoring tools, ITSM platforms, and custom integrations with no dedicated connector.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |---|---|---|---|---|
      | `headers` | Array of `{name, array, required}` | No | `[]` | Headers to extract from the incoming request. See `headers[]` fields below |
      | `body_schema` | SchemaField[] | Yes | - | Field-by-field definition of the JSON body the endpoint expects. Defines the shape of the `body` output |

      ##### `headers[]` fields

      | Field | Type | Required | Default | Description |
      |---|---|---|---|---|
      | `name` | String | Yes | - | Exact header name the caller will send. Pattern `[A-Za-z0-9_-]+` |
      | `array` | Boolean | No | `false` | When `true`, the incoming header value is split on `,\s+` into an array |
      | `required` | Boolean | No | `false` | When `true`, requests that omit this header are rejected |

      #### Example Input

      Trigger configuration (set once by the runbook author):

      ```json
      {
        "headers": [
          { "name": "X-Request-Id", "array": false, "required": true },
          { "name": "X-Tags", "array": true, "required": false }
        ],
        "body_schema": [
          { "id": "event_type", "label": "Event type", "type": "string", "required": true },
          {
            "id": "data", "label": "Data", "type": "nested", "required": false,
            "fields": [
              { "id": "source",  "label": "Source",  "type": "string", "required": false },
              { "id": "message", "label": "Message", "type": "string", "required": false }
            ]
          }
        ]
      }
      ```

      Sample incoming request, API key variant:

      ```sh
      curl -X POST 'https://<your-ipaas-host>/inbound/<account_id>/<solution_uuid>/<runbook_uuid>/customer_42?region=eu' \
        -H 'X-API-Key: <api-key-value>' \
        -H 'X-Request-Id: 8b4e1c2f' \
        -H 'X-Tags: priority, followup' \
        -H 'Content-Type: application/json' \
        -d '{
          "event_type": "alert.created",
          "data": { "source": "external-system", "message": "threshold exceeded" }
        }'
      ```

      Sample incoming request, Basic Auth variant:

      ```sh
      curl -X POST 'https://<your-ipaas-host>/inbound/<account_id>/<solution_uuid>/<runbook_uuid>' \
        -u '<username>:<password>' \
        -H 'X-Request-Id: 8b4e1c2f' \
        -H 'Content-Type: application/json' \
        -d '{ "event_type": "alert.created", "data": { "message": "threshold exceeded" } }'
      ```

      #### Output

      | Field | Type | Description |
      |---|---|---|
      | `url_postfix` | String | Trailing path segment after the runbook UUID. For `/inbound/<account_id>/<solution_uuid>/<runbook_uuid>/customer_42` it would be `customer_42`. `nil` when the caller appends nothing |
      | `query_params` | Hash | Query-string parameters parsed from the request URL. Empty hash when the URL has no query string |
      | `headers` | Nested | Present only when the trigger's `headers` config is non-empty. Contains one field per declared header; array-type headers are split on `,\s+` |
      | `body` | Nested | Parsed JSON body, structured according to `body_schema` |

      Note: `url_postfix` and `query_params` are independent. The first comes from the URL path glob; the second from the URL query string. A single request can populate either, both, or neither.

      #### Example Output

      For the API-key request above:

      ```json
      {
        "url_postfix": "customer_42",
        "query_params": { "region": "eu" },
        "headers": {
          "X-Request-Id": "8b4e1c2f",
          "X-Tags": ["priority", "followup"]
        },
        "body": {
          "event_type": "alert.created",
          "data": { "source": "external-system", "message": "threshold exceeded" }
        }
      }
      ```

      #### Error Handling

      All validation failures return HTTP `400 Bad Request` with a JSON body of the form `{ "error": "<message>" }`.

      | Condition | Error message |
      |---|---|
      | Missing or mismatched API-key value | `Invalid or missing API key.` |
      | Missing or mismatched Basic Auth credentials | `Invalid basic authentication header.` |
      | Body is missing a field declared required in `body_schema`, or a field has the wrong type | `Output invalid: <details>` |
      | A header declared `required: true` is absent from the request | `Output invalid: <details>` |

      #### Best Practices
      - Declare every header you rely on in the `headers` config so it appears on `trigger_output.headers.<name>`. The connector discards undeclared headers.
      - Set `array: true` on `headers[]` entries for multi-value headers (e.g. `X-Forwarded-For`, comma-separated tag lists). The connector splits on `,\s+`.
      - Use `url_postfix` (the trailing path segment, e.g. `…/<runbook_uuid>/customer_42`) to pass routing info and branch on `trigger_output.url_postfix` in the runbook. This keeps routing out of the body.
      - Make `body_schema` strict: mark every required field `required: true` and pick specific types (`integer`, `date_time`, etc.) rather than free-form strings. The platform rejects non-conforming bodies at the edge instead of failing mid-runbook.

      ## Actions
      None. This connector is inbound only.

      ## Best Practices
      - For outbound calls (from a runbook to an external system) use the **HTTP** connector. This connector handles inbound only.
      - If multiple callers share one endpoint, give each a distinct Basic Auth `username`/`password` pair (or distinct API-key value) so request logs and audit trails distinguish them.
      - Branch on `body.event_type` or `url_postfix` inside the runbook rather than standing up one trigger per event type. Fewer endpoints means fewer credentials to rotate.
      - Pair with the **Ruby** connector when downstream actions need a reshaped or validated version of the incoming body.
      - Review and rotate API-key and Basic Auth credentials whenever the set of caller systems changes.

      ## Common Use Cases
      - **Monitoring alerts**: receive events from any monitoring tool that can POST JSON, then branch on `body.event_type` to fan out to different incident-creation runbooks.
      - **ITSM webhooks**: accept ticket or change callbacks from third-party ITSM platforms with vendor-specific payloads by declaring each vendor's fields in `body_schema`.
      - **Integration callbacks**: wire up any app that can POST JSON with Basic Auth or an API key, even for apps with no dedicated connector.
      - **Request/response bridges**: pair this inbound trigger with the outbound **HTTP** connector to accept requests in one payload shape and forward them in another.

      ## References
      - [RFC 7617: HTTP Basic Authentication](https://www.rfc-editor.org/rfc/rfc7617)
      - [RFC 8259: JSON Data Interchange Format](https://www.rfc-editor.org/rfc/rfc8259)
    END_OF_DESCRIPTION

    inbound_connection do
      api_key_validator
      basic_auth_validator
    end

    trigger 'c23047dd-eb10-42b4-a67d-6ea6c58e3958' do
      name 'JSON Endpoint'
      avatar '/assets/icons/filetype-json.svg'
      description <<~'END_OF_DESCRIPTION'
        Exposes a single HTTPS `POST` endpoint that the caller invokes with a JSON body. The trigger parses the body against the configured `body_schema`, extracts any declared headers, reads an optional trailing path segment as `url_postfix`, captures any query-string parameters, and emits a structured payload to the runbook.

        **Use case**: receive webhook callbacks from any system that can POST JSON with an API key or Basic Auth. Common callers include monitoring tools, ITSM platforms, and custom integrations with no dedicated connector.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |---|---|---|---|---|
        | `headers` | Array of `{name, array, required}` | No | `[]` | Headers to extract from the incoming request. See `headers[]` fields below |
        | `body_schema` | SchemaField[] | Yes | - | Field-by-field definition of the JSON body the endpoint expects. Defines the shape of the `body` output |

        #### `headers[]` fields

        | Field | Type | Required | Default | Description |
        |---|---|---|---|---|
        | `name` | String | Yes | - | Exact header name the caller will send. Pattern `[A-Za-z0-9_-]+` |
        | `array` | Boolean | No | `false` | When `true`, the incoming header value is split on `,\s+` into an array |
        | `required` | Boolean | No | `false` | When `true`, requests that omit this header are rejected |

        ### Example Input

        Trigger configuration (set once by the runbook author):

        ```json
        {
          "headers": [
            { "name": "X-Request-Id", "array": false, "required": true },
            { "name": "X-Tags", "array": true, "required": false }
          ],
          "body_schema": [
            { "id": "event_type", "label": "Event type", "type": "string", "required": true },
            {
              "id": "data", "label": "Data", "type": "nested", "required": false,
              "fields": [
                { "id": "source",  "label": "Source",  "type": "string", "required": false },
                { "id": "message", "label": "Message", "type": "string", "required": false }
              ]
            }
          ]
        }
        ```

        Sample incoming request, API key variant:

        ```sh
        curl -X POST 'https://<your-ipaas-host>/inbound/<account_id>/<solution_uuid>/<runbook_uuid>/customer_42?region=eu' \
          -H 'X-API-Key: <api-key-value>' \
          -H 'X-Request-Id: 8b4e1c2f' \
          -H 'X-Tags: priority, followup' \
          -H 'Content-Type: application/json' \
          -d '{
            "event_type": "alert.created",
            "data": { "source": "external-system", "message": "threshold exceeded" }
          }'
        ```

        Sample incoming request, Basic Auth variant:

        ```sh
        curl -X POST 'https://<your-ipaas-host>/inbound/<account_id>/<solution_uuid>/<runbook_uuid>' \
          -u '<username>:<password>' \
          -H 'X-Request-Id: 8b4e1c2f' \
          -H 'Content-Type: application/json' \
          -d '{ "event_type": "alert.created", "data": { "message": "threshold exceeded" } }'
        ```

        ### Output

        | Field | Type | Description |
        |---|---|---|
        | `url_postfix` | String | Trailing path segment after the runbook UUID. For `/inbound/<account_id>/<solution_uuid>/<runbook_uuid>/customer_42` it would be `customer_42`. `nil` when the caller appends nothing |
        | `query_params` | Hash | Query-string parameters parsed from the request URL. Empty hash when the URL has no query string |
        | `headers` | Nested | Present only when the trigger's `headers` config is non-empty. Contains one field per declared header; array-type headers are split on `,\s+` |
        | `body` | Nested | Parsed JSON body, structured according to `body_schema` |

        Note: `url_postfix` and `query_params` are independent. The first comes from the URL path glob; the second from the URL query string. A single request can populate either, both, or neither.

        ### Example Output

        For the API-key request above:

        ```json
        {
          "url_postfix": "customer_42",
          "query_params": { "region": "eu" },
          "headers": {
            "X-Request-Id": "8b4e1c2f",
            "X-Tags": ["priority", "followup"]
          },
          "body": {
            "event_type": "alert.created",
            "data": { "source": "external-system", "message": "threshold exceeded" }
          }
        }
        ```

        ### Error Handling

        All validation failures return HTTP `400 Bad Request` with a JSON body of the form `{ "error": "<message>" }`.

        | Condition | Error message |
        |---|---|
        | Missing or mismatched API-key value | `Invalid or missing API key.` |
        | Missing or mismatched Basic Auth credentials | `Invalid basic authentication header.` |
        | Body is missing a field declared required in `body_schema`, or a field has the wrong type | `Output invalid: <details>` |
        | A header declared `required: true` is absent from the request | `Output invalid: <details>` |

        ### Best Practices
        - Declare every header you rely on in the `headers` config so it appears on `trigger_output.headers.<name>`. The connector discards undeclared headers.
        - Set `array: true` on `headers[]` entries for multi-value headers (e.g. `X-Forwarded-For`, comma-separated tag lists). The connector splits on `,\s+`.
        - Use `url_postfix` (the trailing path segment, e.g. `…/<runbook_uuid>/customer_42`) to pass routing info and branch on `trigger_output.url_postfix` in the runbook. This keeps routing out of the body.
        - Make `body_schema` strict: mark every required field `required: true` and pick specific types (`integer`, `date_time`, etc.) rather than free-form strings. The platform rejects non-conforming bodies at the edge instead of failing mid-runbook.
      END_OF_DESCRIPTION

      config_schema do
        field :headers,
              'Headers',
              [:nested],
              default: [] do
          field :name,
                'Header name',
                :string,
                required: true,
                pattern: /[A-Za-z0-9\-_]+/
          field :array,
                'Array',
                :boolean
          field :required,
                'Required',
                :boolean
        end

        field :body_schema,
              'Body schema',
              [:schema_field],
              required: true

        after_update do
          regenerate_schema(output_schema)
        end
      end

      output_schema do
        field :url_postfix, 'URL Postfix', :string
        field :query_params, 'Query Parameters', :hash
        trigger_headers = trigger.config[:headers]
        if trigger_headers.any?
          headers_required = trigger_headers.any? { |header| header[:required] }
          field :headers, 'Headers', :nested, required: headers_required do
            trigger_headers.each do |header|
              next unless header[:name].present?

              field header[:name].to_sym, header[:name], :string,
                    array: header[:array],
                    required: header[:required]
            end
          end
        end
        field :body, 'Body', :nested, fields: trigger.config[:body_schema]
      end

      parse do |request|
        context_identifier_header = request.headers['x-job-context-identifier']
        self.job_context_identifier = context_identifier_header if context_identifier_header.present?

        uri = URI.parse(request.url)
        body_content = request.body&.read
        parsed_body = if body_content.present?
                        begin
                          JSON.parse(body_content)
                        rescue JSON::ParserError
                          fail_job!('Request body could not be parsed')
                        end
                      else
                        body_content
                      end
        request_params = {
          body: parsed_body,
          url_postfix: request.params['url_postfix'],
          query_params: uri.query ? Rack::Utils.parse_query(uri.query) : {},
        }
        trigger_headers = trigger.config[:headers]
        next request_params if trigger_headers.none?

        header_values = trigger.config[:headers].each_with_object({}) do |header, h|
          value = request.headers[header[:name]]
          value = value.split(/,\s+/) if header[:array] && value.is_a?(String)
          h[header[:name]] = header[:array] ? Array(value) : value if value.present?
          h
        end
        request_params.merge({ headers: header_values })
      end

      # protection_profile :high_volume
    end
  end
end

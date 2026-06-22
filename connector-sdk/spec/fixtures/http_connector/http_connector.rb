class HttpConnector < IPaaS::Connector::Definition
  connector '6a8f5f03-bf6b-40d6-9ae3-ae3a7d4734c1' do
    name 'HTTP'
    avatar '/assets/icons/send.svg'
    description <<~END_OF_DESCRIPTION
      ## Overview
      A generic outbound HTTPS connector for making arbitrary HTTP calls to any external API. Use it when no dedicated connector exists for the target service, or to call simple webhooks.

      ## Prerequisites
      - **Base URL** for the target API.
      - Credentials for one of the four supported auth modes (API key, Basic auth, Bearer token, or OAuth 2.0), or none for public endpoints. Consult the target API's own documentation for how to obtain these.

      ## Authentication
      All four auth modes coexist; populate only the one(s) your target API requires. The connector skips blank sections at request time.

      ### API key
      Nested `api_key` config:

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `key` | String | Yes | Header or query-param name (e.g. `X-API-Key`) |
      | `value` | Secret | Yes | The key value |
      | `placement` | Enum | No (default `Header`) | `Header` or `Query params` |

      ### Basic auth
      Nested `basic_auth` config:

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `username` | String | Yes | |
      | `password` | Secret | Yes | |

      ### Bearer token
      Nested `bearer` config:

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `bearer_token` | Secret | Yes | |

      ### OAuth 2
      Nested `oauth2` config:

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `grant_type` | Enum | Yes | `Client Credentials` or `Refresh Token` |
      | `authorization_url` | URI | Yes | Token endpoint |
      | `client_id` | String | Yes | |
      | `client_secret` | Secret | Yes | |
      | `refresh_token` | String | Only when `grant_type = Refresh Token` | |

      The connector exchanges credentials for a token at `authorization_url` and sends `Authorization: Bearer <access_token>` on the outbound request.

      ## Triggers
      None. This connector is outbound only.

      ## Actions

      ### Send HTTP request

      Send a custom HTTP request to an external application. Returns the response's status code, headers, and body to the workflow.

      Use case: send an HTTP request to an internal or external service.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |---|---|---|---|---|
      | `method` | Enum | Yes | - | One of `HEAD`, `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `OPTIONS`, `TRACE` |
      | `path` | String | No | - | Sub-path appended to the connection's **Base URL** (e.g. `/users/1`). Allowed characters match `[A-Za-z0-9\\-._~!$&'()*+,;=:@%/]`; put query strings in `query_parameters` and URL fragments (`#...`) are not supported. |
      | `headers` | Array of `{name, value}` | No | `[]` | Request headers. Header names must match `[A-Za-z0-9\\-_]+`. The connector joins repeated names into a single comma-separated value. |
      | `query_parameters` | Array of `{name, value}` | No | `[]` | Query-string parameters. Names may include `[` and `]` for APIs using `filter[field]`-style keys. The connector appends `[]` to repeated names: two `q` entries become `q[]=A&q[]=B` on the wire. To send a target API a bare repeated parameter, encode the values yourself in a single entry. |
      | `body` | Binary | No | - | Raw request body. The connector does not auto-serialise. Send JSON by setting a `Content-Type: application/json` header and a stringified JSON body. |

      #### Defaults
      The connector sends `User-Agent: Xurrent iPaaS` on every request. Override it by adding a `User-Agent` entry to `headers`.

      #### Example Input

      ```json
      {
        "method": "GET",
        "path": "/users/1",
        "headers": [{ "name": "Accept", "value": "application/json" }],
        "query_parameters": [{ "name": "include", "value": "profile" }],
        "body": null
      }
      ```

      #### Output

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `response.status` | Integer | Yes | HTTP status code |
      | `response.headers` | Array of `{name, value}` | No | One entry per response header name. When the response repeats a header name, the connector combines the values into a single comma-joined `value` per RFC 9110 §5.3. |
      | `response.body` | Binary | No | Raw response body |

      #### Example Output

      ```json
      {
        "response": {
          "status": 200,
          "headers": [
            { "name": "content-type", "value": "application/json" },
            { "name": "x-request-id", "value": "abc-123" }
          ],
          "body": "{\\"id\\":1,\\"name\\":\\"Ada Lovelace\\"}"
        }
      }
      ```

      #### Error Handling
      The connector does **not** retry or back off. The connector returns any HTTP response to the workflow as-is, including 4xx and 5xx. Handle status codes in your runbook (e.g. branch on `response.status >= 400`). If the connector cannot send the request at all (DNS failure, TLS error, timeout), the action fails with the underlying error.

      #### Best Practices
      - Branch on `response.status >= 400` in the runbook. The connector never retries and never fails on HTTP error responses.
      - Send JSON bodies by setting `Content-Type: application/json` in `headers` and passing a stringified JSON `body`. The connector does not auto-serialise.
      - Use one of the four configured auth modes instead of pasting credentials into `headers`, `query_parameters`, or `body`. The platform logs those fields as-is and does not treat them as secrets.
      - Prefer a dedicated vendor connector when one exists. HTTP has no pagination helpers, response-body parsing, or rate-limit handling.

      ## Rate Limiting

      | HTTP status | Connector behaviour |
      |---|---|
      | 2xx | The connector returns `response.status`, `response.headers`, and `response.body` to the workflow |
      | 4xx / 5xx | Returned as-is. Branch in the runbook on `response.status` |
      | 429 / 503 | Returned as-is. No automatic retry or `Retry-After` handling |
      | Network error (DNS, TLS, timeout) | Action fails with the underlying error |

      Outbound requests have a 5-second connect timeout and a 5-minute total request timeout.

      ## Best Practices
      - Treat HTTP as a privileged primitive. `base_url` accepts any URI, including internal hosts, so restrict who can create HTTP connections and review `base_url` values before enabling.
      - Keep `base_url` narrow (one per external API) so per-connection permissions and audit trails stay meaningful.
      - For paginated APIs, iterate in the runbook using the vendor's `next`/`cursor` fields from `response.body`. The connector does not paginate for you.
      - Keep `body` sizes modest. The connector does not stream.

      ## Common Use Cases
      - **Webhook to an internal service**: `POST` a JSON payload built from workflow inputs, then branch on `response.status` to confirm delivery.
      - **Custom REST request**: `GET`, `POST`, or `PATCH` a resource on any external REST endpoint, then branch on `response.status` and parse `response.body` in the runbook.
      - **Scheduled cache warm-up**: scheduled `GET` to keep an upstream endpoint's cache warm.
      - **Outbound notification**: `POST` a summary payload to a chat or alerts webhook.

      ## References
      - [RFC 9110: HTTP Semantics](https://www.rfc-editor.org/rfc/rfc9110)
      - [RFC 7617: HTTP Basic Authentication](https://www.rfc-editor.org/rfc/rfc7617)
      - [RFC 6750: Bearer Token Usage](https://www.rfc-editor.org/rfc/rfc6750)
      - [RFC 6749: OAuth 2.0](https://www.rfc-editor.org/rfc/rfc6749)
    END_OF_DESCRIPTION

    outbound_connection do
      api_key_authenticator
      basic_auth_authenticator
      bearer_authenticator
      oauth2_authenticator

      config_schema do
        field :base_url,
              'Base URL',
              :uri,
              required: true
      end
    end

    action '0195fa8b-e402-713c-bf69-cf192637bbe3' do
      name 'Send HTTP request'
      avatar '/assets/icons/send.svg'
      description <<~END_OF_DESCRIPTION
        Send a custom HTTP request to an external application. Returns the response's status code, headers, and body to the workflow.

        Use case: send an HTTP request to an internal or external service.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |---|---|---|---|---|
        | `method` | Enum | Yes | - | One of `HEAD`, `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `OPTIONS`, `TRACE` |
        | `path` | String | No | - | Sub-path appended to the connection's **Base URL** (e.g. `/users/1`). Allowed characters match `[A-Za-z0-9\\-._~!$&'()*+,;=:@%/]`; put query strings in `query_parameters` and URL fragments (`#...`) are not supported. |
        | `headers` | Array of `{name, value}` | No | `[]` | Request headers. Header names must match `[A-Za-z0-9\\-_]+`. The connector joins repeated names into a single comma-separated value. |
        | `query_parameters` | Array of `{name, value}` | No | `[]` | Query-string parameters. Names may include `[` and `]` for APIs using `filter[field]`-style keys. The connector appends `[]` to repeated names: two `q` entries become `q[]=A&q[]=B` on the wire. To send a target API a bare repeated parameter, encode the values yourself in a single entry. |
        | `body` | Binary | No | - | Raw request body. The connector does not auto-serialise. Send JSON by setting a `Content-Type: application/json` header and a stringified JSON body. |

        ### Defaults
        The connector sends `User-Agent: Xurrent iPaaS` on every request. Override it by adding a `User-Agent` entry to `headers`.

        ### Example Input

        ```json
        {
          "method": "GET",
          "path": "/users/1",
          "headers": [{ "name": "Accept", "value": "application/json" }],
          "query_parameters": [{ "name": "include", "value": "profile" }],
          "body": null
        }
        ```

        ### Output

        | Field | Type | Required | Description |
        |---|---|---|---|
        | `response.status` | Integer | Yes | HTTP status code |
        | `response.headers` | Array of `{name, value}` | No | One entry per response header name. When the response repeats a header name, the connector combines the values into a single comma-joined `value` per RFC 9110 §5.3. |
        | `response.body` | Binary | No | Raw response body |

        ### Example Output

        ```json
        {
          "response": {
            "status": 200,
            "headers": [
              { "name": "content-type", "value": "application/json" },
              { "name": "x-request-id", "value": "abc-123" }
            ],
            "body": "{\\"id\\":1,\\"name\\":\\"Ada Lovelace\\"}"
          }
        }
        ```

        ### Error Handling
        The connector does **not** retry or back off. The connector returns any HTTP response to the workflow as-is, including 4xx and 5xx. Handle status codes in your runbook (e.g. branch on `response.status >= 400`). If the connector cannot send the request at all (DNS failure, TLS error, timeout), the action fails with the underlying error.

        ### Best Practices
        - Branch on `response.status >= 400` in the runbook. The connector never retries and never fails on HTTP error responses.
        - Send JSON bodies by setting `Content-Type: application/json` in `headers` and passing a stringified JSON `body`. The connector does not auto-serialise.
        - Use one of the four configured auth modes instead of pasting credentials into `headers`, `query_parameters`, or `body`. The platform logs those fields as-is and does not treat them as secrets.
        - Prefer a dedicated vendor connector when one exists. HTTP has no pagination helpers, response-body parsing, or rate-limit handling.
      END_OF_DESCRIPTION

      input_schema do
        field :method,
              'Method',
              :string,
              required: true,
              enumeration: %w[HEAD GET POST PUT PATCH DELETE OPTIONS TRACE]
        field :path,
              'Path',
              :string,
              pattern: %r{\A[A-Za-z0-9\-._~!$&'()*+,;=:@%/]+\z}
        field :headers,
              'Headers',
              [:nested],
              default: [] do
          field :name,
                'Header name',
                :string,
                required: true,
                pattern: /\A[A-Za-z0-9\-_]+\z/
          field :value,
                'Value',
                :string
        end
        field :query_parameters,
              'Query parameters',
              [:nested],
              default: [] do
          field :name,
                'Query parameter name',
                :string,
                required: true,
                pattern: /\A[A-Za-z0-9\-_\[\]]+\z/
          field :value,
                'Value',
                :string
        end
        field :body,
              'Body',
              :binary
      end

      output_schema do
        field :response,
              'Response',
              :nested do
          field :status,
                'status',
                :integer,
                required: true
          field :headers,
                'Headers',
                [:nested],
                default: [] do
            field :name,
                  'Name',
                  :string,
                  required: true,
                  pattern: /[A-Za-z0-9\-_]+/
            field :value,
                  'Value',
                  :string,
                  required: true
          end
          field :body,
                'Body',
                :binary
        end
      end

      run do
        method = action.input[:method].to_s.downcase.to_sym
        url = URI.parse(outbound_connection.config[:base_url])
        sub_path = action.input[:path]
        if sub_path.present?
          sub_path = "/#{sub_path}" unless url.path.ends_with?('/') || sub_path.starts_with?('/')
          url.path += sub_path
        end
        headers = action.input[:headers]&.each_with_object({}) do |name_value, h|
          header_name = name_value[:name]
          header_value = name_value[:value]
          h[header_name] = if h.key?(header_name)
                             Array(h[header_name]) + [header_value]
                           else
                             header_value
                           end
        end
        params = action.input[:query_parameters]&.each_with_object({}) do |name_value, h|
          param_name = name_value[:name]
          param_value = name_value[:value]
          h[param_name] = if h.key?(param_name)
                            Array(h[param_name]) + [param_value]
                          else
                            param_value
                          end
        end
        body = action.input[:body]

        log(
          'HTTP %<method>s request to %<url>s with headers %<headers>s, query parameters %<params>s and body: %<body>s',
          { method: method, url: url, headers: headers, params: params, body: body }
        )
        response = http_send(method, url) do |request|
          request.headers.merge!(headers) if headers.present?
          request.params.merge!(params) if params.present?
          request.body = body if body.present?
        end
        log(
          'HTTP response %<status>s with headers %<headers>s and body "%<body>s"',
          { status: response.status, headers: response.headers, body: response.body }
        )

        [{
          output: {
            response: {
              status: response.status,
              headers: response.headers.map { |h, v| { name: h, value: v } },
              body: response.body,
            },
          },
        }]
      end

      # protection_profile :high_volume
    end
  end
end

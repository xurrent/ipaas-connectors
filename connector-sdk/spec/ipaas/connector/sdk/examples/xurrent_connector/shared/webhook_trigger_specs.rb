module WebhookTriggerSpecs
  def self.included(base)
    base.class_eval do
      let(:trigger_template_id) { '01930641-dd8e-7e8c-8550-e8cdbe31eddb' }

      let(:verification_payload_schema) do
        [
          { id: 'callback', label: 'Callback URL', type: 'string', required: true },
        ]
      end

      let(:trigger_config) do
        {
          payload_schema: verification_payload_schema.dup,
        }
      end

      let(:es256_pem) { JwtTestPem::ES256 }

      let(:policy_config) do
        {
          account_url: 'https://wdc.test.host',
          algorithm: 'ES256',
          public_key_pem: es256_pem[:public],
        }
      end

      let(:event_headers) do
        {
          'accept' => '*/*',
          'content-type' => 'application/json; charset=utf-8',
          'link' => '<https://wdc.xurrent-demo.com/app_instances/1>; rel="canonical", ' \
                    '<https://api.xurrent-demo.com/v1/app_instances/1>; rel="resource"',
          'user-agent' => 'xurrent/1.0 (https://developer.xurrent.com/v1/webhooks)',
          'x-xurrent-delivery' => '00c7bb4a-b3ba-4744-8126-1e7ef87ef90a',
        }
      end

      let(:webhook_body) do
        JSON.parse(<<~JSON)
          {
            "webhook_id": 2,
            "webhook_nodeID": "uvw",
            "account_id": "wdc",
            "account": "https://wdc.xurrent-staging.com",
            "name": "Test-IPaaS",
            "event": "problem.update",
            "object_id": 332,
            "object_nodeID": "abc",
            "person_id": 6,
            "person_nodeID": "xyz",
            "person_name": "Howard Tanner",
            "payload": {
              "status": "analyzed",
              "team": {
                "id": 14,
                "name": "End-User Support, Houston",
                "account": {
                  "id": "wdc",
                  "name": "Widget Data Center"
                },
                "nodeID": "def"
              },
              "member": {
                "id": 336,
                "name": "Joseph Coleman",
                "account": {
                  "id": "widget",
                  "name": "Widget International"
                },
                "nodeID": "ghi"
              },
              "audit_line_id": 71960,
              "audit_line_nodeID": "jkl"
            }
          }
        JSON
      end

      def post_webhook(body)
        post_trigger(body, headers: event_headers)
      end

      def post_encoded_webhook(body)
        payload = IPaaS::Job::JWT.make_jwt_payload(issuer_claim: policy_config[:account_url],
                                                   subject_claim: 'abc',
                                                   data: body)
        token = IPaaS::Job::JWT.encode_jwt(payload, pem: es256_pem[:private], algorithm: 'ES256')
        post_webhook(jwt: token)
      end

      def expect_jwt_invalid_issuer_error(_alternative_url)
        output = post_encoded_webhook(webhook_body)
        expect(output).to eq({ error: 'Webhook JWT verification failed' })
      end
    end
  end
end

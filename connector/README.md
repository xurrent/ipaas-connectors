# iPaaS Connector

## Installation

```
gem 'ipaas-connector'
```

## Usage

Examples:
```
require 'ipaas/connector'

class HttpConnector < IPaaS::Connector::Definition
    connector '6a8f5f03-bf6b-40d6-9ae3-ae3a7d4734c1' do
      name 'HTTP'
      avatar 'https://ipaas.eu.xurrent.com/avatars/ipaas/http.svg'
      description 'Default HTTPS connector...'
    end
end
```

For more complete examples see the connector-SDK.

## DSL

### Connector

* `uuid`: unique identifier
* `name`: unique name
* `avatar`: URL pointing to an image or SVG
* `description`: Markdown description
* `inbound_connection`:
  * `validators`: list of supported OOTB validation methods for inbound traffic, e.g. JWT
  * `config_schema`: Configuration options as ruby block
  * `validate`: code for custom validation of inbound requests
* `outbound_connection`:
    * `authenticators`: list of supported OOTB authenticators for outbound traffic
    * `config_schema`: Configuration options as ruby block
    * `setup_info`: code returning information that helps the end-user set up the connection
    * `provision`: code to be executed when the outbound connection is provisioned
    * `deprovision`: code to be executed when the outbound connection is deprovisioned
    * `authenticate`: code for custom authorization of outbound traffic
    * `config_tester`: optional code to test the resolved connection configuration, e.g. by calling the
      external system. Must return `{status:, message:}` within 10 seconds, where status is `:success`
      (test performed and passed), `:failed` (test performed and not successful) or `:error` (problem
      executing the test)
* `trigger_templates`, array of:
    * `uuid`: unique identifier
    * `name`: unique name
    * `avatar`: URL pointing to an image or SVG
    * `description`: Markdown description
    * `config_schema`: Configuration options as ruby block
    * `output_schema`: Output schema as ruby block
    * `extract_blueprint`: code to extract the trigger's blueprint files into the blueprint store
    * `provision`: code to be executed when the trigger is provisioned
    * `deprovision`: code to be executed when the trigger is deprovisioned
    * `parse`: code to parse incoming request (body + headers) and returns a hash 
               conforming the output schema.
               This code may also performs additional validation on the incomonig request.
               Methods bad_request(message) and discard(message) are available.
               Bad-request will respond with a 422 and discard will respond with 200.
               In both cases the runbook will not start.
    * `respond_with`: code to customize the response (status, body and headers) returned to the trigger's caller
* `action_templates`, array of:
    * `uuid`: unique identifier
    * `version`: number
    * `name`: unique name
    * `avatar`: URL pointing to an image or SVG
    * `description`: Markdown description
    * `input_schema`: Configuration options as ruby block
    * `output_schema`, Description of the output schema, each with its own UUID.
    * `output_schemas`: array of all output schemas
    * `run`: code to perform the action based on input fields and returns the output for one or more output schemas.
             Actions connected to those output schemas will be triggered next.
             This code also performs any validation required on the input fields and will fail the step if the input
             is invalid or if the action could not be performed (e.g. due to timeouts).

The following fields will always be added to the trigger config schema:
* `url_postfix`: used to customize the URL of the trigger endpoint
* `discard_trigger_event`: boolean, used to discard a job before the actions are called if the user defined condition is met

The following fields will always be added to the trigger output schema:
* `deduplication_id`: used to identify and discard duplicate incoming requests

The following fields will always be added to the action input schema:
* `concurrent`: boolean, set to true if outbound calls may be processed concurrently

### Schema

* `uuid`: unique identifier for the schema to reference it later in case multiple schemas are present
* `name`: optional name to describe the output schema when multiple outputs are present
* `fields`, array of:
  * `id`: (string) unique reference (on this level)
  * `label`: (string) unique name (on this level)
  * `type`: (symbol) primitive type or nested type
  * `array`: (boolean) set to true if the field should hold an array of values
  * `default`: (given type) default value
  * `sample`: (given type) sample value
  * `hint`: (string) provides additional information to the end-user
  * `visibility`: (string) one of visible, optional, hidden
  * `required`: (boolean) whether the field must receive a value
  * `pattern`: (regexp) ensures the value conforms to the pattern
  * `min`: (given type) minimum value
  * `max`: (given type) maximum value
  * `min_length`: minimum nr of characters in a string or values in an array
  * `max_length`: maximum nr of characters in a string or values in an array
  * `validator`: code to be executed to validate the field value
  * `enumeration`: (array of hash with id and label) providing all valid values
  * `fields`: (array of field) descriptions of sub-fields in case the type is set to nested.
  * `after_update(fields, values)`: code to be executed after initialization and when a field value is updated and must return the (renewed) fields. Values is a hash containing the resolved field values from the current mapping.

#### Field Types

The following field types are available:
* `:string`: String
* `:binary`: String
* `:base64`: String
* `:uri`: String
* `:time_zone`: String
* `:integer`: Integer
* `:float`: Float
* `:boolean`: Boolean
* `:nested`: Hash
* `:hash`: Hash
* `:date`: Date
* `:time`: Time
* `:date_time`: DateTime
* `:regexp`: Regexp
* `:recurrence`: Hash
* `:schema_field`: Schema::Field

#### Custom Field Types

It is also possible to register your own types as follows:

```ruby
module IPaaS
  module Connector
    module Types
      module RunbookType
        include IPaaS::Connector::Types::Base

        class << self
          def ruby_class
            IPaaS::Connector::Runbook
          end

          def resolve(value)
            return value if value.is_a?(IPaaS::Connector::Runbook)

            uuid = value.is_a?(Hash) ? value[:uuid] : value
            IPaaS::Connector::Runbook.by_uuid(uuid)
          end

          def example(field)
            '4a86113d-3106-4e17-8885-8ee10858030d'
          end
        end
      end
    end
  end
end

IPaaS::Connector::Types.register(IPaaS::Connector::Types::RunbookType)
```

## Development

After checking out the `connector` and `connector-sdk` projects in adjacent directories,
run the following commands in the root directory of the `connector` project:

```shell
bundle install
bundle exec rake connector:sync
```

To run specs:

```shell
bundle exec rspec
```

## Copyright

Copyright (c) 2024 Xurrent Inc.

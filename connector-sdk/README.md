# iPaaS Connector SDK

Project to write and test iPaaS connectors. Connectors are pieces of Ruby code that provide triggers and actions to
be used in runbooks. To use the triggers and actions defined by a connector in a solution's runbooks a connection based
on the connector is added to a solution.

This repository contains the standard Xurrent provided connectors and tests to verify them. 

The connectors themselves live in `spec/fixtures` and their tests live in `spec/ipaas/connector/sdk/examples`.
Connectors are defined using the DSL defined in the [connector project](../connector).

## Installation

```
gem 'ipaas-connector-sdk'
```

## Development

After checking out the `connector` and `connector-sdk` projects in adjacent directories,
run the following command in the root directory of this project:

```shell
bundle install
```

To run specs:

```shell
bundle exec rspec
```

Copyright (c) 2024 Xurrent Inc.

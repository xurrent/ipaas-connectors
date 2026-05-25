# Xurrent iPaaS Connectors

Public mirror of the [Xurrent iPaaS](https://www.xurrent.com/) connector code:

- [`connector/`](./connector): the `ipaas-connector` gem. Public DSL and runtime API used to define connectors.
- [`connector-sdk/`](./connector-sdk): the `ipaas-connector-sdk` gem. Shared building blocks and reference connectors that ship with the platform.

The platform itself is closed-source. We publish the connector code so partners and customers can build their own connectors, and so they can read, run, test, and propose changes to the standard connectors that ship with iPaaS.

## License

MIT. See [LICENSE](./LICENSE) for the full text.

## Running the specs

Both projects use Ruby (see [`.ruby-version`](./connector/.ruby-version)) and Bundler:

```shell
cd connector
bundle install
bundle exec rspec
bundle exec rubocop
```

```shell
cd connector-sdk
bundle install
bundle exec rspec
bundle exec rubocop
```

## Building your own connectors

The `ipaas-connector-sdk` gem doubles as a project template for connectors you build yourself. Fork this repository, or copy the `connector-sdk/` layout into a new project, and put your connector definitions, fixtures, and specs alongside the existing examples. Keep private connectors in your fork; open PRs against this repository only for changes to the standard connectors.

[AUTHORING.md](./AUTHORING.md) walks through the file layout, the DSL, the sandbox the runtime enforces on connector code, and the test conventions.

## Contributing

Pull requests for new connectors, fixes to existing ones, and additional tests are all welcome. The workflow in [`.github/workflows/test.yml`](./.github/workflows/test.yml) runs RSpec and RuboCop on every PR; make sure both pass locally before opening one.

## Reporting issues

GitHub Issues, Projects, and the Wiki are disabled on this repository. We track work in Xurrent; anything raised elsewhere is unlikely to reach us.

Register a request in your Xurrent account against the **iPaaS** service so your bug report or feature request reaches the team.

## Relationship to the internal repository

This repository holds a snapshot of two directories from Xurrent's internal monorepo. An automated job refreshes it periodically; the commit history is flattened and carries no internal authors or messages. The internal repository remains the source of truth. Pull requests merged here get reviewed and replayed against it before they ship in iPaaS.

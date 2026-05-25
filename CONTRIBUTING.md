# Contributing to Xurrent iPaaS Connectors

Thanks for your interest in improving the Xurrent iPaaS connectors. This repository is the public mirror of two gems — `ipaas-connector` and `ipaas-connector-sdk` — that ship inside the Xurrent iPaaS platform. Pull requests for new connectors, fixes to existing ones, and additional tests are welcome.

## Before you start

- Read the [README](./README.md) for an overview, how to run the specs, and the issue-reporting policy.
- Read [AGENTS.md](./AGENTS.md) and the relevant sub-project AGENTS.md ([connector/](./connector/AGENTS.md), [connector-sdk/](./connector-sdk/AGENTS.md)) for the coding standards every change must follow.
- If your AI assistant (Claude, Codex, JetBrains AI, Cursor, …) supports project rules, make sure it has indexed those `AGENTS.md` files before starting work.

## Pull request checklist

Before opening a PR, make sure:

- `bundle exec rspec` passes in the sub-project you changed.
- `bundle exec rubocop` is clean — zero offenses.
- New code is covered by tests; specs follow the patterns described in `AGENTS.md`.
- The PR description explains the *why* of the change, not just the *what*.
- **For PRs adding a new public connector**, attach the avatar to use — an SVG icon, square aspect, no external font dependencies — and reference it from the connector's `avatar` field as `/assets/icons/<connector_name>.svg`. We wire the asset into the platform when the PR is replayed internally.

The [`Tests`](./.github/workflows/test.yml) workflow runs RSpec and RuboCop on every PR; both must be green before review.

## Reporting bugs and requesting features

GitHub Projects, and the Wiki are disabled on this repository — we track work in Xurrent. To make sure your report is seen, register a request in your Xurrent account against the **iPaaS** service. See the [README](./README.md#reporting-issues) for details.

## How changes are merged

Approved pull requests are reviewed by the Xurrent iPaaS team and replayed against the internal source-of-truth repository before being shipped to customers. The merge timing on this public mirror therefore does not directly reflect when a change goes live in the platform.

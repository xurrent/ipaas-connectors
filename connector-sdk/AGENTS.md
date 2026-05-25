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

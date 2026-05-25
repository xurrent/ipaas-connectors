# Connector AGENTS.md

## Context
**Public API** for iPaaS connectors, runbooks, triggers and actions.

## Rules
1. **API Integrity**: No dependencies on `connector-sdk/` or `platform/` details.
2. **Implementation**: Use idiomatic Ruby. Wrap job failures with standard error handling (see existing error classes in `lib/`).
3. **Global Rules**: Adhere to [../AGENTS.md](../AGENTS.md).

## Sub-Directory Rules
- [Proc Rules Specs](./spec/ipaas/connector/common/proc_rules/AGENTS.md)

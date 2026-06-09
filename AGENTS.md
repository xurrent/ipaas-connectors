# AGENTS.md - Project Rules & Standards

ALL AI AGENTS: You MUST follow these rules and any sub-project `AGENTS.md`.

## Context
This repository is the public mirror of the connector code that powers
[Xurrent iPaaS](https://www.xurrent.com/) — Xurrent's Integration Platform
as a Service. iPaaS is multi-tenant; tenants are called 'accounts'.
Integrations are defined in solutions that consist of runbooks, where each
runbook has a trigger and a sequence of actions (steps).

The platform itself is not in this repository — only the connector libraries
that define how iPaaS talks to external systems. The full platform is
maintained internally by Xurrent and is the source of truth; this repo is
refreshed periodically from it.

## Project Overview & Boundaries
- **connector/**: Core Ruby integration logic. **Public API**.
- **connector-sdk/**: Shared SDK with reference connectors. **Project Template for customers**.

## Global AI Guidelines
1. **Tooling**:
    - Use `rbenv` (or any Ruby version manager) and respect `.ruby-version`.
2. **Linting**:
    - Ruby: Zero RuboCop offenses.
3. **Testing**:
    - **100% coverage** for all new code.
    - Group tests in `describe` blocks, combine describe blocks with the same subject.
    - Combine test cases with identical setup/action but different expectations.
    - Ensure test cases have explicit expectations matching their name.
    - Check `spec/` for patterns.
4. **Git Workflow**:
    - Add new files immediately.
    - NO push to remote (especially `main`) or force-push without explicit approval.
    - **Run git commands from the project root** using relative paths
      (e.g. `git add connector/lib/...`). Do NOT prefix git commands with `cd`;
      only `bundle exec` commands need a `cd` into sub-project directories.
5. **Communication**: Be direct, concise, and fix errors without apologies.
6. **Consistency**: Follow existing patterns and sub-project rules below.
7. **DRY**: Avoid duplicating code or logic. Use existing patterns and abstractions whenever possible.
8. **Naming**: Use `GraphQL` (not `Graphql`) in Ruby module/class names — it is an acronym.
9. **Comments**: Be concise and ONLY describe why, the code itself describes what and how.

## Documentation Consistency
When writing or updating documentation:
1. **Cross-reference all mentions**: After changing any section, verify every other section that references the same concept still agrees. Don't leave stale descriptions after partial updates.
2. **Summary sections must match detail sections**: If a schema or API is described both in a summary list and in a detailed section later, they must be identical.

## Reporting and tracking
GitHub Issues, Projects, and the Wiki on this repository are intentionally
disabled. To report a bug or request a feature, register a request in your
Xurrent account against the **iPaaS** service — see the README for details.

## Sub-Project Rules
When editing files in a sub-project, also read its specific `AGENTS.md`:
- [Connector Rules](./connector/AGENTS.md) (Public API/Ruby)
- [SDK Rules](./connector-sdk/AGENTS.md) (Templates/API Stability)

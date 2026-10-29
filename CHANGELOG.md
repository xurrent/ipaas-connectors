# Changelog

All notable changes to the publicly mirrored portions of the Xurrent iPaaS connector code are recorded here.

This file is appended to manually as part of the publishing process; each entry summarises the changes that were included in a given refresh of the public mirror. 

## 2026-10-29

### Changed
- Upgraded to Ruby 4.0; both gems now require Ruby 4.0 or later.
- An HTTP request with a body but no `Content-Type` is sent as `application/x-www-form-urlencoded`.

### Added
- Jira Cloud connector, to create, update, search and transition issues, list an issue's available transitions, manage comments and attachments, look up and create users, and trigger on Jira events or by polling.
- Microsoft Outlook connector: create and delete calendar events, and renew mail subscriptions from a scheduled action.

### Fixed
- Bug fixes and security hardening.


## 2026-10-15

### Added
- Microsoft Outlook connector, to read email bodies and attachments, send email with attachments, and move or archive email.

### Changed
- The Slack connection requires the bot token.
- Stricter validation of field and runtime values: values nested too deeply or containing themselves are reported.

### Fixed
- Bug fixes, security hardening and dependency updates.


## 2026-10-01

### Changed
- In expressions, `.class` may only be used to get the class name, and `to_json` takes no arguments.
- A schema or field can no longer be defined twice.

### Fixed
- Bug fixes and security hardening.


## 2026-09-25

### Added
- ClickUp connector, with dynamic options for its location fields.
- A keyword for exploded query parameters.

### Changed
- Expressions may only reference classes on an allow-list.
- A connector's helpers are sealed once it is loaded.

### Fixed
- Bug fixes, including handling of already-encoded query parameter values.


## 2026-09-14

### Added
- Jamf Pro connector for Apple device inventory.
- A schema field can carry a block that lists its options.

### Changed
- Schema field ids may be up to 64 characters (was 40).
- Connector constants must be frozen, and connector files must follow the allowed shape.
- Expressions nested too deeply are refused with a validation error.

### Fixed
- Rotated OAuth 2 refresh tokens are persisted.
- Bug fixes, security hardening and dependency updates.


## 2026-08-24

### Added
- Slack connector.
- GraphQL connector: credential fields and Basic authentication.

### Changed
- Upgraded to Ruby 3.4.10.

### Fixed
- Already-encoded query parameters are no longer encoded again, and empty HTTP response header values are accepted.
- Bug fixes and stability improvements.


## 2026-07-09

### Added
- OAuth 2.0 inbound authentication.
- Batch CSV parse action.

### Changed
- Connection and connector names may be as short as 3 characters.
- Authored expressions run under a timeout, and unused methods were removed from the expression allow-list.


## 2026-07-02

### Added
- HTTP connector: OAuth 2 scope.

### Changed
- The GraphQL and Xurrent connectors cache their schema and queries per connection.

### Fixed
- Dependency security updates.


## 2026-06-22

### Fixed
- Unparseable trigger payloads are rejected with a 400 instead of failing.
- Bug fixes and performance improvements.


## 2026-06-13

### Added
- Date and time methods in expressions.

### Fixed
- Bug fixes and documentation corrections.


## 2026-06-11

### Added
- A `config_tester` function for outbound connections.
- Local helpers in connection templates.


## 2026-06-09

### Added
- Dropdowns and pickers for scheduler fields.
- GraphQL JSON scalars map to the `any` type.

### Fixed
- Bug fixes and performance improvements, including GraphQL schema caching.


## 2026-05-25

### Added
- Initial public release of the `ipaas-connector` and `ipaas-connector-sdk` gems.

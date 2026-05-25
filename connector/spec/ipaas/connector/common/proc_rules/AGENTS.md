# Proc Rules Spec Guidelines

## valid_methods_rule_spec.rb

When adding new methods to `valid_methods_rule.rb`, add them to the existing loop in the spec — do NOT create separate `describe` blocks per method.

The spec uses a single loop over expected-allowed methods, verifying each one passes `validate_method` without error. This keeps the spec DRY and avoids boilerplate for every new allowlist entry.

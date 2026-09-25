# Proc Rules Spec Guidelines

## valid_methods_rule_spec.rb

When adding new methods to `valid_methods_rule.rb`, add them to the existing loop in the spec — do NOT create separate `describe` blocks per method.

The spec uses a single loop over expected-allowed methods, verifying each one passes `validate_method` without error. This keeps the spec DRY and avoids boilerplate for every new allowlist entry.

## known_bad_sources_spec.rb

A **regression** check, not a discovery tool: every source in it is a route that was open once and
is closed now. It finds nothing new, so it should not be taken as automated evidence that all bad
constructs are prevented.

Every rejected entry asserts the **exact** messages, and every rejected entry is paired with a
near-identical accepted twin — one that names only listed paths in consumed or called positions,
since a bare class reference is itself refused. A boolean-only assertion is not acceptable: several of these sources
were already rejected for an unrelated reason (`Marshal.load("x")` on the method name, for one), so
`valid? == false` passes without the rule under test doing anything.

The spec drives `ProcHelper#valid?` rather than a single rule, because two of the three escape
routes span rules. Do not "fix" it back to the sibling specs' `errors_for` single-rule harness.
It clears `ProcHelper.validated_before` in `before(:each)`; without that clear a warm cache
short-circuits `valid?` and every rejection expectation passes for the wrong reason.

## Writing spec sources for these rules

Two traps that make a spec source fail for a reason you did not intend:

- **`ProcHelper.proc_source` extracts the whole enclosing expression, not the block body.** So
  `@connector.helper(:x) { 'hi' }` is rejected as `Access to '@connector' not allowed.` even though
  nothing inside the block touches an instance variable. Hoist the receiver into a local first. This
  is pre-existing behaviour and applies to constants and globals on the enclosing line too.
- **`proc { … }` is a method call in the enclosing expression.** `ProcHelper.proc_source` hands the rules
  `proc { X }`, and `proc` is on no method list, so the source is refused as `Method 'proc' not allowed.`
  before anything inside the block is judged. Write block fixtures as `-> { X }`.
- **A bare identifier is not a local.** A variable captured from the enclosing scope parses as a
  receiverless `send`, so `File.read(p)` fails with `Method 'p' not allowed.` and
  `h.reduce({}) { }` with `Method 'h' not allowed.` Use literals, `params[:x]` or `config`. A local
  assigned *inside* the proc body is fine.

## no_shared_variable_access_rule_spec.rb

Instance, class and global variables only. Its "what stays permitted" list names constants on
purpose: this rule must stay silent on them, or the constants rule's verdict would be duplicated or
contradicted here.

## valid_constants_rule_spec.rb

Tier is an explicit axis: the same source is judged as a String proc and as a block proc, because a
block proc may read the constants its own file assigns and a String proc may not.

Every refusal asserts the exact message and sits beside an accepted twin. Any list planted for a
spec goes in through `stub_const` and an `IPaaS.make_shareable` hash, never a plain `{}`: the rule's
data is deeply frozen, and a stub that is not would pass a shareability check for the wrong reason.

## parser_target_drift_spec.rb

Pins against the **running Ruby** (`RUBY_VERSION`), deliberately not against a `.ruby-version` file:
there are five of those in the repo, a spec run from `connector/` would read a different one than CI
does, and an upgrade touching one but not the other would leave the pin green. Do not "fix" this to
read the file.

The node pin cannot catch a bare target bump on its own — measured, targets 3.4/3.5/4.0 emit an
identical node set because the parser gem knows no newer syntax yet. The version pin is what catches
the upgrade; the node pin catches the gem later catching up to it. Both are needed.

Pins `ProcHelper::TARGET_RUBY_VERSION` to the running Ruby's major.minor, and pins the exact set of
AST node types a fixed source corpus emits at that target. Any major or minor Ruby will trip the version pin;
the node pin trips later, when the parser gem catches up to the new syntax. Re-review every rule against the
changed node forms before re-pinning either.

## helpers_proxy_spec.rb (sibling, `spec/ipaas/connector/common/`)

`helpers` is **not** governed by the rules in this directory, and a source like
`helpers.send(...)` is still **accepted** by every rule here — see the
[rule guidelines](../../../../../lib/ipaas/connector/common/proc_rules/AGENTS.md) for why the
receiver rather than a rule is the control there.

`helpers_proxy_spec.rb` applies this directory's convention one stage later: paired refused and
accepted sources, exact `NoMethodError` messages, and a separate assertion that the rules still
return `valid? == true` for every refused source — without which a case could pass because some
rule started rejecting it. Context is an explicit axis (template, `Action`, auth binding, and a
schema block), because each reaches `helpers` by a different route and a table covering one cannot
see the others.

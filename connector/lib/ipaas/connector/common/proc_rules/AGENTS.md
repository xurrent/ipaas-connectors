# Proc Rules Guidelines

The proc rules provide a first line of defense against malicious code.

Any change to the rules requires explicit mention in risk analysis and PRs and thorough review and automated test coverage.

Especially important to review and highlight are edits to:

- `RUBY_METHODS`
- `ADDITIONAL_METHODS`
- `ProcSafe.registry`
- `ValidConstantsRule::ALLOWED_CONSTANTS` — the list deciding which classes an expression may name
- `ValidConstantsRule::READ_METHODS` — also the source of `HelpersProxy::RESERVED_NAMES`, so an
  edit changes which helper names a connector may define
- `ValidConstantsRule::PATTERN_NODES`
- `REFLECTIVE_METHODS`
- `ValidMethodsRule::SOLUTION_METHODS` — the only methods `solution` may be used to call
- `ClassCallContext` — the positions a `.class` or `solution` value may take
- `ProcHelper::TARGET_RUBY_VERSION`
- `ProcHelper::MAX_SOURCE_BYTES` and `Connector::MAX_SOURCE_FILE_BYTES` — both refuse before
  any parse, and are what keeps iPaaS from having to process too large content
- `ProcHelper::MAX_NESTING_DEPTH` — a source over it is refused before any rule sees it, thereby
  limiting what reaches the parser.
- `Connector#proc_validations`, `Connector.proc_validations_factory`, `ProcHelper::GEM_LIB` and
  `ProcHelper::STRING_PROC_FILE` — the per-connector validation store, what builds it, and the two
  paths that decide which blocks bypass it or are refused. `ValidConstantsRule` asks `ProcHelper` the same
  two questions to decide which blocks are exempt from the list, so the boundaries are defined once. The
  accessors must stay off every method allow-list (a guard spec pins them); a wrong prefix depth
  silently judges connector blocks as the gem's, and a wrong String-proc file routes blocks born
  inside an expression into a connector's store instead of refusing them.

A row on the list permits **reading** the path and calling what it lists, which takes two guards
that are easy to lose in a refactor. Both are covered by specs that fail without them:

- A listed path is refused where it would be a **definition target** (`class << Foo::Bar`,
  `module Foo::Bar`, `Foo::Bar::X = 1`). No rule governs reopening a module, so permitting a path
  as a definition target would let a proc redefine or remove methods on it for the whole process.
- A listed path is refused where it merely **starts a longer lookup**, including when an
  expression carries its value there first — `(Foo::Bar)::X`, `Foo::Bar.itself::X`,
  `[Foo::Bar][0]::X`. Without that, a row naming a namespace that contains constants would
  expose all of them.

See the [spec guidelines](../../../../../spec/ipaas/connector/common/proc_rules/AGENTS.md) for more details on
writing automated tests for the proc rules.

## `ValidConstantsRule::ALLOWED_CONSTANTS`

The list of constant paths an expression may name, and per path the methods it may call on it
directly. It is fail closed and it is the only judge of constants: a path not on it is refused, and
a call on a listed path is refused unless the method is in that path's row.
The list is the same data in every process: nothing on it is derived from what happens to be
loaded, so identical source gets the same verdict wherever it is judged. A row's presence permits reading the
path (`rescue JSON::ParserError`, `raise ArgumentError`, `is_a?(Hash)`); an empty list adds no
method to that.

Rules for the data, each covered by a spec that fails without it:

- **Exact paths, root first, no prefixes.** `[:OpenSSL, :HMAC]` does not admit `OpenSSL::Digest`,
  and a namespace is a separate row nothing needs today. `::JSON` and `JSON` are the same row.
- **A row is a surface, not a name.** Assume any method the method lists permit is callable on any
  object an expression can reach, so assess what every listed method exposes before adding it. A
  row governs the direct spelling `Path.method`; a class may otherwise appear only where the
  construct consumes it — a `rescue` list, the condition of a `when`, a pattern (`case … in`,
  `x in C`, `x => C`, and the sub-patterns inside them), or an argument to `raise`, `is_a?`,
  `kind_of?` or `instance_of?` (`READ_METHODS`; no helper may be registered under those names,
  so `helpers.raise(Time)` is refused on dispatch however the proxy is reached). Bound to a
  variable, placed in a literal, left in a body (an array literal in a rescue body included) or
  passed to anything else it is refused, because from there the method lists alone would govern
  what is called on it. A value constant
  (a listed path that is not a class or module) may be read anywhere.
- **A pattern is a position, and the two families spell it on opposite sides.** `x => Array`
  matches; `Array => a` binds the class and hands it to the author; both are a `match_pattern`
  node. So a class is accepted at the last child there, and at the first child of an `in`.
  `PATTERN_NODES` adds the sub-pattern nodes, which need no position because every child of
  one that can hold a class is itself a pattern. Pattern-only is **not** the test, and reading
  it as one is how a hole gets added: `if_guard` and `pin` are pattern-only too, they hold an
  evaluated expression, and listing either would permit `in a if Array` and `in ^(Array)`.
  A `pair` needs its position for the same reason from the other side — a hash literal and a
  keyword argument build that node too — so it counts only under a `hash_pattern`, which is
  what keeps `x = {a: Time}` and `x.is_a?(Time => 1)` refused.
- **Deeply frozen.** The constant is built with `IPaaS.make_shareable`; a mutable list is a list
  anyone can widen at run time.
- **Additions cite the corpus.** A row exists because content needed it, and the request adding
  it names the uses. Prefer a `proc_safe` verb where the need is one narrow operation.

Two things an expression may name without a row, each judged by where the block was written:

- **A block's own constants.** A block written in a connector file may read the constants that file
  assigns; an alias among them to a module a connector body may name is judged as that module, so
  its row applies under the alias too. Ownership is by file, not by presence in the lexical scope:
  the scope also holds whatever evaluated the file. The verdict depends on the block's file while
  `ProcHelper#validation_cache_key` is the source text alone; that holds because every block in a
  connector's store comes from that connector's one file.
- **This gem's own blocks.** A block the DSL hands over at load from one of this gem's files is
  exempt from the list. This is a deliberate widening: the gem's blocks are ours, shipped with it and
  validated at boot, and the exemption is what lets DSL-internal reads need no rows. The one gem
  file an author's code is evaluated in is where String procs run, so a block born there is not
  exempt, and a Proc a String proc produces must never be handed back to the validator.

Registered in `BASIC_RULES`, and the only rule `NodeValidator` hands the block to (`node_validator_spec`
pins both).

## `.class` is for the class name only

`.class` reaches the class of any value a proc holds, and no constant row governs what is then
called on it, so it may only be used for the class's name. `ClassCallContext.permitted?` decides
which positions qualify, and `ValidMethodsRule` refuses every other `.class` and `&:class`.

## `solution` answers only its listed methods

`solution` is off the allowlist and judged by position: accepted only as the receiver (or the
stringified `name`) of a method in `SOLUTION_METHODS`, decided by `ValidMethodsRule.solution_call_permitted?`.
A `&:solution` or reflective `:solution` is refused by name, the way `to_json` is.

## An assignment is judged as its explicit expansion

`on_op_asgn` (aliased to `on_or_asgn`/`on_and_asgn`) exists so a shorthand assignment is validated
exactly as the source it expands to would be. The expansion is not always the same program, so the
invariant is scoped: `a ||= 1` declares the local, while `a || a = 1` reads a receiverless send.

Deriving the setter is guarded on the target being a call. A shorthand assignment targets a local
at least as often as an attribute, and `a ||= 1` refused as `Method 'a=' not allowed.` would reject
far more than it protects.

A rule that governs reads has to answer the same question for writes: refusing `$g` while letting
`$g = 1` through is the shape of the mistake. Ask it of every assignment node type, not only the one that
prompted a change. `ValidConstantsRule` answers it in `dispatched_methods`, where a row listing a reader
would otherwise carry `Path.reader ||= 1`: the writer that form calls is spelled nowhere, so it is
derived from the target and judged beside the reader.

## `helpers` is exempt here on purpose

`ValidMethodsRule#top_level_helper?` skips the allowlist for the first send off a receiverless
`helpers`, because the names in that position are connector-defined and no fixed list can hold
them. The control is the receiver, not the rule: `Helpers#for_proc` hands a proc a `HelpersProxy`
(a `BasicObject`) that dispatches registered helper names and nothing else.

Two consequences when changing anything here:

- A source such as `helpers.send(...)` is **accepted** by these rules and refused on dispatch. That
  is correct, not a gap. Regression cover lives in
  `../../../../../spec/ipaas/connector/common/helpers_proxy_spec.rb`, not in the specs beside these
  rules.
- Do not move that check into a rule. Such a rule would have to be aware of the helpers defined at
  the moment the proc is actually executed. This is not possible with static analysis (or at least
  very hard and error-prone): validation can run before the connector has finished registering, and
  its result is cached against the proc source alone, so the verdict would fall to whichever context
  happened to be validated first. The current approach lets a proc name anything on `helpers`, and
  refuses on dispatch everything the connector did not register — there is no list of permitted
  names to maintain.

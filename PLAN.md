# Tree-sitter in MoonBit

## Scope and decisions

Port the full functionality of `.repos/tree-sitter` to pure MoonBit, including
the parser runtime. Upstream baseline: `4a412a01a0147d0f50bf7e749572fa632d1ab203`
(workspace version 0.28.0). The reference checkout remains untouched and is not
vendored into this repository. Preserve its MIT license and attribution.

Grammar definitions are MoonBit programs (`grammar.mbtx`), executed by
`moon run`, using a typed grammar DSL. There is no JavaScript grammar evaluator,
Rust generator, C parser runtime, or FFI in the delivered implementation.
Support the upstream grammar JSON interchange format for migration and tests.
The portable library must work on native, JavaScript, and Wasm GC; filesystem
and CLI integration may use native MoonBit standard libraries.

## Milestones and acceptance checks

Each checked item means implemented and tested, not merely scaffolded. Commit
small coherent changes after the relevant checks pass. Keep this plan updated
with concrete evidence and remaining compatibility gaps.

- [x] 0. Establish the source baseline, project, and implementation plan.
- [ ] 1. Grammar frontend: typed rules, mbtx execution, grammar JSON round trip,
      validation and actionable diagnostics. Cover every upstream rule variant
      and explicitly reject unsupported options until their implementation.
- [ ] 2. Lexical generator: Unicode scalar sets, regex parsing, NFA construction,
      DFA generation, longest match and lexical precedence, immediate tokens,
      keyword extraction, external scanner protocol.
- [ ] 3. Parse-table generator: rule normalization, repetition, fields, aliases,
      FIRST/nullable, LR states, static precedence and associativity, explicit
      conflicts, dynamic precedence, inlines, supertypes, reserved words,
      table serialization and deterministic MoonBit emission.
- [ ] 4. Runtime: contextual lexing and GLR parsing, syntax trees, hidden nodes,
      fields and aliases, byte/point locations, tree cursors, missing/error
      recovery, cancellation and resource limits.
- [ ] 5. Incremental runtime: edits, invalidation, subtree reuse, included ranges,
      changed ranges, scanner-state persistence. Compare incremental trees with
      fresh parses across sequences of edits; measure actual reused work.
- [ ] 6. Query engine: query grammar, validation, structural matching, captures,
      fields, anchors, alternatives, quantifiers, predicates, properties,
      cursor ranges, limits, cancellation, upstream query regression cases.
- [ ] 7. Highlighting and tags: query-based captures, locals, injection handling,
      highlight events/HTML, definitions/references, documentation extraction.
- [ ] 8. Loader/config/CLI: generate, parse, corpus test, query, highlight, tags,
      grammar discovery, diagnostics and exit codes; reproducible mbtx examples.
- [ ] 9. Compatibility/performance gate: upstream corpus and API test inventory,
      differential tests against the reference (development only), fuzz/edits,
      cross-target tests, representative benchmarks and user documentation.

## Architecture

Public packages own their types: `grammar`, `language`, `generate`, runtime
(root package), `query`, `highlight`, `tags`, and `loader`. Internal packages
hold regex/compiler helpers. `cmd/treesitter` provides the CLI. Serialized
languages separate grammar generation from runtime use. Runtime tests must
also exercise real generated languages, not only handwritten tables.

## Validation policy

Run `moon check --warn-list +unnecessary_annotation` frequently, targeted tests
per change, then `moon fmt` and `moon info` before commits. Check generated API
changes. Exercise native, JS and Wasm GC for portable functionality. Port
upstream fixtures with their attribution and assert expected behavior; do not
silently update expected output to match a divergent implementation.

## Progress and known gaps

Planning baseline only. No runtime or compatibility claims yet. The upstream
runtime alone contains approximately 15,000 lines of C; full completion means
all milestones and the compatibility gate, not merely parsing one language.

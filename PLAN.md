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

### Grammar frontend checkpoint

Typed rule IR covers all 19 upstream rule variants. Grammar JSON round trips
preserve start-rule order and metadata. Reference and shape diagnostics are
covered by 5 tests passing on native, JS and Wasm GC. The mbtx example is written,
but the installed `moon` resolves standalone imports only from the registry;
local unpublished imports need a development runner. Milestone 1 remains open
until that path is exercised. Regex and parser-specific validation belong to
subsequent compiler passes.

### Lexer checkpoint

Implemented scalar range sets, regex AST, Thompson NFA and deterministic subset
construction, longest-prefix scanning, Unicode property categories/scripts/
script extensions/binary properties, Unicode `\d`/`\s`/`\w`, case folding matching
upstream's long-s/Kelvin exclusions, and malformed UTF-8 progress. Unicode 16.0.0
DATA comes from the checksum-verified regex-syntax 0.8.11 pinned by upstream;
its license and a development-only importer are included. No Rust is executed.
Ten tests pass on native, JS, and Wasm GC. Remaining lexical work includes inline
flags, class set operations, combined contextual automata and external scanners.

### Parse-table checkpoint

Implemented lexical extraction, repetition normalization, fields/aliases,
inline expansion, nullable/FIRST analysis, canonical LR(1) item closure and
state construction, numeric precedence/associativity, declared GLR conflicts,
dynamic precedence metadata, deterministic table construction, resource limits,
and language table validation. Four compiler tests bring the suite to 14 tests,
passing on native, JS and Wasm GC. Named precedence, reserved contexts, word
extraction, supertypes, external scanners and nonterminal extras are explicitly
rejected pending implementation. Runtime integration is next.

### Runtime checkpoint

The root package now contains a pure MoonBit GLR parser, contextual token
selection, lexical precedence, numeric dynamic precedence, bounded recovery by
insertion/deletion, UTF-8 locations, persistent syntax nodes, fields, aliases,
hidden-node flattening, named extras, tree cursors and cancellation/work limits.
Six integration tests exercise generated languages and expected trees; 20 tests
pass across native, JS and Wasm GC. Recovery is not yet upstream-equivalent.
Incremental reuse, included ranges, scanner persistence and complete node/cursor
API coverage remain open.

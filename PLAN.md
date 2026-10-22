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
- [x] 1. Grammar frontend: typed rules, mbtx execution, grammar JSON round trip,
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

The grammar frontend is complete. Compiler, runtime, query and tooling packages
have working, tested implementations; their full compatibility milestones remain
open. The checkpoints below are chronological: later entries supersede earlier
feature gaps. Full completion requires every milestone and the compatibility gate.

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

### Incremental checkpoint

Added persistent tree copies, input edits, byte/point relocation, change flags,
conservative suffix-subtree reuse guarded by identical remaining source and LR
entry state, and structural changed ranges. Reuse counters and parser-step
counts are observable. Tests verify identity reuse, reduced parser steps,
fresh/incremental agreement, newline relocation, consecutive edits, and fallback
when source changes without edits or languages differ. 23 tests pass on all
three targets. This is conservative reuse, not yet upstream's full reuse and
changed-range algorithms; included ranges and external scanner states remain.

### mbtx and language artifact checkpoint

A native MoonBit loader now executes local unpublished mbtx grammars in an
isolated temporary workspace, preserving source line numbers and cleaning up
afterward. No publishing or global registry changes are needed. The CLI supports
`grammar-json`, `generate`, `parse`, and `emit`. A versioned, validated language
JSON format carries precompiled lexer/parse tables; generated MoonBit factories
load those tables without the generator. The mbtx arithmetic example has been
executed end to end and its emitted factory is tested on all three backends.
The CLI's filesystem/process support uses moonbitlang/async 0.20.2. Core parser,
lexer, generator, and query packages do not import that dependency.

### Query checkpoint

Added query tokenization/validation, node and anonymous-token patterns, fields,
negated fields, captures, alternatives, named-sibling anchors, child quantifiers,
equality/regex/any-of predicates, property settings, source-order captures,
byte-range filtering and explicit cancellation/work/match limits. Five query
regressions are included. The suite is now 32 passing tests on native, JS and
Wasm GC. Supertype patterns, grouped sibling patterns, custom property predicates,
upstream-complete quantifier semantics, streaming cursors and injection predicates
remain compatibility work; unsupported predicates currently fail explicitly.

### Upstream corpus checkpoint

Frozen 14 grammar fixture groups directly from the pinned upstream checkout,
retaining expected corpus output. The development-only importer evaluates the
reference JS DSL once; all committed tests execute with the MoonBit compiler
and runtime. Fixed innermost field inheritance, immediate-token preference and
shift/reduce precedence using the upstream active-item/FIRST-set algorithm.
Added a portable corpus reader/runner and CLI `test` command. Whitespace-only
inputs are preserved. 47 tests pass on native, JS and Wasm GC. This is a selected
compatibility suite, not the complete upstream test matrix.

### Generator compatibility expansion

Named precedence now follows upstream's ordered name/rule comparisons. Keyword
capture uses the grammar's word token to reject keyword prefixes of longer
identifiers. Anonymous underscore-prefixed tokens remain visible. The selected
upstream matrix now contains 26 fixtures (including one generation-only fixture
without upstream expected output and one required conflict rejection). 64 tests
passed on all three targets after these changes. Precedence metadata was added
to the portable format and the emitted arithmetic factory was regenerated.

### Incremental hardening

A 40-edit growth/shrink regression compares every node's kind, fields, flags,
byte range and point range against fresh parses. Candidate reuse is deliberately
disabled for tables with GLR conflicts until reusable parse forests are available;
reusing only a previous winning derivation could change dynamic precedence.
Node IDs are advanced before accepting a tree produced by another parser.

### Highlighting and tags checkpoint

Added balanced highlight events, dotted capture-name configuration, HTML escaping,
and query-driven definitions/references with names, source ranges and documentation
captures. CLI commands `query`, `highlight` and `tags` now exercise these packages.
Locals, language injections and documentation transformation directives remain
open. These additions and included-range work pass 69 tests on all three targets.

### Included ranges checkpoint

The runtime can parse ordered disjoint source ranges, validates UTF-8 byte/point
coordinates, and projects nodes back into the original source. Tokens can span
range boundaries. Trees retain and edit their included ranges. This path reparses
rather than applying ordinary subtree reuse to projected coordinates. Regression
coverage checks disjoint lines, tokens spanning gaps, invalid ranges and cache
isolation; 69 tests pass on native, JS and Wasm GC.

### Supertype checkpoint

The generator validates hidden supertype categories and the runtime retains their
actual reduction paths. Queries support `(supertype)` and `(supertype/subtype)`;
identically named concrete nodes outside that category do not match accidentally.
Supertype metadata survives language serialization. Terminal and multi-child
supertypes are rejected, including the pinned upstream terminal-supertype fixture.
72 tests pass across all backends. The upstream hidden-field/supertype fixture also
uses nonterminal extras, so it remains outside the passing compatibility set.

### External scanner checkpoint

Grammar externals now generate terminal metadata, including internal-token
fallbacks and anonymous externals. Pure MoonBit scanner callbacks receive valid
symbols, a Unicode cursor and a per-branch serialized state (maximum 1024 bytes).
The cursor supports skip, mark-end, EOF, Unicode columns, cancellation checks and
included-range boundaries. Zero-width tokens and extras cannot spin unchanged.
Snapshots are retained on nodes; scanner-aware incremental reuse remains disabled
until scanner lookahead dependencies can be verified. Five upstream scanner
fixtures are ported without changing their corpus expectations. 81 tests pass on
all three targets. Native scanner libraries are never loaded; scanners must be
written in MoonBit and supplied to the runtime.

### Reserved words checkpoint

Reserved keyword sets now affect lexical selection only when the word token would
otherwise win. Context overrides survive normalization, LR closure and reduction
lookahead, allowing property names that are reserved globally. Portable tables
carry the resulting per-state sets. Regression tests cover both accepted and
rejected identifiers and reduction boundaries; 83 tests pass on all backends.
Full upstream reserved-word corpus parity still depends on error recovery.

### Reproducible examples checkpoint

Added a complete mbtx JSON grammar, generated factory, nested Unicode/escape and
invalid-input tests, query highlights, executable README example, and a single
`tools/check.sh` verification command. The emitter now produces formatted syntax
without deprecation warnings. The script checks all 86 tests on native/JS/Wasm GC,
executes both mbtx grammars, compares regenerated factories byte-for-byte, and
smoke-tests parse/highlight commands. No reference checkout is needed for this
normal validation path. Full port completion remains open as detailed above.

### Runtime scaling checkpoint

A reproducible native release benchmark exposed quadratic copying in hidden
repetitions: 100 versus 1000 JSON objects took roughly 0.86 versus 26.9 ms.
Persistent child segments with cached materialization reduced those measurements
to 0.74 versus 7.9 ms on the same machine. An edit/reuse case measured 0.46 ms
versus 0.75 ms for a fresh parse. These are local observations, not upstream parity
claims or CI timing thresholds. An additional 2000-object test verifies child
order, counts and fields. All 87 tests pass across native, JS and Wasm GC.

### Regex compatibility checkpoint

Added nested classes, ASCII POSIX classes, intersection/difference/symmetric
difference, leaf-level case folding before negation and set operations, global
and scoped i/s/u flags, safe ASCII-only byte classes, lazy-quantifier syntax with
longest-match lexical semantics, and a nesting limit. Expectations for nested
folding and scoped flags are ported from the pinned upstream lexer tests. Other
flags and complete regex diagnostics remain open. `tools/check.sh` passes all
89 tests on three backends and reproduces both committed mbtx-generated factories.

### Nonterminal extras checkpoint

Nonterminal extras now have canonical LR entry states and independent runtime
frames, preserving surrounding stacks, fields and serialized scanner state.
Nested extras share ordinary grammar rules; hidden extra children do not inherit
unrelated surrounding fields. The upstream `extra_non_terminals`,
`extra_non_terminals_with_shared_rules` and `field_lookup_through_hidden_nodes`
corpora pass unchanged. 92 tests pass on native, JS and Wasm GC.

### Completion and release requirements

After closing the remaining compatibility gaps, run Codex CLI with ultra reasoning
for an independent review, address actionable findings and rerun validation.
Then create `moonbit-community/treesitter`, use `moonbit-community/treesitter` as
the module name, configure CI and a release publishing workflow, and publish to
mooncakes.io. These release actions were explicitly requested by the user.

### EOF and external word compatibility

EOF constraints now gate reductions rather than shift a fake terminal. Discarded
EOF alternatives do not poison reachable repetition branches, and equivalent
unconditional reductions subsume EOF-only reductions. Invisible start rules are
rejected. External word tokens and nullable regex tokens are accepted, matching
upstream scanner fixtures. Five more scanner callbacks and 17 reference fixture
groups bring the suite to 109 tests across native, JS and Wasm GC. CLI diagnostics
now expose the underlying error detail. A development audit inventories all 74
upstream grammar fixtures separately from the frozen, passing test suite.
EOF recovery shape and other broader recovery cases remain open.

### Scanner boundary compatibility

Ported the percent-string/interpolation, lookahead-to-EOF, inverted token range,
and supplementary Unicode scanner fixtures to MoonBit callbacks. Scanner ranges
now clamp their start to a previously marked end after later skip advances,
matching the reference lexer. A direct get-column-at-EOF regression supplements
its generation-only upstream fixture. 115 tests pass on all three targets.

### Query groups, local bindings and documentation directives

Sibling pattern groups now match adjacent roots, including nested groups and
quantified documentation captures. Property predicates accept caller-provided
state; general predicates accept explicit evaluators and fail when none exists.
Local queries resolve references through lexical scopes, honor scope inheritance,
and exclude the definition's initializer. Tags apply select-adjacent! and strip!
to documentation captures. Regression tests cover sibling captures, callbacks,
shadowing, initializers and documentation gaps.

### Local and injected highlighting

Highlight configurations accept locals and injection queries. References inherit
their definition's highlight; local property predicates can exclude special
patterns. Injections resolve languages through a caller callback, support self,
parent, combined content and child exclusion, intersect parent included ranges,
and enforce a recursion limit. Highlight spans remain in original UTF-8 source
coordinates and are clipped to disjoint injection ranges. Cross-target regression
coverage includes combined content separated by host-language delimiters.

### Corpus CST mode

The corpus reader now accepts :cst and ignores s-expression comments outside
strings. A portable CST renderer includes anonymous tokens, fields, ranges and
leaf text. The pinned basic_cst fixture passes unchanged. The complete current
suite contains 122 passing tests on native, JavaScript and Wasm GC.

### Lazy query cursor and navigation

Queries now expose a lazy match cursor with lifetime-wide work limits,
cancellation between results, byte/point ranges and maximum starting depth.
Tree navigation adds point descendants, named field lookup, preorder seeking,
cursor copying/resetting, and tree-relative parent/sibling lookup. Tree lookup
uses persistent node identity rather than parser-local numeric ids. Targeted
runtime/query/lexer tests (44) pass on native, JavaScript and Wasm GC.

### Remaining regex flags and named groups

Regex compilation now accepts scoped/global extended whitespace and comments,
CRLF-aware dot semantics, multiline and ungreedy flags (assertions still reject,
and DFA matching retains longest-match behavior). Escaped spaces and hashes
remain literal. Named capture groups compile as ordinary groups with duplicate
name validation. These semantics are covered by cross-target lexical tests.

### Metadata, discovery and native CLI

Added tree-sitter.json metadata parsing, file/extension/content/shebang and
injection-language selection, deterministic discovery of configured grammar
folders, query-file loading, and loading generated tables or mbtx/JSON grammars.
The native CLI supports language listing, configuration initialization, automatic
parse-language selection, CST output and recursive corpus directories. Portable
selection tests pass on native/JS/Wasm GC; native filesystem discovery is tested
in temporary directories. Automatic selection was exercised end-to-end from the
JSON example directory, compiling its mbtx grammar and parsing sample.json.

### Release preparation

Prepared Linux/macOS CI and a release-tag-checked Mooncakes publishing workflow.
Both execute the full validation script before publication. Publishing expects
the MOONCAKES_TOKEN secret as the Mooncakes credentials JSON and removes the
runner's temporary credentials afterward. Workflow YAML parses successfully.
GitHub creation, remote CI verification and registry publication remain pending;
the port is not yet release-ready. Codex CLI 0.153.4 is running an early review
with its configured gpt-6-astra model and reasoning effort ultra, focusing first
on the remaining recovery mismatch and then release blockers. A final review
and fixes are still required before release.

### Ultra review repairs and recovery competition

Codex CLI ultra reviewed the implementation and reported seven concrete defects.
Fixed scoped/static and dynamic precedence, assertion-aware regex matching,
separator visibility, tag precedence, compound extensions and empty-root edits;
added regression coverage. Recovery now pauses failed branches, retains competing
recovery continuations, bounds speculative recovery versions, and compares
subtree costs including missing tokens and error grouping. The frozen upstream
error_recovery_loop corpus now passes unchanged. UTF-8 callback input is also
implemented with cancellation and an input-size bound. Native: 152 tests pass;
portable target results and broader real-language corpora are the next gate.
The pinned generator now builds with Rust 1.90 as a development-only reference.

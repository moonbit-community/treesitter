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

### Real JSON corpus and node schemas

The pinned JSON v0.24.8 grammar now passes all six unchanged upstream error
corpus cases. Lexer failures retain invalid runs and the failing EOF codepoint;
corpus comparison optionally omits fields as upstream does. The same corpus
passes with the pinned reference generator/runtime. Native/JS/Wasm GC: 153/152/152.

Added language.node_types() and the native node-types command. It describes
aliases, hidden-rule field propagation, recursive cardinalities, supertypes,
root/extra flags and lexical identities. Differential comparison matches JSON
and 61 of 62 accepted upstream fixture schemas exactly; those 61 schemas are
frozen as portable regressions. The remaining uses_current_column difference is
its block's named-child required flag: this implementation computes true for
repeat1(statement), while upstream reports false. Track this metadata difference
rather than changing either expected snapshot silently. tools/audit_node_types.py
reproduces the complete schema audit with the pinned generator.

### Query controls, scanner reuse and resumable parsing

Added a capture cursor that interleaves enclosing and nested matches in source
order while retaining each match's metadata. Queries expose pattern byte ranges,
disabled patterns/captures, and reject impossible named-child/field combinations.
Capture predicates still see disabled captures before output filtering.

Unambiguous scanner languages can reuse unchanged suffix subtrees when incoming
scanner snapshots and Unicode columns match; reuse restores the outgoing snapshot.
Ambiguous tables still conservatively reparse. Cancellation saves the actual parse
stacks, lookahead, recovery competition and budgets. resume_parse continues them;
reset discards them, and parse starts fresh. Included-range resumes restore source
coordinates. Native: 221 tests pass; runtime and query changes pass JS/Wasm GC.

### Encoded input

Added UTF-16 little/big endian input with source-byte offsets/point columns,
malformed-surrogate progress, cross-range decoding, scanner Unicode columns,
node/tree text decoding and projected resume state. UTF-16 injection highlighting
uses the same encoding and renders decoded HTML. Unchanged encoded trees can be
reused as a whole; edited encoded ranges currently reparse. Native: 225 tests;
43 runtime/highlight tests pass on JS and Wasm GC.

Incremental prefix reuse now records lexer and reduction lookahead dependencies,
including failed longer-token alternatives, external scanner reads, and EOF.
Unchanged prefixes can be reused without assuming that all following input is
unchanged. Regressions cover distant edits changing token choice and insertion
at an observed EOF. The full native, JavaScript, and Wasm GC check script passes.
Large C and JavaScript grammars reach the canonical LR state budget; kernel
storage and closure construction are the next scaling work, before release.

Canonical LR generation now interns kernels rather than retaining full closures,
and precomputes FIRST/reserved lookaheads for each production suffix. The default
state budget is 100,000. C v0.24.2 generates 21,091 states/1,134 productions and
JavaScript v0.25.0 generates 17,098 states/1,003 productions. All 229 native and
228 portable tests pass, including the state-merging lexical conflict fixture;
no LALR merging or lexical-context widening was introduced. Both committed mbtx
factories still regenerate byte-for-byte.

The C corpus exposed lexical tie ordering and named-extra boundaries. Equal
regex matches now use grammar extraction order, including anonymous tokens in
earlier rules. Named extras restart immediate-token recognition; anonymous
separator whitespace still prevents immediate matches. Focused regressions and
the native suite pass; generated examples have been regenerated for the intended
token-order change.

GLR branch convergence and accepted-tree selection now compare immutable hidden
production hierarchies after error cost and dynamic precedence. This prevents
queue timing from selecting a shorter hidden derivation over the grammar's
earlier alternative. All 85 C v0.24.2 corpus cases pass after this and the lexical
fixes. The full check script passes 232 native / 231 JS / 231 Wasm GC tests.

Changed ranges now use synchronized visible-tree cursors with padding intervals,
rather than widening changes to every parent whose child count differs. Insertion
at a node's right boundary resizes that edited node as upstream does. A frozen
matrix of 229 edits, generated by the pinned C runtime against JSON v0.24.8,
matches exactly; each case also compares incremental and fresh trees. The
reference regeneration helper is tools/import_changed_ranges.py. The full check
script passes 233 native / 232 JS / 232 Wasm GC tests. Broader language/error and
included-range differential coverage remains part of the compatibility gate.

The native command runner is now a reusable `cli` package. The executable accepts
`--scanner scanner.mbtx` before a command, compiling a public language-name scanner
registry into an isolated MoonBit workspace. The registry is used for parsing,
corpus tests, query/tag input, root highlighting, and injected languages. The
quoted-language example exercises compilation and parsing in tools/check.sh.
Native type checking and native interface inspection are included in CI checks.
The full script passes (233 native / 232 JS / 232 Wasm GC tests plus all CLI smoke
checks). README compatibility notes now reflect current implementation status.

Incremental reuse now accepts deterministic regions in grammars that contain GLR
conflicts. Nodes created with competing actions/stacks retain a fragility flag,
including through hidden reductions and final extra attachment, and are never
reused. A 160-edit stress sequence compares every node with a fresh parse. It
also exposed stale recovery dominance entries: when paused competitors are
removed, their visited configurations must no longer suppress the resumed stack.
Resetting that recovery epoch fixes a reproducible NoParse on malformed input.
All checks pass: 234 native / 233 JS / 233 Wasm GC plus CLI scanner compilation.

Query validation rejects anchors at group edges, duplicate required occurrences
of a single-valued field, and supertype paths whose subtype is not a member.
Structural/node/field diagnostics now retain source byte offsets, including
queries with UTF-8 comments. Eighteen query tests pass on native, JS, and Wasm GC;
the complete native suite passes 236 tests. Sequence validation beyond these
schema constraints remains in the broader upstream API audit.

Public grammar coverage now includes a pure MoonBit JavaScript v0.25.0 external
scanner. Its complete upstream corpus exposed an inline metadata bug: an alias
or field on the removed inline step must override each inserted step's metadata.
The fix passes a focused regression on all three targets and the full native
suite (238 tests). C remains 85/85; JavaScript reaches 113/116 with imports,
object/block ambiguity, and reserved-word identifiers still under investigation.

The public JavaScript imports test also exposed duplicate lexical extraction:
`token("import")` in a named rule and anonymous `"import"` in another rule must
share one token. Named rules with shared lexical definitions retain their syntax
wrapper. Token identity now removes plain token wrappers, and syntax retention
uses lexical occurrence counts. Two focused regressions cover shared strings
and named patterns. The complete check script passes 240 native / 239 JS / 239
Wasm GC tests and CLI smoke checks; the expanded public matrix is being rerun.

The pinned public matrix now includes Go v0.25.0. Its first generation attempt
identified overly strict validation of a rule listed as both inline and a
supertype: upstream drops that supertype entry and keeps the inline rule. The
port now does the same, with cross-target regression coverage. Go generates
15,481 states and passes 64/67 corpus cases; reserved-keyword recovery, string
literals, and generic calls remain to investigate. Latest public results are
JSON 6/6, C 85/85, JavaScript 115/116, Go 64/67. Upstream itself passes all 116
JavaScript parse cases, confirming the remaining await/identifier discrepancy.

The second Codex CLI ultra audit completed in _build/second-ultra-review.md,
reporting seven concrete defects and additional full-port coverage gaps. Its
1,153 edit probes found no incremental/fresh node mismatch but did find upstream
changed-range discrepancies. Publication remains gated on these findings.

Fixed recovery root bounds: finishing an empty root with pending ERROR syntax
now includes that syntax in the root's extent. A pinned JSON regression checks
incomplete-array root bounds and the empty-to-incomplete changed range on all
three targets. This addresses second-audit finding 1.

Second-audit query findings 4–7 are fixed: independent repeated-child runs remain
visible; skipped optional/repeated children transfer or remove anchors according
to their direction; anonymous tokens can begin sibling groups; absent optional
captures satisfy universal predicates, including empty capture pairs. Parent
captures now precede descendant captures within a match, preserving same-node
capture order. Twenty-two query tests pass on native, JS, and Wasm GC, and the
full native suite passes 246 tests. These cases are derived from the pinned
reference probes, with expected capture-order assertions corrected accordingly.

Second-audit finding 2 is fixed: nodes whose start is deleted by an edit now
collapse at the replacement's end, including their row/column coordinates.
Replacement text is no longer assigned to each overlapped sibling. A reference
importer freezes 123 edited-tree span cases covering punctuation, nested nodes,
multiple siblings, and newlines; every node's byte and point spans match C on
all targets. The focused changed-range regression now reports [1,3) for
`1 2 3` -> `113`. Replaying the audit's 1,153 edits reduces matching-tree range
discrepancies from 106 to 35, with zero incremental/fresh node mismatches;
remaining changed-range differences still require investigation.

Second-audit finding 3 is fixed: lexical expressions retain scoped precedence on
DFA transitions. Contextual lexing advances competing DFAs together when scoped
precedence is present, so a completion competes with the next transition rather
than only final longest matches. Weighted transitions survive serialization;
legacy three-field transitions remain readable. Positive and negative scoped
precedence examples match pinned C output on all targets. The complete check
script passes 250 native / 249 JS / 249 Wasm GC tests and all CLI checks. The
public matrix remains JSON 6/6, C 85/85, JavaScript 115/116, Go 64/67. All seven
concrete second-audit findings now have fixes and regression coverage, while
broader changed-range, GLR, API, CLI, and performance coverage remains open.

Public JavaScript now passes all 116 corpus cases; Go reaches 65/67 with only
two malformed-input recovery cases remaining. Live equivalent stack links keep
the first derivation before a shift, with shared prefix/leading-node checks;
completed trees still use hierarchical comparison. Reductions complete before
other queued versions advance. Missing-token recovery considers tokens in
extraction order and keeps the first viable insertion, matching upstream's
selection. Focused C-oracle regressions cover nested await/call ambiguity and
missing punctuation versus an external semicolon. The complete check script
passes 252 native / 251 JS / 251 Wasm GC tests and CLI smoke checks.

Added pure MoonBit parser logging via LogType and Parser.set_logger, covering
lexical recognition, process/shift/reduce, missing-token insertion, recovery,
and acceptance. Logging is optional, persists across reset/resumption, and
allocates diagnostic strings only when enabled. Cross-target tests cover
installation, disabling, reset, and cancellation/resumption. A development trace
shows a remaining Go recovery problem: a context-only raw-string-content token
can consume the rest of the source in fallback lexing. Upstream's recovery-token
conflict analysis excludes such tokens; the port still needs that analysis.
The pinned reference generator/runtime was also verified at Go 67/67.

Custom input decoding now accepts a stateless application decoder while retaining
original byte coordinates. Invalid scalar values and byte counts become U+FFFD
with guaranteed forward progress. Decoder identity gates incremental reuse;
node text, points, and external scanner columns use the same decoding path.
Three tests cover Latin-1, variable-width scalars, malformed decoder results,
and scanner columns. The complete check script passes 257 native / 256 JS /
256 Wasm GC tests and the CLI smoke checks.

Recovery lexing now uses generated token-conflict analysis instead of every
lexical token. The analysis accounts for separator prefixes, token continuation
characters, precedence, coincident parse-state tokens, and keyword protection.
Invalid-character runs use the same filtered vocabulary and retain their
lookahead dependencies. Existing serialized tables remain readable; generated
examples now include the recovery vocabulary. A pinned C-oracle regression
checks that string-content tokens cannot consume later words/comments after an
invalid character. All checks pass (259 native / 258 JS / 258 Wasm GC). The Go
string-literal corpus case now passes: Go is 66/67, with reserved-keyword recovery
still open. JSON 6/6, C 85/85, and JavaScript 116/116 remain passing.

Recovering to an earlier stack state now detaches trailing extras before
constructing ERROR and reattaches them afterward, matching parser.c's
recover_to_state. A C-reference fixture checks both comment placement and the
error's byte extent. This fixes the comment placement in the second half of the
remaining Go case, while its first competing parse still needs scheduling work.

Query API coverage now includes capture quantifiers (sequence/alternative/
repetition algebra), predicate/directive inspection, cursor-local match IDs,
and removal of a match's remaining captures. Byte/point containing ranges
constrain all matched nodes, including uncaptured roots and sibling groups,
and can be combined with intersecting ranges. Zero end coordinates are treated
as unbounded. All checks pass: 266 native / 265 JS / 265 Wasm GC tests and CLI
smoke checks. The stable public grammar matrix is JSON 6/6, C 85/85,
JavaScript 116/116, Go 66/67. An experimental paused-stack pruning change made
Go 67/67 but regressed upstream error_recovery_loop; it was reverted. Proper
stack-round scheduling remains required rather than a token-shift shortcut.

The pinned grammar audit now compiles every shipped .scm query file using the
new `query --check` CLI mode, without needing source input or an external scanner.
All 11 files pass (JSON 1, C 2, JavaScript 6, Go 2). Compilation and corpus counts
are reported separately, with any failure keeping the audit nonzero. This does
not yet validate annotated highlight/tag execution fixtures. The stable corpus
counts remain 6/6, 85/85, 116/116, and 66/67 respectively.

The CLI now scaffolds mbtx grammar projects with `init <name> <directory>`:
portable grammar source, tree-sitter.json metadata, a corpus case, highlight
query, sample input, README, and ignore file. Names are validated, existing files
are checked before creation, and writes are exclusive. The metadata intentionally
starts UNLICENSED until the grammar author chooses a license. Native tests cover
name validation and overwrite refusal; tools/check.sh initializes a temporary
project, compiles its mbtx grammar, and passes its corpus. The full script passes
268 native / 265 JS / 265 Wasm GC tests and all smoke checks.

Scanner command forwarding now compiles its driver into an isolated target
directory and executes it in the original working directory. Arguments are no
longer rewritten as absolute paths, which previously corrupted grammar names
and could corrupt flag values. The full check script passes, including relative
source/table paths and `--scanner ... init scanned <directory>`; all 268 native /
265 JS / 265 Wasm GC tests remain green.

Parser scheduling now advances versions in byte-frontier rounds, coalesces
equivalent future configurations, and prunes obsolete error versions only at
round boundaries. Recovery preparation preserves the reference's historical
version count and does not prematurely advance the next frontier. A small
C-oracle regression exercises two successive errors separated by a valid
conditional; cancellation at 99 successive callback boundaries preserves both
the result and parse-step count. All checks pass: 269 native / 266 JS / 266
Wasm GC and CLI smoke checks. The public corpus matrix is now entirely green:
JSON 6/6, C 85/85, JavaScript 116/116, Go 67/67, plus 11 query compilations.
This remains a selected compatibility baseline, not proof of a complete port.

The CI workflow now fetches the four pinned public grammar revisions and runs
their complete corpus/query compilation matrix in a separate Ubuntu job. The
same command passes locally; hosted execution awaits repository creation.

Public JavaScript tag execution exposed an optional-prefix query bug: a later
documented function suppressed an earlier function with no comments. Skipped
optional prefixes now coexist with populated matches for different captures,
while populated alternatives dominate their own empty alternatives. Frozen
C-query examples cover both sibling groups and child patterns. All 29 query
tests pass on native, JS and Wasm GC.

Highlight captures now follow upstream's later-pattern precedence, including
local-definition color inheritance. Tags allow names outside their syntax
capture and union the two extents; names containing syntax errors are skipped.
Highlight/tag consumers ignore unrecognized general directives as upstream
does, while retaining text/property filtering and documentation directives.
The complete check script passes 271 native / 268 JS / 268 Wasm GC tests.
Executing the unchanged public C/JavaScript highlight and tag fixtures now
passes all 90 position assertions across nine files.

The public grammar audit now executes those highlight/tag fixtures through the
native CLI, with isolated discovery configuration and unchanged upstream query
files. It checks comments returned by the query engine, decodes highlighted HTML
while verifying source preservation, and validates tag name ranges. Its ASCII
position-comment reader rejects non-ASCII input explicitly; general Unicode
grapheme-column assertion support remains open. CI treats fixture failures as
failures separately from corpus and query-compilation counts.

Fixed implicit lexical precedence: after explicit precedence and longest match,
a literal outranks an immediate pattern (upstream weights literal=2,
immediate=1). A C-oracle fixture confirms equal-length selection and that a
longer immediate match still wins. The full check script passes 272 native /
269 JS / 269 Wasm GC tests and all CLI smoke checks.

Accepted root extents now include EOF's skipped trailing input. Changed-range
cursors represent trailing padding explicitly, preserving unchanged whitespace
when the last syntax node is deleted. Four frozen C edit cases and a newline
extent test pass; full checks pass 273 native / 270 JS / 270 Wasm GC. The public
matrix remains 274/274 corpus cases, 11/11 query files, and 90/90 annotations.

Replaying all 1,153 edit probes finds zero incremental/fresh node mismatches.
There are 38 range discrepancies among cases with matching named S-expressions
and 236 differing S-expression pairs (including error serialization differences).
Some range discrepancies arise from different anonymous punctuation inside
recovery trees, rather than range comparison itself. An experiment coalescing
more recovery paths reduced the range differences but introduced new tree-shape
regressions; it was reverted. Preserving competing stack histories remains open.

Grammar/scanner workspaces now discover the runtime checkout through the
provided directory or executable ancestors, checking the module name rather
than treating an arbitrary grammar project as the runtime. With no checkout,
the workspace retains only its script and uses the versioned registry import.
Native tests cover nested projects, unrelated manifests, file paths and the
registry workspace shape. CLI smoke tests generate mbtx and load a scanner from
an unrelated directory without TREESITTER_MBT_ROOT. Full checks pass 275 native /
270 JS / 270 Wasm GC; installing and resolving the actual published module must
still be verified at release, after the community namespace is applied.

The native CLI now fuzzes corpus cases with deterministic byte edits and their
inverses. Each step checks incremental trees against fresh trees, including
anonymous nodes, fields, flags and byte/point ranges, plus child ordering and
parent bounds. Failures record the seed, original bytes and edit history. The
ChaCha8 seed stream is local to this implementation. Full checks pass 278 native /
270 JS / 270 Wasm GC tests. Individual public-grammar runs pass 276 JSON checks
(10 iterations), and 510 C / 696 JavaScript / 402 Go checks (two iterations).
The public audit now includes a bounded two-iteration run per case; it does not
yet validate changed-range coverage or replace differential recovery testing.

The combined four-grammar audit passes all 274 corpus cases, 11 query files,
90 annotations and 1,644 bounded edit/undo checks. Added the public regex grammar
at v0.25.0 (`b2ac15e27fce703d2f37a79ccd94a5c0cbe9720b`), using its unchanged
grammar JSON, corpus and highlight query: all 37 cases, one query and 222
edit/undo checks pass. The pinned five-grammar matrix therefore covers 311
corpus cases, 12 query files, 90 annotations and 1,866 edit checks.

Larger public examples exposed the default 100,000 parser-step limit on the
247 KB jQuery source. Parsing now defaults to unlimited steps (`max_steps=0`),
including callback and encoded input; explicit positive budgets and cancellation
remain available, and negative budgets are rejected. The jQuery named tree now
matches the pinned C runtime exactly. Full checks remain 278 native / 270 JS /
270 Wasm GC, including the explicit-limit regression.

Added ten unchanged public example files to the matrix, totaling 877,693 bytes.
All named S-expressions match hashes from the pinned C runtime and pinned grammar
parsers, including the 247,351-byte jQuery and 216,674-byte C cluster sources.
The development-only reference helper verifies clean revisions and reproduces
the hashes without rewriting committed expectations. CI parses with MoonBit and
compares those hashes; output, errors and elapsed time are retained separately.
This is correctness evidence on larger files, not a comparative performance claim.

Query repetitions now require the next concrete sibling, matching upstream's
loop-back semantics; anonymous commas stop a number run unless the query matches
the separators. Corrected a prior test expectation that incorrectly grouped
numbers across commas, using a freshly compiled pinned C query oracle. Thirty
query tests pass on all targets; highlight/tag unit tests and all 90 public
annotation assertions remain passing. Further probes expose open query work:
top-level quantifiers are not parsed, and repeated sibling groups with optional
separators still differ in path selection from upstream. Keep these in the query
compatibility gate rather than treating the passing public queries as full parity.

Rust v0.24.2 exposed a recovery-vocabulary bug: synthetic lookaheads used to
complete structured comments made every token appear lexically coincident.
LR items now retain the provenance of those lookaheads, and recovery-token
analysis excludes synthetic completion contexts while retaining real shifts
and grammar lookaheads. A small C-oracle regression checks both the excluded
greedy token and the recovered tree, alongside valid comments and macro input.
Full checks pass 280 native / 272 JS / 272 Wasm GC. This resolves Rust's malformed
string-prefix case; two malformed macro-body recovery cases remain different.

Added a pure MoonBit Rust external scanner with the upstream one-byte raw-string
state, nested comments, doc markers/content, string boundaries and float scanning.
The source and preserved MIT license are in examples/rust. The separate candidate
manifest pins Rust v0.24.2 at `77a3747266f4d621d0757825e6b11edcbf991ca5`.
`tools/audit_grammars.py --manifest tools/grammar_candidates.json` generates 67,636
states and 4,635 productions, passes 149/151 corpus cases, compiles three query
files, and passes 906 edit/undo checks. It deliberately exits nonzero for `Json
macro contents` and `Longer json macro contents`; these are not blessed as expected
successes or included in the passing five-grammar CI totals.

Changing recovery scanner validity alone did not resolve those cases and changed
the longer malformed tree; that runtime experiment was reverted. The pinned C
trace retains competing stack histories through potential reductions and merges
their recovery versions, while the port commits to flat histories. The next
runtime step is to preserve those histories through reductions, recovery pops,
and version condensation, with the existing 1,153-edit differential probe and
all six public grammars as checks. The five-grammar audit remains fully passing
after the generator fix (311 corpora / 12 queries / 90 annotations / 1,866 edits /
10 full-source named trees).

Default aliases now apply to a symbol's public identity before a successful
parent reduction, including inside ERROR nodes. The generator selects the most
frequent alias (first occurrence breaks ties), excludes unaliased uses and extras,
and computes frequencies before inline expansion. Frozen C regressions cover
named and anonymous tokens, context-specific overrides, extras, serialization,
and inline rules. Full checks pass 282 native / 274 JS / 274 Wasm GC tests and
CLI smoke checks. Regenerated Rust remains 149/151 with all three query files
and 906 edit checks passing; its two malformed macro cases remain open.

A broader recovery-history experiment was reverted after introducing a JSON
changed-range regression. Instrumenting the C reference showed that hidden raw
quote tokens lost their default alias in the port, understating skipped-token
costs; the isolated alias fix above corrects that independently. Remaining
recovery work includes merging an earlier ERROR when recovering across syntax
that follows it, and preserving alternative histories without premature pruning.

Recovery now keeps extras before a popped stack entry outside its new ERROR,
folds an immediately preceding ERROR into the new error's children, and stops
searching deeper once the current state accepts the lookahead. Potential
recovery reductions exclude EOF-only lookaheads and empty productions, matching
the C runtime. This prevents nested document roots from appearing in recovery
errors. Two frozen C regression tests cover repeated damage, intervening comments,
and premature root reduction. Full checks pass 284 native / 276 JS / 276 Wasm GC
and CLI smoke checks. Rust improves to 150/151: the short `Json macro contents`
case now matches, its prefix case remains passing, and only `Longer json macro
contents` fails. All three Rust query files and 906 edit checks still pass.

Comparing the 1,153 JSON edits with an isolated build of the preceding commit
finds 49 newly matching C tree pairs and zero newly differing tree pairs or
changed ranges among previously matching cases. There are now 187 differing
S-expression pairs and 40 range differences among matching named trees (two are
on newly matching trees); incremental/fresh comparisons still have zero failures.
A separate pre-existing tie-selection gap remains for `a 1 @ a 2 @ a 3;` in the
small `document = repeat(statement)`, `statement = 'a' number ';'` grammar: C keeps
the final statement outside ERROR, while the port keeps the first statement's
prefix. It is not included as a passing regression or evidence of full parity.

The full five-grammar matrix remains passing after these recovery changes:
311 corpus cases, 12 query files, 90 annotations, 1,866 edit/undo checks, and all
ten large named-tree comparisons. The remaining Rust trace first diverges at the
`{` following `"src":`: C tries a retained pre-reduction string state before
recovering farther down the stack; the flat histories instead admit a nested
block. This is the next concrete history-preservation regression to resolve.

### Recovery continuations and compacted states

The latest trace separates two causes: the canonical Rust string-completion
state lacks the `{` reduction available in C's compacted table, and potential
reductions discard histories needed later in recovery. Preserving histories
alone did not improve the canonical-table result, so that experiment was
reverted before implementing compatible-state compaction.

That work exposed two independent runtime defects. Missing-token candidates now
require a reduction path that actually shifts the real non-EOF lookahead; an
initial reduction alone is insufficient. EOF candidates retain their existing
completion behavior. This fixes the frozen `error_recovery_loop` tree with
compacted tables. Incremental reuse now retains the reduction's cached lookahead,
trailing extras and offset, translating them when a subtree moves. Re-lexing
after a reused JavaScript method body had interpreted `finally` as a keyword
instead of the already-recognized property identifier, even after a no-op edit.
The pinned JavaScript edit audit reproduces that regression. A focused test
covers shifted trailing comments and invalidation of their dependencies.

Compatible-state compaction now groups canonical kernels, splits incompatible
actions and lexical contexts, propagates successor distinctions to a stable
partition, and remaps all transitions. External-token validity and nonterminal
extra completion prevent unsafe lookahead additions. Regression tests cover a
shared reduction with different callers, LR(1) reduce/reduce distinctions, and
overlapping lexical tokens. Canonical states are still built first, so the
100,000-state construction budget is unchanged. Unit-reduction elimination and
complete equivalence with upstream's minimizer remain open.

Generated state counts are now C 3,896, JavaScript 4,091, Go 2,592, Regex 383,
and Rust 13,216 (previously 67,636 for Rust). The checked-in JSON factory was
regenerated. Full checks pass 288 native / 280 JS / 280 Wasm GC plus CLI smoke
checks. All five public grammars pass 311 corpora, 12 query files, 90 annotations,
1,866 edit/undo checks, and ten large named-tree comparisons. The 1,153 JSON-edit
probe remains at 187 differing C S-expression pairs and 40 differing ranges,
with zero incremental/fresh mismatches or parser errors. Compaction alone leaves
Rust at 150/151; retaining competing recovery histories with these tables is the
next investigation. The full-port/review/publication gate remains open.

Potential reductions now retain their alternative stack histories on one
recovering version instead of scheduling them as separate competing versions.
Recovery searches those histories breadth first and preserves alternative paths
to the first viable state. Nonterminal-extra entry shifts retain the unreduced
history, and missing-token validation runs against each prepared stack. The
existing version and recovery-depth bounds still apply. This resolves Rust's
`Longer json macro contents` without changing its frozen expected tree.

Rust now passes 151/151 corpora, three query compilations and 906 edit/undo
checks. The five-grammar matrix remains fully passing, giving 462 corpus cases,
15 query files and 2,772 edit/undo checks across the six grammars, plus the
existing 90 annotations and ten large named-tree comparisons. Full portable/CLI
checks pass 288 native / 280 JS / 280 Wasm GC. The 1,153-edit JSON differential
remains 187 differing C S-expression pairs / 40 differing ranges, with zero
incremental/fresh mismatches or parser errors. General GSS optimization, the
remaining differential gaps and the other compatibility milestones remain open.

Rust's unchanged pinned manifest entry has moved into the default public CI
matrix. The now-empty candidate manifest was removed; select the Rust suite
with `python3 tools/audit_grammars.py --fetch rust`. README totals now include
all six passing grammars. Hosted CI, the final Codex CLI ultra review, repository
creation and publication remain pending the full compatibility gate.

The public-query API now supports copying a compiled query with independent
disabled-pattern, disabled-capture and capture-name state. Tests exercise copies
made after disabling settings and subsequent changes on both objects. All 31
query tests pass on native, JS and Wasm GC. Top-level query quantifiers and
root/non-local/guaranteed-step analysis remain open.

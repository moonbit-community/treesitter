# Compatibility with upstream Tree-sitter

The reference is Tree-sitter 0.28.0 at commit
`4a412a01a0147d0f50bf7e749572fa632d1ab203`. Every package is a structural
port of the corresponding upstream source (see [PORTING.md](PORTING.md)) and
is checked against a build of that commit; anything not listed here is
intended to behave identically, and a difference is a bug.

## Verified agreement

| Area | Check | Result |
| --- | --- | --- |
| Generator | `parser.c`, `node-types.json` and error text for the 74 upstream test grammars (12 of which upstream rejects), 17 fixture grammars and 17 additional languages | 108/108 byte-identical |
| Runtime | trees for every corpus input, plus 2 random mutations each | 13,269/13,269 |
| Runtime | 3 random incremental edits per input: edited trees, changed ranges, fresh reparse | 13,269/13,269 |
| Runtime | parser and lexer log streams | 8,846/8,846 |
| Runtime | UTF-16LE, UTF-16BE, random included ranges | 4,432/4,432 each |
| Queries | matches and captures of every grammar's query files and the test queries | 11,623/11,623 |
| Grammar modules | embedded tables of the 34 languages vs upstream's `parser.c` | 34/34 identical |
| Highlight, tags | event streams, HTML, tags of 10 fixture grammars | byte-identical |
| Regex | `is_match`, `find`, `find_iter` (bytes and UTF-8 mode) and error messages vs the `regex` crate | 486,885 + 410,406 pairs identical |
| Regex | compilation size limit at 316 boundary patterns | identical |
| `grammar.json` reading | error messages for 3,001 malformed grammars (serde_json behaviour) | identical |
| CLI | help, errors, completions, generate, parse, query, highlight, tags, test, fuzz, init, version | 1,695/1,695 command lines |

The comparisons cover the upstream test and fixture grammars and the 14
further grammar repositories pinned in
[grammars/grammars.json](grammars/grammars.json) (c-sharp, css, haskell,
julia, ocaml, regex, scala, verilog, lua, make, markdown, toml, yaml, zig),
including every external scanner: the scanners of all fixture, test and
additional grammars are ported to MoonBit and compiled from their original
C sources for the reference side. They are reproduced by
`tools/oracle/oracle.sh` and `tools/oracle/diff_cli.sh` (run in CI by the
`oracle` job). The upstream test suites of the CLI crate (`parser_test.rs`,
`node_test.rs`, `tree_test.rs`, `query_test.rs`, `corpus_test.rs`,
`highlight_test.rs`, `tags_test.rs` and others) are ported in `tests/` and the
packages' own tests.

## Not applicable or not ported

| Upstream feature | Status |
| --- | --- |
| Loading compiled parsers (`parser.c`, shared libraries, `TSLanguage` ABI objects) | MoonBit cannot load native code. Languages are portable tables, produced by `generate` (`src/language.json`) or by the `build` command as a MoonBit module. |
| Wasm grammars (`wasm_store.c`, `TREE_SITTER_FEATURE_WASM`), `build --wasm`, `playground` | Not ported. |
| C API (`lib/include/tree_sitter/api.h`), `c_lib.rs` of highlight and tags, custom allocators | Not exposed; the public API is the port of the Rust binding. |
| External scanners written in C | Each scanner is ported to MoonBit (`scanners`). New grammars provide `src/scanner.mbtx`, which the CLI compiles into a cached driver. |
| QuickJS (`--js-runtime native`) | Not available; `grammar.js` is evaluated with node, bun or deno, as upstream does. |
| CLI: Ctrl-C cancellation, generator debug traces under `generate --log`, dialoguer's terminal UI in `init` (line prompts instead), colored clap output, `RUST_BACKTRACE` backtraces | Not ported. |
| Optional query debug output (`DEBUG_QUERY_STEPS`, `DEBUG_ANALYZE_QUERY`, `DEBUG_EXECUTE_QUERY` in `query.c`) | Off in the default upstream build; not ported. |
| Optional scanner debug traces (tree-sitter-scala's `scanner.c` compiled with `-DDEBUG`) | Off in the default upstream build; not ported. |
| tree-sitter-markdown's optional Rust `parser` feature (`MarkdownParser`, `MarkdownTree`, `MarkdownCursor`, `MarkdownParseOptions`) | Not ported. `moonbit-community/tree-sitter-markdown` exports what the binding exports without the feature: the block and inline languages, their queries and node types. Combined parsing works as `parser.rs` does it: parse the block tree, then parse each `inline` node's ranges with `inline_language()` using included ranges. |
| `fuzz` allocation tracking | Not applicable (memory is garbage collected); a failed consistency assertion during a trial is reported as an error and counts as a failed test. |

## Representation differences

- Numeric node ids (`Node::id`) are unique within a tree but are not memory
  addresses.
- Offsets, rows and columns are `Int`. `Int::max_value()` stands for
  upstream's `usize::MAX`/`u32::MAX` sentinels; values above `0x7FFFFFFE`
  (only possible for documents over 2 GiB or offsets given to
  `root_node_with_offset`) are reported as `0x7FFFFFFF`.
- MoonBit has no destructors. A discarded `Tree` keeps its share of the
  reference counts of its subtrees, so a subtree once shared with a
  discarded tree is copied rather than mutated in place by later edits of
  the remaining tree; the resulting trees are identical, only the
  `Node::id`s along the edited path and the cost of the copy differ.
  Parsers are not destroyed automatically either: call `Parser::delete`
  (the equivalent of dropping the Rust `Parser`) to run the external
  scanner's `destroy` for a parse that was cancelled and not reset.
- A query cursor drops its tree once its execution is exhausted. A cursor
  whose matches or captures are abandoned before exhaustion keeps the tree
  alive until its next `exec` (this includes the cursors `Highlighter` and
  `TagsContext` reuse); upstream's cursor does not own the tree.
- `Tree::print_dot_graph` and `Parser::print_dot_graphs_to` write upstream's
  exact bytes to a `Buffer`; String destinations (`StringBuilder`,
  `Parser::print_dot_graphs`) receive them decoded as UTF-8 with invalid
  bytes replaced by U+FFFD.
- `Range<usize>` values are `(Int, Int)` pairs; cancellation flags are
  `Ref[Int]`.
- Upstream sorts query-testing assertions with an unstable sort; the port uses
  a stable one. With more than 20 assertions at one position their order
  could differ. `usize::MAX` in query-testing results (the end column of a
  zero-length assertion at column 0) prints as 2147483647.
- The CLI's test diffs use an LCS diff instead of the `similar` crate's Myers
  diff, so ambiguous diffs may be drawn differently.
- Portable symbol, field and language names are the values of the C string
  literals in `parser.c`. Where C leaves a literal implementation-defined
  (an out-of-range hexadecimal escape keeps its low 8 bits, as with GCC;
  `\u` escapes below U+00A0 follow C23), the port picks that behaviour, and
  bytes that are not UTF-8 decode to U+FFFD (the Rust binding would panic).
- Upstream's debug-build assertions (for example the `u16` bounds of reduce
  actions) are not reproduced; the port behaves like release builds.
- The regex size limit reproduces regex-automata's NFA accounting; the meta
  engine's exact-prefix literal bypass is not modelled, as it only applies
  to regexes far below the limit. Alternations of 3,000 or more literals use
  a port of aho-corasick's leftmost-first automaton, as upstream does.
- `Regex::is_match` in UTF-8 mode, for regexes that can match the empty
  string, follows the meta engine's choice of engine (lazy DFA; the bounded
  backtracker for haystacks of at most 128 bytes once the lazy DFA gives up
  on a Unicode word boundary; otherwise the PikeVM). The backtracker's
  visited-set limit (NFAs of more than about 16,000 states) and the lazy DFA
  giving up when its cache thrashes are not modelled.
- The YAML scanner's schema (`YAML_SCHEMA` at build time upstream, `core` by
  default) is selected with `@scanners.yaml_scanner_with_schema`.

## Nondeterministic upstream behaviour

Some CLI output depends on the iteration order of Rust `HashMap`/`HashSet`s
with per-process random keys, so upstream can produce different results on
different runs; the port always uses registration (or entry) order, one of
the orders upstream can produce:

- First-line language detection tries the distinct `first-line-regex`
  patterns in map order and keeps the result of the last one tried (no
  language if it does not match).
- `init`'s file types and `fuzz`'s unmatched skip definitions are listed in
  set/map order.

## Other CLI differences

- `parse --debug-graph` with an invalid `--edits`: upstream deadlocks (the
  parser keeps a duplicate of dot's input open); the port finishes
  `log.html` with the graphs produced so far and reports the error. Graph
  node ids in `log.html` are object ids, not memory addresses.
- Panics print Rust's message, location and thread id and exit with status
  101; locations in crates.io dependencies are given under
  `$CARGO_HOME/registry/src/index.crates.io-1949cf8c6b5b557f/`.
- clap names the program after argv[0]; under moon's executable names
  (`treesitter`, `treesitter.exe`) the CLI presents itself as `tree-sitter`.
- `--open-log` uses Launch Services on macOS; under WSL, local files are not
  opened through the Windows browser.
- Highlighting a language with injections first loads the injected
  languages in extra passes; the output is identical, reported times
  include them.
- Writes to stdout are all-or-error (no partial writes). File names that are
  not valid UTF-8 are decoded lossily, so glob patterns may match or sort
  them differently, and such a path that does not exist gives "No files
  were found…" rather than upstream's "Invalid path: …".
- When a command is re-run through a compiled MoonBit scanner driver,
  arguments that are not valid UTF-8 reach the driver decoded lossily, so
  clap's InvalidUtf8 check does not apply there.
- Query `--byte-range`/`--row-range` values are truncated to u32 as the
  Rust binding does; values above 0x7FFFFFFE are represented as 0x7FFFFFFF,
  so a range whose start and end both lie in 2³¹…2³²−2 with start > end is
  set (and matches nothing) instead of being ignored by the C cursor.
- A failed C `assert` in a ported external scanner prints macOS libc's
  diagnostic (`Assertion failed: (expr), function f, file scanner.c, line
  N.`) on stderr and then ends with a MoonBit panic instead of `abort()`.

## Undefined behaviour in upstream code

The `uses_current_column` test grammar's C scanner writes past its indent
buffer on some malformed inputs. C then crashes or stops at an arbitrary
point; the port follows the scanner's logic without corrupting memory and
does not reproduce that. The oracle compares this grammar on its unmodified
corpus only.

External scanners use the C library's character classes in the "C" locale
(ASCII-only `isw*`), as the upstream fixtures do when run by the CLI.

Scanner bugs that are well defined in C are reproduced, for example the
OCaml scanner restoring only part of a quoted-string delimiter after an edit
(it copies `length` bytes of an `int32_t` array). Paths that would be
undefined in C but cannot be reached through serialization (such as the
YAML scanner overflowing its serialization buffer with about 254 nested
indents) abort in the port.

## Platform

The library packages are pure MoonBit and build for native, JavaScript and
Wasm GC. The CLI, loader and config are native only and use one C file of
host bindings (`cli/support/stub.c`): binary writes to stdout and stderr with
errno, reading special files, process spawning (`posix_spawn`, with Rust's
signal setup and blocking pipe ends) and wait status, `fcntl` blocking mode,
process exit, a monotonic clock, `isatty`, `strerror`, `getcwd`, the default
temporary directory, the passwd home directory, the target OS, and macOS
Launch Services for `--open-log`.

## Performance

Measured on an Apple M-series machine against release builds of the pinned
upstream:

- Generator: 3.1–3.4× the CPU time of `tree-sitter generate` (cpp, c,
  rust, ruby, typescript); table construction is 2.8–3.1×.
- Runtime: 1.4–2.0× the time of the C runtime (`-O2`) to parse a file
  from scratch (C 1.36×, JSON 2.0×, Go 1.85×, Python 1.65×, JavaScript 1.84×,
  Rust 1.82× on upstream example files). Most of the
  remaining cost is reference counting and allocating subtrees.

# Compatibility with upstream Tree-sitter

The reference is Tree-sitter 0.28.0 at commit
`4a412a01a0147d0f50bf7e749572fa632d1ab203`. Every package is a structural
port of the corresponding upstream source (see [PORTING.md](PORTING.md)) and
is checked against a build of that commit; anything not listed here is
intended to behave identically, and a difference is a bug.

## Verified agreement

| Area | Check | Result |
| --- | --- | --- |
| Generator | `parser.c`, `node-types.json` and error text for the 74 upstream test grammars (12 of which upstream rejects) and 17 fixture grammars | 91/91 byte-identical |
| Runtime | trees for every corpus input, plus 2 random mutations each | 5,487/5,487 |
| Runtime | 3 random incremental edits per input: edited trees, changed ranges, fresh reparse | 5,487/5,487 |
| Runtime | parser and lexer log streams | 3,658/3,658 |
| Runtime | UTF-16LE, UTF-16BE, random included ranges | 1,838/1,838 each |
| Queries | matches and captures of every upstream query file and test query | 4,964/4,964 |
| Highlight, tags | event streams, HTML, tags of 10 fixture grammars | byte-identical |
| Regex | matching, `find_iter` and error messages vs the `regex` crate | 446,822 pairs identical |
| CLI | help, errors, completions, generate, parse, query, highlight, tags, test, fuzz, init, version | 1,151/1,151 command lines |

All runtime comparisons include the external scanners of the html,
javascript, typescript, tsx, rust, php, bash, ruby, python, cpp and jsdoc
fixture grammars and of the 19 upstream test grammars. They are reproduced by
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
| CLI: Ctrl-C cancellation, generator debug traces under `generate --log`, dialoguer's terminal UI in `init` (line prompts instead), colored clap output | Not ported. |

## Representation differences

- Numeric node ids (`Node::id`) are unique within a tree but are not memory
  addresses; `usize::MAX` sentinels are `0x7FFFFFFF`.
- `Range<usize>` values are `(Int, Int)` pairs; cancellation flags are
  `Ref[Int]`.
- Upstream sorts query-testing assertions with an unstable sort; the port uses
  a stable one. With more than 20 assertions at one position their order
  could differ.
- The CLI's test diffs use an LCS diff instead of the `similar` crate's Myers
  diff, so ambiguous diffs may be drawn differently; serde_json data errors
  lack the `at line L column C` suffix.

## Undefined behaviour in upstream code

The `uses_current_column` test grammar's C scanner writes past its indent
buffer on some malformed inputs. C then crashes or stops at an arbitrary
point; the port follows the scanner's logic without corrupting memory and
does not reproduce that. The oracle compares this grammar on its unmodified
corpus only.

External scanners use the C library's character classes in the "C" locale
(ASCII-only `isw*`), as the upstream fixtures do when run by the CLI.

## Platform

The library packages are pure MoonBit and build for native, JavaScript and
Wasm GC. The CLI, loader and config are native only and use a 64-line C file
(`cli/support/stub.c`) for unbuffered binary writes to stdout and stderr,
process exit, a monotonic clock, `isatty` and `strerror`.

## Performance

Measured on an Apple M-series machine against release builds of the pinned
upstream:

- Generator: 3.1–3.4× the CPU time of `tree-sitter generate` (cpp, c,
  rust, ruby, typescript); table construction is 2.8–3.1×.
- Runtime: 1.4–2.0× the time of the C runtime (`-O2`) to parse a file
  from scratch (C 1.36×, JSON 2.0×, Go 1.85×, Python 1.65×, JavaScript 1.84×,
  Rust 1.82× on upstream example files). Most of the
  remaining cost is reference counting and allocating subtrees.

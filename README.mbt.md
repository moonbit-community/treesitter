# Tree-sitter in pure MoonBit

An experimental port of Tree-sitter's grammar compiler, parser runtime and tooling.
Grammars are MoonBit programs in `.mbtx` files. Generated languages contain
portable tables and execute without a C runtime, Rust generator or JavaScript
grammar evaluator.

**This is not yet a complete or drop-in Tree-sitter implementation.** The scope is
the full repository. [COMPATIBILITY.md](COMPATIBILITY.md) lists what is missing
in 0.1.0; [PLAN.md](PLAN.md) records the implementation milestones and evidence.
The reference is Tree-sitter 0.28.0 at commit
`4a412a01a0147d0f50bf7e749572fa632d1ab203`.

## Install

The public source repository is available now. Mooncakes publication is pending
credentials for the community namespace. After 0.1.0 is published, add the
library to a MoonBit project:

```sh
moon add moonbit-community/treesitter@0.1.0
```

For the native CLI, clone this repository and run the commands below, or install
from the checkout with `moon install ./cmd/treesitter`. After publication, use
`moon install moonbit-community/treesitter/cmd/treesitter@0.1.0` to install from
Mooncakes. Grammar scripts use `.mbtx`, but the CLI and its script loader require
the native backend.

## Try an mbtx grammar

Use MoonBit `0.1.20261021` or newer. Run these commands from this repository's root:

```sh
moon update
moon run cmd/treesitter --target native -- generate examples/json/grammar.mbtx _build/json.language.json
moon run cmd/treesitter --target native -- parse _build/json.language.json examples/json/sample.json
moon run cmd/treesitter --target native -- highlight _build/json.language.json examples/json/highlights.scm examples/json/sample.json
```

The loader executes the mbtx program with `moon run` inside a temporary
workspace. It locates this checkout through the working directory or executable
ancestors, supporting unpublished local development from another directory.
When no checkout is available, it uses the versioned Mooncakes dependency
`moonbit-community/treesitter@0.1.0`; this path requires registry publication.
A grammar program writes exactly one grammar JSON object to stdout; send any
other diagnostics to stderr. Grammar programs execute with the permissions of
the invoking process. `TREESITTER_MBT_ROOT` supplies an explicit checkout hint.

See [examples/grammar.mbtx](examples/grammar.mbtx) for arithmetic and
[examples/json/grammar.mbtx](examples/json/grammar.mbtx) for nested JSON with
strings, escapes, Unicode, arrays, objects and named fields.

The typed grammar API is also usable directly:

```mbt check
///|
test "compile a grammar and parse its language" {
  let grammar = @grammar.Grammar::new("words", [
    ("document", Repeat(Symbol("word"))),
    ("word", @grammar.pattern("[a-z]+")),
  ])
  let language = @generate.generate(grammar)
  let tree = @treesitter.Parser::new(language).parse_string("hello moonbit")
  assert_eq(tree.root_node().to_sexp(), "(document (word) (word))")
}
```

## Generate once, parse anywhere

```sh
moon run cmd/treesitter --target native -- emit _build/json.language.json _build/json.mbt
```

The emitted file defines `language()`, loading validated lexer and parser tables.
Place it in a MoonBit package importing `moonbit-community/treesitter/language`. Consumers
import that package and `moonbit-community/treesitter` for `Parser`. The checked-in
[JSON factory](examples/json/language.mbt) and
[arithmetic factory](examples/arithmetic/language.mbt) demonstrate this setup.
Their runtime tests do not import the generator.

Core libraries run on native, JavaScript and Wasm GC. Only the native loader and
CLI depend on `moonbitlang/async` for files and processes. Serialized languages
use this project's versioned JSON format, not Tree-sitter's C language ABI.
Upstream `grammar.json` is accepted as a migration input.

## Command line

| Command | Arguments | Result |
| --- | --- | --- |
| `grammar-json` | `grammar.mbtx` | Grammar JSON on stdout |
| `generate` | `grammar.mbtx\|grammar.json output.json` | Compiled language tables |
| `emit` | `language.json output.mbt` | MoonBit language factory |
| `node-types` | `language.json output.json` | Node and field schemas |
| `languages` | `[config.json]` | Discovered language configurations |
| `init-config` | `output.json` | Initial parser-directory configuration |
| `parse` | `[language.json] source` | Named-node s-expression; fails on syntax errors |
| `test` | `language.json corpus-file-or-directory [--update]` | Verify cases or update changed expectations |
| `fuzz` | `language.json corpus-file-or-directory` | Seeded edits, fresh/incremental checks, and undo validation |
| `query` | `language.json query.scm source` | Capture JSON lines |
| `query --check` | `language.json query.scm` | Validate query syntax and grammar references |
| `init` | `name directory` | Create an mbtx grammar, corpus test, and highlight query |
| `highlight` | `language.json highlights.scm source` | Escaped HTML spans |
| `tags` | `language.json tags.scm source` | Definition/reference JSON lines |

All commands use `moon run cmd/treesitter --target native -- COMMAND ...`.
`parse`, `highlight`, and `tags` also accept a source path alone and select a
language using discovered `tree-sitter.json` files and parser directories.
`parse --cst language.json source` prints the concrete tree with byte locations.

`fuzz` accepts `--seed N`, `--iterations N`, `--edits N`, and test-name regex
filters `--include REGEX` / `--exclude REGEX`. Defaults are seed 0, 100 iterations
per case, and up to three edits followed by their inverses. It checks every
node's kind, byte/point ranges, flags and fields against a fresh parse, validates
child ordering and bounds, and checks restoration after undo. Failures include
the seed, original bytes and complete edit history as JSON. Its deterministic
ChaCha8 stream is specific to this CLI and does not reproduce Rust StdRng seeds.

`test --update` (or `-u`) replaces failed expectations with formatted syntax trees.
It preserves test inputs, headers, skipped cases, and passing expectations.
Unexpected parse errors and failed `:error` assertions stop the update before
any corpus file is written. Review the resulting diff after changing a grammar.

Use `--scanner scanner.mbtx` before a command to compile a pure MoonBit scanner
registry with the CLI. The registry exports
`pub fn scanner(language : String) -> @ts.ExternalScanner?`; returning scanners
by language name also supports highlighting injections. See
[the quoted-language example](examples/quoted/scanner.mbtx):

```sh
moon run cmd/treesitter --target native -- generate examples/quoted/grammar.mbtx _build/quoted.language.json
moon run cmd/treesitter --target native -- --scanner examples/quoted/scanner.mbtx parse _build/quoted.language.json examples/quoted/sample.txt
```

The native `cli` package exposes the same command runner and scanner callback
for applications that compile their registry once into a custom executable.

## Library packages

| Package | Responsibility |
| --- | --- |
| `grammar` | Typed grammar DSL and upstream grammar JSON |
| `lex` | Unicode regexes, NFA/DFA compilation and scanning |
| `generate` | Normalization, LR tables, precedence, conflicts and emission |
| `language` | Validated portable tables and serialization |
| Root package | Parser, persistent nodes/trees, edits, cursors and scanners |
| `query` | Structural patterns, captures and text predicates |
| `highlight` | Highlight events and HTML |
| `tags` | Definitions, references and documentation captures |
| `corpus` | Corpus reading and verification |
| `mbtx`, `loader`, `cli` | Script execution, discovery, and native commands |

Byte offsets and `Point.column` count bytes in the input encoding. UTF-8 is the
default; `parse_encoded` also accepts UTF-16 LE/BE and stateless custom decoders. External scanners' `get_column`
counts Unicode scalar values, following Tree-sitter's scanner API. Input edits
update a tree's coordinates before passing it as `old_tree` to `Parser.parse`.
Trees and node handles preserve their existing structure through persistent
copies. Included ranges retain coordinates in the original source.

Node equality compares persistent identity within the same tree. Tree copies and
new parse results have distinct identities, including when they reuse syntax
data. Offset views and edited node handles retain their identity. Numeric node
IDs can repeat across trees; use node equality to compare handles.

External scanners are callbacks constructed with `ExternalScanner::new`. They
receive a cursor, valid-token flags in grammar `externals` order, and a serialized
state. Return `ScanResult` with the token index and next state, or `None`. Keep
all mutable scanner state in that snapshot, which is isolated per GLR branch.
See [scanner_test.mbt](scanner_test.mbt) and
[ported fixture scanners](compat/scanners_test.mbt) for complete examples.

## Compatibility status

Implemented paths include numeric/named/dynamic precedence, associativity,
declared GLR conflicts, inlining, fields, aliases, hidden supertypes, word tokens,
reserved contexts, immediate tokens, external scanners, and nonterminal extras.
The generator compacts compatible LR states while preserving action and lexical
conflicts; canonical construction still precedes compaction.
Runtime support includes recovery, cancellation/resumption, UTF-8 input callbacks,
UTF-16, included ranges, scanner snapshots, edits, subtree reuse, and changed ranges.
Parsing has no step limit by default (`max_steps=0`); callers can set a positive
budget or provide a cancellation callback.
Queries include groups, quantifiers, ordered capture cursors, structural validation,
text/property predicates, and cancellation. Highlighting supports locals and nested
injections; tags support documentation and scope-aware name classification.

The pinned fixture suite, 229 frozen JSON changed-range edits, and 123 edited
old-tree span cases pass. The public grammar matrix uses pinned revisions and
unchanged upstream corpora:

| Grammar | Corpus cases passing |
| --- | --- |
| JSON v0.24.8 | 6 / 6 |
| C v0.24.2 | 85 / 85 |
| JavaScript v0.25.0, with a MoonBit scanner | 116 / 116 |
| Go v0.25.0 | 67 / 67 |
| Regex v0.25.0 | 37 / 37 |
| Rust v0.24.2, with a MoonBit scanner | 151 / 151 |

All 15 shipped query files pass compilation against the generated tables.
The nine C/JavaScript highlight and tag fixture files also pass all 90 position
assertions, including local-variable classification and JavaScript injection.
The development assertion reader supports these ASCII fixtures and rejects
non-ASCII input pending upstream-compatible grapheme-column handling.
All 462 corpus cases pass. These include malformed-input recovery cases;
the audit exits nonzero for any corpus, query, annotation, or fuzz failure.
CI runs this pinned public matrix in a separate Ubuntu job alongside the
portable-library and CLI checks on Linux and macOS. Corpus, query compilation,
and query execution results are reported separately in the audit's JSON output.
The audit also runs two seeded fuzz iterations per corpus case, with up to two
edits and their inverses, and reports those checks separately: 2,772 checks pass.
Ten upstream example files (878 KB in total, including jQuery and Go's runtime)
also match named-tree hashes frozen from the pinned C reference. The audit runs
only the MoonBit implementation; `python3 tools/freeze_public_examples.py`
reproduces the reference hashes as a separate development check requiring `cc`.
The hashes cover named trees; byte ranges, anonymous nodes, and edit behavior
are exercised by the other suites.

Rust's pure MoonBit scanner is in `examples/rust/scanner.mbtx`. Its full corpus,
including the malformed macro-body recovery cases, now runs in the default CI
matrix. Use `python3 tools/audit_grammars.py --fetch rust` to run it separately.

Remaining compatibility work includes ambiguous-forest incremental reuse,
incremental optimization for encoded/included-range inputs, broader upstream API
and query regressions, performance comparisons, and one optional-child difference
in node schema metadata. Deterministic regions can be reused in ambiguous
languages; nodes built while branches compete are conservatively reparsed. The
second ultra audit's seven concrete findings have regression fixes; broader
changed-range discrepancies and missing CLI/API capabilities still prevent a
full-port claim. This experimental release documents these gaps in
[COMPATIBILITY.md](COMPATIBILITY.md); full-port work continues in [PLAN.md](PLAN.md).

Unsupported grammar/query features fail explicitly where recognized. Error-tree
shape and subtle query semantics may differ. The frozen suite is a selected
compatibility matrix, not the entire upstream test suite.

## Validate and reproduce

```sh
sh tools/check.sh
python3 tools/audit_grammars.py --fetch
```

This checks warnings, native/JS/Wasm GC tests, executes both mbtx grammars,
regenerates their factories into `_build`, checks them against committed sources,
and runs JSON discovery/highlighting and the compiled MoonBit scanner example.
The separate public grammar audit fetches only pinned commits into `.repos`,
checks their tracked files, and writes tables, full logs, and `results.json` under
`_build/grammar-matrix`. Grammar JSON is compiled by MoonBit; the JavaScript
external scanner is also MoonBit. `moon fmt` and `moon info` maintain formatting
and generated public interfaces. Run `moon bench benchmarks --target native --release`
for fresh-parse scaling and incremental-edit measurements. These are local
baselines, not a performance comparison with upstream Tree-sitter.

`tools/import_fixtures.py` freezes selected upstream grammars/corpora from the
pinned `.repos/tree-sitter` checkout. Node is used only for this development-time
import; the resulting tests use the MoonBit compiler and runtime. Unicode data
is from the upstream-pinned regex-syntax version; see `tools/import_unicode.py`.
Normal builds and tests need neither reference checkout nor Node grammar evaluation.

## License

MIT, preserving Tree-sitter attribution in [LICENSE](LICENSE) and [NOTICE](NOTICE).
Unicode data has its own license in [licenses/UNICODE.txt](licenses/UNICODE.txt).

# Tree-sitter in pure MoonBit

A faithful port of [Tree-sitter](https://github.com/tree-sitter/tree-sitter)
0.28.0 (commit `4a412a01a0147d0f50bf7e749572fa632d1ab203`) to MoonBit: the
parser generator, the parsing runtime, queries, highlighting, tags, the
external scanners of the upstream fixture grammars and the `tree-sitter` CLI.
Each package is a structural, file-by-file translation of the corresponding
upstream source and is tested differentially against the pinned upstream
build (see [Validation](#validation)).

Languages are portable tables (`@language.Language`) that the MoonBit runtime
executes directly; no C runtime, Rust generator or dynamic library is
involved. [COMPATIBILITY.md](COMPATIBILITY.md) lists what differs from
upstream and why; [PORTING.md](PORTING.md) maps every package to its upstream
source.

## Library

The root package `moonbit-community/treesitter` is the port of upstream's Rust
binding (`lib/binding_rust/lib.rs`): `Parser`, `Tree`, `Node`, `TreeCursor`,
`Query`, `QueryCursor`, `LookaheadIterator` and friends, with the same names
and semantics.

```mbt check
///|
test "generate a grammar, parse and query" {
  // A grammar.json document (here built with the @grammar DSL; upstream's
  // `tree-sitter generate` writes the same format to src/grammar.json).
  let grammar = @grammar.Grammar::new("words", [
    ("document", Repeat(Symbol("word"))),
    ("word", @grammar.pattern("[a-z]+")),
  ])
  let generated = @generate.generate_from_grammar_json(
    grammar.to_json().stringify(),
  )
  // `generated.c_code` is the parser.c upstream would emit, byte for byte.
  let language = @treesitter.Language::new(generated.language)
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let source = @utf8.encode("hello moonbit")
  guard parser.parse(source) is Some(tree) else { fail("parse failed") }
  inspect(tree.root_node().to_sexp(), content="(document (word) (word))")
  let query = @treesitter.Query::new(language, "(word) @w")
  let cursor = @treesitter.QueryCursor::new()
  let matches = cursor.matches(query, tree.root_node(), source)
  let mut count = 0
  while matches.next() is Some(_) {
    count += 1
  }
  inspect(count, content="2")
}
```

| Package | Upstream source |
| --- | --- |
| `moonbit-community/treesitter` | `lib/binding_rust/lib.rs` |
| `runtime` | `lib/src` (parser, lexer, stack, subtree, tree, node, tree cursor, changed ranges) |
| `language` | `TSLanguage` (`lib/src/parser.h`, `language.c`) as portable tables |
| `query` | `lib/src/query.c` |
| `generate` | `crates/generate` |
| `regex_syntax`, `regex` | the `regex-syntax` 0.8 subset the generator and tags use, and a matcher |
| `highlight`, `tags` | `crates/highlight`, `crates/tags` |
| `scanners` | the C external scanners of the upstream fixture and test grammars |
| `query_testing`, `cli_test` | the CLI's assertion and corpus testing |
| `cli`, `loader`, `config`, `clap`, `clap_complete`, `cmd/treesitter` | `crates/cli`, `crates/loader`, `crates/config`, and the clap subset they use (native only) |
| `grammar` | a MoonBit DSL producing `grammar.json` (no upstream equivalent; stands in for `grammar.js`) |

The runtime, query, generator, highlight and tags packages build for native,
JavaScript and Wasm GC. The CLI, loader and config are native only.

## Command line

```sh
moon build --target native --release cmd/treesitter
_build/native/release/build/cmd/treesitter/treesitter.exe --help
```

The executable is `tree-sitter` 0.28.0: same subcommands, flags, help text and
output. In a grammar directory, `generate` reads `grammar.js` (with node, bun
or deno, as upstream), `src/grammar.json` or a MoonBit `grammar.mbtx`, and
writes `src/parser.c`, `src/node-types.json`, `src/grammar.json` and the
portable `src/language.json`. `parse`, `query`, `highlight`, `tags`, `test`
and `fuzz` load languages through `tree-sitter.json` exactly like upstream.

MoonBit cannot load compiled parsers, so:

- `build` writes a MoonBit module with `pub fn language() -> @language.Language`
  instead of a shared library (`--wasm` is rejected);
- grammars with an external scanner use its port in `scanners`, or a
  `src/scanner.mbtx` defining `pub fn scanner() -> @runtime.ExternalScanner`,
  which the CLI compiles into a cached driver;
- `playground` is unavailable.

## Validation

Every package is compared with the pinned upstream build:

```sh
CARGO="cargo +1.97.1" sh tools/oracle/oracle_setup.sh  # pinned upstream + reference outputs
sh tools/oracle/oracle.sh                               # generator, runtime, queries
sh tools/oracle/diff_cli.sh                             # CLI commands
moon test --target native                             # ported upstream test suites
```

The oracle checks that the generator emits byte-identical `parser.c` and
`node-types.json` for all 91 upstream test and fixture grammars (including
error messages for rejected grammars), that parse trees, incremental edits,
changed ranges, parser logs, UTF-16 input and included ranges match the C
runtime on every corpus input and random mutations and edits of them, and
that query matches and captures match `query.c`. The CLI comparison runs
1151 command lines through both executables. The ported upstream test suites
(`tests/`, and the tests of each package) run with `moon test`.

## License

MIT, preserving Tree-sitter attribution in [LICENSE](LICENSE) and [NOTICE](NOTICE).
Unicode data has its own license in [licenses/UNICODE.txt](licenses/UNICODE.txt).

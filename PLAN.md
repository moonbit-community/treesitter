# Plan and status

The goal is a faithful MoonBit port of Tree-sitter 0.28.0 (commit
`4a412a01a0147d0f50bf7e749572fa632d1ab203`): every package translates the
corresponding upstream source structurally and is verified differentially
against a build of that commit. An earlier, independent reimplementation
(see the git history before the switch-over commit) was replaced by this
port because it diverged from upstream in recovery, query semantics and
generated tables.

## Done

| Component | Upstream | Verification |
| --- | --- | --- |
| `generate` (+ `regex_syntax`) | `crates/generate` | `parser.c`, `node-types.json` and errors identical for all 91 reference grammars; ported unit tests |
| `language`, `runtime` | `lib/src` | trees, edits, changed ranges, logs, UTF-16, included ranges identical to C on all corpora, mutations and random edits |
| `query` | `lib/src/query.c` | matches and captures identical to C; `query_test.rs` ported |
| root package | `lib/binding_rust` | the CLI crate's parser, node, tree, language, query, corpus and pathological test suites ported (`tests/`) |
| `scanners` | fixture and test grammar `scanner.c` files | identical trees and logs in every mode, except upstream undefined behaviour in `uses_current_column` |
| `highlight`, `tags`, `query_testing` | `crates/highlight`, `crates/tags`, CLI query testing | event streams, HTML, tags and assertions identical to the Rust crates |
| `regex` | the `regex` crate subset tags and loader use | matching, `find_iter` and errors identical |
| `cli`, `loader`, `config`, `clap`, `clap_complete`, `cmd/treesitter` | `crates/cli`, `crates/loader`, `crates/config`, clap | 1,148 command lines identical to the upstream CLI |

CI runs the ported test suites on every backend (`tools/check.sh`) and the
whole differential oracle against a fresh build of the pinned upstream
(`tools/oracle/oracle_setup.sh`, `tools/oracle/oracle.sh`,
`tools/oracle/diff_cli.sh`).

## Remaining

- Performance: see [COMPATIBILITY.md](COMPATIBILITY.md#performance). The
  remaining cost is mostly reference counting and boxed small structs.
- Wasm grammar support (`wasm_store.c`) and `playground`, if MoonBit gains a
  way to run them.
- Release 0.1.0 to Mooncakes (see [RELEASING.md](RELEASING.md)) once the
  work above is reviewed.

Progress is tracked in
[issue #1](https://github.com/moonbit-community/treesitter/issues/1).

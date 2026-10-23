# Compatibility and missing functionality in 0.1.0

Version 0.1.0 is an experimental, incomplete port of Tree-sitter to pure MoonBit.
It is suitable for evaluating MoonBit grammars and the parser APIs. It does not
yet provide full Tree-sitter behavior or stable API compatibility. The full
repository remains the intended scope; publishing this release does not close
that work.

The reference is Tree-sitter 0.28.0 at commit
`4a412a01a0147d0f50bf7e749572fa632d1ab203`. Compatibility statements below refer
to that baseline and the pinned grammar revisions in
[tools/grammar_matrix.json](tools/grammar_matrix.json).

## Available now

- Typed MoonBit grammar definitions in `.mbtx`, upstream `grammar.json` input,
  Unicode lexical compilation, LR table generation, precedence and conflicts.
- Pure MoonBit parsing with GLR alternatives, error recovery, external scanner
  callbacks, persistent trees and cursors, edits, incremental subtree reuse,
  changed ranges, included ranges, UTF-8 and UTF-16 input.
- Structural queries with captures, quantifiers and predicates; highlighting,
  locals, injections, HTML output, tags and documentation captures.
- Grammar discovery and native commands for generation, parsing, queries,
  highlighting, tags, corpus testing/updating, deterministic edit fuzzing,
  grammar initialization, node schemas and MoonBit language factories.
- Portable libraries tested on native, JavaScript and Wasm GC. Filesystem,
  process, loader and CLI integration require native MoonBit.

See [README.mbt.md](README.mbt.md) for examples and the command reference.

## Missing or different

| Area | Current limitation and practical consequence |
| --- | --- |
| Grammar migration | JavaScript `grammar.js` is not evaluated. Supply upstream `grammar.json` or rewrite the grammar with the MoonBit DSL. C/C++ external scanners must be ported to MoonBit. JavaScript and Rust scanner examples are included. |
| Generated languages | This project uses its own versioned portable table format. It cannot load upstream `parser.c`, native shared libraries, C language ABI objects or upstream Wasm language binaries. |
| Queries | Rooted/nonlocal pattern analysis and guaranteed-step metadata APIs are missing. Some grouped/quantified alternatives, match completion ordering, and ranged queries differ, especially around hidden repetition nodes and uncaptured alternatives. Do not assume identical capture streams for every upstream query. |
| Error recovery | Malformed input can produce different error trees, missing-token choices and token placement. These differences can also change reported changed ranges. |
| Incremental performance | Deterministic subtrees can be reused, but ambiguous regions and encoded/included-range inputs are handled conservatively. Full graph-structured stack sharing and upstream performance parity have not been established. |
| Node schemas | One of 62 frozen schema fixtures differs: `uses_current_column` reports a different `children.required` value for its block node. |
| Diagnostics and CLI | Parser/tree DOT graph diagnostics, the playground and shell completions are missing. CLI flags and output formats are this project's interface, not a promise of upstream command compatibility. |
| API coverage | The complete upstream API/feature inventory and regression migration remain unfinished. Numeric node IDs are not globally unique; node equality represents persistent identity within a tree. |
| Test tooling | The public highlight/tag annotation reader supports the checked ASCII fixtures; upstream-compatible grapheme-column handling for non-ASCII annotations is unfinished. |

This is a known-gap inventory, not a guarantee that all other edge cases match.
Unrecognized behavior may still need implementation or correction. A complete
whole-port review and broader performance comparison are still outstanding.

## Validation evidence

The release preparation checkpoint passed 356 native, 347 JavaScript and
347 Wasm GC tests, plus the CLI integration suite. The public grammar audit
passes all 462 unchanged corpus cases across JSON, C, JavaScript, Go, Regex and
Rust, all 15 query-file compilation checks, 90 highlight/tag position assertions,
2,772 incremental/fresh/undo checks and named-tree hashes for 10 larger examples
containing 877,693 bytes. These selected suites do not constitute full upstream
compatibility.

Development-only differential probes found additional gaps that are not hidden
by the passing corpus matrix:

- A 1,153-edit runtime probe retained 79 tree-output differences and 50
  changed-range differences among cases with matching tree output. It found no
  parser failures or disagreement between this port's fresh and incremental
  tree outputs.
- 1,224 unbounded query probes and 378 quantified-alternative probes matched
  the reference exactly. Other probes retained 15 differences in 300 root/range
  cases, 21 in 196 group-capture cases, and 12 in 225 extended-alternative cases.
  Ten upstream timeouts were excluded from the latter comparison. A separate
  positive-closure probe retained 12 ranged-query differences in 96 cases.

These probes cover overlapping cases and are not a combined pass percentage.
Their temporary development harnesses are not shipped; the committed,
reproducible checks are:

```sh
sh tools/check.sh
python3 tools/audit_grammars.py --fetch
```

The public audit fetches pinned grammar repositories only for testing. The
distributed implementation does not call the upstream C runtime or Rust
generator. [PLAN.md](PLAN.md) records the ongoing implementation history.

## Next milestones

1. Finish query analysis and close the remaining completion/range discrepancies.
2. Align recovery and changed-range behavior with the C reference.
3. Complete the API, diagnostics and CLI inventory and remaining implementations.
4. Measure and improve generator, GLR and incremental performance.
5. Run the final whole-port Codex CLI ultra review and address its findings.

Report reproducible issues with the grammar, input, query or edit sequence,
MoonBit version, and expected upstream behavior. Keep the grammar's original
license and attribution when sharing fixtures.

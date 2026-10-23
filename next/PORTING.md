# Faithful port: conventions

`next/` holds a structural port of Tree-sitter 0.28.0 (pinned at
`4a412a01a0147d0f50bf7e749572fa632d1ab203`) that will replace the earlier
reimplementation. The pinned upstream checkout lives at
`/Users/dii/git/treesitter/.repos/ts-pinned` (its CLI is built at
`target/release/tree-sitter`; run cargo with `+1.97.1`).

Packages:

- `next/language`: `Language`, a field-for-field mirror of C `TSLanguage`.
  The generated C lex functions are represented by `LexProgram`, whose
  interpretation must equal the C that `render.rs` emits.
- `next/generate`: port of `crates/generate`.
- `next/regex_syntax`: port of the subset of `regex-syntax 0.8.11` that the
  generator uses (AST parser, HIR translator, smart constructors, Unicode).

## Rules

1. **One MoonBit file per upstream file**, same base name
   (`build_tables/item.rs` → `next/generate/item.mbt`). Start each file with
   `// Port of tree-sitter crates/generate/src/<path>.`. Keep upstream's
   function names, structure and comments. Port upstream `#[cfg(test)]` tests
   into `<name>_test.mbt` (or `_wbtest.mbt` when private items are needed).
2. **Output must be identical**, including every numbering that leaks into
   tables (state ids, symbol order, `StrId` intern order). Port loops in the
   same order. Never iterate a MoonBit `Map` where upstream iterates a sorted
   or ordered structure unless the insertion order is provably the same.
   - `IndexMap`/`IndexSet` → MoonBit `Map` (insertion ordered). Watch
     `swap_remove` vs `shift_remove`: MoonBit `Map::remove` preserves order
     (= `shift_remove`); emulate `swap_remove` explicitly.
   - `BTreeMap`/`BTreeSet` → `@sorted_map`/`@sorted_set` or sorted arrays.
   - `HashMap`/`FxHashMap`/`HashSet` → `Map` only for lookups. If upstream
     iterates one in a way that can influence output, stop and report it.
   - Rust `sort`, `sort_by`, `sort_by_key` are **stable**. For a natural-order
     sort use core's `arr.mut_view().stable_sort()`; with a comparator or key
     use `stable_sort_by`/`stable_sort_by_key` (util.mbt; core has no stable
     `_by` variants). MoonBit's `Array::sort*` are unstable. Rust `sort_unstable*` with possible ties
     between distinguishable elements must be flagged in a comment and
     reported.
   - `Vec::dedup` → `dedup` (util.mbt); `Vec::swap_remove` → `swap_remove`.
3. Rust value types (`Copy` structs) become immutable MoonBit structs; update
   with `{ ..x, field: v }`. Beware aliasing when upstream clones a `Vec` or a
   struct containing one: call `.copy()`.
4. Errors: define a `suberror` per upstream error enum and implement `Show`
   so `to_string()` reproduces upstream's `Display` text **exactly**
   (`expected_error.txt` fixtures compare it).
5. Foundation files (`strpool`, `bitvec`, `symbols`, `rules`, `grammars`,
   `nfa`, `tables`, `dedup`, `util`, `interfaces`) are shared. Prefer adding
   methods in your own files; if a foundation change is unavoidable, keep it
   minimal and mention it in your report. Implement the `declare`d contracts
   in `interfaces.mbt` by moving the declaration into your file as a real
   definition with the same signature.
6. Validate with `moon check`, `moon test next/generate` (and your package),
   and the differential oracle: `sh tools/next/ref_generate.sh` writes
   upstream outputs for every test and fixture grammar to `_build/ref/<name>`.
   For intermediate structures, copy the upstream crate to a scratch
   directory and add debug prints there; never modify the pinned checkout.
7. Run `moon fmt` on your files before finishing. Commit with focused
   messages.

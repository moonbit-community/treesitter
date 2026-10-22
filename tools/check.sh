#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
moon check --warn-list +unnecessary_annotation
moon check --target native --warn-list +unnecessary_annotation
moon test --target native
moon test --target js
moon test --target wasm-gc
grammar_init_dir=$(mktemp -d "${TMPDIR:-/tmp}/treesitter-init.XXXXXX")
trap 'rm -rf "$grammar_init_dir"' EXIT HUP INT TERM
moon run cmd/treesitter --target native -- init starter "$grammar_init_dir"
moon run cmd/treesitter --target native -- generate "$grammar_init_dir/grammar.mbtx" "$grammar_init_dir/language.json"
moon run cmd/treesitter --target native -- test "$grammar_init_dir/language.json" "$grammar_init_dir/test/corpus"
moon run cmd/treesitter --target native -- fuzz "$grammar_init_dir/language.json" "$grammar_init_dir/test/corpus" --seed 7 --iterations 2 --edits 2
moon run cmd/treesitter --target native -- generate examples/grammar.mbtx _build/arithmetic.language.json
moon run cmd/treesitter --target native -- emit _build/arithmetic.language.json _build/arithmetic.mbt
moon run cmd/treesitter --target native -- generate examples/json/grammar.mbtx _build/json.language.json
moon run cmd/treesitter --target native -- emit _build/json.language.json _build/json.mbt
cmp _build/arithmetic.mbt examples/arithmetic/language.mbt
cmp _build/json.mbt examples/json/language.mbt
moon run cmd/treesitter --target native -- parse _build/json.language.json examples/json/sample.json
moon run cmd/treesitter --target native -- query --check _build/json.language.json examples/json/highlights.scm
moon run cmd/treesitter --target native -- highlight _build/json.language.json examples/json/highlights.scm examples/json/sample.json > _build/json.html
tree_sitter_root=$PWD
(
  cd examples/json
  unset TREESITTER_MBT_ROOT
  "$tree_sitter_root/_build/native/debug/build/cmd/treesitter/treesitter.exe" highlight sample.json > "$tree_sitter_root/_build/configured-highlight.html"
  "$tree_sitter_root/_build/native/debug/build/cmd/treesitter/treesitter.exe" tags sample.json > "$tree_sitter_root/_build/configured-tags.jsonl"
)
cmp _build/json.html _build/configured-highlight.html
test -s _build/configured-tags.jsonl
moon run cmd/treesitter --target native -- generate examples/quoted/grammar.mbtx _build/quoted.language.json
moon run cmd/treesitter --target native -- --scanner examples/quoted/scanner.mbtx parse _build/quoted.language.json examples/quoted/sample.txt > _build/quoted.sexp
cmp _build/quoted.sexp examples/quoted/expected.sexp
moon run cmd/treesitter --target native -- --scanner examples/quoted/scanner.mbtx init scanned "$grammar_init_dir/scanned"
test -f "$grammar_init_dir/scanned/example.scanned"
(
  cd "$grammar_init_dir"
  unset TREESITTER_MBT_ROOT
  "$tree_sitter_root/_build/native/debug/build/cmd/treesitter/treesitter.exe" generate grammar.mbtx outside.language.json
  "$tree_sitter_root/_build/native/debug/build/cmd/treesitter/treesitter.exe" --scanner "$tree_sitter_root/examples/quoted/scanner.mbtx" parse "$tree_sitter_root/_build/quoted.language.json" "$tree_sitter_root/examples/quoted/sample.txt" > outside-scanner.sexp
  cmp outside-scanner.sexp "$tree_sitter_root/examples/quoted/expected.sexp"
)
moon fmt --check
moon fmt --check examples/grammar.mbtx examples/json/grammar.mbtx examples/quoted/grammar.mbtx examples/quoted/scanner.mbtx examples/javascript/scanner.mbtx

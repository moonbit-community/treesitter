#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
moon check --warn-list +unnecessary_annotation
moon test --target native
moon test --target js
moon test --target wasm-gc
moon run cmd/treesitter --target native -- generate examples/grammar.mbtx _build/arithmetic.language.json
moon run cmd/treesitter --target native -- emit _build/arithmetic.language.json _build/arithmetic.mbt
moon run cmd/treesitter --target native -- generate examples/json/grammar.mbtx _build/json.language.json
moon run cmd/treesitter --target native -- emit _build/json.language.json _build/json.mbt
cmp _build/arithmetic.mbt examples/arithmetic/language.mbt
cmp _build/json.mbt examples/json/language.mbt
moon run cmd/treesitter --target native -- parse _build/json.language.json examples/json/sample.json
moon run cmd/treesitter --target native -- highlight _build/json.language.json examples/json/highlights.scm examples/json/sample.json > _build/json.html
tree_sitter_root=$PWD
(
  cd examples/json
  TREESITTER_MBT_ROOT="$tree_sitter_root" "$tree_sitter_root/_build/native/debug/build/cmd/treesitter/treesitter.exe" highlight sample.json > "$tree_sitter_root/_build/configured-highlight.html"
  TREESITTER_MBT_ROOT="$tree_sitter_root" "$tree_sitter_root/_build/native/debug/build/cmd/treesitter/treesitter.exe" tags sample.json > "$tree_sitter_root/_build/configured-tags.jsonl"
)
cmp _build/json.html _build/configured-highlight.html
test -s _build/configured-tags.jsonl
moon fmt --check
moon fmt --check examples/grammar.mbtx examples/json/grammar.mbtx

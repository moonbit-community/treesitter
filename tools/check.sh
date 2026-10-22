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
moon fmt --check
moon fmt --check examples/grammar.mbtx examples/json/grammar.mbtx

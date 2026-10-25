#!/bin/sh
# Differential harness for generate/render.mbt.
#
# Builds a copy of the pinned upstream CLI whose `render_c_code` serializes its
# inputs to JSON (tools/oracle/render_harness), then regenerates every grammar
# produced by tools/oracle/ref_generate.sh, writing for each variant
#   _build/render_dump/<name>/input<variant>.json   inputs of render_c_code
#   _build/render_dump/<name>/parser<variant>.c     upstream output for them
# Variants: "" (ABI 15, the `ref_generate.sh` configuration, checked against
# _build/ref), "_abi14" (`--abi 14`) and "_semver" (with a tree-sitter.json
# declaring version 1.22.333). Run `sh tools/oracle/ref_generate.sh` first.
# Development-only.
set -u
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
UPSTREAM=${UPSTREAM:-$(cd ../../.. 2>/dev/null && pwd)/.repos/ts-pinned}
[ -d "$UPSTREAM/test" ] || UPSTREAM=$(git rev-parse --path-format=absolute --git-common-dir)/../.repos/ts-pinned
COPY=${RENDER_HARNESS_DIR:-$ROOT/_build/render_harness}
mkdir -p "$COPY"
rsync -a --exclude target --exclude test/fixtures --exclude .git "$UPSTREAM/" "$COPY/"
cp tools/oracle/render_harness/render_dump.rs "$COPY/crates/generate/src/render_dump.rs"
python3 -I tools/oracle/render_harness/patch.py "$COPY/crates/generate/src"
(cd "$COPY" && cargo +1.97.1 build --release -p tree-sitter-cli) || exit 1
TS="$COPY/target/release/tree-sitter"
OUT=_build/render_dump
mkdir -p "$OUT"

# run <name> <ref dir> <suffix> <abi> <semver or "">: regenerate one variant.
run() {
  name=$1 ref=$2 suffix=$3 abi=$4 semver=$5
  work="$OUT/$name/work$suffix"
  rm -rf "$work"
  mkdir -p "$work"
  cp -R "$ref/." "$work/"
  rm -f "$work/src/parser.c"
  if [ -n "$semver" ]; then
    printf '{"metadata":{"version":"%s"}}\n' "$semver" > "$work/tree-sitter.json"
  fi
  (
    cd "$work" || exit 1
    case "$name" in
      fixture_*) g=src/grammar.json ;;
      *) if [ -f grammar.js ]; then g=grammar.js; else g=grammar.json; fi ;;
    esac
    TS_RENDER_DUMP="$ROOT/$OUT/$name/input$suffix.json" "$TS" generate --abi "$abi" "$g" > /dev/null 2>&1
  )
  if [ -f "$work/src/parser.c" ]; then
    mv "$work/src/parser.c" "$OUT/$name/parser$suffix.c"
  fi
  rm -rf "$work"
}

for ref in _build/ref/*/; do
  name=$(basename "$ref")
  [ -f "$ref/src/parser.c" ] || continue
  rm -rf "$OUT/$name"
  mkdir -p "$OUT/$name"
  run "$name" "$ref" "" 15 ""
  # The harness CLI is upstream plus the dump hook, so for the variants without
  # an upstream reference its own output is the reference.
  run "$name" "$ref" _abi14 14 ""
  run "$name" "$ref" _semver 15 1.22.333
  if cmp -s "$OUT/$name/parser.c" "$ref/src/parser.c"; then
    echo "$name ok"
  else
    echo "$name FAILED"
  fi
done

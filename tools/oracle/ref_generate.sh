#!/bin/sh
# Generate upstream reference outputs (grammar.json, parser.c, node-types.json)
# for every upstream test grammar using the pinned tree-sitter CLI.
# Development-only oracle for the faithful port. Output: _build/ref/<name>/src.
set -u
cd "$(dirname "$0")/../.."
UPSTREAM=${UPSTREAM:-$(cd ../../.. 2>/dev/null && pwd)/.repos/ts-pinned}
[ -d "$UPSTREAM/test" ] || UPSTREAM=$(git rev-parse --path-format=absolute --git-common-dir)/../.repos/ts-pinned
TS="$UPSTREAM/target/release/tree-sitter"
OUT=_build/ref
mkdir -p "$OUT"
for dir in "$UPSTREAM"/test/fixtures/test_grammars/*/; do
  name=$(basename "$dir")
  [ -f "$dir/grammar.js" ] || [ -f "$dir/grammar.json" ] || continue
  rm -rf "$OUT/$name"
  cp -R "$dir" "$OUT/$name"
  (
    cd "$OUT/$name" || exit 1
    if [ -f grammar.js ]; then g=grammar.js; else g=grammar.json; fi
    if "$TS" generate "$g" > generate.log 2>&1; then echo "$name ok"; else echo "$name FAILED"; fi
  )
done
# Upstream fixture grammars (fetched with `cargo xtask fetch-fixtures`), regenerated
# from their committed src/grammar.json with the pinned CLI.
for json in "$UPSTREAM"/test/fixtures/grammars/*/src/grammar.json "$UPSTREAM"/test/fixtures/grammars/*/*/src/grammar.json; do
  [ -f "$json" ] || continue
  rel=${json#"$UPSTREAM"/test/fixtures/grammars/}
  name=fixture_$(echo "${rel%/src/grammar.json}" | tr '/' '_')
  rm -rf "$OUT/$name"
  mkdir -p "$OUT/$name/src"
  cp "$json" "$OUT/$name/src/grammar.json"
  (
    cd "$OUT/$name" || exit 1
    if "$TS" generate src/grammar.json > generate.log 2>&1; then echo "$name ok"; else echo "$name FAILED"; fi
  )
done

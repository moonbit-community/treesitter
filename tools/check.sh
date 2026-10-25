#!/bin/sh
# Type-check every backend, run the test suites and exercise the CLI on the
# examples. The differential checks against upstream are separate
# (tools/oracle/oracle_setup.sh, tools/oracle/oracle.sh, tools/oracle/diff_cli.sh).
set -eu
cd "$(dirname "$0")/.."
moon check --target all
moon test --target native
moon test --target js
moon test --target wasm-gc
moon build --target native --release cmd/treesitter
ts=$PWD/_build/native/release/build/cmd/treesitter/treesitter.exe

work=$(mktemp -d "${TMPDIR:-/tmp}/treesitter-check.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/config"
export TREE_SITTER_DIR="$work/config"

# Grammars written in MoonBit (.mbtx), one of them with a MoonBit scanner.
for example in arithmetic json quoted; do
  cp -R "examples/$example" "$work/$example"
  (
    cd "$work/$example"
    "$ts" generate grammar.mbtx
    test -f src/parser.c && test -f src/node-types.json && test -f src/language.json
    if [ -d test/corpus ]; then "$ts" test; fi
  )
done
(
  cd "$work/json"
  "$ts" parse sample.json
  "$ts" query highlights.scm sample.json > /dev/null
  "$ts" highlight --html sample.json > "$work/json.html"
  test -s "$work/json.html"
  "$ts" build -o "$work/json_language.mbt" .
  test -s "$work/json_language.mbt"
)
(
  cd "$work/quoted"
  "$ts" parse sample.quoted
)

echo "check passed"

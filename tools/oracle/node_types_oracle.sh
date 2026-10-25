#!/bin/sh
# Differential oracle for the node_types port (generate/node_types*.mbt).
#
# 1. Copies upstream crates/generate into _build/next_oracle/tsharness, patches
#    in a dump harness (tools/oracle/oracle) and builds it with the pinned toolchain.
# 2. Dumps, for every _build/ref/*/src/grammar.json (run tools/oracle/ref_generate.sh
#    first), for the upstream node_types unit-test grammars and for a few extra
#    grammars: the prepared inputs of get_variable_info/generate_node_types_json
#    and upstream's outputs (variable info, supertype symbol map, node-types.json
#    text or error text).
# 3. Runs generate/oracle on the dumps and compares node-types.json byte for
#    byte with _build/ref/<name>/src/node-types.json.
set -eu
cd "$(dirname "$0")/../.."
REPO=$(pwd)
UPSTREAM=${UPSTREAM:-$(cd ../../.. 2>/dev/null && pwd)/.repos/ts-pinned}
[ -d "$UPSTREAM/crates/generate" ] || UPSTREAM=$(git rev-parse --path-format=absolute --git-common-dir)/../.repos/ts-pinned
OUT=$REPO/_build/next_oracle
WS=$OUT/tsharness
rm -rf "$WS"
mkdir -p "$WS/crates" "$WS/lib/include/tree_sitter" "$WS/lib/src"
cp -R "$UPSTREAM/crates/generate" "$WS/crates/"
cp "$UPSTREAM/Cargo.lock" "$WS/"
cp "$UPSTREAM/lib/include/tree_sitter/api.h" "$WS/lib/include/tree_sitter/"
cp "$UPSTREAM/lib/src/parser.h" "$WS/lib/src/"
python3 tools/oracle/oracle/patch_upstream.py "$WS" "$UPSTREAM"
CARGO="cargo +1.97.1"
FEATURES="--offline --no-default-features --features load -p tree-sitter-generate"
(cd "$WS" && $CARGO build $FEATURES --example nt_dump --quiet)

rm -rf "$OUT/node_types" "$OUT/node_types_tests" "$OUT/node_types_extra" "$OUT/extra_grammars"
mkdir -p "$OUT/node_types_tests"
"$WS/target/debug/examples/nt_dump" "$REPO/_build/ref" "$OUT/node_types" > /dev/null
(cd "$WS" && NT_TEST_DUMP_DIR="$OUT/node_types_tests" $CARGO test $FEATURES --lib --quiet node_types:: > /dev/null)
python3 tools/oracle/oracle/extra_node_types_grammars.py "$OUT/extra_grammars"
"$WS/target/debug/examples/nt_dump" "$OUT/extra_grammars" "$OUT/node_types_extra" > /dev/null

moon build --target native generate/oracle
ORACLE=$REPO/_build/native/debug/build/generate/oracle/oracle.exe
status=0
echo "== fixture and test grammars (_build/ref)"
"$ORACLE" "$OUT/node_types" "$REPO/_build/ref" || status=1
echo "== upstream node_types unit-test grammars"
"$ORACLE" "$OUT/node_types_tests" || status=1
echo "== extra grammars"
"$ORACLE" "$OUT/node_types_extra" || status=1
exit $status

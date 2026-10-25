#!/bin/sh
# Differential oracle for the `build_tables` port.
#
# 1. Builds the upstream harness (tools/next/build_tables_harness/setup.sh) if
#    needed, and runs it over every reference grammar from ref_generate.sh,
#    writing _build/bt_ref/<name>/{inputs.json,tables.txt,time_us}: the
#    serialized inputs of upstream's build_tables, a canonical dump of its
#    result (or its error message), and its run time.
# 2. Runs the MoonBit port on the same inputs (generate/tools/
#    build_tables_diff) and compares the dumps. Extra arguments are passed to
#    it, e.g. `--repeat 3 fixture_cpp`.
set -u
cd "$(dirname "$0")/../.."
DUMP=_build/tsgen/target/release/dump
[ -x "$DUMP" ] || sh tools/next/build_tables_harness/setup.sh || exit 1
OUT=_build/bt_ref
mkdir -p "$OUT"
for g in _build/ref/*/src/grammar.json; do
  name=$(basename "$(dirname "$(dirname "$g")")")
  mkdir -p "$OUT/$name"
  "$DUMP" "$g" "$OUT/$name" > "$OUT/$name/time_us" || echo "$name harness FAILED"
done
# Grammars for paths the reference grammars don't reach (ambiguous extras,
# unnecessary conflicts).
for g in tools/next/build_tables_extra/*.json; do
  name=extra_$(basename "$g" .json)
  mkdir -p "$OUT/$name"
  "$DUMP" "$g" "$OUT/$name" > "$OUT/$name/time_us" || echo "$name harness FAILED"
done
moon build --target native --release generate/tools/build_tables_diff || exit 1
_build/native/release/build/generate/tools/build_tables_diff/build_tables_diff.exe "$OUT" "$@"

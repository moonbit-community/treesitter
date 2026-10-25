#!/bin/sh
# Differential check of the `parse_grammar` + `prepare_grammar` port.
#
# Compares the MoonBit dump (`generate/cmd/dump_prepared`) against the
# same dump produced by a scratch copy of the upstream crate, for every
# `_build/ref/*/src/grammar.json` written by `tools/oracle/ref_generate.sh`.
#
# UPSTREAM_DUMP must point at the upstream dump binary: a copy of
# `crates/generate` with `src/dump.rs` (the Rust twin of
# `generate/prepare_grammar_dump.mbt`), a `StrPool::len` accessor and a
# `src/bin/dump_prepared.rs` driver, built with
# `cargo +1.97.1 build --release --no-default-features --bin dump_prepared`.
# Output: _build/diff_prepare/<name>.{ref,out,diff}.
set -u
cd "$(dirname "$0")/../.."
: "${UPSTREAM_DUMP:?set UPSTREAM_DUMP to the upstream dump_prepared binary}"
moon build --target native generate/cmd/dump_prepared >/dev/null || exit 1
MB=_build/native/debug/build/generate/cmd/dump_prepared/dump_prepared.exe
OUT=_build/diff_prepare
rm -rf "$OUT"
mkdir -p "$OUT"
total=0
same=0
for json in _build/ref/*/src/grammar.json; do
  [ -f "$json" ] || continue
  name=$(basename "$(dirname "$(dirname "$json")")")
  total=$((total + 1))
  "$UPSTREAM_DUMP" "$json" > "$OUT/$name.ref" 2>&1
  "$MB" "$json" > "$OUT/$name.out" 2>&1
  if cmp -s "$OUT/$name.ref" "$OUT/$name.out"; then
    same=$((same + 1))
  else
    diff "$OUT/$name.ref" "$OUT/$name.out" > "$OUT/$name.diff"
    echo "MISMATCH $name"
  fi
done
echo "$same/$total identical"

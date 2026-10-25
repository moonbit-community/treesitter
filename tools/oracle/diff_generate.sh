#!/bin/sh
# Development-only: run the MoonBit generator on every reference grammar and
# compare parser.c / node-types.json byte-for-byte with upstream's output
# (or the error text for grammars upstream rejects).
cd "$(dirname "$0")/../.."
PROBE=_build/native/release/build/tools/probe/probe.exe
ok=0; fail=0
for d in _build/ref/*/; do
  n=$(basename "$d")
  g="$d/src/grammar.json"
  [ -f "$g" ] || continue
  out=_build/gen/$n; mkdir -p "$out"; rm -f "$out"/*
  msg=$("$PROBE" generate "$g" "$out" 2>&1)
  if [ -f "$d/src/parser.c" ]; then
    if cmp -s "$out/parser.c" "$d/src/parser.c" && cmp -s "$out/node-types.json" "$d/src/node-types.json"; then
      ok=$((ok+1))
    else
      fail=$((fail+1)); echo "DIFF $n: $(echo "$msg" | head -2)"
    fi
  else
    expected=$(cat "$d/generate.log" 2>/dev/null)
    if echo "$expected" | grep -qF "$(echo "$msg" | sed 's/^error: //' | head -1)" && [ -n "$msg" ]; then
      ok=$((ok+1))
    else
      fail=$((fail+1)); echo "ERRDIFF $n"; echo "  expected: $(echo "$expected" | head -3)"; echo "  actual:   $(echo "$msg" | head -3)"
    fi
  fi
done
echo "identical=$ok different=$fail"
[ "$fail" -eq 0 ]

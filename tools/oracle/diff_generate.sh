#!/bin/sh
# Development-only: run the MoonBit generator on every reference grammar and
# compare its outcome with upstream's (_build/ref/<name>, ref_generate.sh):
#
# - the diagnostics: the probe's `warning: ...` / `error: ...` output must
#   equal upstream's generate.log with only the CLI's presentation removed
#   (generate_log.py), in full;
# - the probe must run to completion (exit status 0);
# - a grammar upstream accepts must produce byte-identical parser.c and
#   node-types.json; a grammar upstream rejects must produce no parser.c.
cd "$(dirname "$0")/../.."
PROBE=${PROBE:-_build/native/release/build/moonbit-community/treesitter/tools/probe/probe.exe}
ok=0; fail=0
for d in _build/ref/*/; do
  n=$(basename "$d")
  g="$d/src/grammar.json"
  [ -f "$g" ] || continue
  out=_build/gen/$n; mkdir -p "$out"; rm -f "$out"/*
  msg=$("$PROBE" generate "$g" "$out" 2>&1)
  code=$?
  problems=""
  [ "$code" -eq 0 ] || problems="$problems probe-exit-$code"
  if ! expected=$(python3 tools/oracle/generate_log.py "$d/generate.log"); then
    problems="$problems unreadable-generate.log"
  elif [ "$msg" != "$expected" ]; then
    problems="$problems diagnostics"
  fi
  if [ -f "$d/src/parser.c" ]; then
    cmp -s "$out/parser.c" "$d/src/parser.c" || problems="$problems parser.c"
    cmp -s "$out/node-types.json" "$d/src/node-types.json" || problems="$problems node-types.json"
  else
    [ -f "$out/parser.c" ] && problems="$problems accepted-a-rejected-grammar"
  fi
  if [ -z "$problems" ]; then
    ok=$((ok+1))
  else
    fail=$((fail+1)); echo "DIFF $n:$problems"
    case $problems in *diagnostics*)
      printf '%s\n' "$expected" > "$out/expected.txt"; printf '%s\n' "$msg" > "$out/actual.txt"
      diff -u "$out/expected.txt" "$out/actual.txt" | head -20 ;;
    esac
  fi
done
echo "identical=$ok different=$fail"
[ "$fail" -eq 0 ]

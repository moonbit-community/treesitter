#!/bin/sh
# Run the differential oracle against the pinned upstream (set up with
# oracle_setup.sh): generator output, runtime trees in every mode, and query
# results. Exits non-zero on any difference.
#
# Usage: sh tools/oracle/oracle.sh [step...]
#   steps: generate ucc mutate edits log utf16le utf16be ranges query
#   (default: all of them, in that order)
set -eu
cd "$(dirname "$0")/../.."
moon build --target native tools/probe
moon build --target native --release tools/probe
status=0
run() {
  echo "== $*"
  "$@" || status=1
}
# uses_current_column's C scanner overflows its indent buffer on some
# malformed inputs (undefined behaviour), so it is compared on the unmodified
# corpus only (step `ucc`) and excluded from every other mode (with random
# included ranges it can exhaust the machine's memory).
UB="--exclude uses_current_column"
# Grammars whose external scanner is not ported yet.
PENDING=$(sed 's/^/--exclude /' tools/oracle/pending_scanners.txt | tr '\n' ' ')
RT="python3 tools/oracle/diff_runtime.py --externals"
for step in ${*:-generate ucc mutate edits log utf16le utf16be ranges query}; do
  case $step in
    generate) run sh tools/oracle/diff_generate.sh ;;
    ucc) run $RT uses_current_column ;;
    mutate) run $RT $UB $PENDING --mutate 2 ;;
    edits) run $RT $UB $PENDING --edits 3 ;;
    log) run $RT $UB $PENDING --log --mutate 1 ;;
    utf16le) run $RT $UB $PENDING --encoding utf16le ;;
    utf16be) run $RT $UB $PENDING --encoding utf16be ;;
    ranges) run $RT $UB $PENDING --ranges 2 ;;
    query) run python3 tools/oracle/diff_query.py --externals $PENDING ;;
    *) echo "unknown step: $step" >&2; exit 2 ;;
  esac
done
exit $status

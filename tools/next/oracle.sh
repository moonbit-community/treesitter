#!/bin/sh
# Run the whole differential oracle against the pinned upstream (set up with
# oracle_setup.sh): generator output, runtime trees in every mode, and query
# results. Exits non-zero on any difference.
set -eu
cd "$(dirname "$0")/../.."
moon build --target native next/probe
moon build --target native --release next/probe
status=0
step() {
  echo "== $*"
  "$@" || status=1
}
step sh tools/next/diff_generate.sh
step python3 tools/next/diff_runtime.py --externals --mutate 2
step python3 tools/next/diff_runtime.py --externals --edits 3
step python3 tools/next/diff_runtime.py --externals --log
step python3 tools/next/diff_runtime.py --externals --encoding utf16le
step python3 tools/next/diff_runtime.py --externals --encoding utf16be
step python3 tools/next/diff_runtime.py --externals --ranges 2
step python3 tools/next/diff_query.py --externals
exit $status

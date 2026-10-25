#!/bin/sh
# Regenerate the grammar modules under grammars/ (one MoonBit module per
# repository of grammars/grammars.json) and the workspace manifest moon.work.
#
# Needs the pinned grammar checkouts: the upstream fixture grammars
# (.repos/ts-pinned, `cargo xtask fetch-fixtures`, see
# tools/oracle/oracle_setup.sh) and the others
# (`python3 tools/oracle/grammars.py fetch`). The output is a deterministic
# function of those checkouts: running this twice gives no diff.
#
# Usage: sh tools/grammars/update.sh [name...]
set -eu
cd "$(dirname "$0")/../.."
moon build --target native --release tools/grammar_modules
python3 tools/grammars/update.py "$@"
moon info

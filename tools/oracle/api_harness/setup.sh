#!/bin/sh
# Development-only oracle for api: copies the pinned upstream Rust binding
# (lib/ and crates/language, whose Cargo.toml files inherit from the upstream
# workspace) to _build/api_harness with standalone manifests, then builds the
# harness, which links the upstream-generated json, c and javascript parsers.
#
#   sh tools/oracle/api_harness/setup.sh
#   _build/api_harness/target/release/api_harness   # query errors, Debug/Display
#   _build/api_harness/target/release/scenarios     # tests/scenarios_test.mbt
set -eu
cd "$(dirname "$0")/../../.."
UPSTREAM=${UPSTREAM:-$(git rev-parse --path-format=absolute --git-common-dir)/../.repos/ts-pinned}
OUT=_build/api_harness
rm -rf "$OUT/ts-lib" "$OUT/ts-language"
mkdir -p "$OUT"
cp -R "$UPSTREAM/lib" "$OUT/ts-lib"
cp -R "$UPSTREAM/crates/language" "$OUT/ts-language"
cp tools/oracle/api_harness/ts-lib.Cargo.toml "$OUT/ts-lib/Cargo.toml"
cp tools/oracle/api_harness/ts-language.Cargo.toml "$OUT/ts-language/Cargo.toml"
UPSTREAM="$UPSTREAM" cargo +1.97.1 build --release --offline \
  --manifest-path tools/oracle/api_harness/Cargo.toml --target-dir "$OUT/target"

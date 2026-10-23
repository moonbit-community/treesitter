#!/bin/sh
# Build the upstream side of the build_tables differential oracle: a scratch
# copy of the pinned crates/generate in _build/tsgen, with harness.rs (input
# serialization and canonical table dump) and a few accessors added. The
# pinned checkout itself is never modified.
set -eu
cd "$(dirname "$0")/../../.."
HERE=tools/next/build_tables_harness
UPSTREAM=${UPSTREAM:-$(git rev-parse --path-format=absolute --git-common-dir)/../.repos/ts-pinned}
OUT=_build/tsgen
rm -rf "$OUT/src"
mkdir -p "$OUT/dump"
cp -R "$UPSTREAM/crates/generate/src" "$OUT/src"
cp "$UPSTREAM/Cargo.lock" "$OUT/Cargo.lock"
cp "$HERE/Cargo.toml" "$OUT/Cargo.toml"
cp "$HERE/harness.rs" "$OUT/src/harness.rs"
cp "$HERE/main.rs" "$OUT/dump/main.rs"
python3 -I - "$OUT/src" <<'EOF'
import sys
src = sys.argv[1]
def patch(path, old, new):
    p = f"{src}/{path}"
    s = open(p).read()
    assert old in s, (path, old)
    open(p, "w").write(s.replace(old, new, 1))
patch("generate.rs", "mod build_tables;", "mod build_tables;\npub mod harness;")
patch("prepare_grammar.rs", "\nmod expand_tokens;", "\npub(crate) mod expand_tokens;")
patch("strpool.rs", "    #[must_use]\n    pub fn resolve(",
      "    pub fn harness_len(&self) -> usize { self.spans.len() }\n\n    #[must_use]\n    pub fn resolve(")
patch("nfa.rs", "impl CharacterSet {",
      "impl CharacterSet {\n    pub fn harness_ranges(&self) -> Vec<(u32, u32)> { self.ranges.iter().map(|r| (r.start, r.end)).collect() }\n")
patch("tables.rs", "impl ActionListPool {",
      "impl ActionListPool {\n    pub fn harness_get_index(&self, i: usize) -> &[ParseAction] { self.get(ActionListId::new(i as u32, false)) }\n")
EOF
cd "$OUT" && cargo +1.97.1 build --release --offline

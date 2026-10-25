#!/bin/sh
# Set up the differential oracle: check out the pinned upstream Tree-sitter
# into .repos/ts-pinned, build its CLI, fetch its fixture grammars, generate
# the reference outputs (_build/ref, ref_generate.sh) and convert the
# generated parse tables to Language JSON (_build/reflang).
#
# Needs git, a C compiler, cargo (CARGO, default `cargo`), node (to evaluate
# the test grammars' grammar.js) and python3.
set -eu
cd "$(dirname "$0")/../.."
COMMIT=4a412a01a0147d0f50bf7e749572fa632d1ab203
UPSTREAM=${UPSTREAM:-$(git rev-parse --path-format=absolute --git-common-dir)/../.repos/ts-pinned}
CARGO=${CARGO:-cargo}

if [ ! -d "$UPSTREAM/.git" ] && [ ! -f "$UPSTREAM/.git" ]; then
  mkdir -p "$(dirname "$UPSTREAM")"
  git init -q "$UPSTREAM"
  git -C "$UPSTREAM" remote add origin https://github.com/tree-sitter/tree-sitter.git
fi
if [ "$(git -C "$UPSTREAM" rev-parse HEAD 2>/dev/null)" != "$COMMIT" ]; then
  git -C "$UPSTREAM" fetch -q --depth 1 origin "$COMMIT"
  git -C "$UPSTREAM" checkout -q --detach "$COMMIT"
fi

(cd "$UPSTREAM" && $CARGO build --release -p tree-sitter-cli)
if [ ! -d "$UPSTREAM/test/fixtures/grammars/json" ]; then
  (cd "$UPSTREAM" && $CARGO xtask fetch-fixtures)
fi

UPSTREAM=$UPSTREAM sh tools/oracle/ref_generate.sh

mkdir -p _build/reflang
for src in _build/ref/*/src; do
  [ -f "$src/parser.c" ] || continue
  name=$(basename "$(dirname "$src")")
  out=_build/reflang/$name.json
  if [ ! -f "$out" ] || [ "$src/parser.c" -nt "$out" ]; then
    python3 tools/oracle/language_from_c.py "$src" "$out"
  fi
done
echo "oracle ready: $(ls _build/reflang | wc -l | tr -d ' ') languages"

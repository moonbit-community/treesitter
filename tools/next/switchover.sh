#!/bin/sh
# One-time switch from the previous engine to the faithful port in next/.
# Moves each next/<pkg> to its final location, removes the replaced packages
# and rewrites import paths. Run from the module root on a clean tree.
set -eu
cd "$(dirname "$0")/../.."
test -z "$(git status --porcelain)" || { echo "tree not clean" >&2; exit 1; }

# 1. Remove the previous engine (root package sources, replaced packages).
git rm -q -- *.mbt moon.pkg pkg.generated.mbti
for pkg in generate language query highlight tags lex cli loader config corpus compat benchmarks cmd/treesitter examples/arithmetic examples/json; do
  if [ -e "$pkg" ]; then git rm -r -q -- "$pkg"; fi
done
# Keep non-MoonBit example assets.
git checkout HEAD -- examples/json/grammar.mbtx examples/json/highlights.scm examples/json/tags.scm \
  examples/json/sample.json examples/json/tree-sitter.json 2>/dev/null || true

# 2. Move the port into place. next/api becomes the root package.
git mv next/api/tests tests
for f in next/api/*; do git mv "$f" .; done
move() { if [ -e "next/$1" ]; then mkdir -p "$(dirname "$2")"; git mv "next/$1" "$2"; fi; }
for pkg in runtime language generate query regex regex_syntax scanners highlight tags query_testing cli_test cli loader config clap clap_complete fixtures; do
  move "$pkg" "$pkg"
done
move cmd/treesitter cmd/treesitter
move probe tools/probe
git mv next/PORTING.md PORTING.md

# 3. Rewrite import paths.
files=$(git ls-files '*.mbt' '*.mbt.md' '*.mbtx' 'moon.pkg' '*/moon.pkg' '*.py' '*.sh' '*.md')
for f in $files; do
  perl -pi -e 's#moonbit-community/treesitter/next/api/tests#moonbit-community/treesitter/tests#g;
               s#moonbit-community/treesitter/next/api"#moonbit-community/treesitter"#g;
               s#moonbit-community/treesitter/next/probe#moonbit-community/treesitter/tools/probe#g;
               s#moonbit-community/treesitter/next/#moonbit-community/treesitter/#g;
               s#next/probe/probe\.exe#tools/probe/probe.exe#g;
               s#\bnext/(api|runtime|language|generate|query|regex|regex_syntax|scanners|highlight|tags|query_testing|cli_test|cli|loader|config|clap|clap_complete|fixtures)\b#$1#g' "$f"
done
rmdir next 2>/dev/null || true
echo "switch-over done; now run moon check / moon info and fix the remaining references"

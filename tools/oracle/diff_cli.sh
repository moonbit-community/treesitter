#!/bin/bash
# Differential test of the MoonBit tree-sitter CLI (cmd/treesitter)
# against the pinned upstream CLI: help texts, usage errors, shell
# completions, `generate` outputs and errors, `parse` in each output mode,
# `query`, `highlight`, `tags`, `test` and `dump-languages`, on copies of the
# upstream fixture and test grammars. Both CLIs run with the same arguments,
# working directory and configuration; stdout, stderr and exit status are
# compared (timings are masked). Results: _build/cli_diff/{report.txt,cases}.
#
# Usage: sh tools/oracle/diff_cli.sh [section...]
#   sections: help errors completions generate parse query highlight tags test langs
#   misc, plus one per file in tools/oracle/diff_cli.d (see its README)
set -u
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
UPSTREAM=${UPSTREAM:-$(cd ../../.. 2>/dev/null && pwd)/.repos/ts-pinned}
[ -d "$UPSTREAM/test" ] || UPSTREAM=$(git rev-parse --path-format=absolute --git-common-dir)/../.repos/ts-pinned
UP="$UPSTREAM/target/release/tree-sitter"
MBT="$ROOT/_build/native/release/build/moonbit-community/treesitter/cmd/treesitter/treesitter.exe"
WORK="$ROOT/_build/cli_diff"
# Extra sections: tools/oracle/diff_cli.d/<name>.sh defines `section_<name>`.
EXTRA_SECTIONS=""
for extra in "$ROOT"/tools/oracle/diff_cli.d/*.sh; do
  [ -f "$extra" ] || continue
  . "$extra"
  EXTRA_SECTIONS="$EXTRA_SECTIONS $(basename "$extra" .sh)"
done
SECTIONS=${*:-"help errors completions generate parse query highlight tags test langs misc$EXTRA_SECTIONS"}

moon build --target native --release cmd/treesitter >/dev/null || exit 1

mkdir -p "$WORK"
rm -rf "$WORK/cases"
mkdir -p "$WORK/cases" "$WORK/config" "$WORK/lib-up" "$WORK/lib-mbt"
# A private temporary directory: both CLIs write fixed names there (e.g.
# `parse --test-number`'s `.tree-sitter-temp`), which concurrent runs of
# this script in other checkouts would otherwise overwrite.
rm -rf "$WORK/tmp"
mkdir -p "$WORK/tmp"
export TMPDIR="$WORK/tmp"
: > "$WORK/report.txt"
pass=0
fail=0

# Copies of the fixture grammars, named tree-sitter-<name> so that
# `find_all_languages` discovers them. Built once.
GRAMMARS="$WORK/grammars"
if [ ! -d "$GRAMMARS" ]; then
  mkdir -p "$GRAMMARS"
  for dir in "$UPSTREAM"/test/fixtures/grammars/*/; do
    name=$(basename "$dir")
    dest="$GRAMMARS/tree-sitter-$name"
    cp -R "$dir" "$dest"
    rm -rf "$dest/bindings" "$dest/node_modules" "$dest/.git"
  done
fi
printf '{\n  "parser-directories": [\n    "%s"\n  ]\n}\n' "$GRAMMARS" > "$WORK/config/config.json"

mask() {
  sed -E \
    -e 's/[0-9]+\.[0-9]+ ms/X ms/g' \
    -e 's/[0-9]+ bytes\/ms/X bytes\/ms/g' \
    -e 's/\(([0-9]+\.[0-9]+) bytes\/ms\)/(X bytes\/ms)/g' \
    -e 's/"(secs|nanos|parse_rate)": [0-9.e+-]+/"\1": X/g' \
    -e 's/Time: [0-9]+ms/Time: Xms/g' \
    -e 's/time: [0-9]+ms/time: Xms/g' \
    -e 's/^[0-9.]+(ns|µs|ms|s)$/DURATION/' \
    -e "s#$WORK/lib-(up|mbt)#LIBDIR#g" \
    -e 's/ -- Warning: Slow parse rate \(X bytes\/ms\)//g' \
    -e 's/success percentage: [0-9.]+%/success percentage: X%/g' \
    -e "s/Parse: +X ms/Parse: X ms/g" \
    -e "s/[[:blank:]]+X bytes\/ms/ X bytes\/ms/g" \
    -e "s/^thread 'main' \([0-9]+\) panicked/thread 'main' (TID) panicked/"
}

# run_case NAME DIR [env assignments --] ARGS...
run_case() {
  name=$1; shift
  dir=$1; shift
  envs=()
  if [ "${1:-}" = "env" ]; then
    shift
    while [ "$1" != "--" ]; do envs+=("$1"); shift; done
    shift
  fi
  case_dir="$WORK/cases/$name"
  mkdir -p "$case_dir"
  for which in up mbt; do
    if [ $which = up ]; then cli=$UP; else cli=$MBT; fi
    (cd "$dir" && env NO_COLOR=1 TREE_SITTER_DIR="$WORK/config" \
      TREE_SITTER_LIBDIR="$WORK/lib-$which" "${envs[@]+"${envs[@]}"}" \
      "$cli" "$@" > "$case_dir/$which.out" 2> "$case_dir/$which.err" < /dev/null)
    echo $? > "$case_dir/$which.code"
    mask < "$case_dir/$which.out" > "$case_dir/$which.out.m"
    sed -e "s#$UP#TREE_SITTER#g" -e "s#$MBT#TREE_SITTER#g" "$case_dir/$which.err" | mask > "$case_dir/$which.err.m"
  done
  if cmp -s "$case_dir/up.out.m" "$case_dir/mbt.out.m" &&
    cmp -s "$case_dir/up.err.m" "$case_dir/mbt.err.m" &&
    cmp -s "$case_dir/up.code" "$case_dir/mbt.code"; then
    pass=$((pass + 1))
    echo "PASS $name" >> "$WORK/report.txt"
  else
    fail=$((fail + 1))
    echo "FAIL $name" >> "$WORK/report.txt"
    echo "FAIL $name"
  fi
}

# Compare files produced by both CLIs in two copies of a directory.
compare_trees() {
  name=$1; a=$2; b=$3; shift 3
  for f in "$@"; do
    if [ -e "$a/$f" ] || [ -e "$b/$f" ]; then
      if cmp -s "$a/$f" "$b/$f"; then
        pass=$((pass + 1)); echo "PASS $name:$f" >> "$WORK/report.txt"
      else
        fail=$((fail + 1)); echo "FAIL $name:$f" >> "$WORK/report.txt"; echo "FAIL $name:$f"
      fi
    fi
  done
}

COMMANDS="init-config init generate build parse test version fuzz query highlight tags playground dump-languages complete"

for section in $SECTIONS; do
  case $section in
  help)
    run_case help-root-long "$WORK" --help
    run_case help-root-short "$WORK" -h
    run_case help-none "$WORK"
    run_case version-long "$WORK" --version
    run_case version-short "$WORK" -V
    for c in $COMMANDS; do
      run_case "help-$c-short" "$WORK" $c -h
      run_case "help-$c-long" "$WORK" $c --help
    done
    for alias in i gen g b p t publish f q hi play pg web-ui langs comp; do
      run_case "help-alias-$alias" "$WORK" $alias -h
    done
    ;;
  errors)
    run_case err-unknown-sub "$WORK" pars
    run_case err-unknown-sub2 "$WORK" frobnicate
    run_case err-unknown-flag "$WORK" parse --foo
    run_case err-unknown-flag-similar "$WORK" parse --xm
    run_case err-unknown-flag-sub "$WORK" --cst
    run_case err-unknown-short "$WORK" parse -Z
    run_case err-missing-required "$WORK" query
    run_case err-missing-shell "$WORK" complete
    run_case err-invalid-value "$WORK" parse --encoding utf32 x
    run_case err-invalid-value-similar "$WORK" complete -s bsh
    run_case err-empty-value "$WORK" parse --scope
    run_case err-invalid-number "$WORK" parse --timeout abc x
    run_case err-invalid-number2 "$WORK" parse -n -3
    run_case err-u32-range "$WORK" parse -n 99999999999 x
    run_case err-conflict "$WORK" generate --json --json-summary
    run_case err-conflict2 "$WORK" parse -n 1 x.js
    run_case err-conflict3 "$WORK" parse -p . -r x
    run_case err-requires "$WORK" parse --open-log x
    run_case err-requires2 "$WORK" parse --lang-name foo x
    run_case err-twice "$WORK" parse -q -q x
    run_case err-twice2 "$WORK" parse --scope a --scope b x
    run_case err-flag-value "$WORK" parse --quiet=yes x
    run_case err-debug-value "$WORK" parse -d x.js
    run_case err-bad-regex "$WORK" test --include '('
    run_case err-bad-semver "$WORK" version 1.x
    run_case err-escape-sub "$WORK" -- parse
    run_case err-no-files "$WORK" parse does-not-exist.js
    run_case err-range "$WORK" query q.scm x --byte-range 5
    ;;
  completions)
    for s in bash zsh fish elvish power-shell nushell; do
      run_case "complete-$s" "$WORK" complete --shell $s
    done
    ;;
  generate)
    gen="$WORK/gen"
    rm -rf "$gen"
    mkdir -p "$gen"
    for dir in "$UPSTREAM"/test/fixtures/test_grammars/*/; do
      name=$(basename "$dir")
      [ -f "$dir/grammar.js" ] || [ -f "$dir/grammar.json" ] || continue
      for which in up mbt; do cp -R "$dir" "$gen/$name-$which"; done
      if [ -f "$dir/grammar.js" ]; then g=grammar.js; else g=grammar.json; fi
      for which in up mbt; do
        if [ $which = up ]; then cli=$UP; else cli=$MBT; fi
        (cd "$gen/$name-$which" && env NO_COLOR=1 "$cli" generate $g > gen.out 2> gen.err; echo $? > gen.code)
        sed -e "s#$gen/$name-$which#GRAMMAR#g" "$gen/$name-$which/gen.err" > "$gen/$name-$which/gen.err.m"
      done
      compare_trees "generate-$name" "$gen/$name-up" "$gen/$name-mbt" \
        src/parser.c src/node-types.json src/grammar.json src/tree_sitter/parser.h \
        src/tree_sitter/array.h src/tree_sitter/alloc.h gen.out gen.err.m gen.code
    done
    # Fixture grammars from their committed grammar.json, with options.
    for dir in "$GRAMMARS"/*/; do
      name=$(basename "$dir")
      [ -f "$dir/src/grammar.json" ] || continue
      for which in up mbt; do
        rm -rf "$gen/$name-$which"
        mkdir -p "$gen/$name-$which/src"
        cp "$dir/src/grammar.json" "$gen/$name-$which/src/"
        [ -f "$dir/tree-sitter.json" ] && cp "$dir/tree-sitter.json" "$gen/$name-$which/"
        if [ $which = up ]; then cli=$UP; else cli=$MBT; fi
        (cd "$gen/$name-$which" && env NO_COLOR=1 "$cli" generate src/grammar.json --abi 14 > gen.out 2> gen.err; echo $? > gen.code)
      done
      compare_trees "generate-abi14-$name" "$gen/$name-up" "$gen/$name-mbt" \
        src/parser.c src/node-types.json gen.out gen.err gen.code
    done
    for which in up mbt; do
      rm -rf "$gen/opts-$which"
      cp -R "$UPSTREAM/test/fixtures/test_grammars/aliased_rules" "$gen/opts-$which"
      if [ $which = up ]; then cli=$UP; else cli=$MBT; fi
      (cd "$gen/opts-$which" && env NO_COLOR=1 "$cli" generate --no-parser -o out > np.out 2> np.err; echo $? > np.code
       env NO_COLOR=1 "$cli" generate --disable-optimizations -o noopt > no.out 2> no.err; echo $? > no.code
       env NO_COLOR=1 "$cli" generate --report-states-for-rule - -o rep > rep.out 2> rep.err; echo $? > rep.code
       env NO_COLOR=1 "$cli" generate --json-summary -o js > js.out 2> js.err; echo $? > js.code
       env NO_COLOR=1 "$cli" generate missing.json > miss.out 2> miss.err; echo $? > miss.code
       env NO_COLOR=1 "$cli" generate grammar.txt > ext.out 2> ext.err; echo $? > ext.code)
    done
    compare_trees generate-options "$gen/opts-up" "$gen/opts-mbt" \
      out/node-types.json out/grammar.json np.out np.err np.code noopt/parser.c no.out no.code \
      rep/parser.c rep.out rep.err rep.code js.err js.code miss.err miss.code ext.err ext.code
    ;;
  parse)
    for g in json javascript python rust ruby bash c cpp go html java embedded-template typescript php jsdoc; do
      gdir="$GRAMMARS/tree-sitter-$g"
      [ -d "$gdir" ] || continue
      files=$(ls "$gdir"/examples/* 2>/dev/null | head -3)
      for f in $files; do
        base=$(basename "$f")
        run_case "parse-$g-$base" "$WORK" parse "$f"
        run_case "parse-cst-$g-$base" "$WORK" parse --cst "$f"
        run_case "parse-xml-$g-$base" "$WORK" parse --xml "$f"
        run_case "parse-noranges-$g-$base" "$WORK" parse --no-ranges "$f"
        run_case "parse-quiet-$g-$base" "$WORK" parse -q "$f"
      done
      # Corpus examples through --test-number.
      for n in 1 2 3; do
        run_case "parse-test-$g-$n" "$gdir" parse -n $n
        run_case "parse-test-cst-$g-$n" "$gdir" parse -n $n --cst
      done
    done
    js="$GRAMMARS/tree-sitter-javascript/examples/jquery.js"
    run_case parse-color-cst "$WORK" env NO_COLOR= -- parse --cst "$GRAMMARS/tree-sitter-json/test/corpus/main.txt" --scope source.json
    run_case parse-multi "$WORK" parse "$js" "$GRAMMARS/tree-sitter-python/examples/python3-grammar.py"
    run_case parse-multi-xml "$WORK" parse --xml "$js" "$GRAMMARS/tree-sitter-python/examples/python3-grammar.py"
    run_case parse-edits "$WORK" parse "$js" --edits "0 0 x" "10,2 3 abc"
    run_case parse-edits-end "$WORK" parse "$js" --edits '$ 0 ;'
    run_case parse-edits-bad "$WORK" parse "$js" --edits "foo"
    run_case parse-debug "$WORK" parse -d "$GRAMMARS/tree-sitter-json/test/corpus/main.txt" --scope source.json
    run_case parse-debug-pretty "$WORK" parse --debug=pretty "$GRAMMARS/tree-sitter-json/test/corpus/main.txt" --scope source.json
    run_case parse-scope "$WORK" parse --scope source.json "$GRAMMARS/tree-sitter-json/test/corpus/main.txt"
    run_case parse-unknown-scope "$WORK" parse --scope source.nope "$js"
    run_case parse-stat "$WORK" parse --stat "$js" "$GRAMMARS/tree-sitter-python/examples/python3-grammar.py"
    run_case parse-json-summary "$WORK" parse --json-summary "$js"
    run_case parse-glob "$WORK" parse "$GRAMMARS/tree-sitter-python/examples/*.py" '!'"$GRAMMARS/tree-sitter-python/examples/python2-grammar.py"
    printf '%s\n' "$js" "$GRAMMARS/tree-sitter-python/examples/python3-grammar.py" > "$WORK/paths.txt"
    run_case parse-paths-file "$WORK" parse --paths "$WORK/paths.txt" -q
    iconv -f UTF-8 -t UTF-16LE "$GRAMMARS/tree-sitter-json/test/corpus/main.txt" > "$WORK/utf16le.json"
    iconv -f UTF-8 -t UTF-16BE "$GRAMMARS/tree-sitter-json/test/corpus/main.txt" > "$WORK/utf16be.json"
    run_case parse-utf16le "$WORK" parse --encoding utf16-le "$WORK/utf16le.json"
    run_case parse-utf16be "$WORK" parse --encoding utf16-be "$WORK/utf16be.json"
    run_case parse-no-lang "$WORK" parse "$WORK/paths.txt"
    printf '{"a": [1, 2, {"b": null}]}\n' > "$WORK/small.json"
    for mode in --dot --debug-graph; do
      for which in up mbt; do
        d="$WORK/graph-$which"
        rm -rf "$d"; mkdir -p "$d"
        if [ $which = up ]; then cli=$UP; else cli=$MBT; fi
        (cd "$d" && env NO_COLOR=1 TREE_SITTER_DIR="$WORK/config" TREE_SITTER_LIBDIR="$WORK/lib-$which" "$cli" parse $mode "$WORK/small.json" --edits "2 1 x" > out.txt 2> err.txt; echo $? > code.txt
         # Upstream names graph nodes by their addresses.
         sed -E 's/node_(0x[0-9a-f]+|[0-9]+)/node_ID/g; s/tree_(0x[0-9a-f]+|[0-9]+)/tree_ID/g' log.html > log.html.m)
      done
      compare_trees "parse$mode" "$WORK/graph-up" "$WORK/graph-mbt" log.html.m out.txt err.txt code.txt
    done
    ;;
  query)
    js="$GRAMMARS/tree-sitter-javascript/examples/jquery.js"
    hq="$GRAMMARS/tree-sitter-javascript/queries/highlights.scm"
    run_case query-matches "$WORK" query "$hq" "$js"
    run_case query-captures "$WORK" query -c "$hq" "$js"
    run_case query-byte-range "$WORK" query "$hq" "$js" --byte-range 100:400
    run_case query-row-range "$WORK" query -c "$hq" "$js" --row-range 3:9
    run_case query-containing "$WORK" query "$hq" "$js" --containing-byte-range 0:300
    run_case query-containing-rows "$WORK" query "$hq" "$js" --containing-row-range 0:20
    run_case query-quiet "$WORK" query -q "$hq" "$js"
    printf '(identifier) @a\n(oops\n' > "$WORK/bad.scm"
    run_case query-bad "$WORK" query "$WORK/bad.scm" "$js"
    for g in rust python c go ruby; do
      gdir="$GRAMMARS/tree-sitter-$g"
      f=$(ls "$gdir"/examples/* 2>/dev/null | head -1)
      [ -n "$f" ] || continue
      for q in "$gdir"/queries/*.scm; do
        run_case "query-$g-$(basename "$q")" "$WORK" query "$q" "$f"
      done
    done
    ;;
  highlight)
    for g in javascript python rust json c go ruby; do
      gdir="$GRAMMARS/tree-sitter-$g"
      f=$(ls "$gdir"/examples/* 2>/dev/null | head -1)
      [ -n "$f" ] || f=$(ls "$gdir"/test/corpus/* | head -1)
      [ -n "$f" ] || continue
      run_case "highlight-$g" "$WORK" highlight "$f"
      run_case "highlight-html-$g" "$WORK" highlight --html "$f"
      run_case "highlight-html-inline-$g" "$WORK" highlight --html --style inline --layout fragment "$f"
      run_case "highlight-html-lines-$g" "$WORK" highlight --html --layout line-numbers "$f"
      run_case "highlight-check-$g" "$WORK" highlight --check -q "$f"
    done
    run_case highlight-color "$WORK" env NO_COLOR= -- highlight "$GRAMMARS/tree-sitter-javascript/examples/jquery.js"
    printf %s\\n "<html>" "<script>" "/** @param {number} y the value */" "function f(y) { return \`a\${y}\`; }" "</script>" "<p class=\"a\">hi &amp; bye</p>" "</html>" > "$WORK/inj.html"
    run_case highlight-injection "$WORK" highlight "$WORK/inj.html"
    run_case highlight-html-injection "$WORK" highlight --html "$WORK/inj.html"
    run_case highlight-injection-erb "$WORK" highlight "$GRAMMARS/tree-sitter-embedded-template/test/corpus/main.txt" --scope text.html.erb
    # A grammar directory without a configured parser directory (the
    # languages come from the current directory); generated from mbtx.
    rm -rf "$WORK/example-json" "$WORK/noconfig"
    cp -R "$ROOT/examples/json" "$WORK/example-json"
    mkdir -p "$WORK/noconfig"
    (cd "$WORK/example-json" && "$MBT" generate grammar.mbtx > /dev/null 2>&1)
    # Upstream compiles this grammar to <libdir>/json.dylib, the name of the
    # fixture json parser: use a separate library directory.
    rm -rf "$WORK/example-lib"
    mkdir -p "$WORK/example-lib"
    for cmd in parse highlight tags; do
      run_case "example-json-$cmd" "$WORK/example-json" env TREE_SITTER_DIR="$WORK/noconfig" TREE_SITTER_LIBDIR="$WORK/example-lib" -- $cmd sample.json
    done
    # Both CLIs cache languages by name; drop the example's `json` so that
    # later runs do not reuse it for the fixture grammar of the same name.
    rm -f "$WORK"/lib-up/json.* "$WORK"/lib-mbt/json.*
    ;;
  tags)
    for g in javascript python rust ruby c go; do
      gdir="$GRAMMARS/tree-sitter-$g"
      f=$(ls "$gdir"/examples/* 2>/dev/null | head -2)
      [ -n "$f" ] || continue
      run_case "tags-$g" "$WORK" tags $f
    done
    ;;
  test)
    for g in json javascript python rust ruby bash c go html embedded-template java jsdoc; do
      gdir="$GRAMMARS/tree-sitter-$g"
      [ -d "$gdir/test" ] || continue
      run_case "test-$g" "$gdir" test --stat total-only
      run_case "test-overview-$g" "$gdir" test --stat total-only --overview-only
      run_case "test-include-$g" "$gdir" test --stat total-only --include '^[A-Ca-c]'
    done
    run_case test-json-summary "$GRAMMARS/tree-sitter-json" test --json-summary
    ;;
  langs)
    run_case dump-languages "$WORK" dump-languages
    ;;
  misc)
    # Failing corpus tests, `--update`, colored diffs and query tests.
    for which in up mbt; do
      d="$WORK/misc-$which"
      rm -rf "$d"
      cp -R "$GRAMMARS/tree-sitter-javascript" "$d"
      rm -rf "$d/test/highlight" "$d/test/tags"
      perl -0pi -e 's/\(program\n  \(expression_statement\n    \(string/(program\n  (expression_statement\n    (number/' "$d/test/corpus/literals.txt"
      mkdir -p "$d/test/custom"
      printf '(identifier) @variable\n(number) @number\n' > "$d/queries/custom.scm"
      printf 'var abc = 1;\n//  ^ variable\n//        ^ number\nfoo(2);\n// <- variable\n' > "$d/test/custom/ok.js"
      printf 'var abc = 1;\n//  ^ number\n' > "$d/test/custom/bad.js"
    done
    for which in up mbt; do
      d="$WORK/misc-$which"
      if [ $which = up ]; then cli=$UP; else cli=$MBT; fi
      (cd "$d" && env NO_COLOR=1 TREE_SITTER_DIR="$WORK/config" TREE_SITTER_LIBDIR="$WORK/lib-$which" "$cli" test --stat total-only > fail.out 2> fail.err; echo $? > fail.code
       env NO_COLOR= TREE_SITTER_DIR="$WORK/config" TREE_SITTER_LIBDIR="$WORK/lib-$which" "$cli" test --stat total-only --include Strings > color.out 2> color.err; echo $? > color.code
       env NO_COLOR=1 TREE_SITTER_DIR="$WORK/config" TREE_SITTER_LIBDIR="$WORK/lib-$which" "$cli" test --stat total-only --json-summary > json.out 2> json.err; echo $? > json.code
       env NO_COLOR=1 TREE_SITTER_DIR="$WORK/config" TREE_SITTER_LIBDIR="$WORK/lib-$which" "$cli" test --stat total-only -u > update.out 2> update.err; echo $? > update.code
       env NO_COLOR=1 TREE_SITTER_DIR="$WORK/config" TREE_SITTER_LIBDIR="$WORK/lib-$which" TREE_SITTER_SEED=7 "$cli" fuzz --iterations 2 --edits 2 --include Strings > fuzz.out 2> fuzz.err; echo $? > fuzz.code)
      for f in fail color json update fuzz; do
        mask < "$d/$f.out" > "$d/$f.out.m"
        sed -e "s#$d#DIR#g" "$d/$f.err" | mask > "$d/$f.err.m"
      done
    done
    compare_trees misc "$WORK/misc-up" "$WORK/misc-mbt" \
      fail.out.m fail.err.m fail.code color.out.m color.err.m color.code \
      json.out.m json.err.m json.code update.out.m update.err.m update.code \
      test/corpus/literals.txt test/corpus/expressions.txt \
      fuzz.out.m fuzz.err.m fuzz.code
    # init and version in a grammar repository.
    for which in up mbt; do
      d="$WORK/init-$which"
      rm -rf "$d"
      mkdir -p "$d/src"
      cp "$GRAMMARS/tree-sitter-json/tree-sitter.json" "$GRAMMARS/tree-sitter-json/grammar.js" "$d/"
      cp "$GRAMMARS/tree-sitter-json/src/grammar.json" "$d/src/"
      if [ $which = up ]; then cli=$UP; else cli=$MBT; fi
      (cd "$d" && env NO_COLOR=1 "$cli" init > init.out 2> init.err; echo $? > init.code
       env NO_COLOR=1 "$cli" version > v1.out 2> v1.err; echo $? > v1.code
       env NO_COLOR=1 "$cli" version --bump minor > v2.out 2> v2.err; echo $? > v2.code)
    done
    (cd "$WORK/init-up" && find . -type f | sort | sed 's#^\./##' | grep -v '^build.zig.zon$' > "$WORK/init-files.txt")
    compare_trees init "$WORK/init-up" "$WORK/init-mbt" $(cat "$WORK/init-files.txt")
    ;;
  *)
    if declare -F "section_$section" > /dev/null; then
      "section_$section"
    else
      fail=$((fail + 1))
      echo "FAIL unknown-section-$section" | tee -a "$WORK/report.txt"
    fi
    ;;
  esac
done

echo "pass: $pass, fail: $fail" | tee -a "$WORK/report.txt"
[ "$fail" -eq 0 ]

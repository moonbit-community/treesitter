# Command logic of `test`, `parse`, `generate` and `init`: the BTreeMap order
# of the corpus tests' languages, exact `{:.2}` statistics, the parser that
# the highlight tests inherit from `test --debug`, full-width `u32`/`usize`
# arguments, walkdir's treatment of symbolic links, and Unicode case
# conversions of grammar names.

# Compare one line pattern of the unmasked stdout of a case.
logic_compare_raw() {
  local name=$1 pattern=$2 case_dir="$WORK/cases/$1"
  grep -o "$pattern" "$case_dir/up.out" > "$case_dir/up.raw"
  grep -o "$pattern" "$case_dir/mbt.out" > "$case_dir/mbt.raw"
  if [ -s "$case_dir/up.raw" ] && cmp -s "$case_dir/up.raw" "$case_dir/mbt.raw"; then
    pass=$((pass + 1)); echo "PASS $name:raw" >> "$WORK/report.txt"
  else
    fail=$((fail + 1)); echo "FAIL $name:raw" >> "$WORK/report.txt"; echo "FAIL $name:raw"
  fi
}

section_logic() {
  local L="$WORK/logic"
  rm -rf "$L"
  mkdir -p "$L"

  # Languages keyed by name in a BTreeMap: `z` is listed first, but after a
  # `:language(...)` test the parser resets to `a`, the first name in str
  # order; of two grammars named `a` the last one wins.
  local R="$L/langs"
  mkdir -p "$R/test/corpus"
  cp -R "$GRAMMARS/tree-sitter-embedded-template" "$R/z"
  cp -R "$GRAMMARS/tree-sitter-json" "$R/a"
  cp -R "$GRAMMARS/tree-sitter-jsdoc" "$R/a2"
  rm -rf "$R"/{z,a,a2}/test "$R"/{z,a,a2}/tree-sitter.json "$R"/{z,a,a2}/package.json
  cat > "$R/tree-sitter.json" <<'EOF'
{
  "grammars": [
    {"name": "z", "scope": "source.z", "path": "z", "file-types": ["z"]},
    {"name": "a", "scope": "source.a", "path": "a", "file-types": ["a"]},
    {"name": "a", "scope": "source.a2", "path": "a2", "file-types": ["a2"]}
  ],
  "metadata": {"version": "0.1.0"}
}
EOF
  local t
  for t in first 'second\n:language(a)' third 'fourth\n:language(z)' fifth; do
    printf '================================================================================\n%b\n================================================================================\n\n1\n\n--------------------------------------------------------------------------------\n\n(document (number))\n\n' "$t"
  done > "$R/test/corpus/langs.txt"
  run_case logic-test-languages "$R" test --stat total-only
  run_case logic-parse-test-number-language "$R" parse -n 2

  # Parse statistics: 1 success out of 32 is 3.125%, printed as 3.12%.
  local S="$L/stat"
  mkdir -p "$S"
  local i
  for i in $(seq 1 31); do echo '{' > "$S/bad$i.json"; done
  echo '[1]' > "$S/ok.json"
  run_case logic-parse-stat-rate "$S" parse -q --stat --scope source.json ok.json 'bad*.json'
  logic_compare_raw logic-parse-stat-rate 'success percentage: [0-9.]*%'
  run_case logic-parse-json-summary "$S" parse -q --json-summary --scope source.json ok.json bad1.json

  # `test --debug`: the highlight tests continue with the corpus parser and
  # its logger.
  local D="$L/debug"
  cp -R "$GRAMMARS/tree-sitter-json" "$D"
  rm -rf "$D/test"
  mkdir -p "$D/test/corpus" "$D/test/highlight"
  printf '====\nnumber\n====\n\n1\n\n----\n\n(document (number))\n' > "$D/test/corpus/one.txt"
  printf '{"a": 1}\n//    ^ number\n' > "$D/test/highlight/one.json"
  run_case logic-test-debug-highlight "$D" test --debug --stat total-only

  # u32 and usize arguments keep their full width.
  run_case logic-parse-test-number-u32-max "$D" parse -n 4294967295
  run_case logic-parse-test-number-above-i32 "$D" parse -n 2147483648
  run_case logic-parse-test-number-neg-zero "$D" parse --test-number=-0
  run_case logic-query-test-number-u32-max "$D" query queries/highlights.scm -n 4294967295
  run_case logic-highlight-test-number-u32-max "$D" highlight -n 4294967295
  run_case logic-generate-abi-above-i32 "$D" generate --abi 2147483648 src/grammar.json
  run_case logic-generate-abi-u64-max "$D" generate --abi 18446744073709551615 src/grammar.json
  run_case logic-generate-abi-plus "$D" generate --abi +16 src/grammar.json

  # walkdir: symbolic links below the walked directories are neither files
  # nor followed; a walked directory that is itself a link is followed.
  local W="$L/walk"
  cp -R "$GRAMMARS/tree-sitter-json" "$W"
  rm -rf "$W/test"
  mkdir -p "$W/test/corpus" "$W/test/custom" "$W/elsewhere/sub" "$W/othertests"
  printf '====\nnumber\n====\n\n1\n\n----\n\n(document (number))\n' > "$W/test/corpus/one.txt"
  printf '(oops' > "$W/elsewhere/bad.scm"
  printf '(oops' > "$W/elsewhere/sub/worse.scm"
  ln -s ../elsewhere/bad.scm "$W/queries/linked.scm"
  ln -s ../elsewhere/sub "$W/queries/linked-dir"
  printf '(number) @number\n' > "$W/queries/custom.scm"
  # (`test` also uses each query test file as the query.)
  printf '(number) @number\n' > "$W/test/custom/ok.json"
  ln -s ok.json "$W/test/custom/link.json"
  printf '(string) @string\n' > "$W/queries/other.scm"
  printf '(string) @string\n' > "$W/othertests/s.json"
  ln -s ../othertests "$W/test/other"
  run_case logic-test-walk-symlinks "$W" test --stat total-only
  # A symlinked queries directory is followed.
  local WQ="$L/walk-root"
  cp -R "$W" "$WQ"
  mv "$WQ/queries" "$WQ/real-queries"
  rm -f "$WQ/real-queries/linked.scm"
  ln -s real-queries "$WQ/queries"
  printf '(oops' > "$WQ/real-queries/broken.scm"
  run_case logic-test-walk-root-symlink "$WQ" test --stat total-only

  # init with a non-ASCII grammar name: heck's Unicode word boundaries and
  # case mappings.
  local which cli d
  for which in up mbt; do
    d="$L/init-$which"
    rm -rf "$d"
    mkdir -p "$d/src"
    sed -e 's/"name": "json"/"name": "ÉFooΣ"/' -e 's/"camelcase": "JSON"/"camelcase": "ÉFooΣ"/' \
      "$GRAMMARS/tree-sitter-json/tree-sitter.json" > "$d/tree-sitter.json"
    cp "$GRAMMARS/tree-sitter-json/grammar.js" "$d/"
    cp "$GRAMMARS/tree-sitter-json/src/grammar.json" "$d/src/"
    if [ $which = up ]; then cli=$UP; else cli=$MBT; fi
    (cd "$d" && env NO_COLOR=1 "$cli" init > init.out 2> init.err; echo $? > init.code)
  done
  (cd "$L/init-up" && find . -type f | sort | sed 's#^\./##' | grep -v '^build.zig.zon$' > "$L/init-files.txt")
  compare_trees logic-init-unicode "$L/init-up" "$L/init-mbt" $(cat "$L/init-files.txt")
}

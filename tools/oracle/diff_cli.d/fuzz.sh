# The `fuzz` command (crates/cli/src/fuzz.rs and fuzz/*.rs) with fixed
# seeds: the edit sequences of rand's `StdRng` (visible through
# TREE_SITTER_DUMP_EDITS, which writes each trial's edited input to
# `fuzz/edit.<seed>.<test>.<trial> <name>`), TREE_SITTER_LOG_SEED, seeds that
# wrap around `usize`, `usize` edit and iteration counts, `--log-graphs`,
# TREE_SITTER_LOG (parser logs on stderr), TREE_SITTER_LOG_GRAPHS (log.html,
# when graphviz is installed), skipped tests, missing corpora, and the
# corpus-header warnings of `parse_tests` (on stderr, so that
# `test --json-summary` prints only JSON).

# fuzz_case NAME GRAMMAR [env VAR=VALUE ... --] ARGS...: run `fuzz ARGS` in
# each CLI's copy of GRAMMAR and compare stdout, stderr, exit status, the
# dumped edits and log.html.
fuzz_case() {
  local name=$1 grammar=$2
  shift 2
  local envs=()
  if [ "${1:-}" = "env" ]; then
    shift
    while [ "$1" != "--" ]; do envs+=("$1"); shift; done
    shift
  fi
  local case_dir="$WORK/cases/$name" which cli d f ok=1
  mkdir -p "$case_dir"
  for which in up mbt; do
    if [ $which = up ]; then cli=$UP; else cli=$MBT; fi
    d="$WORK/fuzz-$which/$grammar"
    rm -rf "$d/fuzz" "$d/log.html"
    (cd "$d" && env NO_COLOR=1 TREE_SITTER_DIR="$WORK/config" \
      TREE_SITTER_LIBDIR="$WORK/lib-$which" "${envs[@]+"${envs[@]}"}" \
      "$cli" fuzz "$@" > "$case_dir/$which.out" 2> "$case_dir/$which.err" < /dev/null)
    echo $? > "$case_dir/$which.code"
    mask < "$case_dir/$which.out" > "$case_dir/$which.out.m"
    # (a seed that is not given is random)
    sed -E -e "s#$d#DIR#g" -e 's/^fuzz seed: [0-9]+$/fuzz seed: SEED/' "$case_dir/$which.err" |
      mask > "$case_dir/$which.err.m"
    : > "$case_dir/$which.dump"
    if [ -d "$d/fuzz" ]; then
      for f in "$d"/fuzz/*; do
        printf '== %s\n' "$(basename "$f")" >> "$case_dir/$which.dump"
        cat "$f" >> "$case_dir/$which.dump"
        printf '\n' >> "$case_dir/$which.dump"
      done
    fi
    # (upstream's graph node ids are addresses)
    rm -f "$case_dir/$which.log.html"
    [ -f "$d/log.html" ] && sed -E 's/(tree|node)_(0x[0-9a-f]+|[0-9]+)/\1_ID/g' \
      "$d/log.html" > "$case_dir/$which.log.html"
  done
  for f in out.m err.m code dump; do
    cmp -s "$case_dir/up.$f" "$case_dir/mbt.$f" || ok=0
  done
  if [ -e "$case_dir/up.log.html" ] || [ -e "$case_dir/mbt.log.html" ]; then
    cmp -s "$case_dir/up.log.html" "$case_dir/mbt.log.html" || ok=0
  fi
  if [ $ok = 1 ]; then
    pass=$((pass + 1)); echo "PASS $name" >> "$WORK/report.txt"
  else
    fail=$((fail + 1)); echo "FAIL $name" >> "$WORK/report.txt"; echo "FAIL $name"
  fi
}

section_fuzz() {
  local which g d
  for which in up mbt; do
    d="$WORK/fuzz-$which"
    rm -rf "$d"
    mkdir -p "$d"
    for g in json python; do
      cp -R "$GRAMMARS/tree-sitter-$g" "$d/$g"
    done
    # A corpus with attribute-like test headers (warnings of `parse_tests`)
    # and a skipped test.
    cp -R "$GRAMMARS/tree-sitter-json" "$d/headers"
    printf '%s\n' \
      '==================' 'Skipped :skip' '==================' '' '[1]' '' '---' '' \
      '(document (array (number)))' '' \
      '==================' ':skp' 'Typo in the name' '==================' '' '2' '' '---' '' \
      '(document (number))' '' \
      '==================' 'Typo in the attributes' ':cst' ':errror' '==================' '' \
      '3' '' '---' '' '(document (number))' '' \
      '==================' 'Both skipped and error' ':skip' ':error' '==================' '' \
      'true' '' '---' '' '(document (true))' '' \
      '==================' 'Attribute marker' ':skip' '==================' '' 'null' '' \
      '---' '' '(document (null))' '' \
      '==================' 'Unterminated header' \
      > "$d/headers/test/corpus/headers.txt"
    # A grammar directory without a corpus, and one with an empty corpus.
    cp -R "$GRAMMARS/tree-sitter-json" "$d/nocorpus"
    rm -rf "$d/nocorpus/test"
    cp -R "$GRAMMARS/tree-sitter-json" "$d/emptycorpus"
    rm -rf "$d/emptycorpus/test/corpus"
    mkdir -p "$d/emptycorpus/test/corpus"
  done

  # Edit sequences (TREE_SITTER_DUMP_EDITS) and logged seeds.
  fuzz_case fuzz-json-seed1 json env TREE_SITTER_SEED=1 TREE_SITTER_LOG_SEED=1 \
    TREE_SITTER_DUMP_EDITS=1 -- --iterations 4 --edits 5
  fuzz_case fuzz-json-seed-large json env TREE_SITTER_SEED=+12345678901234567 \
    TREE_SITTER_LOG_SEED=1 TREE_SITTER_DUMP_EDITS=1 -- --iterations 3
  # `start_seed + trial` wraps around (release build).
  fuzz_case fuzz-json-seed-wrap json env TREE_SITTER_SEED=18446744073709551614 \
    TREE_SITTER_LOG_SEED=1 TREE_SITTER_DUMP_EDITS=1 -- --iterations 4 --edits 2
  fuzz_case fuzz-json-env-counts json env TREE_SITTER_SEED=99 TREE_SITTER_LOG_SEED=1 \
    TREE_SITTER_DUMP_EDITS=1 TREE_SITTER_EDITS=7 TREE_SITTER_ITERATIONS=2 --
  fuzz_case fuzz-json-edits-zero json env TREE_SITTER_SEED=5 TREE_SITTER_DUMP_EDITS=1 -- \
    --iterations 2 --edits 0 --include Arrays
  fuzz_case fuzz-python-seed python env TREE_SITTER_SEED=2024 TREE_SITTER_LOG_SEED=1 \
    TREE_SITTER_DUMP_EDITS=1 -- --iterations 2 --include 'Import|Print'
  # `usize` counts beyond 32 bits (no test runs).
  fuzz_case fuzz-json-iterations-u64 json env TREE_SITTER_SEED=3 -- \
    --iterations 18446744073709551615 --edits 18446744073709551615 --include '^$'
  fuzz_case fuzz-json-env-u64 json env TREE_SITTER_SEED=3 \
    TREE_SITTER_ITERATIONS=4294967297 TREE_SITTER_EDITS=4294967297 -- --include '^$'
  # Invalid seeds are ignored: a random seed is printed.
  fuzz_case fuzz-json-seed-invalid json env TREE_SITTER_SEED=18446744073709551616 -- \
    --include '^$'
  fuzz_case fuzz-json-seed-negative json env TREE_SITTER_SEED=-1 -- --include '^$'
  fuzz_case fuzz-json-iterations-overflow json env TREE_SITTER_SEED=3 -- \
    --iterations 18446744073709551616
  fuzz_case fuzz-json-exclude json env TREE_SITTER_SEED=11 TREE_SITTER_DUMP_EDITS=1 -- \
    --iterations 1 --exclude 'Arrays|String'
  # Diagnostics on stderr.
  fuzz_case fuzz-json-log-graphs-flag json env TREE_SITTER_SEED=8 -- \
    --iterations 1 --edits 1 --include Top-level --log-graphs
  fuzz_case fuzz-json-parser-log json env TREE_SITTER_SEED=8 TREE_SITTER_LOG=1 -- \
    --iterations 1 --edits 1 --include 'Top-level null'
  if command -v dot > /dev/null; then
    fuzz_case fuzz-json-log-graphs json env TREE_SITTER_SEED=8 TREE_SITTER_LOG_GRAPHS=1 -- \
      --iterations 1 --edits 1 --include 'Top-level null'
  fi
  fuzz_case fuzz-json-skip json env TREE_SITTER_SEED=4 -- --iterations 1 \
    --skip 'json - corpus - main - Arrays' --skip 'json - corpus - main - String content'
  fuzz_case fuzz-headers headers env TREE_SITTER_SEED=6 TREE_SITTER_DUMP_EDITS=1 -- \
    --iterations 1
  fuzz_case fuzz-no-corpus nocorpus env TREE_SITTER_SEED=1 --
  fuzz_case fuzz-empty-corpus emptycorpus env TREE_SITTER_SEED=1 --

  # The header warnings go to stderr: `--json-summary` prints only JSON.
  run_case fuzz-test-headers-json "$WORK/fuzz-up/headers" test --json-summary
  run_case fuzz-test-headers "$WORK/fuzz-up/headers" test --stat total-only
}

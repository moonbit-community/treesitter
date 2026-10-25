# Output and input plumbing (crates/cli/src/{query,parse,tags,highlight,
# util}.rs and Rust's std::io): output written before an error, special
# files read as sources and queries (`/dev/null`, FIFOs), writes to a closed
# pipe (`BufWriter` errors ending in the silently ignored `BrokenPipe`,
# `println!` and clap_complete panics), dot graph sessions without
# graphviz, and the home directory with `HOME` unset (the account database
# fallback of `std::env::home_dir`).

# io_run NAME DIR CMD...: run CMD (with `$cli` set to each CLI) in DIR and
# compare stdout, stderr (panic thread ids masked) and exit status.
io_run() {
  local name=$1 dir=$2
  shift 2
  local case_dir="$WORK/cases/$name" which
  mkdir -p "$case_dir"
  for which in up mbt; do
    if [ $which = up ]; then cli=$UP; else cli=$MBT; fi
    (cd "$dir" && export NO_COLOR=1 TREE_SITTER_DIR="$WORK/config" \
      TREE_SITTER_LIBDIR="$WORK/lib-$which" && eval "$*" \
      > "$case_dir/$which.out" 2> "$case_dir/$which.err" < /dev/null)
    echo $? > "$case_dir/$which.code"
    sed -E "s/^thread 'main' \([0-9]+\) panicked/thread 'main' (TID) panicked/" \
      "$case_dir/$which.out" | mask > "$case_dir/$which.out.m"
    sed -E -e "s#$UP#TREE_SITTER#g" -e "s#$MBT#TREE_SITTER#g" \
      -e "s/^thread 'main' \([0-9]+\) panicked/thread 'main' (TID) panicked/" \
      "$case_dir/$which.err" | mask > "$case_dir/$which.err.m"
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

# closed_pipe CMD...: run CMD with its standard output a pipe whose read end
# is already closed; print its standard error and exit status.
closed_pipe() {
  python3 -I -c '
import os, subprocess, sys
r, w = os.pipe()
os.close(r)
p = subprocess.run(sys.argv[1:], stdout=w, stderr=subprocess.PIPE, stdin=subprocess.DEVNULL)
os.close(w)
sys.stdout.write(p.stderr.decode("utf-8", "replace"))
print("exit status", p.returncode)
' "$@"
}

section_io() {
  local D="$WORK/io"
  rm -rf "$D"
  mkdir -p "$D/adir"
  printf '{"a": [1, 2, {"b": null}]}\n' > "$D/small.json"
  printf '(pair key: (string) @key)\n' > "$D/pairs.scm"
  : > "$D/empty.scm"
  : > "$D/x.zzz"
  local js="$GRAMMARS/tree-sitter-javascript/examples/jquery.js"
  local hq="$GRAMMARS/tree-sitter-javascript/queries/highlights.scm"

  # Output written before an error is not lost.
  run_case io-query-dir-source "$D" query --scope source.json empty.scm adir
  run_case io-query-dir-source-matches "$D" query --scope source.json pairs.scm small.json adir
  run_case io-parse-dir-source "$D" parse small.json adir
  run_case io-parse-xml-dir-source "$D" parse --xml small.json adir
  run_case io-tags-dir-source "$D" tags --scope source.json adir

  # Special files.
  run_case io-query-devnull-source "$D" query --scope source.json pairs.scm /dev/null
  run_case io-query-devnull-query "$D" query --scope source.json /dev/null small.json
  run_case io-parse-devnull "$D" parse --scope source.json /dev/null
  run_case io-parse-cst-devnull "$D" parse --scope source.json --cst /dev/null
  run_case io-parse-xml-devnull "$D" parse --scope source.json --xml /dev/null
  run_case io-highlight-devnull "$D" highlight --scope source.json /dev/null
  run_case io-highlight-html-devnull "$D" highlight --html --scope source.json /dev/null
  run_case io-tags-devnull "$D" tags --scope source.json /dev/null
  io_run io-parse-fifo "$D" 'rm -f fifo && mkfifo fifo && { printf "[1, {\"a\": 2}]\n" > fifo & } && "$cli" parse --scope source.json fifo; s=$?; wait; rm -f fifo; exit $s'
  io_run io-query-fifo "$D" 'rm -f fifo && mkfifo fifo && { cat pairs.scm > fifo & } && "$cli" query --scope source.json fifo small.json; s=$?; wait; rm -f fifo; exit $s'

  # Writes to a closed pipe.
  for shell in bash elvish fish power-shell zsh nushell; do
    io_run "io-closed-complete-$shell" "$D" closed_pipe '"$cli"' complete --shell $shell
  done
  io_run io-closed-help "$D" closed_pipe '"$cli"' --help
  io_run io-closed-parse-small "$D" closed_pipe '"$cli"' parse small.json
  io_run io-closed-parse-stat "$D" closed_pipe '"$cli"' parse --stat small.json
  io_run io-closed-parse "$D" closed_pipe '"$cli"' parse "$js"
  io_run io-closed-parse-cst "$D" closed_pipe '"$cli"' parse --cst "$js"
  io_run io-closed-parse-xml "$D" closed_pipe '"$cli"' parse --xml "$js"
  io_run io-closed-query "$D" closed_pipe '"$cli"' query "$hq" "$js"
  io_run io-closed-query-captures "$D" closed_pipe '"$cli"' query -c "$hq" "$js"
  io_run io-closed-highlight "$D" closed_pipe '"$cli"' highlight "$js"
  io_run io-closed-highlight-html "$D" closed_pipe '"$cli"' highlight --html "$js"
  io_run io-closed-tags "$D" closed_pipe '"$cli"' tags "$js"

  # Dot graph sessions start `dot` right away: without graphviz they fail
  # before parsing (`--debug-graph`) or panic (`--dot`), leaving the header.
  run_case io-graph-warm "$D" parse small.json
  for mode in --debug-graph --dot; do
    for which in up mbt; do
      local g="$D/graph$mode-$which"
      rm -rf "$g"
      mkdir -p "$g"
      if [ $which = up ]; then cli=$UP; else cli=$MBT; fi
      (cd "$g" && env NO_COLOR=1 TREE_SITTER_DIR="$WORK/config" TREE_SITTER_LIBDIR="$WORK/lib-$which" \
        PATH=/nonexistent "$cli" parse $mode "$D/small.json" > out.txt 2> err.raw; echo $? > code.txt
       sed -E "s/^thread 'main' \([0-9]+\) panicked/thread 'main' (TID) panicked/" err.raw > err.txt)
    done
    compare_trees "io-graph-no-dot$mode" "$D/graph$mode-up" "$D/graph$mode-mbt" log.html out.txt err.txt code.txt
  done

  # Concurrent graph sessions (in two directories) do not share files.
  for which in up mbt; do
    if [ $which = up ]; then cli=$UP; else cli=$MBT; fi
    rm -rf "$D/concurrent-$which"
    mkdir -p "$D/concurrent-$which/a" "$D/concurrent-$which/b"
    (export NO_COLOR=1 TREE_SITTER_DIR="$WORK/config" TREE_SITTER_LIBDIR="$WORK/lib-$which"
      cd "$D/concurrent-$which/a" &&
        "$cli" parse --debug-graph "$D/small.json" > out.txt 2> err.txt &
      cd "$D/concurrent-$which/b" &&
        "$cli" parse --debug-graph --scope source.json \
          "$GRAMMARS/tree-sitter-json/test/corpus/main.txt" > out.txt 2> err.txt &
      wait)
    for f in a b; do
      sed -E 's/node_(0x[0-9a-f]+|[0-9]+)/node_ID/g; s/tree_(0x[0-9a-f]+|[0-9]+)/tree_ID/g' \
        "$D/concurrent-$which/$f/log.html" > "$D/concurrent-$which/$f/log.html.m"
      mask < "$D/concurrent-$which/$f/out.txt" > "$D/concurrent-$which/$f/out.txt.m"
    done
  done
  compare_trees io-graph-concurrent "$D/concurrent-up" "$D/concurrent-mbt" \
    a/log.html.m a/out.txt.m a/err.txt b/log.html.m b/out.txt.m b/err.txt

  # `HOME` unset: `~` in the configuration expands to the account's home
  # directory. The second parser directory leads back to the test grammars.
  local up_dirs
  up_dirs=$(printf '%s' "$HOME" | sed -E 's#[^/]+#..#g; s#^/##')
  mkdir -p "$D/home-config"
  printf '{\n  "parser-directories": [\n    "~/.tree-sitter-io-none",\n    "~/%s%s"\n  ]\n}\n' \
    "$up_dirs" "$GRAMMARS" > "$D/home-config/config.json"
  io_run io-home-unset-highlight "$D" 'env -u HOME TREE_SITTER_DIR="$PWD/home-config" "$cli" highlight x.zzz'
  io_run io-home-unset-langs "$D" 'env -u HOME TREE_SITTER_DIR="$PWD/home-config" "$cli" dump-languages'
  io_run io-home-empty-langs "$D" 'env HOME= TREE_SITTER_DIR="$PWD/home-config" "$cli" dump-languages'
}

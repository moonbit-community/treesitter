# Fixes of the second review of the CLI port: child processes (pipes that
# are blocking for the child, /dev/null standard input, signal-aware waits),
# usize edit offsets and query ranges, Rust panics instead of aborts,
# arguments that are not valid UTF-8, the current and temporary
# directories, file creation modes, `str::lines` and `~` expansion.
# Uses `io_run` (io.sh).

# r2_run NAME TEMPLATE CMD...: like `io_run`, but each CLI runs in its own
# fresh copy of the directory TEMPLATE (whose path is masked as DIR).
r2_run() {
  local name=$1 template=$2
  shift 2
  local case_dir="$WORK/cases/$name" which run
  mkdir -p "$case_dir"
  for which in up mbt; do
    if [ $which = up ]; then cli=$UP; else cli=$MBT; fi
    run="$template.run-$which"
    rm -rf "$run"
    cp -R "$template" "$run"
    (cd "$run" && export NO_COLOR=1 TREE_SITTER_DIR="$WORK/config" \
      TREE_SITTER_LIBDIR="$WORK/lib-$which" && eval "$*" \
      > "$case_dir/$which.out" 2> "$case_dir/$which.err" < /dev/null)
    echo $? > "$case_dir/$which.code"
    sed -E -e "s#$run#DIR#g" \
      -e "s/^thread 'main' \([0-9]+\) panicked/thread 'main' (TID) panicked/" \
      "$case_dir/$which.out" | mask > "$case_dir/$which.out.m"
    sed -E -e "s#$UP#TREE_SITTER#g" -e "s#$MBT#TREE_SITTER#g" -e "s#$run#DIR#g" \
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

section_review2() {
  local D="$WORK/review2"
  rm -rf "$D"
  mkdir -p "$D/bin"
  printf '{"a": [1, 2, {"b": null}]}\n' > "$D/small.json"
  printf '0' > "$D/zero.json"
  printf '"\377"' > "$D/ff.json"
  printf '123456789\r' > "$D/cr.json"

  # Fake programs that report how their standard streams were set up.
  cat > "$D/bin/dot" <<'EOF'
#!/bin/sh
exec python3 -I -c '
import os, sys
sys.stderr.write("dot: stdin blocking %s\n" % os.get_blocking(0))
data = sys.stdin.buffer.read()
sys.stderr.write("dot: read graphs %s\n" % (len(data) > 0))
sys.stdout.write("<svg/>\n")
'
EOF
  cat > "$D/bin/node" <<'EOF'
#!/bin/sh
exec python3 -I -c '
import os, sys
sys.stderr.write("node: stdin blocking %s, stdout blocking %s\n" % (os.get_blocking(0), os.get_blocking(1)))
sys.stdin.buffer.read()
sys.exit(3)
'
EOF
  for tool in cargo npm; do
    cat > "$D/bin/$tool" <<'EOF'
#!/bin/sh
python3 -I -c '
import os, stat, sys
sys.stderr.write("stdin is a character device: %s\n" % stat.S_ISCHR(os.fstat(0).st_mode))
'
kill -TERM $$
EOF
  done
  chmod +x "$D/bin/"*
  local path="$D/bin:$PATH"

  # Graphviz and the JavaScript runtime get blocking pipe ends.
  io_run review2-dot-stdin "$D" 'PATH="'"$path"'" "$cli" parse --debug-graph small.json; s=$?; cat log.html | tail -1; exit $s'
  mkdir -p "$D/jsgrammar"
  printf 'module.exports = grammar({name: "x", rules: {a: $ => "a"}});\n' > "$D/jsgrammar/grammar.js"
  io_run review2-node-pipes "$D/jsgrammar" 'PATH="'"$path"'" "$cli" generate --no-parser grammar.js'

  # Cargo and npm get /dev/null as standard input; a signal is a failure.
  for tool in cargo npm; do
    local V="$D/version-$tool"
    mkdir -p "$V"
    printf '{\n  "grammars": [{"name": "x", "scope": "source.x", "path": ".", "file-types": ["x"]}],\n  "metadata": {"version": "0.1.0"}\n}\n' > "$V/tree-sitter.json"
    if [ $tool = cargo ]; then
      # A Cargo.toml that cannot be read makes the update run cargo.
      mkdir -p "$V/Cargo.toml"
      : > "$V/Cargo.lock"
    else
      mkdir -p "$V/package.json"
      : > "$V/package-lock.json"
    fi
    r2_run "review2-version-$tool" "$V" 'echo input | PATH="'"$path"'" "$cli" version 1.2.3'
  done

  # Edit offsets are usize: overflowing i32 is an addressing error, a
  # wrapping usize sum a slice panic.
  run_case review2-edit-i32-overflow "$D" parse zero.json --edits '1 2147483647 '
  run_case review2-edit-above-i32 "$D" parse zero.json --edits '0 2147483648 x'
  run_case review2-edit-position-above-i32 "$D" parse zero.json --edits '99999999999 0 x'
  run_case review2-edit-row-above-i32 "$D" parse zero.json --edits '4294967296,0 0 x'
  io_run review2-edit-usize-wrap "$D" '"$cli" parse zero.json --edits "1 18446744073709551615 x"'
  # Query ranges reach the cursor `as u32`.
  local hq="$GRAMMARS/tree-sitter-json/queries/highlights.scm"
  run_case review2-query-byte-range-u32 "$D" query "$hq" small.json --byte-range 0:99999999999
  run_case review2-query-byte-range-wrap "$D" query "$hq" small.json --byte-range 3:4294967296
  run_case review2-query-row-range-u32 "$D" query "$hq" small.json --row-range 0:4294967297

  # Rust panics (status 101, buffered output flushed) instead of aborts.
  io_run review2-xml-invalid-utf8 "$D" '"$cli" parse --xml ff.json'
  local c
  for c in 'num:  "version": 17,' 'open:  "version": "' 'boundary:  "version": "é1"' 'empty:  "version": "",'; do
    local V="$D/version-${c%%:*}"
    mkdir -p "$V"
    printf '{\n  "grammars": [{"name": "x", "scope": "source.x", "path": ".", "file-types": ["x"]}],\n  "metadata": {"version": "0.1.0"}\n}\n' > "$V/tree-sitter.json"
    printf '{\n%s\n}\n' "${c#*:}" > "$V/package.json"
    r2_run "review2-version-package-json-${c%%:*}" "$V" '"$cli" version 1.2.3; s=$?; cat package.json; exit $s'
  done

  # Arguments that are not valid UTF-8.
  io_run review2-utf8-scope "$D" '"$cli" parse --scope $'"'"'\xff'"'"' /dev/null'
  io_run review2-utf8-scope-equals "$D" '"$cli" parse --scope=$'"'"'a\xffb'"'"' /dev/null'
  io_run review2-utf8-edits "$D" '"$cli" parse /dev/null --edits $'"'"'0 0 \xff'"'"''
  io_run review2-utf8-include "$D" '"$cli" test --include $'"'"'\xff'"'"''
  io_run review2-utf8-version "$D" '"$cli" version $'"'"'\xff'"'"''
  io_run review2-utf8-abi "$D" '"$cli" generate --abi $'"'"'\xff'"'"''
  io_run review2-utf8-enum "$D" '"$cli" complete --shell $'"'"'\xff'"'"''
  io_run review2-utf8-path "$D" '"$cli" parse --config-path $'"'"'\xff'"'"' /dev/null'

  # The current directory: computed after parsing the command line, and
  # `--test-number` reads the process's current directory.
  mkdir -p "$D/elsewhere"
  cp -R "$GRAMMARS/tree-sitter-json" "$D/json"
  run_case review2-test-number-grammar-path "$D/elsewhere" parse -n 1 -p ../json
  io_run review2-cwd-removed-complete "$D" 'mkdir gone && cd gone && rmdir ../gone && "$cli" complete --shell bash'
  io_run review2-cwd-removed-help "$D" 'mkdir gone && cd gone && rmdir ../gone && "$cli" parse --help'
  io_run review2-cwd-removed-test-number "$D" 'mkdir gone && cd gone && rmdir ../gone && "$cli" parse -p ../json -n 1'

  # An empty TMPDIR puts the temporary source in the current directory.
  mkdir -p "$D/json/.tree-sitter-temp"
  run_case review2-tmpdir-empty "$D/json" env TMPDIR= -- parse -n 1 -q
  rmdir "$D/json/.tree-sitter-temp"

  # Files are created with mode 0o666 less the umask.
  local which
  for which in up mbt; do
    if [ $which = up ]; then cli=$UP; else cli=$MBT; fi
    rm -rf "$D/modes-$which"
    mkdir -p "$D/modes-$which/config"
    cp "$GRAMMARS/tree-sitter-json/src/grammar.json" "$D/modes-$which/"
    (cd "$D/modes-$which" && umask 002 &&
      env NO_COLOR=1 "$cli" generate grammar.json > /dev/null 2>&1 &&
      env TREE_SITTER_DIR="$PWD/config" "$cli" init-config > /dev/null 2>&1 &&
      python3 -I -c '
import os, sys
for f in sys.argv[1:]:
    print(f, oct(os.stat(f).st_mode & 0o777))
' src/parser.c src/node-types.json src/tree_sitter/parser.h config/config.json > modes.txt)
  done
  compare_trees review2-file-modes "$D/modes-up" "$D/modes-mbt" modes.txt

  # `str::lines` keeps the `\r` of an unterminated last line.
  run_case review2-cst-final-cr "$D" parse --cst cr.json

  # `~` expansion keeps the spelling of the rest of the path.
  mkdir -p "$D/tilde/home" "$D/tilde/config"
  printf '{\n  "parser-directories": [\n    "~/a//b/./not-real",\n    "$HOME//c"\n  ]\n}\n' > "$D/tilde/config/config.json"
  : > "$D/tilde/x.zzz"
  io_run review2-tilde-spelling "$D/tilde" 'HOME="$PWD/home" TREE_SITTER_DIR="$PWD/config" "$cli" highlight x.zzz 2>&1 | sed "s#$PWD#DIR#g"'
}

# `generate` errors: the `--json-summary` envelope (serde form of
# `GenerateError`, `LoadGrammarError`, `JSError`, `ParseVersionError`, the
# generator's own errors), their text without `--json-summary`, and the JS
# runtime protocol (DSL on stdin, inherited stderr, exit codes and signals,
# invalid UTF-8 output, `--abi` parse panics).

# gen_err_case NAME TEMPLATE_DIR ARGS...: run `generate ARGS` in a fresh copy
# of TEMPLATE_DIR for each CLI; compare stdout, stderr, status and the
# generated grammar.json / node-types.json.
gen_err_case() {
  local name=$1 template=$2
  shift 2
  local which cli d
  for which in up mbt; do
    d="$GE/$name-$which"
    rm -rf "$d"
    cp -R "$template" "$d"
    if [ $which = up ]; then cli=$UP; else cli=$MBT; fi
    (cd "$d" && env NO_COLOR=1 PATH="$GE/bin:$PATH" TREE_SITTER_DIR="$WORK/config" \
      "$cli" generate "$@" > gen.out 2> gen.err < /dev/null
     echo $? > gen.code
     sed -E -e "s#$d#DIR#g" -e "s/^thread 'main' \([0-9]+\) panicked/thread 'main' (TID) panicked/" \
       gen.err > gen.err.m
     sed -e "s#$d#DIR#g" gen.out > gen.out.m)
  done
  compare_trees "generate-errors-$name" "$GE/$name-up" "$GE/$name-mbt" \
    gen.out.m gen.err.m gen.code src/grammar.json src/node-types.json
}

section_generate_errors() {
  GE="$WORK/generate-errors"
  rm -rf "$GE"
  mkdir -p "$GE/bin"
  local T="$GE/templates"
  mkdir -p "$T"

  # Fake JavaScript runtimes. Each reads the whole DSL from stdin first.
  printf '#!/bin/sh\ncat > /dev/null\nprintf "line 1\\nline 2\\n{\\"name\\": \\"x\\", \\"rules\\": {\\"a\\": {\\"type\\": \\"STRING\\", \\"value\\": \\"a\\"}}}"\n' > "$GE/bin/rt-ok"
  printf '#!/bin/sh\ncat > /dev/null\necho "to stderr" >&2\nexit 3\n' > "$GE/bin/rt-exit"
  printf '#!/bin/sh\ncat > /dev/null\nkill -9 $$\n' > "$GE/bin/rt-signal"
  printf '#!/bin/sh\ncat > /dev/null\nprintf "ab\\377cd"\n' > "$GE/bin/rt-utf8"
  printf '#!/bin/sh\ncat > /dev/null\nprintf "ab\\342\\202"\n' > "$GE/bin/rt-utf8-incomplete"
  printf '#!/bin/sh\ncat > /dev/null\nprintf "\\360\\237\\230x"\n' > "$GE/bin/rt-utf8-3"
  printf '#!/bin/sh\ncat > /dev/null\nprintf "{oops"\n' > "$GE/bin/rt-json"
  printf '#!/bin/sh\ncat > /dev/null\nprintf "%%s" "$TREE_SITTER_GRAMMAR_PATH" | sed "s#.*/##" >&2\nprintf "{\\"name\\": \\"y\\", \\"rules\\": {\\"a\\": {\\"type\\": \\"STRING\\", \\"value\\": \\"a\\"}}}"\n' > "$GE/bin/rt-env"
  chmod +x "$GE/bin"/rt-*

  # A grammar.js directory (the fake runtimes ignore its contents).
  mkdir -p "$T/js"
  printf 'module.exports = grammar({name: "x", rules: {a: _ => "a"}});\n' > "$T/js/grammar.js"
  # A valid grammar.json, with tree-sitter.json variants.
  mkdir -p "$T/json/src"
  cp "$UPSTREAM/test/fixtures/test_grammars/aliased_rules/grammar.js" "$T/json/" 2>/dev/null
  printf '{"name": "x", "rules": {"a": {"type": "STRING", "value": "a"}}}\n' > "$T/json/src/grammar.json"
  cp -R "$T/json" "$T/badversion"
  printf '{"grammars": [], "metadata": {"version": "1.x"}}\n' > "$T/badversion/tree-sitter.json"
  cp -R "$T/json" "$T/badjson"
  printf '{"metadata": {"version": 1}}\n' > "$T/badjson/tree-sitter.json"
  cp -R "$T/json" "$T/badjson2"
  printf '{"metadata": \n' > "$T/badjson2/tree-sitter.json"
  cp -R "$T/json" "$T/badutf8"
  printf '{"metadata": {"version": "1.0.0\377"}}\n' > "$T/badutf8/tree-sitter.json"
  # Generator errors.
  mkdir -p "$T/parse-error/src" "$T/prepare-error/src" "$T/conflict/src"
  printf '{"name": "x", "rules": {"a": {"type": "NOPE"}}}\n' > "$T/parse-error/src/grammar.json"
  printf '{"name": "x", "rules": {"a": {"type": "SYMBOL", "name": "b"}}}\n' > "$T/prepare-error/src/grammar.json"
  cp "$UPSTREAM/test/fixtures/test_grammars/conflict_in_repeat_rule/grammar.js" "$T/conflict/" 2>/dev/null
  # Other inputs.
  mkdir -p "$T/misc/adir"
  printf 'x\n' > "$T/misc/grammar.txt"
  printf '{"name": "x", "rules": {"a": {"type": "STRING", "value": "a"}}}\n' > "$T/misc/g.json"
  printf '{"name": "x", "rules": \377}\n' > "$T/misc/bad-utf8.json"

  for json in "" --json-summary; do
    local s=${json:+-json}
    gen_err_case "abi-16$s" "$T/json" src/grammar.json --abi 16 $json
    gen_err_case "abi-big$s" "$T/json" src/grammar.json --abi 2147483648 $json
    gen_err_case "abi-max$s" "$T/json" src/grammar.json --abi 18446744073709551615 $json
    gen_err_case "missing$s" "$T/misc" missing.json $json
    gen_err_case "extension$s" "$T/misc" grammar.txt $json
    gen_err_case "dir$s" "$T/misc" adir $json
    gen_err_case "new-dir$s" "$T/misc" newdir $json
    gen_err_case "json-utf8$s" "$T/misc" bad-utf8.json $json
    gen_err_case "ok$s" "$T/misc" g.json $json
    gen_err_case "no-parser$s" "$T/misc" g.json --no-parser $json
    gen_err_case "version$s" "$T/badversion" src/grammar.json $json
    gen_err_case "version-json$s" "$T/badjson" src/grammar.json $json
    gen_err_case "version-json2$s" "$T/badjson2" src/grammar.json $json
    gen_err_case "version-utf8$s" "$T/badutf8" src/grammar.json $json
    gen_err_case "parse-grammar$s" "$T/parse-error" src/grammar.json $json
    gen_err_case "prepare$s" "$T/prepare-error" src/grammar.json $json
    gen_err_case "no-parser-prepare$s" "$T/prepare-error" src/grammar.json --no-parser $json
    for rt in rt-ok rt-exit rt-signal rt-utf8 rt-utf8-incomplete rt-utf8-3 rt-json rt-env rt-missing; do
      gen_err_case "js-$rt$s" "$T/js" --js-runtime $rt $json
    done
    gen_err_case "js-missing-file$s" "$T/js" nope/grammar.js $json
  done
  if command -v node > /dev/null; then
    gen_err_case conflict-node-json "$T/conflict" --json-summary
  fi
  for abi in x "" + 99999999999999999999 99999999999999999999x; do
    gen_err_case "abi-parse-${abi:-empty}" "$T/json" src/grammar.json --abi "$abi"
  done
}

# Loader cases: semver validation of `version`, Rust `Debug` escaping,
# first-line language detection, `grammar.json` name detection, grammar path
# equality and language alias order, and the removal of the legacy macOS
# cache directory.
section_loader() {
  local L="$WORK/loader"
  rm -rf "$L"
  mkdir -p "$L/config" "$L/parsers" "$L/work"

  # semver 1.0.28: numeric pre-release identifiers must not have leading
  # zeros, build metadata may; characters are quoted with `char` Debug.
  run_case loader-semver-pre-leading-zero "$WORK" version 1.2.3-01 --help
  run_case loader-semver-pre-leading-zero-later "$WORK" version 1.2.3-a.00 --help
  run_case loader-semver-pre-alnum-zero "$WORK" version 1.2.3-01a --help
  run_case loader-semver-build-leading-zero "$WORK" version 1.2.3+01 --help
  run_case loader-semver-newline "$WORK" version $'1.2.3\n' --help
  run_case loader-semver-nel "$WORK" version $'1.2.3\xc2\x85' --help
  run_case loader-semver-quote "$WORK" version "1.2.3'" --help
  run_case loader-semver-combining "$WORK" version $'1.\xcc\x81' --help
  run_case loader-semver-pre-non-ascii "$WORK" version $'1.2.3-\xc3\xa9' --help
  run_case loader-semver-empty-segment "$WORK" version 1.2.3-a..b --help

  # Tag docs are printed with `str` Debug: U+0085, a combining mark and a
  # zero-width space are escaped.
  printf '// a\xc2\x85b\xcc\x81c\xe2\x80\x8bd\nfunction f() {}\n' > "$L/work/doc.js"
  run_case loader-tags-doc-escapes "$WORK" tags "$L/work/doc.js"

  # A configuration of parser directories just for these cases.
  printf '{\n  "parser-directories": [\n    "%s"\n  ]\n}\n' "$L/parsers" > "$L/config/config.json"
  local cfg="TREE_SITTER_DIR=$L/config"

  # Grammar paths `g`, `g/.` and `./g//` are one language (dump-languages
  # shows the first one's path); `file-types` use `str` Debug.
  local g="$L/parsers/tree-sitter-paths"
  mkdir -p "$g/g/src"
  cat > "$g/tree-sitter.json" <<'EOF'
{
  "grammars": [
    { "name": "b", "scope": "source.b", "path": "g", "file-types": ["b\u0085x"] },
    { "name": "aa", "scope": "source.aa", "path": "g/." },
    { "name": "c", "scope": "source.c", "path": "./g//" },
    { "name": "d", "scope": "source.d", "path": "../tree-sitter-paths/g" }
  ],
  "metadata": { "version": "0.1.0" }
}
EOF
  # `grammar.json` names come from its first three lines only.
  mkdir -p "$L/parsers/tree-sitter-name-ok/src" "$L/parsers/tree-sitter-name-bad/src"
  printf '{\n  "name": "name_ok",\n  "rules": {},\n\xff\xfe\n}\n' \
    > "$L/parsers/tree-sitter-name-ok/src/grammar.json"
  printf '{\n  "\xff": 1,\n  "name": "name_bad"\n}\n' \
    > "$L/parsers/tree-sitter-name-bad/src/grammar.json"
  # One first-line pattern (with several, upstream's choice depends on its
  # HashMap's random iteration order).
  local fl="$L/parsers/tree-sitter-firstline"
  cp -R "$GRAMMARS/tree-sitter-json" "$fl"
  cat > "$fl/tree-sitter.json" <<'EOF'
{
  "grammars": [
    { "name": "firstline", "scope": "source.firstline", "path": ".", "first-line-regex": "^#!/x" }
  ],
  "metadata": { "version": "0.1.0" }
}
EOF
  run_case loader-dump-languages "$L/work" env "$cfg" -- dump-languages

  # First-line detection reads the first line as strict UTF-8.
  printf '#!/x\n' > "$L/work/match"
  printf '#!/x\xff\n{}\n' > "$L/work/invalid-first-line"
  printf '#!/y\n\xff\n' > "$L/work/invalid-second-line"
  printf '#!/x' > "$L/work/no-newline"
  : > "$L/work/empty"
  for f in match invalid-first-line invalid-second-line no-newline empty; do
    run_case "loader-first-line-$f" "$L/work" env "$cfg" -- parse "$f"
  done

  # Aliases of one language are sorted by Rust string order: fuzz names its
  # tests after the first one (`aa`, not `b`).
  local a="$L/alias"
  cp -R "$GRAMMARS/tree-sitter-json" "$a"
  cat > "$a/tree-sitter.json" <<'EOF'
{
  "grammars": [
    { "name": "b", "scope": "source.b", "path": "." },
    { "name": "aa", "scope": "source.aa", "path": "." }
  ],
  "metadata": { "version": "0.1.0" }
}
EOF
  run_case loader-alias-order-fuzz "$a" env "$cfg" TREE_SITTER_SEED=7 -- \
    fuzz --iterations 1 --edits 1 --include Arrays

  # Without TREE_SITTER_LIBDIR, macOS removes ~/Library/Caches/tree-sitter;
  # a failed removal fails the command. Both CLIs use the same HOME in turn.
  if [ "$(uname)" = Darwin ]; then
    local home="$L/home" which cli
    for which in up mbt; do
      if [ $which = up ]; then cli=$UP; else cli=$MBT; fi
      local out="$L/legacy-$which"
      mkdir -p "$out"
      # Removed.
      rm -rf "$home"
      mkdir -p "$home/Library/Caches/tree-sitter/lib/sub"
      touch "$home/Library/Caches/tree-sitter/lib/x.dylib"
      (cd "$L/work" && env -u TREE_SITTER_LIBDIR -u XDG_CACHE_HOME NO_COLOR=1 \
        HOME="$home" TREE_SITTER_DIR="$L/config" "$cli" complete --shell fish \
        > /dev/null 2> "$out/removed.err"; echo $? > "$out/removed.code")
      ls -A "$home/Library/Caches" > "$out/removed.ls"
      # A symbolic link to a directory passes the `is_dir` check and is
      # removed itself; its target is kept.
      rm -rf "$home"
      mkdir -p "$home/Library/Caches" "$home/target/keep"
      ln -s "$home/target" "$home/Library/Caches/tree-sitter"
      (cd "$L/work" && env -u TREE_SITTER_LIBDIR -u XDG_CACHE_HOME NO_COLOR=1 \
        HOME="$home" TREE_SITTER_DIR="$L/config" "$cli" complete --shell fish \
        > /dev/null 2> "$out/symlink.err"; echo $? > "$out/symlink.code")
      { ls -A "$home/Library/Caches"; ls -A "$home/target"; } > "$out/symlink.ls"
      # Not removable: the error names the legacy directory.
      rm -rf "$home"
      mkdir -p "$home/Library/Caches/tree-sitter"
      touch "$home/Library/Caches/tree-sitter/x"
      chmod 555 "$home/Library/Caches"
      (cd "$L/work" && env -u TREE_SITTER_LIBDIR -u XDG_CACHE_HOME NO_COLOR=1 \
        HOME="$home" TREE_SITTER_DIR="$L/config" "$cli" complete --shell fish \
        > /dev/null 2> "$out/failed.err"; echo $? > "$out/failed.code")
      chmod 755 "$home/Library/Caches"
      ls -A "$home/Library/Caches/tree-sitter" > "$out/failed.ls"
      rm -rf "$home"
    done
    compare_trees loader-legacy-cache "$L/legacy-up" "$L/legacy-mbt" \
      removed.err removed.code removed.ls symlink.err symlink.code symlink.ls \
      failed.err failed.code failed.ls
  fi
}

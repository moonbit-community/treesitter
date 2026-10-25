# Paths and glob patterns of `parse` (crates/cli/src/input.rs with glob
# 0.3.4): directory order, dotfiles and the special `.`/`..` entries,
# recursive wildcards, the trailing-separator "directories only" flag,
# symbolic links, pattern syntax errors, unreadable directories and `!`
# exclusions compared as `Path`s. `parse -q -t` prints one line per selected
# file, so the selected paths and their order are visible.
section_glob() {
  local G="$WORK/glob"
  [ -d "$G" ] && chmod -R u+rwx "$G"
  rm -rf "$G"
  mkdir -p "$G/a/b/c" "$G/a/.hid" "$G/d" "$G/p/locked"
  local f
  for f in a/x.json a/b/y.json a/b/c/z.json a/.hid/h.json a/.dot.json top.json \
    d/Z.json d/_.json d/a.json d/é.json d/B.json d/😀.json d/～.json d/]x.json \
    p/ok.json p/locked/q.json; do
    echo '[1]' > "$G/$f"
  done
  ln -s a/b "$G/lnk"
  ln -s nowhere "$G/dangling"

  run_case glob-recursive "$G" parse -q -t '**/*.json'
  run_case glob-sorted "$G" parse -q -t 'd/*'
  run_case glob-dot-class "$G" parse -q -t 'a/[.]*.json'
  run_case glob-dot-wildcard "$G" parse -q -t 'a/?dot.json' 'a/*/h.json'
  run_case glob-dot-special "$G" parse -q -t 'a/.*'
  run_case glob-dot-special-cwd "$G" parse -q -t '.*'
  run_case glob-dot-nested "$G" parse -q -t 'a/.*/h.json'
  run_case glob-dotdot "$G" parse -q -t 'a/..*/a/x.json'
  run_case glob-class-caret "$G" parse -q -t 'd/[^a]*'
  run_case glob-class-negated "$G" parse -q -t 'd/[!a_]*'
  run_case glob-class-bracket "$G" parse -q -t 'd/[]Z]*'
  run_case glob-class-range "$G" parse -q -t 'd/[～-😀]*' 'd/[A-Z].json'
  run_case glob-recursive-order "$G" parse -q -t 'a/**/*.json'
  run_case glob-recursive-collapse "$G" parse -q -t 'a/**/**/z.json'
  run_case glob-recursive-dirs "$G" parse -q -t 'a/**/'
  run_case glob-recursive-last "$G" parse -q -t 'a/b/**'
  run_case glob-dirs-only "$G" parse -q -t 'a/*.json/'
  run_case glob-dirs-only-star "$G" parse -q -t '*/'
  run_case glob-file-slash "$G" parse -q -t 'a/x.json/'
  run_case glob-file-slash-star "$G" parse -q -t 'a/x.json/*'
  run_case glob-curdir "$G" parse -q -t './a/*.json'
  run_case glob-curdir-star "$G" parse -q -t './*.json'
  run_case glob-inner-curdir "$G" parse -q -t 'a/./*.json'
  run_case glob-double-sep "$G" parse -q -t 'a//*.json'
  run_case glob-symlink "$G" parse -q -t 'lnk/**/*.json'
  run_case glob-symlink-parent "$G" parse -q -t 'lnk/../*.json'
  run_case glob-absolute "$G" parse -q -t "$G/d/[BZ]*"
  run_case glob-no-match "$G" parse -q -t 'zzz*'
  run_case glob-err-bracket "$G" parse -q -t '['
  run_case glob-err-negated-empty "$G" parse -q -t 'a/[!]'
  run_case glob-err-recursive-suffix "$G" parse -q -t 'a/**b.json'
  run_case glob-err-recursive-prefix "$G" parse -q -t 'a/b**'
  run_case glob-err-wildcards "$G" parse -q -t 'a/***'
  run_case glob-err-component "$G" parse -q -t 'a[/]b'
  run_case glob-err-unicode-pos "$G" parse -q -t 'é/😀['
  # Only a leading `!` *component* excludes (`Path::starts_with("!")`):
  # `!d/a.json` is the pattern `!d/a.json`, `!/d/a.json` excludes `d/a.json`.
  run_case glob-exclude-not-component "$G" parse -q -t 'd/*.json' '!d/a.json' '!d/[BZ]*'
  run_case glob-exclude "$G" parse -q -t 'd/*.json' '!/d/a.json' '!/d/[BZ]*'
  run_case glob-exclude-normalized "$G" parse -q -t 'a/./x.json' 'top.json' '!/a/x.json'
  run_case glob-exclude-root-sep "$G" parse -q -t 'a/./x.json' 'top.json' '!/a//x.json/'
  run_case glob-exclude-inner-curdir "$G" parse -q -t 'a/x.json' 'top.json' '!/./a/x.json'
  # `./a/x.json` != `a/x.json` (a leading `.` is a component)
  run_case glob-exclude-curdir "$G" parse -q -t './a/x.json' '!/a/x.json'
  run_case glob-exclude-glob "$G" parse -q -t '**/*.json' '!/d/*' '!/a//*.json' '!//lnk/**/*'
  run_case glob-exclude-first-only "$G" parse -q -t top.json top.json '!/top.json'
  run_case glob-bang-name "$G" parse -q -t top.json '!top.json*'

  chmod 000 "$G/p/locked"
  run_case glob-unreadable "$G" parse -q -t 'p/*/*.json'
  run_case glob-unreadable-recursive "$G" parse -q -t 'p/**/*.json'
  run_case glob-unreadable-literal "$G" parse -q -t 'p/locked/q.json' 'p/*.json'
  run_case glob-unreadable-excluded "$G" parse -q -t 'p/ok.json' '!/p/*/*'
  chmod 755 "$G/p/locked"
}

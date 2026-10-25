# Command-line parsing cases of the clap port: value parsers, the implicit
# argument groups of `#[derive(Args)]` in error usage, and the binary name
# taken from argv[0].
section_clap() {
  # `PathBuf` values must not be empty.
  run_case clap-path-empty-long "$WORK" parse --paths= --help
  run_case clap-path-empty-pos "$WORK" parse "" --help
  run_case clap-path-empty-generate "$WORK" generate ""
  run_case clap-path-empty-short "$WORK" query -p "" q.scm
  # `u32` values go through `i64::from_str` and a range check.
  run_case clap-u32-neg-zero "$WORK" parse --test-number=-0 --help
  run_case clap-u32-plus "$WORK" parse --test-number=+7 --help
  run_case clap-u32-plus-only "$WORK" parse --test-number=+ x
  run_case clap-u32-minus-only "$WORK" parse --test-number=- x
  run_case clap-u32-neg-leading-zeros "$WORK" parse --test-number=-00012 x
  run_case clap-u32-too-small "$WORK" parse --test-number=-99999999999999999999 x
  run_case clap-u32-i64-max "$WORK" parse --test-number=9223372036854775807 x
  run_case clap-u32-i64-overflow "$WORK" parse --test-number=9223372036854775808 x
  run_case clap-u32-overflow-then-invalid "$WORK" parse --test-number=99999999999999999999x x
  run_case clap-u32-invalid-unicode-digit "$WORK" parse --test-number=$'\xd9\xa3' x
  # `u64` and `usize` values use `u64::from_str`.
  run_case clap-u64-neg-zero "$WORK" parse --timeout=-0 x
  run_case clap-u64-plus "$WORK" parse --timeout=+5 --help
  run_case clap-u64-overflow-then-invalid "$WORK" parse --timeout=99999999999999999999x x
  run_case clap-usize-max "$WORK" fuzz --edits=18446744073709551615 --help
  run_case clap-usize-overflow "$WORK" fuzz --iterations=18446744073709551616 x
  # The group of each argument struct appears in the usage of errors.
  run_case clap-group-init "$WORK" init --update=x
  run_case clap-group-generate "$WORK" generate --log=x
  run_case clap-group-build "$WORK" build --wasm=x
  run_case clap-group-parse "$WORK" parse --dot --cst=x
  run_case clap-group-parse-pos "$WORK" parse a.js --quiet=x
  run_case clap-group-test "$WORK" test --open-log --debug=quiet --help
  run_case clap-group-fuzz "$WORK" fuzz --log-graphs=x
  run_case clap-group-query "$WORK" query --captures=x
  run_case clap-group-highlight "$WORK" highlight --html --check=x
  run_case clap-group-tags "$WORK" tags --time=x
  run_case clap-group-playground "$WORK" playground --quiet=x
  # The binary name comes from the file name of argv[0].
  local argv0="$WORK/clap-argv0"
  rm -rf "$argv0"
  mkdir -p "$argv0/up" "$argv0/mbt"
  ln -s "$UP" "$argv0/up/different-name"
  ln -s "$MBT" "$argv0/mbt/different-name"
  local UP="$argv0/up/different-name" MBT="$argv0/mbt/different-name"
  run_case clap-argv0-help "$WORK" --help
  run_case clap-argv0-none "$WORK"
  run_case clap-argv0-sub-help "$WORK" parse -h
  run_case clap-argv0-unknown "$WORK" parse --foo
  run_case clap-argv0-missing "$WORK" query
  run_case clap-argv0-invalid-sub "$WORK" pars
  run_case clap-argv0-group "$WORK" test --open-log --debug=quiet
  run_case clap-argv0-version "$WORK" --version
  run_case clap-argv0-complete "$WORK" complete --shell fish
}

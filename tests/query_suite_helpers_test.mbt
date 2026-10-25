// Helpers for the port of tree-sitter crates/cli/src/tests/query_test.rs
// (query_suite_*_test.mbt): ports of the `helpers/fixtures.rs` functions it
// uses (`get_test_fixture_language`, `get_test_language`, and the
// `generate_parser` wrapper of tests.rs), the `ITERATION_COUNT` and
// `EXAMPLE_FILTER` settings, and the `unindent`/`indoc!` text helpers.

///|
/// `generate_parser` (tests.rs): generate a parser for `grammar.json` text
/// with semantic version 0.0.0 and the default optimizations, returning the
/// grammar name and the generated parser. Upstream returns the `parser.c`
/// text; here the `GeneratedParser` also carries the portable language tables
/// computed from the same tables, which `get_test_language` loads.
fn generate_parser(
  grammar_json : String,
) -> (String, @generate.GeneratedParser) raise {
  let parser = @generate.generate_from_grammar_json(
    grammar_json,
    semantic_version=(0, 0, 0),
  )
  (parser.language.name, parser)
}

///|
/// `get_test_language` (helpers/fixtures.rs): load a generated parser. The
/// `path` names the grammar directory, whose `scanner.c` upstream compiles
/// in; here the external scanner comes from `scanners` by name.
fn get_test_language(
  name : String,
  parser : @generate.GeneratedParser,
  path : String?,
) -> @treesitter.Language {
  ignore(path)
  let raw = parser.language
  if raw.external_token_count > 0 &&
    @scanners.scanner_for(name) is Some(scanner) {
    @treesitter.Language::new(raw, external_scanner=scanner)
  } else {
    @treesitter.Language::new(raw)
  }
}

///|
/// `ITERATION_COUNT` (fuzz.rs): `TREE_SITTER_ITERATIONS`, 10 by default.
fn iteration_count() -> Int32 {
  match @env.get_env_var("TREE_SITTER_ITERATIONS") {
    Some(s) => @string.parse_int(s) catch { _ => 10 }
    None => 10
  }
}

///|
/// `EXAMPLE_FILTER`: `TREE_SITTER_TEST_EXAMPLE_FILTER`.
fn example_filter() -> String? {
  @env.get_env_var("TREE_SITTER_TEST_EXAMPLE_FILTER")
}

///|
/// The number of leading spaces or tabs of `line`, or `None` if it consists
/// only of them (the `unindent` crate's `count_spaces`).
fn unindent_count_spaces(line : StringView) -> Int32? {
  for i in 0..<line.length() {
    let c = line.unsafe_get(i)
    if c != ' ' && c != '\t' {
      return Some(i)
    }
  }
  None
}

///|
/// The `unindent` crate's line splitting: like `str::lines`, splits on `\n`,
/// strips a trailing `\r`, and yields no final empty line after a trailing
/// newline.
fn unindent_lines(s : String) -> Array[StringView] {
  let lines = []
  let mut start = 0
  for i in 0..<s.length() {
    if s.unsafe_get(i) == '\n' {
      let end = if i > start && s.unsafe_get(i - 1) == '\r' { i - 1 } else { i }
      lines.push(s.view(start_offset=start, end_offset=end))
      start = i + 1
    }
  }
  if start < s.length() {
    let end = if s.unsafe_get(s.length() - 1) == '\r' {
      s.length() - 1
    } else {
      s.length()
    }
    lines.push(s.view(start_offset=start, end_offset=end))
  }
  lines
}

///|
/// `unindent::unindent`, which `indoc!` also applies (at compile time):
/// remove the largest common indentation of the lines after the first, and
/// drop the first line when the text starts with a newline.
fn unindent(s : String) -> String {
  let ignore_first_line = s.has_prefix("\n") || s.has_prefix("\r\n")
  let lines = unindent_lines(s)
  let mut spaces : Int32? = None
  for i, line in lines {
    if i == 0 {
      continue
    }
    if unindent_count_spaces(line) is Some(n) {
      spaces = Some(
        match spaces {
          Some(m) if m <= n => m
          _ => n
        },
      )
    }
  }
  let spaces = spaces.unwrap_or(0)
  let result = StringBuilder()
  for i, line in lines {
    if i > 1 || (i == 1 && !ignore_first_line) {
      result.write_char('\n')
    }
    if i == 0 {
      result.write_view(line)
    } else if line.length() > spaces {
      result.write_view(line.view(start_offset=spaces))
    }
  }
  if s.has_suffix("\n") {
    result.write_char('\n')
  }
  result.to_string()
}

///|
/// `indoc!`: the same algorithm as [`unindent`].
fn indoc(s : String) -> String {
  unindent(s)
}

///|
test "unindent" {
  assert_eq(unindent("\n    a\n      b\n    c\n"), "a\n  b\nc\n")
  assert_eq(unindent("x\n  a\n   b"), "x\na\n b")
  assert_eq(unindent("\n  a\n\n  b\n  "), "a\n\nb\n")
}

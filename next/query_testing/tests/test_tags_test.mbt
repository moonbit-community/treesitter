// Port of tree-sitter crates/cli/src/tests/test_tags_test.rs.

///|
async test "tags_test_with_basic_test" {
  guard @fixtures.get_language("python") is Some(language) else { return }
  guard @fixtures.get_tags_config("python") is Some(config) else { return }
  let source = [
    "# hi", "def abc(d):", "    # <- definition.function", "    e = fgh(d)", "    #    ^ reference.call",
    "    return d(e)", "    #      ^ reference.call", "    #        ^ !variable.parameter",
    "",
  ].join("\n")
  let assertions = @query_testing.parse_position_comments(
    @api.Parser::new(),
    language,
    utf8(source),
  )
  assert_eq(assertions, [
    assertion(1, 4, 1, false, "definition.function"),
    assertion(3, 9, 1, false, "reference.call"),
    assertion(5, 11, 1, false, "reference.call"),
    assertion(5, 13, 1, true, "variable.parameter"),
  ])
  let tags_context = @tags.TagsContext::new()
  let tag_positions = @query_testing.get_tag_positions(
    tags_context,
    config,
    utf8(source),
  )
  assert_eq(tag_positions, [
    (point(1, 4), point(1, 7), "definition.function"),
    (point(3, 8), point(3, 11), "reference.call"),
    (point(5, 11), point(5, 12), "reference.call"),
  ])
  // `test_tag` needs a tag at a negative assertion's position, so the whole
  // assertion-based test fails (as upstream's does).
  try @query_testing.test_tag(tags_context, config, utf8(source)) catch {
    e =>
      inspect(
        e,
        content="Failure - row: 5, column: 13, expected tag: 'variable.parameter', actual tag: none.",
      )
  } noraise {
    _ => fail("expected a failure")
  }
}

///|
/// The assertion-based tests of the fixture grammars (`test/highlight` and
/// `test/tags` of the grammars whose scanners are ported). Expected counts and
/// failure messages are those of upstream's `test_highlight`/`test_tag` with
/// the same highlight names (the recognized names of highlight_test.mbt).
async test "fixture grammar assertion tests" {
  let names : Array[String] = [
    "attribute", "boolean", "carriage-return", "comment", "constant", "constant.builtin",
    "constructor", "embedded", "function", "function.builtin", "keyword", "module",
    "number", "operator", "property", "property.builtin", "punctuation", "punctuation.bracket",
    "punctuation.delimiter", "punctuation.special", "string", "string.special", "tag",
    "type", "type.builtin", "variable", "variable.builtin", "variable.parameter",
  ]
  guard @fixtures.get_language_queries_path("python") is Some(queries) else {
    return
  }
  let grammars = queries.strip_suffix("/python/queries").unwrap().to_owned()
  let results = []
  for
    case in [
      ("python", "highlight", "keywords.py"),
      ("python", "highlight", "parameters.py"),
      ("python", "highlight", "pattern_matching.py"),
      ("python", "tags", "main.py"),
      ("ruby", "highlight", "classes.rb"),
      ("ruby", "highlight", "constants.rb"),
      ("ruby", "highlight", "literals.rb"),
      ("ruby", "highlight", "patterns.rb"),
      ("ruby", "highlight", "variables.rb"),
      ("c", "highlight", "keywords.c"),
      ("c", "highlight", "names.c"),
      ("cpp", "highlight", "keywords.cpp"),
      ("cpp", "highlight", "names.cpp"),
      ("java", "highlight", "types.java"),
    ] {
    let (name, kind, file) = case
    guard @fixtures.get_language(name) is Some(_) else { return }
    let source = @fs.read_file("\{grammars}/\{name}/test/\{kind}/\{file}").binary()
    let result = if kind == "highlight" {
      guard @fixtures.get_highlight_config(name, None, names) is Some(config) else {
        return
      }
      @query_testing.test_highlight(
        @highlight.Highlighter::new(),
        config,
        names,
        _ => None,
        source,
      ).to_string() catch {
        e => e.to_string()
      }
    } else {
      guard @fixtures.get_tags_config(name) is Some(config) else { return }
      @query_testing.test_tag(@tags.TagsContext::new(), config, source).to_string() catch {
        e => e.to_string()
      }
    }
    results.push("\{name}/\{kind}/\{file}: \{result}")
  }
  inspect(
    results.join("\n"),
    content=(
      #|python/highlight/keywords.py: 15
      #|python/highlight/parameters.py: 2
      #|python/highlight/pattern_matching.py: 17
      #|python/tags/main.py: 5
      #|ruby/highlight/classes.rb: Failure - row: 0, column: 2, expected highlight 'function.method.builtin', actual highlights: 'function.builtin'
      #|ruby/highlight/constants.rb: Failure - row: 9, column: 7, expected highlight 'function.method', actual highlights: 'function'
      #|ruby/highlight/literals.rb: Failure - row: 8, column: 2, expected highlight 'string.special.symbol', actual highlights: 'string.special'
      #|ruby/highlight/patterns.rb: 10
      #|ruby/highlight/variables.rb: Failure - row: 4, column: 11, expected highlight 'function.method', actual highlights: 'function'
      #|c/highlight/keywords.c: 3
      #|c/highlight/names.c: Failure - row: 29, column: 2, expected highlight 'label', actual highlights: none.
      #|cpp/highlight/keywords.cpp: 13
      #|cpp/highlight/names.cpp: Failure - row: 16, column: 2, expected highlight 'type', actual highlights: none.
      #|java/highlight/types.java: Failure - row: 23, column: 10, expected highlight 'function.method', actual highlights: 'function'
    ),
  )
}

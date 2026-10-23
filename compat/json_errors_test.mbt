// JSON v0.24.8 and Tree-sitter pinned error corpus. See NOTICE.

///|
fn upstream_json_language() -> @language.Language raise {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"json","rules":{"document":{"type":"REPEAT","content":{"type":"SYMBOL","name":"_value"}},"_value":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"object"},{"type":"SYMBOL","name":"array"},{"type":"SYMBOL","name":"number"},{"type":"SYMBOL","name":"string"},{"type":"SYMBOL","name":"true"},{"type":"SYMBOL","name":"false"},{"type":"SYMBOL","name":"null"}]},"object":{"type":"SEQ","members":[{"type":"STRING","value":"{"},{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"SYMBOL","name":"pair"},{"type":"REPEAT","content":{"type":"SEQ","members":[{"type":"STRING","value":","},{"type":"SYMBOL","name":"pair"}]}}]},{"type":"BLANK"}]},{"type":"STRING","value":"}"}]},"pair":{"type":"SEQ","members":[{"type":"FIELD","name":"key","content":{"type":"SYMBOL","name":"string"}},{"type":"STRING","value":":"},{"type":"FIELD","name":"value","content":{"type":"SYMBOL","name":"_value"}}]},"array":{"type":"SEQ","members":[{"type":"STRING","value":"["},{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"SYMBOL","name":"_value"},{"type":"REPEAT","content":{"type":"SEQ","members":[{"type":"STRING","value":","},{"type":"SYMBOL","name":"_value"}]}}]},{"type":"BLANK"}]},{"type":"STRING","value":"]"}]},"string":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"STRING","value":"\""},{"type":"STRING","value":"\""}]},{"type":"SEQ","members":[{"type":"STRING","value":"\""},{"type":"SYMBOL","name":"_string_content"},{"type":"STRING","value":"\""}]}]},"_string_content":{"type":"REPEAT1","content":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"string_content"},{"type":"SYMBOL","name":"escape_sequence"}]}},"string_content":{"type":"IMMEDIATE_TOKEN","content":{"type":"PREC","value":1,"content":{"type":"PATTERN","value":"[^\\\\\"\\n]+"}}},"escape_sequence":{"type":"IMMEDIATE_TOKEN","content":{"type":"SEQ","members":[{"type":"STRING","value":"\\"},{"type":"PATTERN","value":"(\\\"|\\\\|\\/|b|f|n|r|t|u)"}]}},"number":{"type":"TOKEN","content":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"SEQ","members":[{"type":"CHOICE","members":[{"type":"STRING","value":"-"},{"type":"BLANK"}]},{"type":"CHOICE","members":[{"type":"STRING","value":"0"},{"type":"SEQ","members":[{"type":"PATTERN","value":"[1-9]"},{"type":"CHOICE","members":[{"type":"PATTERN","value":"\\d+"},{"type":"BLANK"}]}]}]}]},{"type":"STRING","value":"."},{"type":"CHOICE","members":[{"type":"PATTERN","value":"\\d+"},{"type":"BLANK"}]},{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"CHOICE","members":[{"type":"STRING","value":"e"},{"type":"STRING","value":"E"}]},{"type":"SEQ","members":[{"type":"CHOICE","members":[{"type":"STRING","value":"-"},{"type":"BLANK"}]},{"type":"PATTERN","value":"\\d+"}]}]},{"type":"BLANK"}]}]},{"type":"SEQ","members":[{"type":"SEQ","members":[{"type":"CHOICE","members":[{"type":"STRING","value":"-"},{"type":"BLANK"}]},{"type":"CHOICE","members":[{"type":"STRING","value":"0"},{"type":"SEQ","members":[{"type":"PATTERN","value":"[1-9]"},{"type":"CHOICE","members":[{"type":"PATTERN","value":"\\d+"},{"type":"BLANK"}]}]}]}]},{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"CHOICE","members":[{"type":"STRING","value":"e"},{"type":"STRING","value":"E"}]},{"type":"SEQ","members":[{"type":"CHOICE","members":[{"type":"STRING","value":"-"},{"type":"BLANK"}]},{"type":"PATTERN","value":"\\d+"}]}]},{"type":"BLANK"}]}]}]}},"true":{"type":"STRING","value":"true"},"false":{"type":"STRING","value":"false"},"null":{"type":"STRING","value":"null"},"comment":{"type":"TOKEN","content":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"STRING","value":"//"},{"type":"PATTERN","value":".*"}]},{"type":"SEQ","members":[{"type":"STRING","value":"/*"},{"type":"PATTERN","value":"[^*]*\\*+([^/*][^*]*\\*+)*"},{"type":"STRING","value":"/"}]}]}}},"extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"comment"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":["_value"]}
  @generate.generate(@grammar.Grammar::parse(grammar))
}

///|
test "upstream JSON error corpus" {
  let corpus = "==========================================\ntop-level errors\n==========================================\n\n[}\n\n---\n\n(document\n  (ERROR))\n\n==========================================\nunexpected tokens\n==========================================\n\nbarf\n\n---\n\n(document\n  (ERROR\n    (UNEXPECTED 'b')))\n\n==========================================\nerrors inside arrays\n==========================================\n\n[1, , 2]\n\n---\n\n(document\n  (array\n    (number)\n    (ERROR)\n    (number)))\n\n==========================================\nerrors inside objects\n==========================================\n\n{ \"key1\": 1, oops }\n\n---\n\n(document\n  (object\n    (pair\n      (string\n        (string_content))\n      (number))\n    (ERROR\n      (UNEXPECTED 'o'))))\n\n==========================================\nerrors inside nested objects\n==========================================\n\n{ \"key1\": { \"key2\": 1, 2 }, \"key3\": 3 [ }\n\n---\n\n(document\n  (object\n    (pair\n      (string\n        (string_content))\n      (object\n        (pair\n          (string\n            (string_content))\n          (number))\n        (ERROR\n          (number))))\n    (pair\n      (string\n        (string_content))\n      (number))\n    (ERROR)))\n\n===============================\nincomplete tokens at EOF\n========================\n\nnul\n---\n\n(document\n  (ERROR\n    (UNEXPECTED '\\0')))\n"
  let language = upstream_json_language()
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(result.passed, msg="\{result.name}: \{result.actual}")
  }
}

///|
test "empty recovered root encloses pending errors and reports insertion" {
  let parser = @ts.Parser::new(upstream_json_language())
  let old = parser.parse_string("")
  old.edit({
    start_byte: 0,
    old_end_byte: 0,
    new_end_byte: 1,
    start_point: { row: 0, column: 0, },
    old_end_point: { row: 0, column: 0, },
    new_end_point: { row: 0, column: 1, },
  })
  let next = parser.parse(b"[", old_tree=old)
  let root = next.root_node()
  assert_eq(root.start_byte(), 0)
  assert_eq(root.end_byte(), 1)
  assert_eq(root.to_sexp(), "(document (ERROR))")
  let ranges = old.changed_ranges(next)
  assert_eq(ranges.length(), 1)
  assert_eq((ranges[0].start_byte, ranges[0].end_byte), (0, 1))
}

///|
test "replacement spanning siblings shrinks deleted content after insertion" {
  let parser = @ts.Parser::new(upstream_json_language())
  let old = parser.parse_string("1 2 3")
  old.edit({
    start_byte: 1,
    old_end_byte: 4,
    new_end_byte: 2,
    start_point: { row: 0, column: 1, },
    old_end_point: { row: 0, column: 4, },
    new_end_point: { row: 0, column: 2, },
  })
  assert_eq(
    old.root_node().children().map(n => (n.start_byte(), n.end_byte())),
    [(0, 1), (2, 2), (2, 3)],
  )
  let next = parser.parse(b"113", old_tree=old)
  let ranges = old.changed_ranges(next)
  assert_eq(ranges.length(), 1)
  assert_eq((ranges[0].start_byte, ranges[0].end_byte), (1, 3))
}

///|
test "recovery recognizes immediate tokens before skipped whitespace" {
  // Frozen from the pinned C runtime and JSON grammar.
  let parser = @ts.Parser::new(upstream_json_language())
  assert_eq(
    parser.parse_string("\\").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED '\\0')))",
  )
  assert_eq(
    parser.parse_string("\\2").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED '2')) (number))",
  )
  assert_eq(
    parser.parse_string("[1,\\,3]").root_node().to_sexp(),
    "(document (array (number) (ERROR (UNEXPECTED ',')) (number)))",
  )
  assert_eq(
    parser.parse_string("[\\n]").root_node().to_sexp(),
    "(document (array (ERROR (escape_sequence))))",
  )
  assert_eq(
    parser.parse_string("\\n").root_node().to_sexp(),
    "(document (ERROR (escape_sequence)))",
  )
  assert_eq(
    parser.parse_string("1\\n").root_node().to_sexp(),
    "(document (number) (ERROR (escape_sequence)))",
  )
}

///|
test "recovery immediate tokens remain unavailable after leading whitespace" {
  let parser = @ts.Parser::new(upstream_json_language())
  for source in [" \\n", "1 \\n", "[ \\n]"] {
    let root = parser.parse_string(source).root_node()
    assert_true(root.has_error())
    assert_false(root.to_sexp().contains("(escape_sequence)"))
  }
}

///|
test "error s expressions preserve upstream character and missing-token notation" {
  // Frozen C strings distinguish diagnostic text from JSON escaping.
  let parser = @ts.Parser::new(upstream_json_language())
  assert_eq(
    parser.parse_string(" \\n").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED '\\')))",
  )
  assert_eq(
    parser.parse_string("'").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED ''')))",
  )
  assert_eq(
    parser.parse_string("é").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED 233)))",
  )
  assert_eq(
    parser.parse_string("😀").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED 128512)))",
  )
  assert_eq(
    parser.parse_string("\u{0001}").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED 1)))",
  )
  assert_eq(
    parser.parse_string("").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED 127)))",
  )
  assert_eq(
    parser.parse_string("\"x").root_node().to_sexp(),
    "(document (string (string_content) (MISSING \"\"\")))",
  )
  assert_eq(
    parser.parse_string("[1,\"").root_node().to_sexp(),
    "(document (ERROR (number)))",
  )
}

///|
test "error lexing restarts after partial tokens and separators" {
  // Frozen from the C error lexer, including immediate tokens after a retry.
  let parser = @ts.Parser::new(upstream_json_language())
  assert_eq(
    parser.parse_string("@\\n").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED '@') (escape_sequence)))",
  )
  assert_eq(
    parser.parse_string("@ \\n").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED '@') (escape_sequence)))",
  )
  assert_eq(
    parser.parse_string("\\x\\n").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED 'x') (escape_sequence)))",
  )
  assert_eq(
    parser.parse_string("[ @\\n ]").root_node().to_sexp(),
    "(document (array (ERROR (UNEXPECTED '@') (escape_sequence))))",
  )
  assert_eq(
    parser.parse_string("@ tru").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED '@')))",
  )
  assert_eq(
    parser.parse_string("@ 1").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED '@')) (number))",
  )
  assert_eq(
    parser.parse_string("@   ").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED '@')))",
  )
  assert_eq(
    parser.parse_string("@fa 1").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED '@')) (number))",
  )
  assert_eq(
    parser.parse_string("@\\x1").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED '@')) (number))",
  )
}

///|
test "invalid UTF8 diagnostics differ from a valid replacement character" {
  // Frozen C diagnostics; malformed sequences continue to advance by bytes.
  let parser = @ts.Parser::new(upstream_json_language())
  let malformed : Array[Bytes] = [
    [0xff],
    [0xc2],
    [0xf0, 0x9f],
    [0xed, 0xa0, 0x80],
    [0xc0, 0x80],
    [0xf4, 0x90, 0x80, 0x80],
    [0x5c, 0xff],
  ]
  for input in malformed {
    let root = parser.parse(input).root_node()
    assert_eq(root.to_sexp(), "(document (ERROR (UNEXPECTED INVALID)))")
    assert_eq(root.end_byte(), input.length())
  }
  assert_eq(
    parser.parse([0xef, 0xbf, 0xbd]).root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED 65533)))",
  )
  assert_eq(
    parser.parse([0x40, 0xff]).root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED '@')))",
  )
}

///|
test "comments remain outside recovered errors and inside continued errors" {
  // Frozen from the pinned C runtime.
  let parser = @ts.Parser::new(upstream_json_language())
  assert_eq(
    parser.parse_string("@/*x*/1").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED '@')) (comment) (number))",
  )
  assert_eq(
    parser.parse_string("@/*x*/").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED '@')) (comment))",
  )
  assert_eq(
    parser.parse_string("@/*x*/@").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED '@') (comment) (UNEXPECTED '@')))",
  )
  assert_eq(
    parser.parse_string("@/*x*/\\n").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED '@') (comment) (escape_sequence)))",
  )
  assert_eq(
    parser.parse_string("@/*x*/ @").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED '@') (comment) (UNEXPECTED '@')))",
  )
  assert_eq(
    parser.parse_string("[ @/*x*/ 1]").root_node().to_sexp(),
    "(document (array (ERROR (UNEXPECTED '@')) (comment) (number)))",
  )
  assert_eq(
    parser.parse_string("@/*x*/true").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED '@')) (comment) (true))",
  )
  assert_eq(
    parser.parse_string("@//hi\n@").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED '@') (comment) (UNEXPECTED '@')))",
  )
  assert_eq(
    parser.parse_string("@/*x*/\\n/*y*/@").root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED '@') (comment) (escape_sequence) (comment) (UNEXPECTED '@')))",
  )
}

///|
test "missing candidates reduce before competing recovery and precede padding" {
  // Frozen C trees and ranges, including missing punctuation before whitespace.
  let parser = @ts.Parser::new(upstream_json_language())
  for
    (source, expected, missing_at) in [
      (
        "1 2 {3", "(document (number) (number) (object (MISSING \"}\")) (number))",
        5,
      ),
      (
        "1{ 2 3", "(document (number) (object (MISSING \"}\")) (number) (number))",
        2,
      ),
      ("[1  ", "(document (array (number) (MISSING \"]\")))", 2),
      ("[1 /*x*/  ", "(document (array (number) (comment) (MISSING \"]\")))", 8),
      (
        "1 { /*x*/ 2", "(document (number) (object (comment) (MISSING \"}\")) (number))",
        9,
      ),
    ] {
    let root = parser.parse_string(source).root_node()
    assert_eq(root.to_sexp(), expected)
    let cursor = root.walk()
    let mut found = false
    for i in 0..<root.descendant_count() {
      assert_true(cursor.goto_descendant(i))
      let node = cursor.node()
      if node.is_missing() {
        found = true
        assert_eq(
          (node.start_byte(), node.end_byte()),
          (missing_at, missing_at),
        )
        assert_eq(node.start_position(), { row: 0, column: missing_at, })
      }
    }
    assert_true(found)
  }
  // With no existing prefix, the cheaper error path remains available.
  assert_eq(
    parser.parse_string("{3").root_node().to_sexp(),
    "(document (ERROR) (number))",
  )
  let old = parser.parse_string("1 2 3")
  old.edit({
    start_byte: 1,
    old_end_byte: 1,
    new_end_byte: 2,
    start_point: { row: 0, column: 1, },
    old_end_point: { row: 0, column: 1, },
    new_end_point: { row: 0, column: 2, },
  })
  let next = parser.parse(b"1{ 2 3", old_tree=old)
  assert_eq(old.changed_ranges(next).map(r => (r.start_byte, r.end_byte)), [
    (1, 2),
  ])
}

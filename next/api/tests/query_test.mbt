// Port of tree-sitter crates/cli/src/tests/query_test.rs. Query
// construction only needs a language's tables, so error tests use the
// upstream languages directly; tests that parse use grammars without
// external scanners (C, JSON, Java) or are adapted to them.

///|
async test "query_errors_on_invalid_syntax" {
  guard get_language("javascript") is Some(language) else { return }
  guard get_language("c") is Some(c) else { return }
  guard get_language("python") is Some(python) else { return }
  ignore(@api.Query::new(language, "(if_statement)"))
  ignore(
    @api.Query::new(
      language, "(if_statement condition:(parenthesized_expression (identifier)))",
    ),
  )
  let message = (l, s) => query_error(l, s).message()
  // Mismatched parens
  assert_eq(message(language, "(if_statement"), "(if_statement\n             ^")
  assert_eq(
    message(language, "; comment 1\n; comment 2\n  (if_statement))"),
    "  (if_statement))\n                ^",
  )
  // Return an error at the *beginning* of a bare identifier not followed a
  // colon. If there's a colon but no pattern, return an error at the end of
  // the colon.
  assert_eq(
    message(language, "(if_statement identifier)"),
    "(if_statement identifier)\n              ^",
  )
  assert_eq(
    message(language, "(if_statement condition:)"),
    "(if_statement condition:)\n                        ^",
  )
  // Return an error at the beginning of an unterminated string.
  assert_eq(
    message(language, "(identifier) \"h "),
    "(identifier) \"h \n             ^",
  )
  // Empty tree pattern
  assert_eq(
    message(language, "((identifier) ()"),
    "((identifier) ()\n               ^",
  )
  // Empty alternation
  assert_eq(
    message(language, "((identifier) [])"),
    "((identifier) [])\n               ^",
  )
  // Unclosed sibling expression with predicate
  assert_eq(
    message(language, "((identifier) (#a?)"),
    "((identifier) (#a?)\n                   ^",
  )
  // Predicate not ending in `?` or `!`
  assert_eq(
    message(language, "((identifier) (#a))"),
    "((identifier) (#a))\n                 ^",
  )
  // Unclosed predicate
  assert_eq(
    message(language, "((identifier) @x (#eq? @x a"),
    "((identifier) @x (#eq? @x a\n                           ^",
  )
  // Need at least one child node for a child anchor
  assert_eq(
    message(language, "(statement_block .)"),
    "(statement_block .)\n                  ^",
  )
  // Need a field name after a negated field operator
  assert_eq(
    message(language, "(statement_block ! (if_statement))"),
    "(statement_block ! (if_statement))\n                   ^",
  )
  // Unclosed alternation within a tree
  assert_eq(
    message(c, "(parameter_list [ \")\" @foo)"),
    "(parameter_list [ \")\" @foo)\n                          ^",
  )
  // Unclosed tree within an alternation
  assert_eq(
    message(
      python, "[(unary_operator (_) @operand) (not_operator (_) @operand]",
    ),
    "[(unary_operator (_) @operand) (not_operator (_) @operand]\n                                                         ^",
  )
  // MISSING keyword with full pattern
  assert_eq(
    message(c, "(MISSING (function_declarator (identifier))) "),
    "(MISSING (function_declarator (identifier))) \n         ^",
  )
  // MISSING keyword with multiple identifiers
  assert_eq(
    message(c, "(MISSING function_declarator function_declarator) "),
    "(MISSING function_declarator function_declarator) \n                             ^",
  )
  assert_eq(
    error_parts(query_error(language, "(statement / export_statement)")),
    (Syntax, 0, 11, 11, "(statement / export_statement)\n           ^"),
  )
}

///|
async test "query_rejects_excessive_pattern_depth" {
  guard get_language("basic_cst") is Some(language) else { return }
  let nesting = 300
  let source = "(_ ".repeat(nesting) + "_" + ")".repeat(nesting)
  assert_eq(query_error(language, source).kind(), Structure)
}

///|
async test "query_errors_on_anchor_at_group_edge" {
  guard get_language("javascript") is Some(language) else { return }
  // Anchors between siblings, or at the first/last position of a *node*
  // pattern, are valid.
  ignore(@api.Query::new(language, "((_) . (_))"))
  ignore(@api.Query::new(language, "(program (_) (_) .)"))
  ignore(@api.Query::new(language, "(program (_)* @x . (_))"))
  // A `.` at the edge of a *group* is rejected.
  assert_eq(
    error_parts(query_error(language, "((_) .)")),
    (Syntax, 0, 5, 5, "((_) .)\n     ^"),
  )
  assert_eq(
    error_parts(query_error(language, "(program ((_)+ .)? (_))")),
    (Syntax, 0, 15, 15, "(program ((_)+ .)? (_))\n               ^"),
  )
}

///|
async test "query_errors_on_invalid_symbols" {
  guard get_language("javascript") is Some(language) else { return }
  let parts = s => error_parts(query_error(language, s))
  assert_eq(parts("\">>>>\""), (NodeType, 0, 1, 1, "\">>>>\""))
  assert_eq(parts("\"te\\\"st\""), (NodeType, 0, 1, 1, "\"te\\\"st\""))
  assert_eq(parts("\"\\\\\" @cap"), (NodeType, 0, 1, 1, "\"\\\\\""))
  assert_eq(parts("(clas)"), (NodeType, 0, 1, 1, "\"clas\""))
  assert_eq(
    parts("(if_statement (arrayyyyy))"),
    (NodeType, 0, 15, 15, "\"arrayyyyy\""),
  )
  assert_eq(
    parts("(if_statement condition: (non_existent3))"),
    (NodeType, 0, 26, 26, "\"non_existent3\""),
  )
  assert_eq(
    parts("(if_statement condit: (identifier))"),
    (Field, 0, 14, 14, "\"condit\""),
  )
  assert_eq(
    parts("(if_statement conditioning: (identifier))"),
    (Field, 0, 14, 14, "\"conditioning\""),
  )
  assert_eq(
    parts("(if_statement !alternativ)"),
    (Field, 0, 15, 15, "\"alternativ\""),
  )
  assert_eq(
    parts("(if_statement !alternatives)"),
    (Field, 0, 15, 15, "\"alternatives\""),
  )
  assert_eq(parts("fakefield: (identifier)"), (Field, 0, 0, 0, "\"fakefield\""))
  assert_eq(parts("(ERR)"), (NodeType, 0, 1, 1, "\"ERR\""))
  assert_eq(parts("(MISS)"), (NodeType, 0, 1, 1, "\"MISS\""))
  // test_query_error_does_not_oob
  assert_eq(parts("(clas"), (NodeType, 0, 1, 1, "\"clas\""))
  // Names are scanned by Unicode alphanumerics.
  assert_eq(
    parts("(héllo_wörld-x y)"),
    (NodeType, 0, 1, 1, "\"héllo_wörld-x\""),
  )
}

///|
async test "query_errors_on_invalid_predicates" {
  guard get_language("javascript") is Some(language) else { return }
  let parts = s => error_parts(query_error(language, s))
  assert_eq(
    parts("((identifier) @id (@id))"),
    (Syntax, 0, 19, 19, "((identifier) @id (@id))\n                   ^"),
  )
  assert_eq(
    parts("((identifier) @id (#eq? @id))"),
    (
      Predicate,
      0,
      0,
      0,
      "Wrong number of arguments to #eq? predicate. Expected 2, got 1.",
    ),
  )
  assert_eq(
    parts("((identifier) @id (#eq? @id @ok))"),
    (Capture, 0, 29, 29, "\"ok\""),
  )
}

///|
/// Every validation error of lib.rs's `Query::from_raw_parts` and
/// `Query::parse_property`, with the row of the failing pattern.
async test "query predicate validation errors" {
  guard get_language("javascript") is Some(language) else { return }
  let predicate = (s : String) => {
    let e = query_error(language, "\n(identifier) @a\n((identifier) @id \{s})")
    assert_eq(e.kind(), Predicate)
    assert_eq((e.row(), e.column(), e.offset()), (2, 0, 0))
    e.to_string()
  }
  inspect(
    predicate("(#eq? @id)"),
    content="Query error at 3:1. Invalid predicate: Wrong number of arguments to #eq? predicate. Expected 2, got 1.",
  )
  inspect(
    predicate("(#not-eq? @id a b)"),
    content="Query error at 3:1. Invalid predicate: Wrong number of arguments to #eq? predicate. Expected 2, got 3.",
  )
  inspect(
    predicate("(#any-eq? \"a\" @id)"),
    content="Query error at 3:1. Invalid predicate: First argument to #eq? predicate must be a capture name. Got literal \"a\".",
  )
  inspect(
    predicate("(#match? @id)"),
    content="Query error at 3:1. Invalid predicate: Wrong number of arguments to #match? predicate. Expected 2, got 1.",
  )
  inspect(
    predicate("(#not-match? \"a\" \"b\")"),
    content="Query error at 3:1. Invalid predicate: First argument to #match? predicate must be a capture name. Got literal \"a\".",
  )
  inspect(
    predicate("(#any-match? @id @id)"),
    content="Query error at 3:1. Invalid predicate: Second argument to #match? predicate must be a literal. Got capture @id.",
  )
  inspect(
    predicate("(#match? @id \"(\")"),
    content="Query error at 3:1. Invalid predicate: Invalid regex '('",
  )
  inspect(
    predicate("(#match? @id \"\\\\w{500}\")"),
    content="Query error at 3:1. Invalid predicate: Invalid regex '\\w{500}'",
  )
  inspect(
    predicate("(#any-of?)"),
    content="Query error at 3:1. Invalid predicate: Wrong number of arguments to #any-of? predicate. Expected at least 1, got 0.",
  )
  inspect(
    predicate("(#not-any-of? \"a\" \"b\")"),
    content="Query error at 3:1. Invalid predicate: First argument to #any-of? predicate must be a capture name. Got literal \"a\".",
  )
  inspect(
    predicate("(#any-of? @id \"a\" @a)"),
    content="Query error at 3:1. Invalid predicate: Arguments to #any-of? predicate must be literals. Got capture @a.",
  )
  inspect(
    predicate("(#set!)"),
    content="Query error at 3:1. Invalid predicate: Wrong number of arguments to set! predicate. Expected 1 to 3, got 0.",
  )
  inspect(
    predicate("(#is? a b c d)"),
    content="Query error at 3:1. Invalid predicate: Wrong number of arguments to is? predicate. Expected 1 to 3, got 4.",
  )
  inspect(
    predicate("(#set! @id @a)"),
    content="Query error at 3:1. Invalid predicate: Invalid arguments to set! predicate. Unexpected second capture name @a",
  )
  inspect(
    predicate("(#is-not? a b c)"),
    content="Query error at 3:1. Invalid predicate: Invalid arguments to is-not? predicate. Unexpected third argument @c",
  )
  inspect(
    predicate("(#set! @id)"),
    content="Query error at 3:1. Invalid predicate: Invalid arguments to set! predicate. Missing key argument",
  )
}

///|
async test "query error Display" {
  guard get_language("javascript") is Some(language) else { return }
  inspect(
    query_error(language, "\n  (if_statement"),
    content=(
      #|Query error at 2:16. Invalid syntax:
      #|  (if_statement
      #|               ^
    ),
  )
  inspect(
    query_error(language, "(clas)"),
    content="Query error at 1:2. Invalid node type \"clas\"",
  )
  inspect(
    query_error(language, "(if_statement condit: (identifier))"),
    content="Query error at 1:15. Invalid field name \"condit\"",
  )
  inspect(
    query_error(language, "((identifier) @id (#eq? @id @ok))"),
    content="Query error at 1:30. Invalid capture name \"ok\"",
  )
  inspect(
    query_error(language, "(identifier (identifier))"),
    content=(
      #|Query error at 1:13. Impossible pattern:
      #|(identifier (identifier))
      #|            ^
    ),
  )
  // An error at the end of the source.
  assert_eq(
    error_parts(query_error(language, "(identifier)\n(")),
    (Syntax, 1, 1, 14, "(\n ^"),
  )
  assert_eq(
    error_parts(query_error(language, "(identifier)\n(\n")),
    (Syntax, 2, 0, 15, "Unexpected EOF"),
  )
  // A language with an unsupported ABI version.
  let old = @api.Language::new({ ..language.raw(), abi_version: 12, })
  let e = query_error(old, "(identifier)")
  assert_eq(e.kind(), Language)
  inspect(
    e,
    content="Incompatible language version 12. Expected minimum 13, maximum 15",
  )
}

///|
async test "query_errors_on_impossible_patterns" {
  guard get_language("javascript") is Some(js_lang) else { return }
  guard get_language("ruby") is Some(rb_lang) else { return }
  let parts = (l, s) => error_parts(query_error(l, s))
  assert_eq(
    parts(
      js_lang, "(binary_expression left: (expression (identifier)) left: (expression (identifier)))",
    ),
    (
      Structure,
      0,
      37,
      37,
      "(binary_expression left: (expression (identifier)) left: (expression (identifier)))\n                                     ^",
    ),
  )
  ignore(
    @api.Query::new(
      js_lang, "(function_declaration name: (identifier) (statement_block))",
    ),
  )
  assert_eq(
    parts(js_lang, "(function_declaration name: (statement_block))"),
    (
      Structure,
      0,
      22,
      22,
      "(function_declaration name: (statement_block))\n                      ^",
    ),
  )
  ignore(@api.Query::new(rb_lang, "(call receiver:(call))"))
  assert_eq(
    parts(rb_lang, "(call receiver:(binary))"),
    (Structure, 0, 6, 6, "(call receiver:(binary))\n      ^"),
  )
  assert_eq(
    parts(
      js_lang,
      (
        #|[
        #|                    (function_expression (identifier))
        #|                    (function_declaration (object))
        #|                    (generator_function_declaration (identifier))
        #|                ]
      ),
    ),
    (
      Structure,
      2,
      42,
      99,
      "                    (function_declaration (object))\n                                          ^",
    ),
  )
  assert_eq(
    parts(js_lang, "(identifier (identifier))"),
    (Structure, 0, 12, 12, "(identifier (identifier))\n            ^"),
  )
  assert_eq(
    parts(js_lang, "(true (true))"),
    (Structure, 0, 6, 6, "(true (true))\n      ^"),
  )
  assert_eq(
    parts(js_lang, "(if_statement condition: (expression))"),
    (
      Structure,
      0,
      14,
      14,
      "(if_statement condition: (expression))\n              ^",
    ),
  )
  assert_eq(
    parts(js_lang, "(identifier/identifier)"),
    (Structure, 0, 0, 0, "(identifier/identifier)\n^"),
  )
  if js_lang.abi_version() >= 15 {
    assert_eq(
      parts(js_lang, "(statement/identifier)"),
      (Structure, 0, 0, 0, "(statement/identifier)\n^"),
    )
  }
}

///|
async test "query_matches_with_alternations_and_predicates" {
  guard get_parsing_language("java") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|(block
      #|    [
      #|        (local_variable_declaration
      #|            (variable_declarator
      #|                (identifier) @def.a
      #|                (string_literal) @lit.a))
      #|        (local_variable_declaration
      #|            (variable_declarator
      #|                (identifier) @def.b
      #|                (null_literal) @lit.b))
      #|    ]
      #|    (expression_statement
      #|        (method_invocation [
      #|            (argument_list
      #|                (identifier) @ref.a
      #|                (string_literal))
      #|            (argument_list
      #|                (null_literal)
      #|                (identifier) @ref.b)
      #|        ]))
      #|    (#eq? @def.a @ref.a )
      #|    (#eq? @def.b @ref.b ))
    ),
  )
  assert_query_matches(
    language,
    query,
    (
      #|void test() {
      #|    int a = "foo";
      #|    f(null, b);
      #|}
    ),
    [],
  )
}

///|
async test "query_matches_with_indefinite_step_containing_no_captures" {
  guard get_parsing_language("c") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|(struct_specifier
      #|    name: (type_identifier) @name
      #|    body: (field_declaration_list
      #|        (field_declaration
      #|            type: (union_specifier))))
    ),
  )
  assert_query_matches(
    language,
    query,
    (
      #|struct LacksUnionField {
      #|    int a;
      #|    struct {
      #|        B c;
      #|    } d;
      #|    G *h;
      #|};
      #|
      #|struct HasUnionField {
      #|    int a;
      #|    struct {
      #|        B c;
      #|    } d;
      #|    union {
      #|        bool e;
      #|        float f;
      #|    } g;
      #|    G *h;
      #|};
    ),
    [(0, [("name", "HasUnionField")])],
  )
}

///|
/// `query_captures_with_text_conditions`, adapted to the C grammar.
async test "query_captures_with_text_conditions (c)" {
  guard get_parsing_language("c") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|((identifier) @constant
      #| (#match? @constant "^[A-Z]{2,}$"))
      #|
      #| ((identifier) @constructor
      #|  (#match? @constructor "^[A-Z]"))
      #|
      #|((identifier) @function.builtin
      #| (#eq? @function.builtin "require"))
      #|
      #|((identifier) @variable.builtin
      #|  (#any-of? @variable.builtin
      #|            "arguments"
      #|            "module"
      #|            "console"
      #|            "window"
      #|            "document"))
      #|
      #|((identifier) @variable
      #| (#not-match? @variable "^(lambda|load)$"))
    ),
  )
  let source =
    #|toad;
    #|load;
    #|panda;
    #|lambda;
    #|ab = require(ab);
    #|Cd(EF);
    #|document;
    #|module;
    #|console;
  let tree = parse(parser_for(language), source)
  let cursor = @api.QueryCursor::new()
  let captures = cursor.captures(query, tree.root_node(), utf8(source))
  assert_eq(collect_captures(captures, query, source), [
    ("variable", "toad"),
    ("variable", "panda"),
    ("variable", "ab"),
    ("function.builtin", "require"),
    ("variable", "require"),
    ("variable", "ab"),
    ("constructor", "Cd"),
    ("variable", "Cd"),
    ("constant", "EF"),
    ("constructor", "EF"),
    ("variable", "EF"),
    ("variable.builtin", "document"),
    ("variable", "document"),
    ("variable.builtin", "module"),
    ("variable", "module"),
    ("variable.builtin", "console"),
    ("variable", "console"),
  ])
}

///|
async test "query_captures_with_predicates" {
  guard get_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|((call_expression (identifier) @foo)
      #| (#set! name something)
      #| (#set! cool)
      #| (#something! @foo omg))
      #|
      #|((property_identifier) @bar
      #| (#is? cool)
      #| (#is-not? name something))
    ),
  )
  assert_eq(query.property_settings(0).to_owned(), [
    @api.QueryProperty::new("name", Some("something"), None),
    @api.QueryProperty::new("cool", None, None),
  ])
  assert_eq(query.general_predicates(0).to_owned(), [
    { operator: "something!", args: [Capture(0), String("omg")], },
  ])
  assert_eq(query.property_settings(1).to_owned(), [])
  assert_eq(query.property_predicates(0).to_owned(), [])
  assert_eq(query.property_predicates(1).to_owned(), [
    (@api.QueryProperty::new("cool", None, None), true),
    (@api.QueryProperty::new("name", Some("something"), None), false),
  ])
  // The matching half of the test, on the C grammar.
  guard get_parsing_language("c") is Some(c) else { return }
  let source = "a = window.b;"
  let tree = parse(parser_for(c), source)
  let query = @api.Query::new(
    c,
    (
      #|((identifier) @variable.builtin
      #|  (#match? @variable.builtin "^(arguments|module|console|window|document)$")
      #|  (#is-not? local))
    ),
  )
  let cursor = @api.QueryCursor::new()
  let matches = cursor.matches(query, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query, source), [
    (0, [("variable.builtin", "window")]),
  ])
  assert_eq(query.property_predicates(0).to_owned(), [
    (@api.QueryProperty::new("local", None, None), false),
  ])
}

///|
async test "query_captures_with_quoted_predicate_args" {
  guard get_language("javascript") is Some(language) else { return }
  // Double-quoted strings can contain special escape sequences like \n and
  // \r, escaped double quotes and literal backslashes.
  let query = @api.Query::new(
    language,
    (
      #|((call_expression (identifier) @foo)
      #| (#set! one "\"something\ngreat\""))
      #|
      #|((identifier)
      #| (#set! two "\\s(\r?\n)*$"))
      #|
      #|((function_declaration)
      #| (#set! three "\"something\ngreat\""))
    ),
  )
  assert_eq(query.property_settings(0).to_owned(), [
    @api.QueryProperty::new("one", Some("\"something\ngreat\""), None),
  ])
  assert_eq(query.property_settings(1).to_owned(), [
    @api.QueryProperty::new("two", Some("\\s(\r?\n)*$"), None),
  ])
  assert_eq(query.property_settings(2).to_owned(), [
    @api.QueryProperty::new("three", Some("\"something\ngreat\""), None),
  ])
}

///|
/// `query_captures_with_matches_removed`, adapted to the C grammar.
async test "query_captures_with_matches_removed (c)" {
  guard get_parsing_language("c") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|(binary_expression
      #|    left: (identifier) @left
      #|    operator: _ @op
      #|    right: (identifier) @right)
    ),
  )
  let source = "a == b && c > d && e < f;"
  let bytes = utf8(source)
  let tree = parse(parser_for(language), source)
  let cursor = @api.QueryCursor::new()
  let captured_strings = []
  let captures = cursor.captures(query, tree.root_node(), bytes)
  while captures.next() is Some((m, i)) {
    let capture = m.captures()[i]
    let t = text(capture.node, bytes)
    if t == "a" {
      m.remove()
      continue
    }
    captured_strings.push(t)
  }
  assert_eq(captured_strings, ["c", ">", "d", "e", "<", "f"])
}

///|
async test "query_captures_and_matches_iterators_are_fused" {
  guard get_parsing_language("c") is Some(language) else { return }
  let query = @api.Query::new(language, "(comment) @comment")
  let source = "// one\n// two\n// three\n/* unfinished\n"
  let tree = parse(parser_for(language), source)
  let cursor = @api.QueryCursor::new()
  let captures = cursor.captures(query, tree.root_node(), utf8(source))
  assert_eq(captures.next().unwrap().0.captures()[0].index, 0)
  assert_eq(captures.next().unwrap().0.captures()[0].index, 0)
  assert_eq(captures.next().unwrap().0.captures()[0].index, 0)
  assert_true(captures.next() is None)
  assert_true(captures.next() is None)
  let matches = cursor.matches(query, tree.root_node(), utf8(source))
  assert_eq(matches.next().unwrap().captures()[0].index, 0)
  assert_eq(matches.next().unwrap().captures()[0].index, 0)
  assert_eq(matches.next().unwrap().captures()[0].index, 0)
  assert_true(matches.next() is None)
  assert_true(matches.next() is None)
}

///|
/// `query_text_callback_returns_chunks`, on the C grammar (the source is a
/// valid C expression statement).
async test "query_text_callback_returns_chunks (c)" {
  guard get_parsing_language("c") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|((identifier) @leading_upper
      #| (#match? @leading_upper "^[A-Z][A-Z_]*[a-z]"))
      #|((identifier) @all_upper
      #| (#match? @all_upper "^[A-Z][A-Z_]*$"))
      #|((identifier) @all_lower
      #| (#match? @all_lower "^[a-z][a-z_]*$"))
    ),
  )
  let source = "SOMETHING[a] = transform(AnotherThing[b].property[c], PARAMETER);"
  let bytes = utf8(source)
  // Store the source code in chunks of 3 bytes, and expose it via an
  // iterator API.
  let source_chunks = []
  for i = 0; i < bytes.length(); i = i + 3 {
    source_chunks.push(bytes[i:(i + 3).min(bytes.length())])
  }
  let chunks_in_range = (start : Int32, end : Int32) => {
    let mut offset = 0
    source_chunks
    .iter()
    .filter_map(chunk => {
      let end_offset = offset + chunk.length()
      let result = if offset < end && start < end_offset {
        let end_in_chunk = (end - offset).min(chunk.length())
        let start_in_chunk = start.max(offset) - offset
        Some(chunk[start_in_chunk:end_in_chunk])
      } else {
        None
      }
      offset = end_offset
      result
    })
  }
  let collect_text = (start, end) => {
    let b = Buffer()
    for c in chunks_in_range(start, end) {
      b.write_bytesview(c)
    }
    @utf8.decode_lossy(b.to_bytes())
  }
  assert_eq(collect_text(0, 9), "SOMETHING")
  assert_eq(collect_text(15, 24), "transform")
  let tree = parse(parser_for(language), source)
  let cursor = @api.QueryCursor::new()
  let captures = cursor.captures(
    query,
    tree.root_node(),
    @api.TextCallback::new(node => {
      chunks_in_range(node.start_byte(), node.end_byte())
    }),
  )
  assert_eq(collect_captures(captures, query, source), [
    ("all_upper", "SOMETHING"),
    ("all_lower", "a"),
    ("all_lower", "transform"),
    ("leading_upper", "AnotherThing"),
    ("all_lower", "b"),
    ("all_lower", "c"),
    ("all_upper", "PARAMETER"),
  ])
}

///|
async test "query_start_end_byte_for_pattern" {
  guard get_language("javascript") is Some(language) else { return }
  let patterns_1 =
    #|"+" @operator
    #|"-" @operator
    #|"*" @operator
    #|"=" @operator
    #|"=>" @operator
    #|
  let patterns_2 =
    #|(identifier) @a
    #|(string) @b
    #|
  let patterns_3 =
    #|((identifier) @b (#match? @b i))
    #|(function_declaration name: (identifier) @c)
    #|(method_definition name: (property_identifier) @d)
    #|
  let query = @api.Query::new(language, patterns_1 + patterns_2 + patterns_3)
  assert_eq(query.start_byte_for_pattern(0), 0)
  assert_eq(query.end_byte_for_pattern(0), "\"+\" @operator\n".length())
  assert_eq(query.start_byte_for_pattern(5), patterns_1.length())
  assert_eq(
    query.end_byte_for_pattern(5),
    patterns_1.length() + "(identifier) @a\n".length(),
  )
  assert_eq(
    query.start_byte_for_pattern(7),
    patterns_1.length() + patterns_2.length(),
  )
  assert_eq(
    query.end_byte_for_pattern(7),
    patterns_1.length() +
    patterns_2.length() +
    "((identifier) @b (#match? @b i))\n".length(),
  )
}

///|
async test "query_capture_names" {
  guard get_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|(if_statement
      #|  condition: (parenthesized_expression (binary_expression
      #|    left: _ @left-operand
      #|    operator: "||"
      #|    right: _ @right-operand))
      #|  consequence: (statement_block) @body)
      #|
      #|(while_statement
      #|  condition: _ @loop-condition)
    ),
  )
  assert_eq(query.capture_names().to_owned(), [
    "left-operand", "right-operand", "body", "loop-condition",
  ])
  assert_eq(query.capture_index_for_name("body"), Some(2))
  assert_eq(query.capture_index_for_name("nope"), None)
  assert_eq(query.capture_quantifiers(0).to_owned(), [One, One, One, Zero])
  assert_eq(query.capture_quantifiers(1).to_owned(), [Zero, Zero, Zero, One])
  assert_eq(query.pattern_count(), 2)
  assert_true(query.is_pattern_rooted(0))
  assert_false(query.is_pattern_non_local(0))
}

///|
async test "query_with_no_patterns" {
  guard get_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(language, "")
  assert_eq(query.capture_names().length(), 0)
  assert_eq(query.pattern_count(), 0)
}

///|
/// `query_disable_pattern` and `query_deep_clone`, adapted to the C grammar.
async test "query_disable_pattern and deep_clone (c)" {
  guard get_parsing_language("c") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|(struct_specifier
      #|    name: (type_identifier) @name)
      #|(struct_specifier
      #|    body: (field_declaration_list) @body)
      #|(enum_specifier
      #|    name: (type_identifier) @name)
      #|(enum_specifier
      #|    body: (enumerator_list) @body)
    ),
  )
  let source = "enum A { B }; struct C { int d; };"
  let tree = parse(parser_for(language), source)
  let cursor = @api.QueryCursor::new()
  let clone = query.deep_clone()
  // disable the patterns that match names
  query.disable_pattern(0)
  query.disable_pattern(2)
  let matches = cursor.matches(query, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query, source), [
    (3, [("body", "{ B }")]),
    (1, [("body", "{ int d; }")]),
  ])
  // The clone is unaffected.
  let matches = cursor.matches(clone, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, clone, source), [
    (2, [("name", "A")]),
    (3, [("body", "{ B }")]),
    (0, [("name", "C")]),
    (1, [("body", "{ int d; }")]),
  ])
  assert_true(clone != query)
}

///|
async test "query_alternative_predicate_prefix" {
  guard get_parsing_language("c") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|((call_expression
      #|  function: (identifier) @keyword
      #|  arguments: (argument_list
      #|              (string_literal) @function))
      #| (.eq? @keyword "DEFUN"))
    ),
  )
  let source =
    #|DEFUN ("identity", Fidentity, Sidentity, 1, 1, 0,
    #|       doc: /* Return the argument unchanged.  */
    #|       attributes: const)
    #|  (Lisp_Object arg)
    #|{
    #|  return arg;
    #|}
  assert_query_matches(language, query, source, [
    (0, [("keyword", "DEFUN"), ("function", "\"identity\"")]),
  ])
}

///|
async test "query_quantified_captures" {
  guard get_parsing_language("c") is Some(language) else { return }
  let code =
    #|/// foo
    #|/// bar
    #|/// baz
    #|
    #|void main() {}
    #|
    #|/// qux
    #|/// quux
    #|// quuz
  let rows = [
    (
      // doc comments where all must match the prefix
      code,
      (
        #|((comment)+ @comment.documentation
        #|  (#match? @comment.documentation "^///"))
      ),
      [
        ("comment.documentation", "/// foo"),
        ("comment.documentation", "/// bar"),
        ("comment.documentation", "/// baz"),
      ],
    ),
    (
      // doc comments where one must match the prefix
      code,
      (
        #|((comment)+ @comment.documentation
        #|  (#any-match? @comment.documentation "^///"))
      ),
      [
        ("comment.documentation", "/// foo"),
        ("comment.documentation", "/// bar"),
        ("comment.documentation", "/// baz"),
        ("comment.documentation", "/// qux"),
        ("comment.documentation", "/// quux"),
        ("comment.documentation", "// quuz"),
      ],
    ),
    (
      // multiple quantifiers should not hang query parsing
      "// foo\n// bar\n// baz\n",
      "((comment) ?+ @comment)",
      // This should be identical to the `*` quantifier.
      [
        ("comment", "// foo"),
        ("comment", "// foo"),
        ("comment", "// foo"),
        ("comment", "// bar"),
        ("comment", "// baz"),
      ],
    ),
  ]
  let parser = parser_for(language)
  for row in rows {
    let (code, pattern, expected) = row
    let tree = parse(parser, code)
    let query = @api.Query::new(language, pattern)
    let cursor = @api.QueryCursor::new()
    let captures = cursor.captures(query, tree.root_node(), utf8(code))
    assert_eq(collect_captures(captures, query, code), expected)
  }
}

///|
/// The text predicates' semantics for quantified captures: `eq?`/`not-eq?`
/// must hold for all nodes, the `any-` variants for one, `any-of?` for all;
/// `eq?` between two captures compares nodes pairwise.
async test "satisfies_text_predicates with quantified captures" {
  guard get_parsing_language("c") is Some(language) else { return }
  let source = "// a\n// a\n// b\nx = x; y = z;"
  let bytes = utf8(source)
  let tree = parse(parser_for(language), source)
  let count = (pattern : String) => {
    let query = @api.Query::new(language, pattern)
    let cursor = @api.QueryCursor::new()
    let matches = cursor.matches(query, tree.root_node(), bytes)
    matches.iter().count()
  }
  // Three comments in one match.
  assert_eq(count("((comment)+ @c)"), 1)
  assert_eq(count("((comment)+ @c (#eq? @c \"// a\"))"), 0)
  assert_eq(count("((comment)+ @c (#any-eq? @c \"// a\"))"), 1)
  assert_eq(count("((comment)+ @c (#not-eq? @c \"// c\"))"), 1)
  assert_eq(count("((comment)+ @c (#any-not-eq? @c \"// a\"))"), 1)
  assert_eq(count("((comment)+ @c (#any-not-eq? @c \"// b\" ))"), 1)
  assert_eq(count("((comment)+ @c (#match? @c \"^// [ab]$\"))"), 1)
  assert_eq(count("((comment)+ @c (#not-match? @c \"b\"))"), 0)
  assert_eq(count("((comment)+ @c (#any-not-match? @c \"b\"))"), 1)
  assert_eq(count("((comment)+ @c (#any-of? @c \"// a\" \"// b\"))"), 1)
  assert_eq(count("((comment)+ @c (#any-of? @c \"// a\"))"), 0)
  assert_eq(count("((comment)+ @c (#not-any-of? @c \"// c\"))"), 1)
  // Pairwise comparison of two captures.
  assert_eq(
    count(
      "((assignment_expression left: (identifier) @l right: (identifier) @r) (#eq? @l @r))",
    ),
    1,
  )
  assert_eq(
    count(
      "((assignment_expression left: (identifier) @l right: (identifier) @r) (#not-eq? @l @r))",
    ),
    1,
  )
  // A capture compared with a missing capture fails because the counts
  // differ.
  assert_eq(count("((comment)+ @c (identifier)? @d (#eq? @c @d))"), 0)
}

///|
async test "query_max_start_depth" {
  guard get_parsing_language("c") is Some(language) else { return }
  let source =
    #|if (a1 && a2) {
    #|    if (b1 && b2) { }
    #|    if (c) { }
    #|}
    #|if (d) {
    #|    if (e1 && e2) { }
    #|    if (f) { }
    #|}
    #|
  let rows : Array[(Int32, String, Array[(Int32, Array[(String, String)])])] = [
    // depth 0: match translation unit
    (0, "(translation_unit) @capture", [(0, [("capture", source)])]),
    // depth 0: match none
    (0, "(if_statement) @capture", []),
    // depth 1: match 2 if statements at the top level
    (
      1,
      "(if_statement) @capture",
      [
        (
          0,
          [
            (
              "capture", "if (a1 && a2) {\n    if (b1 && b2) { }\n    if (c) { }\n}",
            ),
          ],
        ),
        (0, [("capture", "if (d) {\n    if (e1 && e2) { }\n    if (f) { }\n}")]),
      ],
    ),
    // depth 1 with deep pattern: match the only the first if statement
    (
      1,
      "(if_statement condition: (parenthesized_expression (binary_expression))) @capture",
      [
        (
          0,
          [
            (
              "capture", "if (a1 && a2) {\n    if (b1 && b2) { }\n    if (c) { }\n}",
            ),
          ],
        ),
      ],
    ),
    // depth 3 with deep pattern: match all if statements with a binexpr
    // condition
    (
      3,
      "(if_statement condition: (parenthesized_expression (binary_expression))) @capture",
      [
        (
          0,
          [
            (
              "capture", "if (a1 && a2) {\n    if (b1 && b2) { }\n    if (c) { }\n}",
            ),
          ],
        ),
        (0, [("capture", "if (b1 && b2) { }")]),
        (0, [("capture", "if (e1 && e2) { }")]),
      ],
    ),
  ]
  let tree = parse(parser_for(language), source)
  let cursor = @api.QueryCursor::new()
  for row in rows {
    let (depth, pattern, expected) = row
    let query = @api.Query::new(language, pattern)
    ignore(cursor.set_max_start_depth(Some(depth)))
    let matches = cursor.matches(query, tree.root_node(), utf8(source))
    assert_eq(collect_matches(matches, query, source), expected)
  }
  // Removing the limit finds all six if statements.
  ignore(cursor.set_max_start_depth(None))
  let query = @api.Query::new(language, "(if_statement) @capture")
  assert_eq(
    cursor.matches(query, tree.root_node(), utf8(source)).iter().count(),
    6,
  )
}

///|
/// `query_matches_within_byte_range` and `..._within_point_range`, adapted
/// to the JSON grammar.
async test "query_matches_within_byte_and_point_range (json)" {
  guard get_parsing_language("json") is Some(language) else { return }
  let query = @api.Query::new(language, "(number) @element")
  let source = "[1, 2, 3, 4, 5, 6, 7]"
  let tree = parse(parser_for(language), source)
  let cursor = @api.QueryCursor::new()
  let elements = (m : Array[(Int32, Array[(String, String)])]) => {
    m.map(x => x.1[0].1)
  }
  let matches = cursor
    .set_byte_range(0, 8)
    .matches(query, tree.root_node(), utf8(source))
  assert_eq(elements(collect_matches(matches, query, source)), ["1", "2", "3"])
  let matches = cursor
    .set_byte_range(5, 15)
    .matches(query, tree.root_node(), utf8(source))
  assert_eq(elements(collect_matches(matches, query, source)), ["3", "4", "5"])
  // An end byte of zero indicates there is no end
  let matches = cursor
    .set_byte_range(12, 0)
    .matches(query, tree.root_node(), utf8(source))
  assert_eq(elements(collect_matches(matches, query, source)), ["5", "6", "7"])
  let source =
    #|[
    #|  1, 2,
    #|  3, 4,
    #|  5, 6,
    #|  7, 8,
    #|  9, 10,
    #|  11, 12
    #|]
    #|
  let tree = parse(parser_for(language), source)
  let cursor = @api.QueryCursor::new()
  let matches = cursor
    .set_point_range(@api.Point::new(1, 0), @api.Point::new(2, 3))
    .matches(query, tree.root_node(), utf8(source))
  assert_eq(elements(collect_matches(matches, query, source)), ["1", "2", "3"])
  let matches = cursor
    .set_point_range(@api.Point::new(2, 0), @api.Point::new(3, 3))
    .matches(query, tree.root_node(), utf8(source))
  assert_eq(elements(collect_matches(matches, query, source)), ["3", "4", "5"])
  // Zero end point is treated like no end point.
  let matches = cursor
    .set_point_range(@api.Point::new(4, 1), @api.Point::new(0, 0))
    .matches(query, tree.root_node(), utf8(source))
  assert_eq(elements(collect_matches(matches, query, source)), [
    "7", "8", "9", "10", "11", "12",
  ])
  // Ranges can also be set on the iterators.
  let matches = cursor.matches(query, tree.root_node(), utf8(source))
  matches.set_point_range(@api.Point::new(6, 0), @api.Point::new(7, 0))
  assert_eq(elements(collect_matches(matches, query, source)), ["11", "12"])
}

///|
async test "query_captures_within_byte_range" {
  guard get_parsing_language("c") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|(call_expression
      #|    function: (identifier) @function
      #|    arguments: (argument_list (string_literal) @string.arg))
      #|
      #|(string_literal) @string
    ),
  )
  let source = "DEFUN (\"safe-length\", Fsafe_length, Ssafe_length, 1, 1, 0)"
  let tree = parse(parser_for(language), source)
  let cursor = @api.QueryCursor::new()
  let captures = cursor
    .set_byte_range(3, 27)
    .captures(query, tree.root_node(), utf8(source))
  assert_eq(collect_captures(captures, query, source), [
    ("function", "DEFUN"),
    ("string.arg", "\"safe-length\""),
    ("string", "\"safe-length\""),
  ])
}

///|
async test "query_matches_contained_within_range (json)" {
  guard get_parsing_language("json") is Some(language) else { return }
  let query = @api.Query::new(language, "(array (number) @element (number))")
  let source = "[1, 2] [3, 4] [5, 6]"
  let tree = parse(parser_for(language), source)
  let cursor = @api.QueryCursor::new()
  let matches = cursor
    .set_containing_byte_range(0, 14)
    .matches(query, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query, source).map(m => m.1[0].1), [
    "1", "3",
  ])
  let cursor = @api.QueryCursor::new()
  let matches = cursor
    .set_containing_point_range(@api.Point::new(0, 6), @api.Point::new(0, 20))
    .matches(query, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query, source).map(m => m.1[0].1), [
    "3", "5",
  ])
}

///|
/// `query_execution_with_timeout` and the progress callback tests, adapted
/// to the JSON grammar.
async test "query progress callback (json)" {
  guard get_parsing_language("json") is Some(language) else { return }
  let count = 1000
  let source = "[" + Array::make(count, "{\"a\": 1}").join(", ") + "]"
  let tree = parse(parser_for(language), source)
  let query = @api.Query::new(language, "(object) @object")
  let cursor = @api.QueryCursor::new()
  // A callback that stops after a few calls ends the query early, for good.
  let mut calls = 0
  let options = @api.QueryCursorOptions::new(progress_callback=state => {
    calls += 1
    assert_true(state.current_byte_offset() >= 0) catch {
      _ => ()
    }
    if calls > 3 {
      Break
    } else {
      Continue
    }
  })
  let matches = cursor.matches_with_options(
    query,
    tree.root_node(),
    utf8(source),
    options,
  )
  let mut found = 0
  while matches.next() is Some(_) {
    found += 1
  }
  assert_true(found < count)
  assert_true(matches.next() is None)
  // Without options, every match is found.
  let matches = cursor.matches(query, tree.root_node(), utf8(source))
  assert_eq(matches.iter().count(), count)
  // A callback that always continues sees progress and changes nothing.
  let mut called = false
  let captures = cursor.captures_with_options(
    query,
    tree.root_node(),
    utf8(source),
    @api.QueryCursorOptions::new(progress_callback=_ => {
      called = true
      Continue
    }),
  )
  assert_eq(captures.iter().count(), count)
  assert_true(called)
}

///|
async test "query_on_empty_source_code (json)" {
  guard get_parsing_language("json") is Some(language) else { return }
  let query = @api.Query::new(language, "(document) @document")
  assert_query_matches(language, query, "", [(0, [("document", "")])])
}

///|
async test "query match limit and Debug" {
  guard get_parsing_language("json") is Some(language) else { return }
  let source = "[1, [2]]"
  let tree = parse(parser_for(language), source)
  let query = @api.Query::new(language, "(array (number) @n)")
  let cursor = @api.QueryCursor::new()
  // The default limit is `u32::MAX`, shown as `Int::max_value()`.
  assert_eq(cursor.match_limit(), 0x7FFFFFFF)
  cursor.set_match_limit(32)
  assert_eq(cursor.match_limit(), 32)
  let matches = cursor.matches(query, tree.root_node(), utf8(source))
  let m = matches.next().unwrap()
  inspect(
    @debug.to_string(m),
    content="QueryMatch { id: 0, pattern_index: 0, captures: [QueryCapture { node: {Node number (0, 1) - (0, 2)}, index: 0 }] }",
  )
  assert_eq(m.id(), 0)
  assert_eq(m.nodes_for_capture_index(0).count(), 1)
  assert_eq(m.nodes_for_capture_index(1).count(), 0)
  assert_true(m.satisfies_text_predicates(query, utf8(source)))
  assert_false(cursor.did_exceed_match_limit())
}

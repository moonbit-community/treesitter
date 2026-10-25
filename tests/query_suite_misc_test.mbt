// Port of tree-sitter crates/cli/src/tests/query_test.rs (lines 5942-6874).
//
// Grammars that upstream generates at test time go through the MoonBit
// generator (`generate_parser` + `get_test_language`).

///|
/// The number of matches a `QueryMatches` iterator yields (`.count()`).
fn[T : @treesitter.TextProvider] m5_count_matches(
  matches : @treesitter.QueryMatches[T],
) -> Int32 {
  let mut count = 0
  while matches.next() is Some(_) {
    count += 1
  }
  count
}

///|
/// The number of captures a `QueryCaptures` iterator yields (`.count()`).
fn[T : @treesitter.TextProvider] m5_count_captures(
  captures : @treesitter.QueryCaptures[T],
) -> Int32 {
  let mut count = 0
  while captures.next() is Some(_) {
    count += 1
  }
  count
}

///|
async test "grammar_with_aliased_literal_query" {
  // module.exports = grammar({
  //   name: 'test',
  //
  //   rules: {
  //     source: $ => repeat(choice($.compound_statement, $.expansion)),
  //
  //     compound_statement: $ => seq(alias(token(prec(-1, '}')), '}')),
  //
  //     expansion: $ => seq('}'),
  //   },
  // });
  let (parser_name, parser_code) = generate_parser(
    (
      #|
      #|        {
      #|            "name": "test",
      #|            "rules": {
      #|                "source": {
      #|                    "type": "REPEAT",
      #|                    "content": {
      #|                        "type": "CHOICE",
      #|                        "members": [
      #|                            {
      #|                                "type": "SYMBOL",
      #|                                "name": "compound_statement"
      #|                            },
      #|                            {
      #|                                "type": "SYMBOL",
      #|                                "name": "expansion"
      #|                            }
      #|                        ]
      #|                    }
      #|                },
      #|                "compound_statement": {
      #|                    "type": "SEQ",
      #|                    "members": [
      #|                        {
      #|                            "type": "ALIAS",
      #|                            "content": {
      #|                                "type": "TOKEN",
      #|                                "content": {
      #|                                    "type": "PREC",
      #|                                    "value": -1,
      #|                                    "content": {
      #|                                        "type": "STRING",
      #|                                        "value": "}"
      #|                                    }
      #|                                }
      #|                            },
      #|                            "named": false,
      #|                            "value": "}"
      #|                        }
      #|                    ]
      #|                },
      #|                "expansion": {
      #|                    "type": "SEQ",
      #|                    "members": [
      #|                        {
      #|                            "type": "STRING",
      #|                            "value": "}"
      #|                        }
      #|                    ]
      #|                }
      #|            }
      #|        }
      #|        
    ),
  )
  let language = get_test_language(parser_name, parser_code, None)
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|        (compound_statement "}" @bracket1)
      #|        (expansion "}" @bracket2)
      #|        
    ),
  ) catch {
    e => fail("expected the query to be valid: \{e}")
  }
  ignore(query)
}

///|
async test "query_with_first_child_in_group_is_anchor" {
  guard get_parsing_language("c") is Some(language) else { return }
  let source_code = "void fun(int a, char b, int c) { };"
  let query =
    #|
    #|            (parameter_list
    #|              .
    #|              ((parameter_declaration) @constant
    #|                (#match? @constant "^int")))
  let query = @treesitter.Query::new(language, query)
  assert_query_matches(language, query, source_code, [
    (0, [("constant", "int a")]),
  ])
}

///|
// This test needs be executed with UBSAN enabled to check for regressions:
// ```
// UBSAN_OPTIONS="halt_on_error=1" \
// CFLAGS="-fsanitize=undefined"   \
// RUSTFLAGS="-lubsan"             \
// cargo test --target $(rustc -vV | sed -nr 's/^host: //p') -- --test-threads 1
// ```
async test "query_compiler_oob_access" {
  guard get_language("java") is Some(language) else { return }
  // UBSAN should not report any OOB access
  ignore(@treesitter.Query::new(language, "(package_declaration _ (_) @name _)"))
}

///|
async test "query_wildcard_with_immediate_first_child" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(language, "(_ . (identifier) @firstChild)")
  let source = "function name(one, two, three) { }"
  assert_query_matches(language, query, source, [
    (0, [("firstChild", "name")]),
    (0, [("firstChild", "one")]),
  ])
}

///|
async test "query_on_empty_source_code" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let source_code = ""
  let query = "(program) @program"
  let query = @treesitter.Query::new(language, query)
  assert_query_matches(language, query, source_code, [(0, [("program", "")])])
}

///|
async test "query_execution_with_timeout" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = parser_for(language)
  let count = 10_000
  let source_code = "function foo() { while (true) { } }\n".repeat(count)
  let tree = parse(parser, source_code)
  let query = @treesitter.Query::new(language, "(function_declaration) @function")
  // Upstream measures `Instant::elapsed().as_micros() > 1000`; the only clock
  // available here, `@env.now()`, counts milliseconds, so "more than 1000
  // microseconds" becomes "more than 1 millisecond".
  let start_time = @env.now()
  let progress_callback = (_ : @treesitter.QueryCursorState) => {
    if @env.now() - start_time > 1 {
      @treesitter.ControlFlow::Break
    } else {
      @treesitter.ControlFlow::Continue
    }
  }
  let cursor = @treesitter.QueryCursor::new()
  let matches = m5_count_matches(
    cursor.matches_with_options(
      query,
      tree.root_node(),
      utf8(source_code),
      @treesitter.QueryCursorOptions::new(progress_callback~),
    ),
  )
  assert_true(matches < count)
  let matches = m5_count_matches(
    cursor.matches(query, tree.root_node(), utf8(source_code)),
  )
  assert_eq(matches, count)
}

///|
async test "query_progress_callback_lives_as_long_as_matches" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = parser_for(language)
  let source_code = "function foo() {}\n".repeat(1000)
  let tree = parse(parser, source_code)
  let query = @treesitter.Query::new(language, "(function_declaration) @function")
  let cursor = @treesitter.QueryCursor::new()
  let mut callback_was_called = false
  let progress_callback = (_ : @treesitter.QueryCursorState) => {
    callback_was_called = true
    @treesitter.ControlFlow::Continue
  }
  let matches = cursor.matches_with_options(
    query,
    tree.root_node(),
    utf8(source_code),
    @treesitter.QueryCursorOptions::new(progress_callback~),
  )
  assert_eq(m5_count_matches(matches), 1000)
  assert_true(callback_was_called)
}

///|
async test "query_captures_progress_callback_stops_behind_an_open_match" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = parser_for(language)
  let numbers = (0).until(1000).map(i => i.to_string()).to_array()
  let source_code = "[\{numbers.join(",")}];"
  let tree = parse(parser, source_code)

  // The first pattern stays in progress until the array ends, so every number
  // capture finishes behind it.
  let query = @treesitter.Query::new(
    language, "(array (number) @first (string)) (number) @number",
  )
  let mut calls = 0
  let progress_callback = (_ : @treesitter.QueryCursorState) => {
    calls += 1
    @treesitter.ControlFlow::Break
  }
  let cursor = @treesitter.QueryCursor::new()
  let captures = m5_count_captures(
    cursor.captures_with_options(
      query,
      tree.root_node(),
      utf8(source_code),
      @treesitter.QueryCursorOptions::new(progress_callback~),
    ),
  )
  assert_true(captures < 1000)
  assert_eq(calls, 1)
}

///|
async test "query_captures_progress_callback_discards_in_progress_matches" {
  guard get_parsing_language("json") is Some(language) else { return }
  let parser = parser_for(language)

  // Within each element, the first pattern holds back the second pattern's captures
  // until the inner array ends. The second pattern then stays in progress, but
  // definite, until the element itself ends.
  let trues = Array::make(12, "true").join(",")
  let element = "[[{\"a\":1},1,2],\{trues}]"
  let source_code = "[\{Array::make(50, element).join(",")}]"
  let tree = parse(parser, source_code)
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|        (array (object) @object (string))
      #|        (array (array (number) @number) "]" @close)
      #|        (number) @n
      #|        
    ),
  )
  for cancel_at in 1..<=20 {
    let calls = Ref(0)
    let progress_callback = (_ : @treesitter.QueryCursorState) => {
      calls.val = calls.val + 1
      if calls.val >= cancel_at {
        @treesitter.ControlFlow::Break
      } else {
        @treesitter.ControlFlow::Continue
      }
    }
    let cursor = @treesitter.QueryCursor::new()
    let captures = cursor.captures_with_options(
      query,
      tree.root_node(),
      utf8(source_code),
      @treesitter.QueryCursorOptions::new(progress_callback~),
    )
    while captures.next() is Some((m, _)) {
      // Once the callback has asked to stop, only finished matches may be returned.
      if calls.val >= cancel_at && m.pattern_index == 1 {
        assert_eq(
          m.captures().length(),
          2,
          msg="cancelled at callback \{cancel_at}",
        )
      }
    }
  }
}

///|
async test "query_progress_callback_halts_for_good" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = parser_for(language)
  let source_code = "function foo() {}\n".repeat(1000)
  let tree = parse(parser, source_code)
  let query = @treesitter.Query::new(language, "(function_declaration) @function")
  let stop = Ref(true)
  let progress_callback = (_ : @treesitter.QueryCursorState) => {
    if stop.val {
      @treesitter.ControlFlow::Break
    } else {
      @treesitter.ControlFlow::Continue
    }
  }
  let cursor = @treesitter.QueryCursor::new()
  let matches = cursor.matches_with_options(
    query,
    tree.root_node(),
    utf8(source_code),
    @treesitter.QueryCursorOptions::new(progress_callback~),
  )
  let mut count = 0
  while matches.next() is Some(_) {
    count += 1
  }
  assert_true(count < 1000)

  // Asking the cursor for more after a cancellation does not resume the query.
  stop.val = false
  assert_true(matches.next() is None)
}

///|
async test "query_progress_callback_keeps_up_with_in_progress_states" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = parser_for(language)
  let depth = 1000
  let source_code = "\{"[".repeat(depth)}\{"]".repeat(depth)};"
  let tree = parse(parser, source_code)

  // No array has a string, so every enclosing array keeps a state in
  // progress, and the cursor visits all of them at every node it steps over.
  let query = @treesitter.Query::new(language, "(array (string) @string)")
  let mut calls = 0
  let progress_callback = (_ : @treesitter.QueryCursorState) => {
    calls += 1
    @treesitter.ControlFlow::Continue
  }
  let cursor = @treesitter.QueryCursor::new()
  let matches = m5_count_matches(
    cursor.matches_with_options(
      query,
      tree.root_node(),
      utf8(source_code),
      @treesitter.QueryCursorOptions::new(progress_callback~),
    ),
  )
  assert_eq(matches, 0)
  assert_true(calls > depth, msg="\{calls} calls for \{depth} nested arrays")
}

///|
async test "query_execution_with_points_causing_underflow" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let parser = parser_for(language)
  let code =
    #|fn main() {
    #|    println!("{:?}", foo());
    #|}
  parser.set_included_ranges([
    {
      start_byte: 24,
      end_byte: 39,
      start_point: @treesitter.Point::new(0, 0), // 5, 12
      end_point: @treesitter.Point::new(0, 0), // 5, 27
    },
  ])
  let query = @treesitter.Query::new(language, "(call_expression) @cap")
  let cursor = @treesitter.QueryCursor::new()
  let tree = parse(parser, code)
  let matches = {
    let root_node = tree.root_node()
    let matches = cursor.matches(query, root_node, utf8(code))
    collect_matches(matches, query, code)
  }
  tree.edit({
    start_byte: 40,
    old_end_byte: 40,
    new_end_byte: 41,
    start_position: @treesitter.Point::new(1, 28),
    old_end_position: @treesitter.Point::new(1, 28),
    new_end_position: @treesitter.Point::new(2, 0),
  })
  guard parser.parse(utf8(code), old_tree=tree) is Some(tree2) else {
    fail("parse failed")
  }
  let matches2 = {
    let root_node = tree2.root_node()
    let matches = cursor.matches(query, root_node, utf8(code))
    collect_matches(matches, query, code)
  }
  assert_eq(matches, matches2)
}

///|
async test "wildcard_behavior_before_anchor" {
  guard get_parsing_language("python") is Some(language) else { return }
  let _ = parser_for(language)
  let source =
    #|
    #|        (a, b)
    #|        (c, d,)
    #|    

  //  In this query, we're targeting any *named* node immediately before a closing parenthesis.
  let query = @treesitter.Query::new(language, "(tuple (_) @last . \")\" .) @match")
  assert_query_matches(language, query, source, [
    (0, [("match", "(a, b)"), ("last", "b")]),
    (0, [("match", "(c, d,)"), ("last", "d")]),
  ])

  // In this query, we're targeting *any* node immediately before a closing
  // parenthesis.
  let query = @treesitter.Query::new(language, "(tuple _ @last . \")\" .) @match")
  assert_query_matches(language, query, source, [
    (0, [("match", "(a, b)"), ("last", "b")]),
    (0, [("match", "(c, d,)"), ("last", ",")]),
  ])
}

///|
async test "pattern_alternatives_follow_last_child_constraint" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let parser = parser_for(language)
  let code =
    #|
    #|fn f() {
    #|    if a {} // <- should NOT match
    #|    if b {}
    #|}
  let tree = parse(parser, code)
  let cursor = @treesitter.QueryCursor::new()
  let query = @treesitter.Query::new(
    language,
    (
      #|(block
      #|        [
      #|            (type_cast_expression)
      #|            (expression_statement)
      #|        ] @last
      #|        .
      #|        )
    ),
  )
  let matches = {
    let root_node = tree.root_node()
    let matches = cursor.matches(query, root_node, utf8(code))
    collect_matches(matches, query, code)
  }
  let flipped_query = @treesitter.Query::new(
    language,
    (
      #|(block
      #|        [
      #|            (expression_statement)
      #|            (type_cast_expression)
      #|        ] @last
      #|        .
      #|        )
    ),
  )
  let flipped_matches = {
    let root_node = tree.root_node()
    let matches = cursor.matches(flipped_query, root_node, utf8(code))
    collect_matches(matches, flipped_query, code)
  }
  assert_eq(matches, [(0, [("last", "if b {}")])])
  assert_eq(matches, flipped_matches)
}

///|
async test "wildcard_parent_allows_fallible_child_patterns" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let _ = parser_for(language)
  let source_code =
    #|
    #|function foo() {
    #|    "bar"
    #|}
    #|    
  let query = @treesitter.Query::new(
    language,
    (
      #|(function_declaration
      #|          (_
      #|            (expression_statement)
      #|          )
      #|        ) @part
    ),
  )
  assert_query_matches(language, query, source_code, [
    (0, [("part", "function foo() {\n    \"bar\"\n}")]),
  ])
}

///|
async test "unfinished_captures_are_not_definite_with_pending_anchors" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = parser_for(language)
  let source_code =
    #|
    #|const foo = [
    #|  1, 2, 3
    #|]
    #|
  let tree = parse(parser, source_code)
  let query = @treesitter.Query::new(language, "(array (_) @foo . \"]\")")
  let matches_cursor = @treesitter.QueryCursor::new()
  let captures_cursor = @treesitter.QueryCursor::new()
  let captures = captures_cursor.captures(
    query,
    tree.root_node(),
    utf8(source_code),
  )
  let captures = collect_captures(captures, query, source_code)
  let matches = matches_cursor.matches(
    query,
    tree.root_node(),
    utf8(source_code),
  )
  let matches = collect_matches(matches, query, source_code)
  assert_eq(captures, [("foo", "3")])
  assert_eq(matches.length(), 1)
  assert_eq(matches[0].1, captures)
}

///|
async test "query_with_predicate_causing_oob_access" {
  guard get_language("rust") is Some(language) else { return }
  let query =
    #|(call_expression
    #|     function: (scoped_identifier
    #|       path: (scoped_identifier (identifier) @_regex (#any-of? @_regex "Regex" "RegexBuilder") .))
    #|     (#set! injection.language "regex"))
  ignore(@treesitter.Query::new(language, query))
}

///|
async test "query_with_anonymous_error_node" {
  guard get_test_fixture_language("anonymous_error") is Some(language) else {
    return
  }
  let parser = parser_for(language)
  let source = "ERROR"
  let tree = parse(parser, source)
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|          "ERROR" @error
      #|          (document "ERROR" @error)
      #|        
    ),
  )
  let cursor = @treesitter.QueryCursor::new()
  let matches = cursor.matches(query, tree.root_node(), utf8(source))
  let matches = collect_matches(matches, query, source)
  assert_eq(matches, [(1, [("error", "ERROR")]), (0, [("error", "ERROR")])])
}

///|
async test "query_allows_error_nodes_with_children" {
  guard get_parsing_language("cpp") is Some(language) else { return }
  let code = "SomeStruct foo{.bar{}};"
  let parser = parser_for(language)
  let tree = parse(parser, code)
  let root = tree.root_node()
  let query = @treesitter.Query::new(language, "(initializer_list (ERROR) @error)")
  let cursor = @treesitter.QueryCursor::new()
  let matches = cursor.matches(query, root, utf8(code))
  let matches = collect_matches(matches, query, code)
  assert_eq(matches, [(0, [("error", ".bar")])])
}

///|
async test "query_assertion_on_unreachable_node_with_child" {
  // The `await_binding` rule is unreachable because it has a lower precedence than
  // `identifier`, so we'll always reduce to an expression of type `identifier`
  // instead whenever we see the token `await` followed by an identifier.
  //
  // A query that tries to capture the `await` token in the `await_binding` rule
  // should not cause an assertion failure during query analysis.
  //
  // Upstream writes this grammar to a temporary `grammar.js` and loads it with
  // `load_grammar_file` (node):
  //
  //   export default grammar({
  //     name: "query_assertion_crash",
  //
  //     rules: {
  //       source_file: $ => repeat($.expression),
  //
  //       expression: $ => choice(
  //         $.await_binding,
  //         $.await_expr,
  //         $.equal_expr,
  //         prec(3, $.identifier),
  //       ),
  //
  //       await_binding: $ => prec(1, seq('await', $.identifier, '=', $.expression)),
  //
  //       await_expr: $ => prec(1, seq('await', $.expression)),
  //
  //       equal_expr: $ => prec.right(2, seq($.expression, '=', $.expression)),
  //
  //       identifier: _ => /[a-z]+/,
  //     }
  //   });
  //
  // `grammar_json` below is the `src/grammar.json` that the pinned upstream
  // CLI (`tree-sitter generate`) produced from that file.
  let grammar_json =
    #|{
    #|  "$schema": "https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json",
    #|  "name": "query_assertion_crash",
    #|  "rules": {
    #|    "source_file": {
    #|      "type": "REPEAT",
    #|      "content": {
    #|        "type": "SYMBOL",
    #|        "name": "expression"
    #|      }
    #|    },
    #|    "expression": {
    #|      "type": "CHOICE",
    #|      "members": [
    #|        {
    #|          "type": "SYMBOL",
    #|          "name": "await_binding"
    #|        },
    #|        {
    #|          "type": "SYMBOL",
    #|          "name": "await_expr"
    #|        },
    #|        {
    #|          "type": "SYMBOL",
    #|          "name": "equal_expr"
    #|        },
    #|        {
    #|          "type": "PREC",
    #|          "value": 3,
    #|          "content": {
    #|            "type": "SYMBOL",
    #|            "name": "identifier"
    #|          }
    #|        }
    #|      ]
    #|    },
    #|    "await_binding": {
    #|      "type": "PREC",
    #|      "value": 1,
    #|      "content": {
    #|        "type": "SEQ",
    #|        "members": [
    #|          {
    #|            "type": "STRING",
    #|            "value": "await"
    #|          },
    #|          {
    #|            "type": "SYMBOL",
    #|            "name": "identifier"
    #|          },
    #|          {
    #|            "type": "STRING",
    #|            "value": "="
    #|          },
    #|          {
    #|            "type": "SYMBOL",
    #|            "name": "expression"
    #|          }
    #|        ]
    #|      }
    #|    },
    #|    "await_expr": {
    #|      "type": "PREC",
    #|      "value": 1,
    #|      "content": {
    #|        "type": "SEQ",
    #|        "members": [
    #|          {
    #|            "type": "STRING",
    #|            "value": "await"
    #|          },
    #|          {
    #|            "type": "SYMBOL",
    #|            "name": "expression"
    #|          }
    #|        ]
    #|      }
    #|    },
    #|    "equal_expr": {
    #|      "type": "PREC_RIGHT",
    #|      "value": 2,
    #|      "content": {
    #|        "type": "SEQ",
    #|        "members": [
    #|          {
    #|            "type": "SYMBOL",
    #|            "name": "expression"
    #|          },
    #|          {
    #|            "type": "STRING",
    #|            "value": "="
    #|          },
    #|          {
    #|            "type": "SYMBOL",
    #|            "name": "expression"
    #|          }
    #|        ]
    #|      }
    #|    },
    #|    "identifier": {
    #|      "type": "PATTERN",
    #|      "value": "[a-z]+"
    #|    }
    #|  },
    #|  "extras": [
    #|    {
    #|      "type": "PATTERN",
    #|      "value": "\\s"
    #|    }
    #|  ],
    #|  "conflicts": [],
    #|  "precedences": [],
    #|  "externals": [],
    #|  "inline": [],
    #|  "supertypes": [],
    #|  "reserved": {}
    #|}
  let (parser_name, parser_code) = generate_parser(grammar_json)
  let language = get_test_language(parser_name, parser_code, None)
  let query_result = try
    @treesitter.Query::new(language, "(await_binding \"await\")")
  catch {
    e => Err(e)
  } noraise {
    q => Ok(q)
  }
  assert_true(query_result is Err(_))
  guard query_result is Err(error) else { return }
  assert_eq(
    error,
    QueryError(
      kind=Structure,
      row=0,
      offset=0,
      column=0,
      message=["(await_binding \"await\")", "^"].join("\n"),
    ),
  )
}

///|
async test "query_supertype_with_anonymous_node" {
  // Upstream writes this grammar to a temporary `grammar.js` and loads it with
  // `load_grammar_file` (node):
  //
  //   export default grammar({
  //     name: "supertype_anonymous_test",
  //
  //     extras: $ => [/\s/, $.comment],
  //
  //     supertypes: $ => [$.expression],
  //
  //     word: $ => $.identifier,
  //
  //     rules: {
  //       source_file: $ => repeat($.expression),
  //
  //       expression: $ => choice(
  //         $.function_call,
  //         '()' // an empty tuple, which should be queryable with the supertype syntax
  //       ),
  //
  //       function_call: $ => seq($.identifier, '()'),
  //
  //       identifier: _ => /[a-zA-Z_][a-zA-Z0-9_]*/,
  //
  //       comment: _ => token(seq('//', /.*/)),
  //     }
  //   });
  //
  // `grammar_json` below is the `src/grammar.json` that the pinned upstream
  // CLI (`tree-sitter generate`) produced from that file.
  let grammar_json =
    #|{
    #|  "$schema": "https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json",
    #|  "name": "supertype_anonymous_test",
    #|  "word": "identifier",
    #|  "rules": {
    #|    "source_file": {
    #|      "type": "REPEAT",
    #|      "content": {
    #|        "type": "SYMBOL",
    #|        "name": "expression"
    #|      }
    #|    },
    #|    "expression": {
    #|      "type": "CHOICE",
    #|      "members": [
    #|        {
    #|          "type": "SYMBOL",
    #|          "name": "function_call"
    #|        },
    #|        {
    #|          "type": "STRING",
    #|          "value": "()"
    #|        }
    #|      ]
    #|    },
    #|    "function_call": {
    #|      "type": "SEQ",
    #|      "members": [
    #|        {
    #|          "type": "SYMBOL",
    #|          "name": "identifier"
    #|        },
    #|        {
    #|          "type": "STRING",
    #|          "value": "()"
    #|        }
    #|      ]
    #|    },
    #|    "identifier": {
    #|      "type": "PATTERN",
    #|      "value": "[a-zA-Z_][a-zA-Z0-9_]*"
    #|    },
    #|    "comment": {
    #|      "type": "TOKEN",
    #|      "content": {
    #|        "type": "SEQ",
    #|        "members": [
    #|          {
    #|            "type": "STRING",
    #|            "value": "//"
    #|          },
    #|          {
    #|            "type": "PATTERN",
    #|            "value": ".*"
    #|          }
    #|        ]
    #|      }
    #|    }
    #|  },
    #|  "extras": [
    #|    {
    #|      "type": "PATTERN",
    #|      "value": "\\s"
    #|    },
    #|    {
    #|      "type": "SYMBOL",
    #|      "name": "comment"
    #|    }
    #|  ],
    #|  "conflicts": [],
    #|  "precedences": [],
    #|  "externals": [],
    #|  "inline": [],
    #|  "supertypes": [
    #|    "expression"
    #|  ],
    #|  "reserved": {}
    #|}
  let (parser_name, parser_code) = generate_parser(grammar_json)
  let language = get_test_language(parser_name, parser_code, None)
  let query = @treesitter.Query::new(language, "(expression/\"()\") @tuple") catch {
    e => fail("expected the query to be valid: \{e}")
  }
  let source = "foo()\n()"
  assert_query_matches(language, query, source, [(0, [("tuple", "()")])])
}

///|
async test "query_negated_field_through_hidden_nodes" {
  guard get_test_fixture_language("field_lookup_through_hidden_nodes")
    is Some(language) else {
    return
  }

  // `spread` is a field of the second list, through the supertype `item`, no
  // node of the `shadow` is `outer`, since its only name is `inner`, and of the
  // `maybe`s only the one with a name has an `outer`.
  let source = indoc(
    (
      #|
      #|        [a]
      #|        [a, ...b]
      #|        let a = b;
      #|        shadow a;
      #|        alias ...a;
      #|        pair ...a, b;
      #|        pair ...a, ...b;
      #|        let a // c
      #|        = b;
      #|        multi a a = b;
      #|        restore a;
      #|        back a b;
      #|        maybe none end;
      #|        maybe a end;
      #|        sum a + b + c;
      #|    
    ),
  )
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|        (list !spread) @list
      #|        (binding !outer) @binding
      #|        (shadow !outer) @shadow
      #|        (aliased !spread) @aliased
      #|        (alias_pair !spread) @pair
      #|        (multi !outer) @multi
      #|        (restored !outer) @restored
      #|        (back !outer) @back
      #|        (maybe !outer) @maybe
      #|        (sum !left) @sum
      #|        
    ),
  )
  assert_query_matches(language, query, source, [
    (0, [("list", "[a]")]),
    (2, [("shadow", "shadow a;")]),
    (3, [("aliased", "alias ...a;")]),
    (4, [("pair", "pair ...a, b;")]),
    (8, [("maybe", "maybe none end;")]),
  ])
}

///|
async test "query_field_on_hidden_rule_reaches_later_siblings" {
  guard get_test_fixture_language("field_on_hidden_rule") is Some(language) else {
    return
  }

  // `outer` reaches the `=` and `b` through the hidden `_binding`, and `left`
  // reaches `a`, the first `+`, and `b` through the nested hidden `_sum`s.
  let source = "let a = b;\nsum a + b + c;\n"
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|        (binding outer: (name) @outer_name)
      #|        (binding outer: _ @outer_node)
      #|        (sum left: "+" @left_operator)
      #|        (sum left: (name) @left_name)
      #|        
    ),
  )
  assert_query_matches(language, query, source, [
    (1, [("outer_node", "=")]),
    (0, [("outer_name", "b")]),
    (1, [("outer_node", "b")]),
    (3, [("left_name", "a")]),
    (2, [("left_operator", "+")]),
    (3, [("left_name", "b")]),
  ])

  // `arg` reaches the `(` through the hidden `_call`, and `a` has an `arg` of
  // its own.
  let query = @treesitter.Query::new(language, "(call arg: (name) @arg_name)")
  assert_query_matches(language, query, "call (a);\n", [
    (0, [("arg_name", "a")]),
  ])
}

///|
async test "last_child_anchor_looks_past_hidden_repeat" {
  guard get_test_fixture_language("last_child_anchor_past_hidden_repeat")
    is Some(language) else {
    return
  }
  let source = "T a.b.c\nL a.b.c\nN a!.b!.c\n"
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|        (trailing_sep (name) @last .)
      #|        (leading_sep (name) @last .)
      #|        (trailing_named (name) @last .)
      #|        
    ),
  )
  assert_query_matches(language, query, source, [
    (0, [("last", "c")]),
    (1, [("last", "c")]),
    (2, [("last", "c")]),
  ])
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|        (trailing_sep . (name) @first)
      #|        (trailing_sep (name) @a . (name) @b)
      #|        
    ),
  )
  assert_query_matches(language, query, source, [
    (0, [("first", "a")]),
    (1, [("a", "a"), ("b", "b")]),
    (1, [("a", "b"), ("b", "c")]),
  ])
}

///|
async test "last_child_anchor_looks_past_hidden_node" {
  guard get_parsing_language("c") is Some(language) else { return }
  let query = @treesitter.Query::new(language, "(translation_unit (_) @last .)")
  let source = "enum E { A };\nint x;\nint y;\n"
  assert_query_matches(language, query, source, [(0, [("last", "int y;")])])
}

// Port of tree-sitter crates/cli/src/tests/query_test.rs (lines 31-708):
// query construction errors.

///|
async test "query_errors_on_invalid_syntax" {
  guard get_language("javascript") is Some(language) else { return }
  guard get_language("c") is Some(c) else { return }
  guard get_language("python") is Some(python) else { return }
  ignore(@treesitter.Query::new(language, "(if_statement)"))
  ignore(
    @treesitter.Query::new(
      language, "(if_statement condition:(parenthesized_expression (identifier)))",
    ),
  )

  // Mismatched parens
  assert_eq(
    query_error(language, "(if_statement").message(),
    ["(if_statement", "             ^"].join("\n"),
  )
  assert_eq(
    query_error(language, "; comment 1\n; comment 2\n  (if_statement))").message(),
    ["  (if_statement))", "                ^"].join("\n"),
  )

  // Return an error at the *beginning* of a bare identifier not followed a colon.
  // If there's a colon but no pattern, return an error at the end of the colon.
  assert_eq(
    query_error(language, "(if_statement identifier)").message(),
    ["(if_statement identifier)", "              ^"].join("\n"),
  )
  assert_eq(
    query_error(language, "(if_statement condition:)").message(),
    ["(if_statement condition:)", "                        ^"].join("\n"),
  )

  // Return an error at the beginning of an unterminated string.
  assert_eq(
    query_error(language, "(identifier) \"h ").message(),
    ["(identifier) \"h ", "             ^"].join("\n"),
  )

  // Empty tree pattern
  assert_eq(
    query_error(language, "((identifier) ()").message(),
    ["((identifier) ()", "               ^"].join("\n"),
  )

  // Empty alternation
  assert_eq(
    query_error(language, "((identifier) [])").message(),
    ["((identifier) [])", "               ^"].join("\n"),
  )

  // Unclosed sibling expression with predicate
  assert_eq(
    query_error(language, "((identifier) (#a?)").message(),
    ["((identifier) (#a?)", "                   ^"].join("\n"),
  )

  // Predicate not ending in `?` or `!`
  assert_eq(
    query_error(language, "((identifier) (#a))").message(),
    ["((identifier) (#a))", "                 ^"].join("\n"),
  )

  // Unclosed predicate
  assert_eq(
    query_error(language, "((identifier) @x (#eq? @x a").message(),
    ["((identifier) @x (#eq? @x a", "                           ^"].join("\n"),
  )

  // Need at least one child node for a child anchor
  assert_eq(
    query_error(language, "(statement_block .)").message(),
    ["(statement_block .)", "                  ^"].join("\n"),
  )

  // Need a field name after a negated field operator
  assert_eq(
    query_error(language, "(statement_block ! (if_statement))").message(),
    ["(statement_block ! (if_statement))", "                   ^"].join("\n"),
  )

  // Unclosed alternation within a tree
  // tree-sitter/tree-sitter/issues/968
  assert_eq(
    query_error(c, "(parameter_list [ \")\" @foo)").message(),
    ["(parameter_list [ \")\" @foo)", "                          ^"].join("\n"),
  )

  // Unclosed tree within an alternation
  // tree-sitter/tree-sitter/issues/1436
  assert_eq(
    query_error(
      python, "[(unary_operator (_) @operand) (not_operator (_) @operand]",
    ).message(),
    [
      "[(unary_operator (_) @operand) (not_operator (_) @operand]", "                                                         ^",
    ].join("\n"),
  )

  // MISSING keyword with full pattern
  assert_eq(
    query_error(c, "(MISSING (function_declarator (identifier))) ").message(),
    ["(MISSING (function_declarator (identifier))) ", "         ^"].join("\n"),
  )

  // MISSING keyword with multiple identifiers
  assert_eq(
    query_error(c, "(MISSING function_declarator function_declarator) ").message(),
    [
      "(MISSING function_declarator function_declarator) ", "                             ^",
    ].join("\n"),
  )
  assert_eq(
    query_error(language, "(statement / export_statement)"),
    @treesitter.QueryError(
      row=0,
      offset=11,
      column=11,
      kind=Syntax,
      message=["(statement / export_statement)", "           ^"].join("\n"),
    ),
  )
}

///|
async test "query_rejects_excessive_pattern_depth" {
  guard get_test_fixture_language("basic_cst") is Some(language) else { return }
  let nesting = 300
  let source = "(_ ".repeat(nesting) + "_" + ")".repeat(nesting)
  let error = query_error(language, source)
  assert_eq(error.kind(), Structure)
}

///|
async test "query_errors_on_anchor_at_group_edge" {
  guard get_language("javascript") is Some(language) else { return }

  // Anchors between siblings, or at the first/last position of a *node*
  // pattern, are valid.
  ignore(@treesitter.Query::new(language, "((_) . (_))"))
  ignore(@treesitter.Query::new(language, "(program (_) (_) .)"))
  ignore(@treesitter.Query::new(language, "(program (_)* @x . (_))"))

  // A `.` at the edge of a *group* is rejected. A group is not a node, so it
  // has no last child to anchor, and there is no sibling within the group to
  // anchor to.
  assert_eq(
    query_error(language, "((_) .)"),
    @treesitter.QueryError(
      row=0,
      offset=5,
      column=5,
      kind=Syntax,
      message=["((_) .)", "     ^"].join("\n"),
    ),
  )
  assert_eq(
    query_error(language, "(program ((_)+ .)? (_))"),
    @treesitter.QueryError(
      row=0,
      offset=15,
      column=15,
      kind=Syntax,
      message=["(program ((_)+ .)? (_))", "               ^"].join("\n"),
    ),
  )
}

///|
async test "query_errors_on_invalid_symbols" {
  guard get_language("javascript") is Some(language) else { return }
  assert_eq(
    query_error(language, "\">>>>\""),
    @treesitter.QueryError(
      row=0,
      offset=1,
      column=1,
      kind=NodeType,
      message="\">>>>\"",
    ),
  )
  assert_eq(
    query_error(language, "\"te\\\"st\""),
    @treesitter.QueryError(
      row=0,
      offset=1,
      column=1,
      kind=NodeType,
      message="\"te\\\"st\"",
    ),
  )
  assert_eq(
    query_error(language, "\"\\\\\" @cap"),
    @treesitter.QueryError(
      row=0,
      offset=1,
      column=1,
      kind=NodeType,
      message="\"\\\\\"",
    ),
  )
  assert_eq(
    query_error(language, "(clas)"),
    @treesitter.QueryError(
      row=0,
      offset=1,
      column=1,
      kind=NodeType,
      message="\"clas\"",
    ),
  )
  assert_eq(
    query_error(language, "(if_statement (arrayyyyy))"),
    @treesitter.QueryError(
      row=0,
      offset=15,
      column=15,
      kind=NodeType,
      message="\"arrayyyyy\"",
    ),
  )
  assert_eq(
    query_error(language, "(if_statement condition: (non_existent3))"),
    @treesitter.QueryError(
      row=0,
      offset=26,
      column=26,
      kind=NodeType,
      message="\"non_existent3\"",
    ),
  )
  assert_eq(
    query_error(language, "(if_statement condit: (identifier))"),
    @treesitter.QueryError(
      row=0,
      offset=14,
      column=14,
      kind=Field,
      message="\"condit\"",
    ),
  )
  assert_eq(
    query_error(language, "(if_statement conditioning: (identifier))"),
    @treesitter.QueryError(
      row=0,
      offset=14,
      column=14,
      kind=Field,
      message="\"conditioning\"",
    ),
  )
  assert_eq(
    query_error(language, "(if_statement !alternativ)"),
    @treesitter.QueryError(
      row=0,
      offset=15,
      column=15,
      kind=Field,
      message="\"alternativ\"",
    ),
  )
  assert_eq(
    query_error(language, "(if_statement !alternatives)"),
    @treesitter.QueryError(
      row=0,
      offset=15,
      column=15,
      kind=Field,
      message="\"alternatives\"",
    ),
  )
  assert_eq(
    query_error(language, "fakefield: (identifier)"),
    @treesitter.QueryError(
      row=0,
      offset=0,
      column=0,
      kind=Field,
      message="\"fakefield\"",
    ),
  )
  assert_eq(
    query_error(language, "(ERR)"),
    @treesitter.QueryError(row=0, offset=1, column=1, kind=NodeType, message="\"ERR\""),
  )
  assert_eq(
    query_error(language, "(MISS)"),
    @treesitter.QueryError(
      row=0,
      offset=1,
      column=1,
      kind=NodeType,
      message="\"MISS\"",
    ),
  )
}

///|
async test "query_errors_on_invalid_predicates" {
  guard get_language("javascript") is Some(language) else { return }
  assert_eq(
    query_error(language, "((identifier) @id (@id))"),
    @treesitter.QueryError(
      kind=Syntax,
      row=0,
      column=19,
      offset=19,
      message=["((identifier) @id (@id))", "                   ^"].join("\n"),
    ),
  )
  assert_eq(
    query_error(language, "((identifier) @id (#eq? @id))"),
    @treesitter.QueryError(
      kind=Predicate,
      row=0,
      column=0,
      offset=0,
      message="Wrong number of arguments to #eq? predicate. Expected 2, got 1.",
    ),
  )
  assert_eq(
    query_error(language, "((identifier) @id (#eq? @id @ok))"),
    @treesitter.QueryError(kind=Capture, row=0, column=29, offset=29, message="\"ok\""),
  )
}

///|
async test "query_errors_on_impossible_patterns" {
  guard get_language("javascript") is Some(js_lang) else { return }
  guard get_language("ruby") is Some(rb_lang) else { return }
  assert_eq(
    query_error(
      js_lang, "(binary_expression left: (expression (identifier)) left: (expression (identifier)))",
    ),
    @treesitter.QueryError(
      kind=Structure,
      row=0,
      offset=37,
      column=37,
      message=[
        "(binary_expression left: (expression (identifier)) left: (expression (identifier)))",
        "                                     ^",
      ].join("\n"),
    ),
  )
  ignore(
    @treesitter.Query::new(
      js_lang, "(function_declaration name: (identifier) (statement_block))",
    ),
  )
  assert_eq(
    query_error(js_lang, "(function_declaration name: (statement_block))"),
    @treesitter.QueryError(
      kind=Structure,
      row=0,
      offset=22,
      column=22,
      message=[
        "(function_declaration name: (statement_block))", "                      ^",
      ].join("\n"),
    ),
  )
  ignore(@treesitter.Query::new(rb_lang, "(call receiver:(call))"))
  assert_eq(
    query_error(rb_lang, "(call receiver:(binary))"),
    @treesitter.QueryError(
      kind=Structure,
      row=0,
      offset=6,
      column=6,
      message=["(call receiver:(binary))", "      ^"].join("\n"),
    ),
  )
  ignore(
    @treesitter.Query::new(
      js_lang,
      (
        #|[
        #|                (function_expression (identifier))
        #|                (function_declaration (identifier))
        #|                (generator_function_declaration (identifier))
        #|            ]
      ),
    ),
  )
  assert_eq(
    query_error(
      js_lang,
      (
        #|[
        #|                    (function_expression (identifier))
        #|                    (function_declaration (object))
        #|                    (generator_function_declaration (identifier))
        #|                ]
      ),
    ),
    @treesitter.QueryError(
      kind=Structure,
      row=2,
      offset=99,
      column=42,
      message=[
        "                    (function_declaration (object))", "                                          ^",
      ].join("\n"),
    ),
  )
  assert_eq(
    query_error(js_lang, "(identifier (identifier))"),
    @treesitter.QueryError(
      kind=Structure,
      row=0,
      offset=12,
      column=12,
      message=["(identifier (identifier))", "            ^"].join("\n"),
    ),
  )
  assert_eq(
    query_error(js_lang, "(true (true))"),
    @treesitter.QueryError(
      kind=Structure,
      row=0,
      offset=6,
      column=6,
      message=["(true (true))", "      ^"].join("\n"),
    ),
  )
  ignore(
    @treesitter.Query::new(
      js_lang,
      (
        #|(if_statement
        #|                condition: (parenthesized_expression (expression) @cond))
      ),
    ),
  )
  assert_eq(
    query_error(js_lang, "(if_statement condition: (expression))"),
    @treesitter.QueryError(
      kind=Structure,
      row=0,
      offset=14,
      column=14,
      message=["(if_statement condition: (expression))", "              ^"].join(
        "\n",
      ),
    ),
  )
  assert_eq(
    query_error(js_lang, "(identifier/identifier)"),
    @treesitter.QueryError(
      row=0,
      offset=0,
      column=0,
      kind=Structure,
      message=["(identifier/identifier)", "^"].join("\n"),
    ),
  )
  if js_lang.abi_version() >= 15 {
    assert_eq(
      query_error(js_lang, "(statement/identifier)"),
      @treesitter.QueryError(
        row=0,
        offset=0,
        column=0,
        kind=Structure,
        message=["(statement/identifier)", "^"].join("\n"),
      ),
    )
    assert_eq(
      query_error(js_lang, "(statement/pattern)"),
      @treesitter.QueryError(
        row=0,
        offset=0,
        column=0,
        kind=Structure,
        message=["(statement/pattern)", "^"].join("\n"),
      ),
    )
  }
}

///|
async test "query_verifies_possible_patterns_with_aliased_parent_nodes" {
  guard get_language("ruby") is Some(language) else { return }
  ignore(@treesitter.Query::new(language, "(destructured_parameter (identifier))"))
  assert_eq(
    query_error(language, "(destructured_parameter (string))"),
    @treesitter.QueryError(
      kind=Structure,
      row=0,
      offset=24,
      column=24,
      message=["(destructured_parameter (string))", "                        ^"].join(
        "\n",
      ),
    ),
  )
}

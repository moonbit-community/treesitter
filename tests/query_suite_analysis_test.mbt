// Port of tree-sitter crates/cli/src/tests/query_test.rs (lines 4865-5941).

///|
/// `split_ascii_whitespace().collect::<Vec<_>>().join(" ")`, used in the
/// assertion messages.
fn m4_squash_whitespace(s : String) -> String {
  let words = []
  let word = StringBuilder()
  for c in s {
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\u{0c}' {
      if word.to_string() != "" {
        words.push(word.to_string())
        word.reset()
      }
    } else {
      word.write_char(c)
    }
  }
  if word.to_string() != "" {
    words.push(word.to_string())
  }
  words.join(" ")
}

///|
/// Whether the row described by `description` is excluded by
/// `TREE_SITTER_TEST_EXAMPLE_FILTER`.
fn m4_filtered_out(description : String) -> Bool {
  match example_filter() {
    Some(filter) => !description.contains(filter)
    None => false
  }
}

///|
priv struct M4GuaranteedRow {
  language : @treesitter.Language
  description : String
  pattern : String
  results_by_substring : Array[(String, Bool)]
}

///|
async test "query_is_pattern_guaranteed_at_step" {
  guard get_language("python") is Some(python) else { return }
  guard get_language("javascript") is Some(javascript) else { return }
  guard get_language("json") is Some(json) else { return }
  guard get_language("ruby") is Some(ruby) else { return }
  guard get_language("java") is Some(java) else { return }
  let rows : Array[M4GuaranteedRow] = [
    {
      description: "no guaranteed steps",
      language: python,
      pattern: "(expression_statement (string))",
      results_by_substring: [("expression_statement", false), ("string", false)],
    },
    {
      description: "all guaranteed steps",
      language: javascript,
      pattern: "(object \"{\" \"}\")",
      results_by_substring: [("object", false), ("{", true), ("}", true)],
    },
    {
      description: "a fallible step that is optional",
      language: javascript,
      pattern: "(object \"{\" (identifier)? @foo \"}\")",
      results_by_substring: [
        ("object", false),
        ("{", true),
        ("(identifier)?", false),
        ("}", true),
      ],
    },
    {
      description: "multiple fallible steps that are optional",
      language: javascript,
      pattern: "(object \"{\" (identifier)? @id1 (\",\" (identifier) @id2)? \"}\")",
      results_by_substring: [
        ("object", false),
        ("{", true),
        ("(identifier)? @id1", false),
        ("\",\"", false),
        ("}", true),
      ],
    },
    {
      description: "guaranteed step after fallibe step",
      language: javascript,
      pattern: "(pair (property_identifier) \":\")",
      results_by_substring: [
        ("pair", false),
        ("property_identifier", false),
        (":", true),
      ],
    },
    {
      description: "fallible step in between two guaranteed steps",
      language: javascript,
      pattern: (
        #|(ternary_expression
        #|                condition: (_)
        #|                "?"
        #|                consequence: (call_expression)
        #|                ":"
        #|                alternative: (_))
      ),
      results_by_substring: [
        ("condition:", false),
        ("\"?\"", false),
        ("consequence:", false),
        ("\":\"", true),
        ("alternative:", true),
      ],
    },
    {
      description: "one guaranteed step after a repetition",
      language: javascript,
      pattern: "(object \"{\" (_) \"}\")",
      results_by_substring: [
        ("object", false),
        ("{", false),
        ("(_)", false),
        ("}", true),
      ],
    },
    {
      description: "guaranteed steps after multiple repetitions",
      language: json,
      pattern: "(object \"{\" (pair) \",\" (pair) \",\" (_) \"}\")",
      results_by_substring: [
        ("object", false),
        ("{", false),
        ("(pair) \",\" (pair)", false),
        ("(pair) \",\" (_)", false),
        ("\",\" (_)", false),
        ("(_)", true),
        ("}", true),
      ],
    },
    {
      description: "a guaranteed step with a field",
      language: javascript,
      pattern: "(binary_expression left: (expression) right: (_))",
      results_by_substring: [
        ("binary_expression", false),
        ("(expression)", false),
        ("(_)", true),
      ],
    },
    {
      description: "multiple guaranteed steps with fields",
      language: javascript,
      pattern: "(function_declaration name: (identifier) body: (statement_block))",
      results_by_substring: [
        ("function_declaration", false),
        ("identifier", true),
        ("statement_block", true),
      ],
    },
    {
      description: "nesting, one guaranteed step",
      language: javascript,
      pattern: (
        #|
        #|                (function_declaration
        #|                    name: (identifier)
        #|                    body: (statement_block "{" (expression_statement) "}"))
      ),
      results_by_substring: [
        ("function_declaration", false),
        ("identifier", false),
        ("statement_block", false),
        ("{", false),
        ("expression_statement", false),
        ("}", true),
      ],
    },
    {
      description: "a guaranteed step after some deeply nested hidden nodes",
      language: ruby,
      pattern: (
        #|
        #|            (singleton_class
        #|                value: (constant)
        #|                "end")
        #|            
      ),
      results_by_substring: [
        ("singleton_class", false),
        ("constant", false),
        ("end", true),
      ],
    },
    {
      description: "nesting, no guaranteed steps",
      language: javascript,
      pattern: (
        #|
        #|            (call_expression
        #|                function: (member_expression
        #|                  property: (property_identifier) @template-tag)
        #|                arguments: (template_string)) @template-call
        #|            
      ),
      results_by_substring: [
        ("property_identifier", false),
        ("template_string", false),
      ],
    },
    {
      description: "a guaranteed step after a nested node",
      language: javascript,
      pattern: (
        #|
        #|            (subscript_expression
        #|                object: (member_expression
        #|                    object: (identifier) @obj
        #|                    property: (property_identifier) @prop)
        #|                "[")
        #|            
      ),
      results_by_substring: [
        ("identifier", false),
        ("property_identifier", false),
        ("[", true),
      ],
    },
    {
      description: "a step that is fallible due to a predicate",
      language: javascript,
      pattern: (
        #|
        #|            (subscript_expression
        #|                object: (member_expression
        #|                    object: (identifier) @obj
        #|                    property: (property_identifier) @prop)
        #|                "["
        #|                (#match? @prop "foo"))
        #|            
      ),
      results_by_substring: [
        ("identifier", false),
        ("property_identifier", false),
        ("[", true),
      ],
    },
    {
      description: "alternation where one branch has guaranteed steps",
      language: javascript,
      pattern: (
        #|
        #|            [
        #|                (unary_expression (identifier))
        #|                (call_expression
        #|                  function: (_)
        #|                  arguments: (_))
        #|                (binary_expression right: (call_expression))
        #|            ]
        #|            
      ),
      results_by_substring: [
        ("identifier", false),
        ("right:", false),
        ("function:", true),
        ("arguments:", true),
      ],
    },
    {
      description: "guaranteed step at the end of an aliased parent node",
      language: ruby,
      pattern: (
        #|
        #|            (method_parameters "(" (identifier) @id")")
        #|            
      ),
      results_by_substring: [
        ("\"(\"", false),
        ("(identifier)", false),
        ("\")\"", true),
      ],
    },
    {
      description: "long, but not too long to analyze",
      language: javascript,
      pattern: (
        #|
        #|            (object "{" (pair) (pair) (pair) (pair) "}")
        #|            
      ),
      results_by_substring: [
        ("\"{\"", false),
        ("(pair)", false),
        ("(pair) \"}\"", false),
        ("\"}\"", true),
      ],
    },
    {
      description: "too long to analyze",
      language: javascript,
      pattern: (
        #|
        #|            (object "{" (pair) (pair) (pair) (pair) (pair) (pair) (pair) (pair) (pair) (pair) (pair) (pair) "}")
        #|            
      ),
      results_by_substring: [
        ("\"{\"", false),
        ("(pair)", false),
        ("(pair) \"}\"", false),
        ("\"}\"", false),
      ],
    },
    {
      description: "hidden nodes that have several fields",
      language: java,
      pattern: (
        #|
        #|            (method_declaration name: (identifier))
        #|            
      ),
      results_by_substring: [("name:", true)],
    },
    {
      description: "top-level non-terminal extra nodes",
      language: ruby,
      pattern: (
        #|
        #|            (heredoc_body
        #|                (interpolation)
        #|                (heredoc_end) @end)
        #|            
      ),
      results_by_substring: [
        ("(heredoc_body", false),
        ("(interpolation)", false),
        ("(heredoc_end)", true),
      ],
    },
    // TODO: figure out why line comments, an extra, are no longer allowed *anywhere*
    // likely culprits are the fact that it's no longer a token itself or that it uses an
    // external token
    // {
    //   description: "multiple extra nodes",
    //   language: rust,
    //   pattern: (
    //     #|
    //     #|            (call_expression
    //     #|                (line_comment) @a
    //     #|                (line_comment) @b
    //     #|                (arguments))
    //     #|
    //   ),
    //   results_by_substring: [
    //     ("(line_comment) @a", false),
    //     ("(line_comment) @b", false),
    //     ("(arguments)", true),
    //   ],
    // },
  ]
  for row in rows {
    if m4_filtered_out(row.description) {
      continue
    }
    let query = @treesitter.Query::new(row.language, row.pattern)
    for result in row.results_by_substring {
      let (substring, is_definite) = result
      guard row.pattern.find(substring) is Some(offset) else {
        fail("substring \{substring} not found")
      }
      assert_eq(
        query.is_pattern_guaranteed_at_step(offset),
        is_definite,
        msg="Description: \{row.description}, Pattern: \{Repr(m4_squash_whitespace(row.pattern))}, substring: \{Repr(substring)}, expected is_definite to be \{is_definite}",
      )
    }
  }
}

///|
priv struct M4RootedRow {
  description : String
  pattern : String
  is_rooted : Bool
}

///|
async test "query_is_pattern_rooted" {
  let rows : Array[M4RootedRow] = [
    { description: "simple token", pattern: "(identifier)", is_rooted: true, },
    {
      description: "simple non-terminal",
      pattern: "(function_definition name: (identifier))",
      is_rooted: true,
    },
    {
      description: "alternative of many tokens",
      pattern: "[\"if\" \"def\" (identifier) (comment)]",
      is_rooted: true,
    },
    {
      description: "alternative of many non-terminals",
      pattern: (
        #|[
        #|                (function_definition name: (identifier))
        #|                (class_definition name: (identifier))
        #|                (block)
        #|            ]
      ),
      is_rooted: true,
    },
    { description: "two siblings", pattern: "(\"{\" \"}\")", is_rooted: false, },
    {
      description: "top-level repetition",
      pattern: "(comment)*",
      is_rooted: false,
    },
    {
      description: "alternative where one option has two siblings",
      pattern: (
        #|[
        #|                (block)
        #|                (class_definition)
        #|                ("(" ")")
        #|                (function_definition)
        #|            ]
      ),
      is_rooted: false,
    },
    {
      description: "alternative where one option has a top-level repetition",
      pattern: (
        #|[
        #|                (block)
        #|                (class_definition)
        #|                (comment)*
        #|                (function_definition)
        #|            ]
      ),
      is_rooted: false,
    },
  ]
  guard get_language("python") is Some(language) else { return }
  for row in rows {
    if m4_filtered_out(row.description) {
      continue
    }
    let query = @treesitter.Query::new(language, row.pattern)
    assert_eq(
      query.is_pattern_rooted(0),
      row.is_rooted,
      msg="Description: \{row.description}, Pattern: \{Repr(m4_squash_whitespace(row.pattern))}",
    )
  }
}

///|
priv struct M4NonLocalRow {
  description : String
  pattern : String
  language : @treesitter.Language
  is_non_local : Bool
}

///|
async test "query_is_pattern_non_local" {
  guard get_language("python") is Some(python) else { return }
  guard get_language("javascript") is Some(javascript) else { return }
  let rows : Array[M4NonLocalRow] = [
    {
      description: "simple token",
      pattern: "(identifier)",
      language: python,
      is_non_local: false,
    },
    {
      description: "siblings that can occur in an argument list",
      pattern: "((identifier) (identifier))",
      language: python,
      is_non_local: true,
    },
    {
      description: "siblings that can occur in a statement block",
      pattern: "((return_statement) (return_statement))",
      language: python,
      is_non_local: true,
    },
    {
      description: "siblings that can occur in a source file",
      pattern: "((function_definition) (class_definition))",
      language: python,
      is_non_local: true,
    },
    {
      description: "siblings that can't occur in any repetition",
      pattern: "(\"{\" \"}\")",
      language: python,
      is_non_local: false,
    },
    {
      description: "siblings that can't occur in any repetition, wildcard root",
      pattern: "(_ \"{\" \"}\") @foo",
      language: javascript,
      is_non_local: false,
    },
    {
      description: "siblings that can occur in a class body, wildcard root",
      pattern: "(_ (method_definition) (method_definition)) @foo",
      language: javascript,
      is_non_local: true,
    },
    {
      description: "top-level repetitions that can occur in a class body",
      pattern: "(method_definition)+ @foo",
      language: javascript,
      is_non_local: true,
    },
    {
      description: "top-level repetitions that can occur in a statement block",
      pattern: "(return_statement)+ @foo",
      language: javascript,
      is_non_local: true,
    },
    {
      description: "rooted pattern that can occur in a statement block",
      pattern: "(return_statement) @foo",
      language: javascript,
      is_non_local: false,
    },
  ]
  for row in rows {
    if m4_filtered_out(row.description) {
      continue
    }
    let query = @treesitter.Query::new(row.language, row.pattern)
    assert_eq(
      query.is_pattern_non_local(0),
      row.is_non_local,
      msg="Description: \{row.description}, Pattern: \{Repr(m4_squash_whitespace(row.pattern))}",
    )
  }
}

///|
priv struct M4QuantifierRow {
  description : String
  language : @treesitter.Language
  pattern : String
  capture_quantifiers : Array[(Int32, String, @treesitter.CaptureQuantifier)]
}

///|
async test "capture_quantifiers" {
  guard get_language("python") is Some(python) else { return }
  guard get_language("javascript") is Some(javascript) else { return }
  let rows : Array[M4QuantifierRow] = [
    // Simple quantifiers
    {
      description: "Top level capture",
      language: python,
      pattern: (
        #|
        #|                (module) @mod
        #|            
      ),
      capture_quantifiers: [(0, "mod", One)],
    },
    {
      description: "Nested list capture capture",
      language: javascript,
      pattern: (
        #|
        #|                (array (_)* @elems) @array
        #|            
      ),
      capture_quantifiers: [(0, "array", One), (0, "elems", ZeroOrMore)],
    },
    {
      description: "Nested non-empty list capture capture",
      language: javascript,
      pattern: (
        #|
        #|                (array (_)+ @elems) @array
        #|            
      ),
      capture_quantifiers: [(0, "array", One), (0, "elems", OneOrMore)],
    },
    // Nested quantifiers
    {
      description: "capture nested in optional pattern",
      language: javascript,
      pattern: (
        #|
        #|                (array (call_expression (arguments (_) @arg))? @call) @array
        #|            
      ),
      capture_quantifiers: [
        (0, "array", One),
        (0, "call", ZeroOrOne),
        (0, "arg", ZeroOrOne),
      ],
    },
    {
      description: "optional capture nested in non-empty list pattern",
      language: javascript,
      pattern: (
        #|
        #|                (array (call_expression (arguments (_)? @arg))+ @call) @array
        #|            
      ),
      capture_quantifiers: [
        (0, "array", One),
        (0, "call", OneOrMore),
        (0, "arg", ZeroOrMore),
      ],
    },
    {
      description: "non-empty list capture nested in optional pattern",
      language: javascript,
      pattern: (
        #|
        #|                (array (call_expression (arguments (_)+ @args))? @call) @array
        #|            
      ),
      capture_quantifiers: [
        (0, "array", One),
        (0, "call", ZeroOrOne),
        (0, "args", ZeroOrMore),
      ],
    },
    // Quantifiers in alternations
    {
      description: "capture is the same in all alternatives",
      language: javascript,
      pattern: (
        #|[
        #|                (function_declaration name:(identifier) @name)
        #|                (call_expression function:(identifier) @name)
        #|            ]
      ),
      capture_quantifiers: [(0, "name", One)],
    },
    {
      description: "capture appears in some alternatives",
      language: javascript,
      pattern: (
        #|[
        #|                (function_declaration name:(identifier) @name)
        #|                (function_expression)
        #|            ] @fun
      ),
      capture_quantifiers: [(0, "fun", One), (0, "name", ZeroOrOne)],
    },
    {
      description: "capture has different quantifiers in alternatives",
      language: javascript,
      pattern: (
        #|[
        #|                (call_expression arguments: (arguments (_)+ @args))
        #|                (new_expression  arguments: (arguments (_)? @args))
        #|            ] @call
      ),
      capture_quantifiers: [(0, "call", One), (0, "args", ZeroOrMore)],
    },
    // Quantifiers in siblings
    {
      description: "siblings have different captures with different quantifiers",
      language: javascript,
      pattern: (
        #|
        #|                (call_expression (arguments (identifier)? @self (_)* @args)) @call
        #|            
      ),
      capture_quantifiers: [
        (0, "call", One),
        (0, "self", ZeroOrOne),
        (0, "args", ZeroOrMore),
      ],
    },
    {
      description: "siblings have same capture with different quantifiers",
      language: javascript,
      pattern: (
        #|
        #|                (call_expression (arguments (identifier) @args (_)* @args)) @call
        #|            
      ),
      capture_quantifiers: [(0, "call", One), (0, "args", OneOrMore)],
    },
    // Combined scenarios
    {
      description: "combined nesting, alternatives, and siblings",
      language: javascript,
      pattern: (
        #|
        #|                (array
        #|                    (call_expression
        #|                        (arguments [
        #|                            (identifier) @self
        #|                            (_)+ @args
        #|                        ])
        #|                    )+ @call
        #|                ) @array
        #|            
      ),
      capture_quantifiers: [
        (0, "array", One),
        (0, "call", OneOrMore),
        (0, "self", ZeroOrMore),
        (0, "args", ZeroOrMore),
      ],
    },
    // Multiple patterns
    {
      description: "multiple patterns",
      language: javascript,
      pattern: (
        #|
        #|                (function_declaration name: (identifier) @x)
        #|                (statement_identifier) @y
        #|                (property_identifier)+ @z
        #|                (array (identifier)* @x)
        #|            
      ),
      capture_quantifiers: [
        // x
        (0, "x", One),
        (1, "x", Zero),
        (2, "x", Zero),
        (3, "x", ZeroOrMore),
        // y
        (0, "y", Zero),
        (1, "y", One),
        (2, "y", Zero),
        (3, "y", Zero),
        // z
        (0, "z", Zero),
        (1, "z", Zero),
        (2, "z", OneOrMore),
        (3, "z", Zero),
      ],
    },
    {
      description: "multiple alternatives",
      language: javascript,
      pattern: (
        #|
        #|            [
        #|                (array (identifier) @x)
        #|                (function_declaration name: (identifier)+ @x)
        #|            ]
        #|            [
        #|                (array (identifier) @x)
        #|                (function_declaration name: (identifier)+ @x)
        #|            ]
        #|            
      ),
      capture_quantifiers: [(0, "x", OneOrMore), (1, "x", OneOrMore)],
    },
  ]
  for row in rows {
    if m4_filtered_out(row.description) {
      continue
    }
    let query = @treesitter.Query::new(row.language, row.pattern)
    for expected in row.capture_quantifiers {
      let (pattern, capture, expected_quantifier) = expected
      guard query.capture_index_for_name(capture) is Some(index) else {
        fail("no capture named \{capture}")
      }
      let actual_quantifier = query.capture_quantifiers(pattern)[index]
      assert_eq(
        actual_quantifier,
        expected_quantifier,
        msg="Description: \{row.description}, Pattern: \{Repr(m4_squash_whitespace(row.pattern))}, expected quantifier of @\{capture} to be \{Repr(expected_quantifier)} instead of \{Repr(actual_quantifier)}",
      )
    }
  }
}

///|
priv struct M4QuantifiedCapturesRow {
  description : String
  language : @treesitter.Language
  code : String
  pattern : String
  captures : Array[(String, String)]
}

///|
async test "query_quantified_captures" {
  guard get_parsing_language("c") is Some(c) else { return }
  let rows : Array[M4QuantifiedCapturesRow] = [
    {
      description: "doc comments where all must match the prefix",
      language: c,
      code: indoc(
        (
          #|
          #|            /// foo
          #|            /// bar
          #|            /// baz
          #|
          #|            void main() {}
          #|
          #|            /// qux
          #|            /// quux
          #|            // quuz
          #|        
        ),
      ),
      pattern: (
        #|
        #|                ((comment)+ @comment.documentation
        #|                  (#match? @comment.documentation "^///"))
        #|            
      ),
      captures: [
        ("comment.documentation", "/// foo"),
        ("comment.documentation", "/// bar"),
        ("comment.documentation", "/// baz"),
      ],
    },
    {
      description: "doc comments where one must match the prefix",
      language: c,
      code: indoc(
        (
          #|
          #|            /// foo
          #|            /// bar
          #|            /// baz
          #|
          #|            void main() {}
          #|
          #|            /// qux
          #|            /// quux
          #|            // quuz
          #|        
        ),
      ),
      pattern: (
        #|
        #|                ((comment)+ @comment.documentation
        #|                  (#any-match? @comment.documentation "^///"))
        #|            
      ),
      captures: [
        ("comment.documentation", "/// foo"),
        ("comment.documentation", "/// bar"),
        ("comment.documentation", "/// baz"),
        ("comment.documentation", "/// qux"),
        ("comment.documentation", "/// quux"),
        ("comment.documentation", "// quuz"),
      ],
    },
    {
      description: "multiple quantifiers should not hang query parsing",
      language: c,
      code: indoc(
        (
          #|
          #|            // foo
          #|            // bar
          #|            // baz
          #|        
        ),
      ),
      pattern: (
        #|
        #|                ((comment) ?+ @comment)
        #|            
      ),
      // This should be identical to the `*` quantifier.
      captures: [
        ("comment", "// foo"),
        ("comment", "// foo"),
        ("comment", "// foo"),
        ("comment", "// bar"),
        ("comment", "// baz"),
      ],
    },
  ]
  for row in rows {
    let parser = @treesitter.Parser::new()
    parser.set_language(row.language)
    let tree = parse(parser, row.code)
    let query = @treesitter.Query::new(row.language, row.pattern)
    let cursor = @treesitter.QueryCursor::new()
    let matches = cursor.captures(query, tree.root_node(), utf8(row.code))
    assert_eq(
      collect_captures(matches, query, row.code),
      row.captures,
      msg="quantified query example: \{Repr(row.description)}",
    )
  }
}

///|
priv struct M4MaxStartDepthRow {
  description : String
  pattern : String
  depth : Int32
  matches : Array[(Int32, Array[(String, String)])]
}

///|
async test "query_max_start_depth" {
  let source = indoc(
    (
      #|
      #|        if (a1 && a2) {
      #|            if (b1 && b2) { }
      #|            if (c) { }
      #|        }
      #|        if (d) {
      #|            if (e1 && e2) { }
      #|            if (f) { }
      #|        }
      #|    
    ),
  )
  let rows : Array[M4MaxStartDepthRow] = [
    {
      description: "depth 0: match translation unit",
      depth: 0,
      pattern: (
        #|
        #|                (translation_unit) @capture
        #|            
      ),
      matches: [
        (
          0,
          [
            (
              "capture", "if (a1 && a2) {\n    if (b1 && b2) { }\n    if (c) { }\n}\nif (d) {\n    if (e1 && e2) { }\n    if (f) { }\n}\n",
            ),
          ],
        ),
      ],
    },
    {
      description: "depth 0: match none",
      depth: 0,
      pattern: (
        #|
        #|                (if_statement) @capture
        #|            
      ),
      matches: [],
    },
    {
      description: "depth 1: match 2 if statements at the top level",
      depth: 1,
      pattern: (
        #|
        #|                (if_statement) @capture
        #|            
      ),
      matches: [
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
    },
    {
      description: "depth 1 with deep pattern: match the only the first if statement",
      depth: 1,
      pattern: (
        #|
        #|                (if_statement
        #|                    condition: (parenthesized_expression
        #|                        (binary_expression)
        #|                    )
        #|                ) @capture
        #|            
      ),
      matches: [
        (
          0,
          [
            (
              "capture", "if (a1 && a2) {\n    if (b1 && b2) { }\n    if (c) { }\n}",
            ),
          ],
        ),
      ],
    },
    {
      description: "depth 3 with deep pattern: match all if statements with a binexpr condition",
      depth: 3,
      pattern: (
        #|
        #|                (if_statement
        #|                    condition: (parenthesized_expression
        #|                        (binary_expression)
        #|                    )
        #|                ) @capture
        #|            
      ),
      matches: [
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
    },
  ]
  guard get_parsing_language("c") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  for row in rows {
    let query = @treesitter.Query::new(language, row.pattern)
    ignore(cursor.set_max_start_depth(Some(row.depth)))
    let matches = cursor.matches(query, tree.root_node(), utf8(source))
    let expected = row.matches.map(x => (x.0, x.1.copy()))
    assert_eq(
      collect_matches(matches, query, source),
      expected,
      msg="query example: \{Repr(row.description)}",
    )
  }
}

///|
async test "query_error_does_not_oob" {
  guard get_language("javascript") is Some(language) else { return }
  assert_eq(
    query_error(language, "(clas"),
    QueryError(row=0, offset=1, column=1, kind=NodeType, message="\"clas\""),
  )
}

///|
async test "consecutive_zero_or_modifiers" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let zero_source = ""
  let three_source = "/**/ /**/ /**/"
  let zero_tree = parse(parser, zero_source)
  let three_tree = parse(parser, three_source)
  let tests = [
    "(comment)*** @capture", "(comment)??? @capture", "(comment)*?* @capture", "(comment)?*? @capture",
  ]
  for test_ in tests {
    let query = @treesitter.Query::new(language, test_)
    let cursor = @treesitter.QueryCursor::new()
    let matches = cursor.matches(
      query,
      zero_tree.root_node(),
      utf8(zero_source),
    )
    assert_true(matches.next() is Some(_))
    let cursor = @treesitter.QueryCursor::new()
    let matches = cursor.matches(
      query,
      three_tree.root_node(),
      utf8(three_source),
    )
    let mut len_3 = false
    let mut len_1 = false
    while matches.next() is Some(m) {
      if m.captures().length() == 3 {
        len_3 = true
      }
      if m.captures().length() == 1 {
        len_1 = true
      }
    }
    assert_eq(len_3, test_.contains("*"))
    assert_eq(len_1, test_.contains("???"))
  }
}

///|
priv struct M4MaxStartDepthMoreRow {
  depth : Int32
  matches : Array[(Int32, Array[(String, String)])]
}

///|
async test "query_max_start_depth_more" {
  let source = indoc(
    (
      #|
      #|        {
      #|            { }
      #|            {
      #|                { }
      #|            }
      #|        }
      #|    
    ),
  )
  let rows : Array[M4MaxStartDepthMoreRow] = [
    {
      depth: 0,
      matches: [(0, [("capture", "{\n    { }\n    {\n        { }\n    }\n}")])],
    },
    {
      depth: 1,
      matches: [
        (0, [("capture", "{\n    { }\n    {\n        { }\n    }\n}")]),
        (0, [("capture", "{ }")]),
        (0, [("capture", "{\n        { }\n    }")]),
      ],
    },
    {
      depth: 2,
      matches: [
        (0, [("capture", "{\n    { }\n    {\n        { }\n    }\n}")]),
        (0, [("capture", "{ }")]),
        (0, [("capture", "{\n        { }\n    }")]),
        (0, [("capture", "{ }")]),
      ],
    },
  ]
  guard get_parsing_language("c") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  let query = @treesitter.Query::new(language, "(compound_statement) @capture")
  let matches = cursor.matches(query, tree.root_node(), utf8(source))
  guard matches.next() is Some(first) else { fail("expected a match") }
  let node = first.captures()[0].node
  assert_eq(node.kind(), "compound_statement")
  for row in rows {
    ignore(cursor.set_max_start_depth(Some(row.depth)))
    let matches = cursor.matches(query, node, utf8(source))
    let expected = row.matches.map(x => (x.0, x.1.copy()))
    assert_eq(collect_matches(matches, query, source), expected)
  }
}

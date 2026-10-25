// Port of tree-sitter crates/cli/src/tests/query_test.rs (lines 2159-3596).

///|
async test "query_matches_with_simple_alternatives" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            (pair
      #|                key: [(property_identifier) (string)] @key
      #|                value: [(function_expression) @val1 (arrow_function) @val2])
      #|            
    ),
  )
  assert_query_matches(
    language,
    query,
    (
      #|
      #|            a = {
      #|                b: c,
      #|                'd': e => f,
      #|                g: {
      #|                    h: function i() {},
      #|                    'x': null,
      #|                    j: _ => k
      #|                },
      #|                'l': function m() {},
      #|            };
      #|            
    ),
    [
      (0, [("key", "'d'"), ("val2", "e => f")]),
      (0, [("key", "h"), ("val1", "function i() {}")]),
      (0, [("key", "j"), ("val2", "_ => k")]),
      (0, [("key", "'l'"), ("val1", "function m() {}")]),
    ],
  )
}

///|
async test "query_matches_with_alternatives_in_repetitions" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            (array
      #|                [(identifier) (string)] @el
      #|                .
      #|                (
      #|                    ","
      #|                    .
      #|                    [(identifier) (string)] @el
      #|                )*)
      #|            
    ),
  )
  assert_query_matches(
    language,
    query,
    (
      #|
      #|            a = [b, 'c', d, 1, e, 'f', 'g', h];
      #|            
    ),
    [
      (0, [("el", "b"), ("el", "'c'"), ("el", "d")]),
      (0, [("el", "e"), ("el", "'f'"), ("el", "'g'"), ("el", "h")]),
    ],
  )
}

///|
async test "query_matches_with_alternatives_at_root" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            [
      #|                "if"
      #|                "else"
      #|                "function"
      #|                "throw"
      #|                "return"
      #|            ] @keyword
      #|            
    ),
  )
  assert_query_matches(
    language,
    query,
    (
      #|
      #|            function a(b, c, d) {
      #|                if (b) {
      #|                    return c;
      #|                } else {
      #|                    throw d;
      #|                }
      #|            }
      #|            
    ),
    [
      (0, [("keyword", "function")]),
      (0, [("keyword", "if")]),
      (0, [("keyword", "return")]),
      (0, [("keyword", "else")]),
      (0, [("keyword", "throw")]),
    ],
  )
}

///|
async test "query_matches_with_alternatives_under_fields" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            (assignment_expression
      #|                left: [
      #|                    (identifier) @variable
      #|                    (member_expression property: (property_identifier) @variable)
      #|                ])
      #|            
    ),
  )
  assert_query_matches(
    language,
    query,
    (
      #|
      #|            a = b;
      #|            b = c.d;
      #|            e.f = g;
      #|            h.i = j.k;
      #|            
    ),
    [
      (0, [("variable", "a")]),
      (0, [("variable", "b")]),
      (0, [("variable", "f")]),
      (0, [("variable", "i")]),
    ],
  )
}

///|
async test "query_matches_in_language_with_simple_aliases" {
  guard get_parsing_language("html") is Some(language) else { return }

  // HTML uses different tokens to track start tags names, end
  // tag names, script tag names, and style tag names. All of
  // these tokens are aliased to `tag_name`.
  let query = @treesitter.Query::new(language, "(tag_name) @tag")
  assert_query_matches(
    language,
    query,
    (
      #|
      #|            <div>
      #|                <script>hi</script>
      #|                <style>hi</style>
      #|            </div>
      #|            
    ),
    [
      (0, [("tag", "div")]),
      (0, [("tag", "script")]),
      (0, [("tag", "script")]),
      (0, [("tag", "style")]),
      (0, [("tag", "style")]),
      (0, [("tag", "div")]),
    ],
  )
}

///|
async test "query_matches_with_different_tokens_with_the_same_string_value" {
  // In Rust, there are two '<' tokens: one for the binary operator,
  // and one with higher precedence for generics.
  guard get_parsing_language("rust") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|                "<" @less
      #|                ">" @greater
      #|                
    ),
  )
  assert_query_matches(language, query, "const A: B<C> = d < e || f > g;", [
    (0, [("less", "<")]),
    (1, [("greater", ">")]),
    (0, [("less", "<")]),
    (1, [("greater", ">")]),
  ])
}

///|
async test "query_matches_with_too_many_permutations_to_track" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            (array (identifier) @pre (identifier) @post)
      #|        
    ),
  )
  let source = "[" + "hello, ".repeat(50) + "];"
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  cursor.set_match_limit(32)
  let matches = cursor.matches(query, tree.root_node(), utf8(source))

  // For this pathological query, some match permutations will be dropped.
  // Just check that a subset of the results are returned, and no crash or
  // leak occurs.
  assert_eq(
    collect_matches(matches, query, source)[0],
    (0, [("pre", "hello"), ("post", "hello")]),
  )
  assert_true(cursor.did_exceed_match_limit())
}

///|
async test "query_sibling_patterns_dont_match_children_of_an_error" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            ("{" @open "}" @close)
      #|
      #|            [
      #|              (line_comment)
      #|              (block_comment)
      #|            ] @comment
      #|
      #|            ("<" @first "<" @second)
      #|            
    ),
  )

  // Most of the document will fail to parse, resulting in a
  // large number of tokens that are *direct* children of an
  // ERROR node.
  //
  // These children should still match, unless they are part
  // of a "non-rooted" pattern, in which there are multiple
  // top-level sibling nodes. Those patterns should not match
  // directly inside of an error node, because the contents of
  // an error node are not syntactically well-structured, so we
  // would get many spurious matches.
  let source =
    #|
    #|            fn a() {}
    #|
    #|            <<<<<<<<<< add pub b fn () {}
    #|            // comment 1
    #|            pub fn b() {
    #|            /* comment 2 */
    #|            ==========
    #|            pub fn c() {
    #|            // comment 3
    #|            >>>>>>>>>> add pub c fn () {}
    #|            }
    #|        
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  let matches = cursor.matches(query, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query, source), [
    (0, [("open", "{"), ("close", "}")]),
    (1, [("comment", "// comment 1")]),
    (1, [("comment", "/* comment 2 */")]),
    (1, [("comment", "// comment 3")]),
  ])
}

///|
async test "query_matches_with_alternatives_and_too_many_permutations_to_track" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            (
      #|                (comment) @doc
      #|                ; not immediate
      #|                (class_declaration) @class
      #|            )
      #|
      #|            (call_expression
      #|                function: [
      #|                    (identifier) @function
      #|                    (member_expression property: (property_identifier) @method)
      #|                ])
      #|            
    ),
  )
  let source = "/* hi */ a.b(); ".repeat(50)
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  cursor.set_match_limit(32)
  let matches = cursor.matches(query, tree.root_node(), utf8(source))
  assert_eq(
    collect_matches(matches, query, source),
    Array::make(50, (1, [("method", "b")])),
  )
  assert_true(cursor.did_exceed_match_limit())
}

///|
async test "repetitions_before_with_alternatives" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            (
      #|                (line_comment)* @comment
      #|                .
      #|                [
      #|                    (struct_item name: (_) @name)
      #|                    (function_item name: (_) @name)
      #|                    (enum_item name: (_) @name)
      #|                    (impl_item type: (_) @name)
      #|                ]
      #|            )
      #|            
    ),
  )
  assert_query_matches(
    language,
    query,
    (
      #|
      #|            // a
      #|            // b
      #|            fn c() {}
      #|
      #|            // d
      #|            // e
      #|            impl F {}
      #|            
    ),
    [
      (0, [("comment", "// a"), ("comment", "// b"), ("name", "c")]),
      (0, [("comment", "// d"), ("comment", "// e"), ("name", "F")]),
    ],
  )
}

///|
async test "query_matches_with_anonymous_tokens" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            ";" @punctuation
      #|            "&&" @operator
      #|            "\"" @quote
      #|            
    ),
  )
  assert_query_matches(language, query, "foo(a && \"b\");", [
    (1, [("operator", "&&")]),
    (2, [("quote", "\"")]),
    (2, [("quote", "\"")]),
    (0, [("punctuation", ";")]),
  ])
}

///|
async test "query_matches_with_supertypes" {
  guard get_parsing_language("python") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            (argument_list (expression) @arg)
      #|
      #|            (keyword_argument
      #|                value: (expression) @kw_arg)
      #|
      #|            (assignment
      #|              left: (identifier) @var_def)
      #|
      #|            (primary_expression/identifier) @var_ref
      #|            
    ),
  )
  assert_query_matches(
    language,
    query,
    (
      #|
      #|                a = b.c(
      #|                    [d],
      #|                    # a comment
      #|                    e=f
      #|                )
      #|            
    ),
    [
      (2, [("var_def", "a")]),
      (3, [("var_ref", "b")]),
      (0, [("arg", "[d]")]),
      (3, [("var_ref", "d")]),
      (1, [("kw_arg", "f")]),
      (3, [("var_ref", "f")]),
    ],
  )
}

///|
async test "query_matches_within_byte_range" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(language, "(identifier) @element")
  let source = "[a, b, c, d, e, f, g]"
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  let matches = cursor
    .set_byte_range(0, 8)
    .matches(query, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query, source), [
    (0, [("element", "a")]),
    (0, [("element", "b")]),
    (0, [("element", "c")]),
  ])
  let matches = cursor
    .set_byte_range(5, 15)
    .matches(query, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query, source), [
    (0, [("element", "c")]),
    (0, [("element", "d")]),
    (0, [("element", "e")]),
  ])

  // An end byte of zero indicates there is no end
  let matches = cursor
    .set_byte_range(12, 0)
    .matches(query, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query, source), [
    (0, [("element", "e")]),
    (0, [("element", "f")]),
    (0, [("element", "g")]),
  ])
}

///|
async test "query_matches_within_point_range" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(language, "(identifier) @element")
  let source = unindent(
    (
      #|
      #|            [
      #|              a, b,
      #|              c, d,
      #|              e, f,
      #|              g, h,
      #|              i, j,
      #|              k, l,
      #|            ]
      #|        
    ),
  )
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  let matches = cursor
    .set_point_range(@treesitter.Point::new(1, 0), @treesitter.Point::new(2, 3))
    .matches(query, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query, source), [
    (0, [("element", "a")]),
    (0, [("element", "b")]),
    (0, [("element", "c")]),
  ])
  let matches = cursor
    .set_point_range(@treesitter.Point::new(2, 0), @treesitter.Point::new(3, 3))
    .matches(query, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query, source), [
    (0, [("element", "c")]),
    (0, [("element", "d")]),
    (0, [("element", "e")]),
  ])

  // Zero end point is treated like no end point.
  let matches = cursor
    .set_point_range(@treesitter.Point::new(4, 1), @treesitter.Point::new(0, 0))
    .matches(query, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query, source), [
    (0, [("element", "g")]),
    (0, [("element", "h")]),
    (0, [("element", "i")]),
    (0, [("element", "j")]),
    (0, [("element", "k")]),
    (0, [("element", "l")]),
  ])
}

///|
async test "query_captures_within_byte_range" {
  guard get_parsing_language("c") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            (call_expression
      #|                function: (identifier) @function
      #|                arguments: (argument_list (string_literal) @string.arg))
      #|
      #|            (string_literal) @string
      #|           
    ),
  )
  let source = "DEFUN (\"safe-length\", Fsafe_length, Ssafe_length, 1, 1, 0)"
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
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
async test "query_cursor_next_capture_with_byte_range" {
  guard get_parsing_language("python") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|(function_definition name: (identifier) @function)
      #|             (attribute attribute: (identifier) @property)
      #|             ((identifier) @variable)
    ),
  )
  let source = "def func():\n  foo.bar.baz()\n"
  //            ^            ^    ^          ^
  // byte_pos   0           12    17        27
  // point_pos (0,0)      (1,0)  (1,5)    (1,15)
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  let captures = cursor
    .set_byte_range(12, 17)
    .captures(query, tree.root_node(), utf8(source))
  assert_eq(collect_captures(captures, query, source), [("variable", "foo")])
}

///|
async test "query_cursor_next_capture_with_point_range" {
  guard get_parsing_language("python") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|(function_definition name: (identifier) @function)
      #|             (attribute attribute: (identifier) @property)
      #|             ((identifier) @variable)
    ),
  )
  let source = "def func():\n  foo.bar.baz()\n"
  //            ^            ^    ^          ^
  // byte_pos   0           12    17        27
  // point_pos (0,0)      (1,0)  (1,5)    (1,15)
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  let captures = cursor
    .set_point_range(@treesitter.Point::new(1, 0), @treesitter.Point::new(1, 5))
    .captures(query, tree.root_node(), utf8(source))
  assert_eq(collect_captures(captures, query, source), [("variable", "foo")])
}

///|
async test "query_matches_with_unrooted_patterns_intersecting_byte_range" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            ("{" @left "}" @right)
      #|            ("<" @left ">" @right)
      #|            
    ),
  )
  let source = "mod a { fn a<B: C, D: E>(f: B) { g(f) } }"
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()

  // within the type parameter list
  let offset = source.find("D: E>").unwrap()
  let matches = cursor
    .set_byte_range(offset, offset)
    .matches(query, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query, source), [
    (1, [("left", "<"), ("right", ">")]),
    (0, [("left", "{"), ("right", "}")]),
  ])

  // from within the type parameter list to within the function body
  let start_offset = source.find("D: E>").unwrap()
  let end_offset = source.find("g(f)").unwrap()
  let matches = cursor
    .set_byte_range(start_offset, end_offset)
    .matches(query, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query, source), [
    (1, [("left", "<"), ("right", ">")]),
    (0, [("left", "{"), ("right", "}")]),
    (0, [("left", "{"), ("right", "}")]),
  ])
}

///|
/// The kinds of the first captures of the matches of `query` intersecting
/// the empty byte range at `offset`.
fn m2_first_capture_kinds(
  cursor : @treesitter.QueryCursor,
  query : @treesitter.Query,
  tree : @treesitter.Tree,
  source : String,
  offset : Int32,
) -> Array[String] {
  let matches = []
  let match_iter = cursor
    .set_byte_range(offset, offset)
    .matches(query, tree.root_node(), utf8(source))
  while match_iter.next() is Some(mat) {
    if mat.captures() is [capture, ..] {
      matches.push(capture.node.kind())
    }
  }
  matches
}

///|
async test "query_matches_with_wildcard_at_root_intersecting_byte_range" {
  guard get_parsing_language("python") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            [
      #|                (_ body: (block))
      #|                (_ consequence: (block))
      #|            ] @indent
      #|            
    ),
  )
  let source = (
      #|
      #|            class A:
      #|                def b():
      #|                    if c:
      #|                        d
      #|                    else:
      #|                        e
      #|        
    )
    .trim(chars=" \t\n\r")
    .to_owned()
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()

  // After the first line of the class definition
  let offset = source.find("A:").unwrap() + 2
  let matches = m2_first_capture_kinds(cursor, query, tree, source, offset)
  assert_eq(matches, ["class_definition"])

  // After the first line of the function definition
  let offset = source.find("b():").unwrap() + 4
  let matches = m2_first_capture_kinds(cursor, query, tree, source, offset)
  assert_eq(matches, ["class_definition", "function_definition"])

  // After the first line of the if statement
  let offset = source.find("c:").unwrap() + 2
  let matches = m2_first_capture_kinds(cursor, query, tree, source, offset)
  assert_eq(matches, ["class_definition", "function_definition", "if_statement"])
}

///|
async test "query_captures_within_byte_range_assigned_after_iterating" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            (function_item
      #|                name: (identifier) @fn_name)
      #|
      #|            (mod_item
      #|                name: (identifier) @mod_name
      #|                body: (declaration_list
      #|                    "{" @lbrace
      #|                    "}" @rbrace))
      #|
      #|            ; functions that return Result<()>
      #|            ((function_item
      #|                return_type: (generic_type
      #|                    type: (type_identifier) @result
      #|                    type_arguments: (type_arguments
      #|                        (unit_type)))
      #|                body: _ @fallible_fn_body)
      #|             (#eq? @result "Result"))
      #|            
    ),
  )
  let source =
    #|
    #|        mod m1 {
    #|            mod m2 {
    #|                fn f1() -> Option<()> { Some(()) }
    #|            }
    #|            fn f2() -> Result<()> { Ok(()) }
    #|            fn f3() {}
    #|        }
    #|        
  let bytes = utf8(source)
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  let captures = cursor.captures(query, tree.root_node(), bytes)

  // Retrieve some captures
  let results = []
  for _ in 0..<5 {
    guard captures.next() is Some((mat, capture_ix)) else { break }
    let capture = mat.captures()[capture_ix]
    results.push(
      (query.capture_names()[capture.index], text(capture.node, bytes)),
    )
  }
  assert_eq(results, [
    ("mod_name", "m1"),
    ("lbrace", "{"),
    ("mod_name", "m2"),
    ("lbrace", "{"),
    ("fn_name", "f1"),
  ])

  // Advance to a range that only partially intersects some matches.
  // Captures from these matches are reported, but only those that
  // intersect the range.
  results.clear()
  captures.set_byte_range(source.find("Ok").unwrap(), bytes.length())
  while captures.next() is Some((mat, capture_ix)) {
    let capture = mat.captures()[capture_ix]
    results.push(
      (query.capture_names()[capture.index], text(capture.node, bytes)),
    )
  }
  assert_eq(results, [
    ("fallible_fn_body", "{ Ok(()) }"),
    ("fn_name", "f3"),
    ("rbrace", "}"),
  ])
}

///|
async test "query_matches_within_range_of_long_repetition" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            (function_item name: (identifier) @fn-name)
      #|            
    ),
  )
  let source = unindent(
    (
      #|
      #|            fn zero() {}
      #|            fn one() {}
      #|            fn two() {}
      #|            fn three() {}
      #|            fn four() {}
      #|            fn five() {}
      #|            fn six() {}
      #|            fn seven() {}
      #|            fn eight() {}
      #|            fn nine() {}
      #|            fn ten() {}
      #|            fn eleven() {}
      #|            fn twelve() {}
      #|        
    ),
  )
  let parser = @treesitter.Parser::new()
  let cursor = @treesitter.QueryCursor::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let matches = cursor
    .set_point_range(@treesitter.Point::new(8, 0), @treesitter.Point::new(20, 0))
    .matches(query, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query, source), [
    (0, [("fn-name", "eight")]),
    (0, [("fn-name", "nine")]),
    (0, [("fn-name", "ten")]),
    (0, [("fn-name", "eleven")]),
    (0, [("fn-name", "twelve")]),
  ])
}

///|
async test "query_matches_contained_within_range" {
  guard get_parsing_language("json") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            ("[" @l_bracket "]" @r_bracket)
      #|            ("{" @l_brace "}" @r_brace)
      #|            
    ),
  )
  let source = unindent(
    (
      #|
      #|            [
      #|                {"key1": "value1"},
      #|                {"key2": "value2"},
      #|                {"key3": "value3"},
      #|                {"key4": "value4"},
      #|                {"key5": "value5"},
      #|                {"key6": "value6"},
      #|                {"key7": "value7"},
      #|                {"key8": "value8"},
      #|                {"key9": "value9"},
      #|                {"key10": "value10"},
      #|                {"key11": "value11"},
      #|                {"key12": "value12"},
      #|            ]
      #|        
    ),
  )
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let expected_matches = [
    (1, [("l_brace", "{"), ("r_brace", "}")]),
    (1, [("l_brace", "{"), ("r_brace", "}")]),
  ]
  {
    let cursor = @treesitter.QueryCursor::new()
    let matches = cursor
      .set_containing_point_range(@treesitter.Point::new(5, 0), @treesitter.Point::new(7, 0))
      .matches(query, tree.root_node(), utf8(source))
    assert_eq(collect_matches(matches, query, source), expected_matches)
  }
  let cursor = @treesitter.QueryCursor::new()
  let matches = cursor
    .set_containing_byte_range(78, 120)
    .matches(query, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query, source), expected_matches)
}

///|
async test "query_matches_different_queries_same_cursor" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query1 = @treesitter.Query::new(
    language,
    (
      #|
      #|            (array (identifier) @id1)
      #|        
    ),
  )
  let query2 = @treesitter.Query::new(
    language,
    (
      #|
      #|            (array (identifier) @id1)
      #|            (pair (identifier) @id2)
      #|        
    ),
  )
  let query3 = @treesitter.Query::new(
    language,
    (
      #|
      #|            (array (identifier) @id1)
      #|            (pair (identifier) @id2)
      #|            (parenthesized_expression (identifier) @id3)
      #|        
    ),
  )
  let source = "[a, {b: b}, (c)];"
  let parser = @treesitter.Parser::new()
  let cursor = @treesitter.QueryCursor::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let matches = cursor.matches(query1, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query1, source), [(0, [("id1", "a")])])
  let matches = cursor.matches(query3, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query3, source), [
    (0, [("id1", "a")]),
    (1, [("id2", "b")]),
    (2, [("id3", "c")]),
  ])
  let matches = cursor.matches(query2, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query2, source), [
    (0, [("id1", "a")]),
    (1, [("id2", "b")]),
  ])
}

///|
async test "query_matches_with_multiple_captures_on_a_node" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|(function_declaration
      #|                (identifier) @name1 @name2 @name3
      #|                (statement_block) @body1 @body2)
    ),
  )
  let source = "function foo() { return 1; }"
  let parser = @treesitter.Parser::new()
  let cursor = @treesitter.QueryCursor::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let matches = cursor.matches(query, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query, source), [
    (
      0,
      [
        ("name1", "foo"),
        ("name2", "foo"),
        ("name3", "foo"),
        ("body1", "{ return 1; }"),
        ("body2", "{ return 1; }"),
      ],
    ),
  ])

  // disabling captures still works when there are multiple captures on a
  // single node.
  query.disable_capture("name2")
  let matches = cursor.matches(query, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query, source), [
    (
      0,
      [
        ("name1", "foo"),
        ("name3", "foo"),
        ("body1", "{ return 1; }"),
        ("body2", "{ return 1; }"),
      ],
    ),
  ])
}

///|
async test "query_matches_with_captured_wildcard_at_root" {
  guard get_parsing_language("python") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            ; captured wildcard at the root
      #|            (_ [
      #|                (except_clause (block) @block)
      #|                (finally_clause (block) @block)
      #|            ]) @stmt
      #|
      #|            [
      #|                (while_statement (block) @block)
      #|                (if_statement (block) @block)
      #|
      #|                ; captured wildcard at the root within an alternation
      #|                (_ [
      #|                    (else_clause (block) @block)
      #|                    (elif_clause (block) @block)
      #|                ])
      #|
      #|                (try_statement (block) @block)
      #|                (for_statement (block) @block)
      #|            ] @stmt
      #|            
    ),
  )
  let source = (
      #|
      #|        for i in j:
      #|            while True:
      #|                if a:
      #|                    print b
      #|                elif c:
      #|                    print d
      #|                else:
      #|                    try:
      #|                        print f
      #|                    except:
      #|                        print g
      #|                    finally:
      #|                        print h
      #|            else:
      #|                print i
      #|        
    )
    .trim(chars=" \t\n\r")
    .to_owned()
  let parser = @treesitter.Parser::new()
  let cursor = @treesitter.QueryCursor::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let match_capture_names_and_rows = []
  let match_iter = cursor.matches(query, tree.root_node(), utf8(source))
  while match_iter.next() is Some(m) {
    let captures = m
      .captures()
      .iter()
      .map(c => {
        (
          query.capture_names()[c.index],
          c.node.kind(),
          c.node.start_position().row,
        )
      })
      .to_array()
    match_capture_names_and_rows.push(captures)
  }
  assert_eq(match_capture_names_and_rows, [
    [("stmt", "for_statement", 0), ("block", "block", 1)],
    [("stmt", "while_statement", 1), ("block", "block", 2)],
    [("stmt", "if_statement", 2), ("block", "block", 3)],
    [("stmt", "if_statement", 2), ("block", "block", 5)],
    [("stmt", "if_statement", 2), ("block", "block", 7)],
    [("stmt", "try_statement", 7), ("block", "block", 8)],
    [("stmt", "try_statement", 7), ("block", "block", 10)],
    [("stmt", "try_statement", 7), ("block", "block", 12)],
    [("stmt", "while_statement", 1), ("block", "block", 14)],
  ])
}

///|
async test "query_matches_with_no_captures" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            (identifier)
      #|            (string) @s
      #|            
    ),
  )
  assert_query_matches(
    language,
    query,
    (
      #|
      #|            a = 'hi';
      #|            b = 'bye';
      #|            
    ),
    [(0, []), (1, [("s", "'hi'")]), (0, []), (1, [("s", "'bye'")])],
  )
}

///|
async test "query_matches_with_repeated_fields" {
  guard get_parsing_language("c") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language, "(field_declaration declarator: (field_identifier) @field)",
  )
  assert_query_matches(
    language,
    query,
    (
      #|
      #|            struct S {
      #|                int a, b, c;
      #|            };
      #|            
    ),
    [(0, [("field", "a")]), (0, [("field", "b")]), (0, [("field", "c")])],
  )
}

///|
async test "query_matches_with_deeply_nested_patterns_with_fields" {
  guard get_parsing_language("python") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            (call
      #|                function: (_) @func
      #|                arguments: (_) @args)
      #|            (call
      #|                function: (attribute
      #|                    object: (_) @receiver
      #|                    attribute: (identifier) @method)
      #|                arguments: (argument_list))
      #|
      #|            ; These don't match anything, but they require additional
      #|            ; states to keep track of their captures.
      #|            (call
      #|                function: (_) @fn
      #|                arguments: (argument_list
      #|                    (keyword_argument
      #|                        name: (identifier) @name
      #|                        value: (_) @val) @arg) @args) @call
      #|            (call
      #|                function: (identifier) @fn
      #|                (#eq? @fn "super")) @super_call
      #|            
    ),
  )
  assert_query_matches(
    language,
    query,
    (
      #|
      #|            a(1).b(2).c(3).d(4).e(5).f(6).g(7).h(8)
      #|            
    ),
    [
      (0, [("func", "a"), ("args", "(1)")]),
      (0, [("func", "a(1).b"), ("args", "(2)")]),
      (1, [("receiver", "a(1)"), ("method", "b")]),
      (0, [("func", "a(1).b(2).c"), ("args", "(3)")]),
      (1, [("receiver", "a(1).b(2)"), ("method", "c")]),
      (0, [("func", "a(1).b(2).c(3).d"), ("args", "(4)")]),
      (1, [("receiver", "a(1).b(2).c(3)"), ("method", "d")]),
      (0, [("func", "a(1).b(2).c(3).d(4).e"), ("args", "(5)")]),
      (1, [("receiver", "a(1).b(2).c(3).d(4)"), ("method", "e")]),
      (0, [("func", "a(1).b(2).c(3).d(4).e(5).f"), ("args", "(6)")]),
      (1, [("receiver", "a(1).b(2).c(3).d(4).e(5)"), ("method", "f")]),
      (0, [("func", "a(1).b(2).c(3).d(4).e(5).f(6).g"), ("args", "(7)")]),
      (1, [("receiver", "a(1).b(2).c(3).d(4).e(5).f(6)"), ("method", "g")]),
      (0, [("func", "a(1).b(2).c(3).d(4).e(5).f(6).g(7).h"), ("args", "(8)")]),
      (1, [("receiver", "a(1).b(2).c(3).d(4).e(5).f(6).g(7)"), ("method", "h")]),
    ],
  )
}

///|
async test "query_alternation_with_inner_quantifier" {
  guard get_parsing_language("c") is Some(language) else { return }
  let source_code =
    #|#include <foo>
    #|#include <bar>
    #|#include <baz>
    #|
    #|// comment
  let matches = [
    (
      0,
      [
        ("capture", "#include <foo>\n"),
        ("capture", "#include <bar>\n"),
        ("capture", "#include <baz>\n"),
      ],
    ),
    (0, [("capture", "// comment")]),
  ]
  let query =
    #|[
    #|       (preproc_include)+
    #|       (comment)
    #|    ] @capture
  let query = @treesitter.Query::new(language, query)
  assert_query_matches(language, query, source_code, matches)
  let query =
    #|[
    #|       (comment)
    #|       (preproc_include)+
    #|    ] @capture
  let query = @treesitter.Query::new(language, query)
  assert_query_matches(language, query, source_code, matches)
}

///|
async test "query_alternation_with_outer_quantifier" {
  guard get_parsing_language("c") is Some(language) else { return }
  let source_code =
    #|#include <foo>
    #|#include <bar>
    #|#include <baz>
    #|
    #|// comment
  let matches = [
    (
      0,
      [
        ("capture", "#include <foo>\n"),
        ("capture", "#include <bar>\n"),
        ("capture", "#include <baz>\n"),
        ("capture", "// comment"),
      ],
    ),
  ]
  let query =
    #|[
    #|        (preproc_include)
    #|        (comment)
    #|    ]+ @capture
  let query = @treesitter.Query::new(language, query)
  assert_query_matches(language, query, source_code, matches)
  let query =
    #|([
    #|        (preproc_include)
    #|        (comment)
    #|    ] (_)?)+ @capture
  let query = @treesitter.Query::new(language, query)
  assert_query_matches(language, query, source_code, matches)
}

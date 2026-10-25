// Port of tree-sitter crates/cli/src/tests/query_test.rs (lines 3597-4800).
// `test_query_random` (in this range) is in query_suite_random_test.mbt.

///|
async test "query_matches_with_alternations_and_predicates" {
  guard get_parsing_language("java") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            (block
      #|                [
      #|                    (local_variable_declaration
      #|                        (variable_declarator
      #|                            (identifier) @def.a
      #|                            (string_literal) @lit.a
      #|                        )
      #|                    )
      #|                    (local_variable_declaration
      #|                        (variable_declarator
      #|                            (identifier) @def.b
      #|                            (null_literal) @lit.b
      #|                        )
      #|                    )
      #|                ]
      #|                (expression_statement
      #|                    (method_invocation [
      #|                        (argument_list
      #|                            (identifier) @ref.a
      #|                            (string_literal)
      #|                        )
      #|                        (argument_list
      #|                            (null_literal)
      #|                            (identifier) @ref.b
      #|                        )
      #|                    ])
      #|                )
      #|                (#eq? @def.a @ref.a )
      #|                (#eq? @def.b @ref.b )
      #|            )
      #|            
    ),
  )
  assert_query_matches(
    language,
    query,
    (
      #|
      #|            void test() {
      #|                int a = "foo";
      #|                f(null, b);
      #|            }
      #|            
    ),
    [],
  )
}

///|
async test "query_matches_with_indefinite_step_containing_no_captures" {
  // This pattern depends on the field declarations within the
  // struct's body, but doesn't capture anything within the body.
  // It demonstrates that internally, state-splitting needs to occur
  // for each field declaration within the body, in order to avoid
  // prematurely failing if the first field does not match.
  //
  // https://github.com/tree-sitter/tree-sitter/issues/937
  guard get_parsing_language("c") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|(struct_specifier
      #|                name: (type_identifier) @name
      #|                body: (field_declaration_list
      #|                    (field_declaration
      #|                        type: (union_specifier))))
    ),
  )
  assert_query_matches(
    language,
    query,
    (
      #|
      #|            struct LacksUnionField {
      #|                int a;
      #|                struct {
      #|                    B c;
      #|                } d;
      #|                G *h;
      #|            };
      #|
      #|            struct HasUnionField {
      #|                int a;
      #|                struct {
      #|                    B c;
      #|                } d;
      #|                union {
      #|                    bool e;
      #|                    float f;
      #|                } g;
      #|                G *h;
      #|            };
      #|            
    ),
    [(0, [("name", "HasUnionField")])],
  )
}

///|
async test "query_captures_basic" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            (pair
      #|              key: _ @method.def
      #|              (function_expression
      #|                name: (identifier) @method.alias))
      #|
      #|            (variable_declarator
      #|              name: _ @function.def
      #|              value: (function_expression
      #|                name: (identifier) @function.alias))
      #|
      #|            ":" @delimiter
      #|            "=" @operator
      #|            
    ),
  )
  let source =
    #|
    #|          a({
    #|            bc: function de() {
    #|              const fg = function hi() {}
    #|            },
    #|            jk: function lm() {
    #|              const no = function pq() {}
    #|            },
    #|          });
    #|        
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  let matches = cursor.matches(query, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query, source), [
    (2, [("delimiter", ":")]),
    (0, [("method.def", "bc"), ("method.alias", "de")]),
    (3, [("operator", "=")]),
    (1, [("function.def", "fg"), ("function.alias", "hi")]),
    (2, [("delimiter", ":")]),
    (0, [("method.def", "jk"), ("method.alias", "lm")]),
    (3, [("operator", "=")]),
    (1, [("function.def", "no"), ("function.alias", "pq")]),
  ])
  let captures = cursor.captures(query, tree.root_node(), utf8(source))
  assert_eq(collect_captures(captures, query, source), [
    ("method.def", "bc"),
    ("delimiter", ":"),
    ("method.alias", "de"),
    ("function.def", "fg"),
    ("operator", "="),
    ("function.alias", "hi"),
    ("method.def", "jk"),
    ("delimiter", ":"),
    ("method.alias", "lm"),
    ("function.def", "no"),
    ("operator", "="),
    ("function.alias", "pq"),
  ])
}

///|
async test "query_captures_with_text_conditions" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            ((identifier) @constant
      #|             (#match? @constant "^[A-Z]{2,}$"))
      #|
      #|             ((identifier) @constructor
      #|              (#match? @constructor "^[A-Z]"))
      #|
      #|            ((identifier) @function.builtin
      #|             (#eq? @function.builtin "require"))
      #|
      #|            ((identifier) @variable.builtin
      #|              (#any-of? @variable.builtin
      #|                        "arguments"
      #|                        "module"
      #|                        "console"
      #|                        "window"
      #|                        "document"))
      #|
      #|            ((identifier) @variable
      #|             (#not-match? @variable "^(lambda|load)$"))
      #|            
    ),
  )
  let source =
    #|
    #|          toad
    #|          load
    #|          panda
    #|          lambda
    #|          const ab = require('./ab');
    #|          new Cd(EF);
    #|          document;
    #|          module;
    #|          console;
    #|        
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  let captures = cursor.captures(query, tree.root_node(), utf8(source))
  assert_eq(collect_captures(captures, query, source), [
    ("variable", "toad"),
    ("variable", "panda"),
    ("variable", "ab"),
    ("function.builtin", "require"),
    ("variable", "require"),
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
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            ((call_expression (identifier) @foo)
      #|             (#set! name something)
      #|             (#set! cool)
      #|             (#something! @foo omg))
      #|
      #|            ((property_identifier) @bar
      #|             (#is? cool)
      #|             (#is-not? name something))
    ),
  )
  assert_eq(query.property_settings(0).to_owned(), [
    @treesitter.QueryProperty::new("name", Some("something"), None),
    @treesitter.QueryProperty::new("cool", None, None),
  ])
  assert_eq(query.general_predicates(0).to_owned(), [
    { operator: "something!", args: [Capture(0), String("omg")], },
  ])
  assert_eq(query.property_settings(1).to_owned(), [])
  assert_eq(query.property_predicates(0).to_owned(), [])
  assert_eq(query.property_predicates(1).to_owned(), [
    (@treesitter.QueryProperty::new("cool", None, None), true),
    (@treesitter.QueryProperty::new("name", Some("something"), None), false),
  ])
  guard get_parsing_language("javascript") is Some(language) else { return }
  let source = "const a = window.b"
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let query = @treesitter.Query::new(
    language,
    (
      #|((identifier) @variable.builtin
      #|                (#match? @variable.builtin "^(arguments|module|console|window|document)$")
      #|                (#is-not? local))
      #|            
    ),
  )
  let cursor = @treesitter.QueryCursor::new()
  let matches = cursor.matches(query, tree.root_node(), utf8(source))
  let matches = collect_matches(matches, query, source)
  assert_eq(matches, [(0, [("variable.builtin", "window")])])
}

///|
async test "query_captures_with_quoted_predicate_args" {
  guard get_language("javascript") is Some(language) else { return }

  // Double-quoted strings can contain:
  // * special escape sequences like \n and \r
  // * escaped double quotes with \*
  // * literal backslashes with \\
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            ((call_expression (identifier) @foo)
      #|             (#set! one "\"something\ngreat\""))
      #|
      #|            ((identifier)
      #|             (#set! two "\\s(\r?\n)*$"))
      #|
      #|            ((function_declaration)
      #|             (#set! three "\"something\ngreat\""))
      #|            
    ),
  )
  assert_eq(query.property_settings(0).to_owned(), [
    @treesitter.QueryProperty::new("one", Some("\"something\ngreat\""), None),
  ])
  assert_eq(query.property_settings(1).to_owned(), [
    @treesitter.QueryProperty::new("two", Some("\\s(\r?\n)*$"), None),
  ])
  assert_eq(query.property_settings(2).to_owned(), [
    @treesitter.QueryProperty::new("three", Some("\"something\ngreat\""), None),
  ])
}

///|
async test "query_captures_with_duplicates" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            (variable_declarator
      #|                name: (identifier) @function
      #|                value: (function_expression))
      #|
      #|            (identifier) @variable
      #|            
    ),
  )
  let source =
    #|
    #|          var x = function() {};
    #|        
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  let captures = cursor.captures(query, tree.root_node(), utf8(source))
  assert_eq(collect_captures(captures, query, source), [
    ("function", "x"),
    ("variable", "x"),
  ])
}

///|
async test "query_captures_with_many_nested_results_without_fields" {
  guard get_parsing_language("javascript") is Some(language) else { return }

  // Search for key-value pairs whose values are anonymous functions.
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            (pair
      #|              key: _ @method-def
      #|              (arrow_function))
      #|
      #|            ":" @colon
      #|            "," @comma
      #|            
    ),
  )

  // The `pair` node for key `y` does not match any pattern, but inside of
  // its value, it contains many other `pair` nodes that do match the pattern.
  // The match for the *outer* pair should be terminated *before* descending into
  // the object value, so that we can avoid needing to buffer all of the inner
  // matches.
  let method_count = 50
  let source = StringBuilder()
  source.write_string("x = { y: {\n")
  for i in 0..<method_count {
    source.write_string("    method\{i}: $ => null,\n")
  }
  source.write_string("}};\n")
  let source = source.to_string()
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  let captures = cursor.captures(query, tree.root_node(), utf8(source))
  let captures = collect_captures(captures, query, source)
  assert_eq(captures[0:13].to_owned(), [
    ("colon", ":"),
    ("method-def", "method0"),
    ("colon", ":"),
    ("comma", ","),
    ("method-def", "method1"),
    ("colon", ":"),
    ("comma", ","),
    ("method-def", "method2"),
    ("colon", ":"),
    ("comma", ","),
    ("method-def", "method3"),
    ("colon", ":"),
    ("comma", ","),
  ])

  // Ensure that we don't drop matches because of needing to buffer too many.
  assert_eq(captures.length(), 1 + 3 * method_count)
}

///|
async test "query_captures_with_many_nested_results_with_fields" {
  guard get_parsing_language("javascript") is Some(language) else { return }

  // Search expressions like `a ? a.b : null`
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            ((ternary_expression
      #|                condition: (identifier) @left
      #|                consequence: (member_expression
      #|                    object: (identifier) @right)
      #|                alternative: (null))
      #|             (#eq? @left @right))
      #|            
    ),
  )

  // The outer expression does not match the pattern, but the consequence of the ternary
  // is an object that *does* contain many occurrences of the pattern.
  let count = 50
  let source = StringBuilder()
  source.write_string("a ? {")
  for i in 0..<count {
    source.write_string("  x: y\{i} ? y\{i}.z : null,\n")
  }
  source.write_string("} : null;\n")
  let source = source.to_string()
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  let captures = cursor.captures(query, tree.root_node(), utf8(source))
  let captures = collect_captures(captures, query, source)
  assert_eq(captures[0:20].to_owned(), [
    ("left", "y0"),
    ("right", "y0"),
    ("left", "y1"),
    ("right", "y1"),
    ("left", "y2"),
    ("right", "y2"),
    ("left", "y3"),
    ("right", "y3"),
    ("left", "y4"),
    ("right", "y4"),
    ("left", "y5"),
    ("right", "y5"),
    ("left", "y6"),
    ("right", "y6"),
    ("left", "y7"),
    ("right", "y7"),
    ("left", "y8"),
    ("right", "y8"),
    ("left", "y9"),
    ("right", "y9"),
  ])

  // Ensure that we don't drop matches because of needing to buffer too many.
  assert_eq(captures.length(), 2 * count)
}

///|
async test "query_captures_with_too_many_nested_results" {
  guard get_parsing_language("javascript") is Some(language) else { return }

  // Search for method calls in general, and also method calls with a template string
  // in place of an argument list (aka "tagged template strings") in particular.
  //
  // This second pattern, which looks for the tagged template strings, is expensive to
  // use with the `captures()` method, because:
  // 1. When calling `captures`, all of the captures must be returned in order of their
  //    appearance.
  // 2. This pattern captures the root `call_expression`.
  // 3. This pattern's result also depends on the final child (the template string).
  // 4. In between the `call_expression` and the possible `template_string`, there can be an
  //    arbitrarily deep subtree.
  //
  // This means that, if any patterns match *after* the initial `call_expression` is
  // captured, but before the final `template_string` is found, those matches must
  // be buffered, in order to prevent captures from being returned out-of-order.
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            ;; easy 👇
      #|            (call_expression
      #|              function: (member_expression
      #|                property: (property_identifier) @method-name))
      #|
      #|            ;; hard 👇
      #|            (call_expression
      #|              function: (member_expression
      #|                property: (property_identifier) @template-tag)
      #|              arguments: (template_string)) @template-call
      #|            
    ),
  )

  // There are a *lot* of matches in between the beginning of the outer `call_expression`
  // (the call to `a(...).f`), which starts at the beginning of the file, and the final
  // template string, which occurs at the end of the file. The query algorithm imposes a
  // limit on the total number of matches which can be buffered at a time. But we don't
  // want to neglect the inner matches just because of the expensive outer match, so we
  // abandon the outer match (which would have captured `f` as a `template-tag`).
  let source = (
      #|
      #|        a(b => {
      #|            b.c0().d0 `😄`;
      #|            b.c1().d1 `😄`;
      #|            b.c2().d2 `😄`;
      #|            b.c3().d3 `😄`;
      #|            b.c4().d4 `😄`;
      #|            b.c5().d5 `😄`;
      #|            b.c6().d6 `😄`;
      #|            b.c7().d7 `😄`;
      #|            b.c8().d8 `😄`;
      #|            b.c9().d9 `😄`;
      #|        }).e().f ``;
      #|        
    )
    .trim()
    .to_owned()
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  cursor.set_match_limit(32)
  let captures = cursor.captures(query, tree.root_node(), utf8(source))
  let captures = collect_captures(captures, query, source)
  assert_eq(captures[0:4].to_owned(), [
    ("template-call", "b.c0().d0 `😄`"),
    ("method-name", "c0"),
    ("method-name", "d0"),
    ("template-tag", "d0"),
  ])
  assert_eq(captures[36:40].to_owned(), [
    ("template-call", "b.c9().d9 `😄`"),
    ("method-name", "c9"),
    ("method-name", "d9"),
    ("template-tag", "d9"),
  ])
  assert_eq(captures[40:].to_owned(), [
    ("method-name", "e"),
    ("method-name", "f"),
  ])
}

///|
async test "query_captures_with_definite_pattern_containing_many_nested_matches" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            (array
      #|              "[" @l-bracket
      #|              "]" @r-bracket)
      #|
      #|            "." @dot
      #|            
    ),
  )

  // The '[' node must be returned before all of the '.' nodes,
  // even though its pattern does not finish until the ']' node
  // at the end of the document. But because the '[' is definite,
  // it can be returned before the pattern finishes matching.
  let source =
    #|
    #|        [
    #|            a.b.c.d.e.f.g.h.i,
    #|            a.b.c.d.e.f.g.h.i,
    #|            a.b.c.d.e.f.g.h.i,
    #|            a.b.c.d.e.f.g.h.i,
    #|            a.b.c.d.e.f.g.h.i,
    #|        ]
    #|        
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  let captures = cursor.captures(query, tree.root_node(), utf8(source))
  let expected = [("l-bracket", "[")]
  for _ in 0..<40 {
    expected.push(("dot", "."))
  }
  expected.push(("r-bracket", "]"))
  assert_eq(collect_captures(captures, query, source), expected)
}

///|
async test "query_captures_ordered_by_both_start_and_end_positions" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            (call_expression) @call
      #|            (member_expression) @member
      #|            (identifier) @variable
      #|            
    ),
  )
  let source =
    #|
    #|          a.b(c.d().e).f;
    #|        
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  let captures = cursor.captures(query, tree.root_node(), utf8(source))
  assert_eq(collect_captures(captures, query, source), [
    ("member", "a.b(c.d().e).f"),
    ("call", "a.b(c.d().e)"),
    ("member", "a.b"),
    ("variable", "a"),
    ("member", "c.d().e"),
    ("call", "c.d()"),
    ("member", "c.d"),
    ("variable", "c"),
  ])
}

///|
async test "query_captures_with_matches_removed" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            (binary_expression
      #|                left: (identifier) @left
      #|                operator: _ @op
      #|                right: (identifier) @right)
      #|            
    ),
  )
  let source =
    #|
    #|          a === b && c > d && e < f;
    #|        
  let bytes = utf8(source)
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  let captured_strings = []
  let captures = cursor.captures(query, tree.root_node(), bytes)
  while captures.next() is Some((m, i)) {
    let capture = m.captures()[i]
    let text = text(capture.node, bytes)
    if text == "a" {
      m.remove()
      continue
    }
    captured_strings.push(text)
  }
  assert_eq(captured_strings, ["c", ">", "d", "e", "<", "f"])
}

///|
async test "query_captures_with_matches_removed_before_they_finish" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  // When Tree-sitter detects that a pattern is guaranteed to match,
  // it will start to eagerly return the captures that it has found,
  // even though it hasn't matched the entire pattern yet. A
  // namespace_import node always has "*", "as" and then an identifier
  // for children, so captures will be emitted eagerly for this pattern.
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            (namespace_import
      #|              "*" @star
      #|              "as" @as
      #|              (identifier) @identifier)
      #|            
    ),
  )
  let source =
    #|
    #|          import * as name from 'module-name';
    #|        
  let bytes = utf8(source)
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  let captured_strings = []
  let captures = cursor.captures(query, tree.root_node(), bytes)
  while captures.next() is Some((m, i)) {
    let capture = m.captures()[i]
    let text = text(capture.node, bytes)
    if text == "as" {
      m.remove()
      continue
    }
    captured_strings.push(text)
  }

  // .remove() removes the match before it is finished. The identifier
  // "name" is part of this match, so we expect that removing the "as"
  // capture from the match should prevent "name" from matching:
  assert_eq(captured_strings, ["*"])
}

///|
async test "query_captures_and_matches_iterators_are_fused" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            (comment) @comment
      #|            
    ),
  )
  let source =
    #|
    #|          // one
    #|          // two
    #|          // three
    #|          /* unfinished
    #|        
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  let captures = cursor.captures(query, tree.root_node(), utf8(source))
  assert_eq(captures.next().unwrap().0.captures()[0].index, 0)
  assert_eq(captures.next().unwrap().0.captures()[0].index, 0)
  assert_eq(captures.next().unwrap().0.captures()[0].index, 0)
  assert_true(captures.next() is None)
  assert_true(captures.next() is None)
  assert_true(captures.next() is None)
  let matches = cursor.matches(query, tree.root_node(), utf8(source))
  assert_eq(matches.next().unwrap().captures()[0].index, 0)
  assert_eq(matches.next().unwrap().captures()[0].index, 0)
  assert_eq(matches.next().unwrap().captures()[0].index, 0)
  assert_true(matches.next() is None)
  assert_true(matches.next() is None)
  assert_true(matches.next() is None)
}

///|
async test "query_text_callback_returns_chunks" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            ((identifier) @leading_upper
      #|             (#match? @leading_upper "^[A-Z][A-Z_]*[a-z]"))
      #|            ((identifier) @all_upper
      #|             (#match? @all_upper "^[A-Z][A-Z_]*$"))
      #|            ((identifier) @all_lower
      #|             (#match? @all_lower "^[a-z][a-z_]*$"))
      #|            
    ),
  )
  let source = "SOMETHING[a] = transform(AnotherThing[b].property[c], PARAMETER);"
  let bytes = utf8(source)

  // Store the source code in chunks of 3 bytes, and expose it via
  // an iterator API.
  let source_chunks : Array[BytesView] = []
  for i = 0; i < bytes.length(); i = i + 3 {
    source_chunks.push(bytes[i:(i + 3).min(bytes.length())])
  }
  let chunks_in_range = (range : (Int32, Int32)) => {
    let (range_start, range_end) = range
    let mut offset = 0
    source_chunks
    .iter()
    .filter_map(chunk => {
      let end_offset = offset + chunk.length()
      if offset < range_end && range_start < end_offset {
        let end_in_chunk = (range_end - offset).min(chunk.length())
        let start_in_chunk = range_start.max(offset) - offset
        offset = end_offset
        Some(chunk[start_in_chunk:end_in_chunk])
      } else {
        offset = end_offset
        None
      }
    })
  }
  let collect_string = (chunks : Iter[BytesView]) => {
    let result = StringBuilder()
    for c in chunks {
      result.write_string(@utf8.decode(c))
    }
    result.to_string()
  }
  assert_eq(collect_string(chunks_in_range((0, 9))), "SOMETHING")
  assert_eq(collect_string(chunks_in_range((15, 24))), "transform")
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  let captures = cursor.captures(
    query,
    tree.root_node(),
    @treesitter.TextCallback::new(node => chunks_in_range(node.byte_range())),
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
  let patterns_1 = indoc(
    (
      #|
      #|        "+" @operator
      #|        "-" @operator
      #|        "*" @operator
      #|        "=" @operator
      #|        "=>" @operator
      #|    
    ),
  )
  let patterns_2 = indoc(
    (
      #|
      #|        (identifier) @a
      #|        (string) @b
      #|    
    ),
  )
  let patterns_3 = indoc(
    (
      #|
      #|        ((identifier) @b (#match? @b i))
      #|        (function_declaration name: (identifier) @c)
      #|        (method_definition name: (property_identifier) @d)
      #|    
    ),
  )
  let source = StringBuilder()
  source.write_string(patterns_1)
  source.write_string(patterns_2)
  source.write_string(patterns_3)
  let query = @treesitter.Query::new(language, source.to_string())
  let len = (s : String) => utf8(s).length()
  assert_eq(query.start_byte_for_pattern(0), 0)
  assert_eq(query.end_byte_for_pattern(0), len("\"+\" @operator\n"))
  assert_eq(query.start_byte_for_pattern(5), len(patterns_1))
  assert_eq(
    query.end_byte_for_pattern(5),
    len(patterns_1) + len("(identifier) @a\n"),
  )
  assert_eq(query.start_byte_for_pattern(7), len(patterns_1) + len(patterns_2))
  assert_eq(
    query.end_byte_for_pattern(7),
    len(patterns_1) +
    len(patterns_2) +
    len("((identifier) @b (#match? @b i))\n"),
  )
}

///|
async test "query_capture_names" {
  guard get_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            (if_statement
      #|              condition: (parenthesized_expression (binary_expression
      #|                left: _ @left-operand
      #|                operator: "||"
      #|                right: _ @right-operand))
      #|              consequence: (statement_block) @body)
      #|
      #|            (while_statement
      #|              condition: _ @loop-condition)
      #|            
    ),
  )
  assert_eq(query.capture_names().to_owned(), [
    "left-operand", "right-operand", "body", "loop-condition",
  ])
}

///|
/// `take_first_node_from_captures` (a local fn of
/// `test_query_lifetime_is_separate_from_nodes_lifetime`).
async fn m3_take_first_node_from_captures(
  source : String,
  query : String,
  node : @treesitter.Node,
) -> @treesitter.Node {
  // Following 2 lines are redundant but needed to demonstrate
  // more understandable compiler error message
  guard get_language("javascript") is Some(language) else {
    fail("missing javascript")
  }
  let query = @treesitter.Query::new(language, query)
  let cursor = @treesitter.QueryCursor::new()
  cursor.matches(query, node, utf8(source)).next().unwrap().captures()[0].node
}

///|
/// `take_first_node_from_matches` (a local fn of
/// `test_query_lifetime_is_separate_from_nodes_lifetime`).
async fn m3_take_first_node_from_matches(
  source : String,
  query : String,
  node : @treesitter.Node,
) -> @treesitter.Node {
  guard get_language("javascript") is Some(language) else {
    fail("missing javascript")
  }
  let query = @treesitter.Query::new(language, query)
  let cursor = @treesitter.QueryCursor::new()
  cursor.captures(query, node, utf8(source)).next().unwrap().0.captures()[0].node
}

///|
async test "query_lifetime_is_separate_from_nodes_lifetime" {
  let query = "(call_expression) @call"
  let source = "a(1); b(2);"
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let node = m3_take_first_node_from_captures(source, query, tree.root_node())
  assert_eq(node.kind(), "call_expression")
  let node = m3_take_first_node_from_matches(source, query, tree.root_node())
  assert_eq(node.kind(), "call_expression")
}

///|
async test "query_with_no_patterns" {
  guard get_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(language, "")
  assert_eq(query.capture_names().to_owned(), [])
  assert_eq(query.pattern_count(), 0)
}

///|
async test "query_comments" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|                ; this is my first comment
      #|                ; i have two comments here
      #|                (function_declaration
      #|                    ; there is also a comment here
      #|                    ; and here
      #|                    name: (identifier) @fn-name)
    ),
  )
  let source = "function one() { }"
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  let matches = cursor.matches(query, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query, source), [(0, [("fn-name", "one")])])
}

///|
async test "query_disable_pattern" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|                (function_declaration
      #|                    name: (identifier) @name)
      #|                (function_declaration
      #|                    body: (statement_block) @body)
      #|                (class_declaration
      #|                    name: (identifier) @name)
      #|                (class_declaration
      #|                    body: (class_body) @body)
      #|            
    ),
  )

  // disable the patterns that match names
  query.disable_pattern(0)
  query.disable_pattern(2)
  let source = "class A { constructor() {} } function b() { return 1; }"
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()
  let matches = cursor.matches(query, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query, source), [
    (3, [("body", "{ constructor() {} }")]),
    (1, [("body", "{ return 1; }")]),
  ])
}

///|
async test "query_deep_clone" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|                (function_declaration
      #|                    name: (identifier) @name)
      #|                (function_declaration
      #|                    body: (statement_block) @body)
      #|            
    ),
  )
  let clone = query.deep_clone()
  clone.disable_pattern(1)
  let source = "function foo() { return 1; }"
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let cursor = @treesitter.QueryCursor::new()

  // The clone with pattern 1 disabled only produces the @name match.
  let clone_matches = collect_matches(
    cursor.matches(clone, tree.root_node(), utf8(source)),
    clone,
    source,
  )
  assert_eq(clone_matches, [(0, [("name", "foo")])])

  // The original is unaffected and still produces both @name and @body.
  let original_matches = collect_matches(
    cursor.matches(query, tree.root_node(), utf8(source)),
    query,
    source,
  )
  assert_eq(original_matches, [
    (0, [("name", "foo")]),
    (1, [("body", "{ return 1; }")]),
  ])
}

///|
async test "query_alternative_predicate_prefix" {
  guard get_parsing_language("c") is Some(language) else { return }
  let query = @treesitter.Query::new(
    language,
    (
      #|
      #|            ((call_expression
      #|              function: (identifier) @keyword
      #|              arguments: (argument_list
      #|                          (string_literal) @function))
      #|             (.eq? @keyword "DEFUN"))
      #|        
    ),
  )
  let source =
    #|
    #|            DEFUN ("identity", Fidentity, Sidentity, 1, 1, 0,
    #|                   doc: /* Return the argument unchanged.  */
    #|                   attributes: const)
    #|              (Lisp_Object arg)
    #|            {
    #|              return arg;
    #|            }
    #|        
  assert_query_matches(language, query, source, [
    (0, [("keyword", "DEFUN"), ("function", "\"identity\"")]),
  ])
}

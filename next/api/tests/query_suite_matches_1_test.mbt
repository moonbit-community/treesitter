// Port of tree-sitter crates/cli/src/tests/query_test.rs (lines 709-2158).

///|
async test "query_matches_with_simple_pattern" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(
    language, "(function_declaration name: (identifier) @fn-name)",
  )

  assert_query_matches(
    language,
    query,
    "function one() { two(); function three() {} }",
    [(0, [("fn-name", "one")]), (0, [("fn-name", "three")])],
  )
}

///|
async test "query_matches_with_multiple_on_same_root" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|(class_declaration
      #|                name: (identifier) @the-class-name
      #|                (class_body
      #|                    (method_definition
      #|                        name: (property_identifier) @the-method-name)))
    ),
  )

  assert_query_matches(
    language,
    query,
    (
      #|
      #|            class Person {
      #|                // the constructor
      #|                constructor(name) { this.name = name; }
      #|
      #|                // the getter
      #|                getFullName() { return this.name; }
      #|            }
      #|            
    ),
    [
      (0, [("the-class-name", "Person"), ("the-method-name", "constructor")]),
      (0, [("the-class-name", "Person"), ("the-method-name", "getFullName")]),
    ],
  )
}

///|
async test "query_matches_with_multiple_patterns_different_roots" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|
      #|                (function_declaration name:(identifier) @fn-def)
      #|                (call_expression function:(identifier) @fn-ref)
      #|            
    ),
  )

  assert_query_matches(
    language,
    query,
    (
      #|
      #|            function f1() {
      #|                f2(f3());
      #|            }
      #|            
    ),
    [(0, [("fn-def", "f1")]), (1, [("fn-ref", "f2")]), (1, [("fn-ref", "f3")])],
  )
}

///|
async test "query_matches_with_multiple_patterns_same_root" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|
      #|              (pair
      #|                key: (property_identifier) @method-def
      #|                value: (function_expression))
      #|
      #|              (pair
      #|                key: (property_identifier) @method-def
      #|                value: (arrow_function))
      #|            
    ),
  )

  assert_query_matches(
    language,
    query,
    (
      #|
      #|            a = {
      #|                b: () => { return c; },
      #|                d: function() { return d; }
      #|            };
      #|            
    ),
    [(1, [("method-def", "b")]), (0, [("method-def", "d")])],
  )
}

///|
async test "query_matches_with_nesting_and_no_fields" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|
      #|                (array
      #|                    (array
      #|                        (identifier) @x1
      #|                        (identifier) @x2))
      #|            
    ),
  )

  assert_query_matches(
    language,
    query,
    (
      #|
      #|            [[a]];
      #|            [[c, d], [e, f, g, h]];
      #|            [[h], [i]];
      #|            
    ),
    [
      (0, [("x1", "c"), ("x2", "d")]),
      (0, [("x1", "e"), ("x2", "f")]),
      (0, [("x1", "e"), ("x2", "g")]),
      (0, [("x1", "f"), ("x2", "g")]),
      (0, [("x1", "e"), ("x2", "h")]),
      (0, [("x1", "f"), ("x2", "h")]),
      (0, [("x1", "g"), ("x2", "h")]),
    ],
  )
}

///|
async test "query_matches_with_many_results" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(language, "(array (identifier) @element)")

  assert_query_matches(
    language,
    query,
    "[hello];\n".repeat(50),
    Array::make(50, (0, [("element", "hello")])),
  )
}

///|
async test "query_matches_with_many_overlapping_results" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|
      #|            (call_expression
      #|                function: (member_expression
      #|                    property: (property_identifier) @method))
      #|            (call_expression
      #|                function: (identifier) @function)
      #|            ((identifier) @constant
      #|             (#match? @constant "[A-Z\\d_]+"))
      #|            
    ),
  )

  let count = 1024

  // Deeply nested chained function calls:
  // a
  //    .foo(bar(BAZ))
  //    .foo(bar(BAZ))
  //    .foo(bar(BAZ))
  //    ...
  let source = "a\{"\n  .foo(bar(BAZ))".repeat(count)}"

  assert_query_matches(
    language,
    query,
    source,
    m1_cycle_take(
      [
        (0, [("method", "foo")]),
        (1, [("function", "bar")]),
        (2, [("constant", "BAZ")]),
      ],
      3 * count,
    ),
  )
}

///|
async test "query_matches_capturing_error_nodes" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|
      #|            (ERROR (identifier) @the-error-identifier) @the-error
      #|            
    ),
  )

  assert_query_matches(language, query, "function a(b,, c, d :e:) {}", [
    (0, [("the-error", ":e:"), ("the-error-identifier", "e")]),
  ])
}

///|
async test "query_matches_capturing_missing_nodes" {
  // (the javascript half is skipped while its external scanner is pending;
  // the c half still runs)
  if get_parsing_language("javascript") is Some(language) {
    let query = @api.Query::new(
      language,
      (
        #|
        #|            (MISSING
        #|              ; Comments should be valid
        #|            ) @missing
        #|            (MISSING
        #|              ; Comments should be valid
        #|              ";"
        #|              ; Comments should be valid
        #|              ) @missing-semicolon
        #|            
      ),
    )

    // Missing anonymous nodes
    assert_query_matches(
      language,
      query,
      (
        #|
        #|            x = function(a) { b; } function(c) { d; }
        #|            //                    ^ MISSING semicolon here
        #|            
      ),
      [(0, [("missing", "")]), (1, [("missing-semicolon", "")])],
    )
  }

  guard get_parsing_language("c") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|(MISSING field_identifier) @missing-field-ident
      #|            (MISSING identifier) @missing-ident
      #|            (MISSING) @missing-anything
    ),
  )

  // Missing named nodes
  assert_query_matches(
    language,
    query,
    (
      #|
      #|            int main() {
      #|              if (a.) {
      #|              //    ^ MISSING field_identifier here
      #|                b();
      #|                c();
      #|
      #|                if (*) d();
      #|                //   ^ MISSING identifier here
      #|              }
      #|            }
      #|            
    ),
    [
      (0, [("missing-field-ident", "")]),
      (2, [("missing-anything", "")]),
      (1, [("missing-ident", "")]),
      (2, [("missing-anything", "")]),
    ],
  )
}

///|
async test "query_matches_with_extra_children" {
  guard get_parsing_language("ruby") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|
      #|            (program(comment) @top_level_comment)
      #|            (argument_list (heredoc_body) @heredoc_in_args)
      #|            
    ),
  )

  assert_query_matches(
    language,
    query,
    (
      #|
      #|            # top-level
      #|            puts(
      #|                # not-top-level
      #|                <<-IN_ARGS, bar.baz
      #|                HELLO
      #|                IN_ARGS
      #|            )
      #|
      #|            puts <<-NOT_IN_ARGS
      #|            NO
      #|            NOT_IN_ARGS
      #|            
    ),
    [
      (0, [("top_level_comment", "# top-level")]),
      (
        1,
        [
          (
            "heredoc_in_args", "\n                HELLO\n                IN_ARGS",
          ),
        ],
      ),
    ],
  )
}

///|
async test "query_matches_with_named_wildcard" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|
      #|            (return_statement (_) @the-return-value)
      #|            (binary_expression operator: _ @the-operator)
      #|            
    ),
  )

  let source = "return a + b - c;"

  let parser = @api.Parser::new()
  parser.set_language(language)
  let tree = parser.parse(utf8(source)).unwrap()
  let cursor = @api.QueryCursor::new()
  let matches = cursor.matches(query, tree.root_node(), utf8(source))

  assert_eq(collect_matches(matches, query, source), [
    (0, [("the-return-value", "a + b - c")]),
    (1, [("the-operator", "+")]),
    (1, [("the-operator", "-")]),
  ])
}

///|
async test "query_matches_with_wildcard_at_the_root" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|
      #|            (_
      #|                (comment) @doc
      #|                .
      #|                (function_declaration
      #|                    name: (identifier) @name))
      #|            
    ),
  )

  assert_query_matches(
    language,
    query,
    "/* one */ var x; /* two */ function y() {} /* three */ class Z {}",
    [(0, [("doc", "/* two */"), ("name", "y")])],
  )

  let query = @api.Query::new(
    language,
    (
      #|
      #|                (_ (string) @a)
      #|                (_ (number) @b)
      #|                (_ (true) @c)
      #|                (_ (false) @d)
      #|            
    ),
  )

  assert_query_matches(language, query, "['hi', x(true), {y: false}]", [
    (0, [("a", "'hi'")]),
    (2, [("c", "true")]),
    (3, [("d", "false")]),
  ])
}

///|
async test "query_matches_with_wildcard_within_wildcard" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|
      #|            (_ (_) @child) @parent
      #|            
    ),
  )

  assert_query_matches(language, query, "/* a */ b; c;", [
    (0, [("parent", "/* a */ b; c;"), ("child", "/* a */")]),
    (0, [("parent", "/* a */ b; c;"), ("child", "b;")]),
    (0, [("parent", "b;"), ("child", "b")]),
    (0, [("parent", "/* a */ b; c;"), ("child", "c;")]),
    (0, [("parent", "c;"), ("child", "c")]),
  ])
}

///|
async test "query_matches_with_immediate_siblings" {
  guard get_parsing_language("python") is Some(language) else { return }

  // The immediate child operator '.' can be used in three similar ways:
  // 1. Before the first child node in a pattern, it means that there cannot be any named
  //    siblings before that child node.
  // 2. After the last child node in a pattern, it means that there cannot be any named
  //    sibling after that child node.
  // 3. Between two child nodes in a pattern, it specifies that there cannot be any named
  //    siblings between those two child nodes.
  let query = @api.Query::new(
    language,
    (
      #|
      #|            (dotted_name
      #|                (identifier) @parent
      #|                .
      #|                (identifier) @child)
      #|            (dotted_name
      #|                (identifier) @last-child
      #|                .)
      #|            (list
      #|                .
      #|                (_) @first-element)
      #|            
    ),
  )

  assert_query_matches(
    language,
    query,
    "import a.b.c.d; return [w, [1, y], z]",
    [
      (0, [("parent", "a"), ("child", "b")]),
      (0, [("parent", "b"), ("child", "c")]),
      (0, [("parent", "c"), ("child", "d")]),
      (1, [("last-child", "d")]),
      (2, [("first-element", "w")]),
      (2, [("first-element", "1")]),
    ],
  )

  let query = @api.Query::new(
    language,
    (
      #|
      #|            (block . (_) @first-stmt)
      #|            (block (_) @stmt)
      #|            (block (_) @last-stmt .)
      #|            
    ),
  )

  assert_query_matches(
    language,
    query,
    (
      #|
      #|            if a:
      #|                b()
      #|                c()
      #|                if d(): e(); f()
      #|                g()
      #|            
    ),
    [
      (0, [("first-stmt", "b()")]),
      (1, [("stmt", "b()")]),
      (1, [("stmt", "c()")]),
      (1, [("stmt", "if d(): e(); f()")]),
      (0, [("first-stmt", "e()")]),
      (1, [("stmt", "e()")]),
      (1, [("stmt", "f()")]),
      (2, [("last-stmt", "f()")]),
      (1, [("stmt", "g()")]),
      (2, [("last-stmt", "g()")]),
    ],
  )
}

///|
async test "query_matches_with_anchor_after_zero_quantifier" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(
    language, "(program (comment)* @doc . (function_declaration name: (identifier) @name))",
  )

  // No comments and the function is not the first child. An anchor after a
  // zero-matched quantifier is vacuous, so the function still matches.
  assert_query_matches(
    language,
    query,
    (
      #|
      #|class X {}
      #|function foo() {}
      #|
    ),
    [(0, [("name", "foo")])],
  )

  // With at least one comment the anchor applies, so the comments must
  // immediately precede the function.
  assert_query_matches(
    language,
    query,
    (
      #|
      #|// c
      #|function foo() {}
      #|
    ),
    [(0, [("doc", "// c"), ("name", "foo")])],
  )
}

///|
async test "query_matches_with_anchor_after_nested_zero_quantifier" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|
      #|            (_
      #|              (field_definition
      #|                property: (_) @name
      #|                value: (_)? @value
      #|              ) @field
      #|              .
      #|              ";" @semicolon
      #|            )
      #|            
    ),
  )

  assert_query_matches(language, query, "class Foo { bar; baz = 0; }", [
    (0, [("field", "bar"), ("name", "bar"), ("semicolon", ";")]),
    (
      0,
      [
        ("field", "baz = 0"),
        ("name", "baz"),
        ("value", "0"),
        ("semicolon", ";"),
      ],
    ),
  ])
}

///|
async test "query_matches_with_last_child_anchor_after_optional" {
  guard get_parsing_language("c") is Some(language) else { return }
  let query = @api.Query::new(
    language, "(preproc_if (preproc_def)+ @def . (preproc_else)? @else .)",
  )

  // The optional `(preproc_else)?` is absent, so the trailing anchor's
  // last-child requirement transfers to the last `preproc_def`. A trailing
  // comment means the def is not the last child, so nothing matches.
  assert_query_matches(
    language,
    query,
    (
      #|
      #|#if X
      #|#define A
      #|// c
      #|#endif
      #|
    ),
    [],
  )

  // With the def as the last child, the (else-less) match is allowed.
  assert_query_matches(
    language,
    query,
    (
      #|
      #|#if X
      #|#define A
      #|#endif
      #|
    ),
    [(0, [("def", "#define A\n")])],
  )
}

///|
async test "query_matches_with_anchors_on_both_sides_of_zero_quantifier" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(
    language, "(program (lexical_declaration) @a . (comment)* . (function_declaration) @b)",
  )

  // Anchors on both sides of a zero-matched quantifier collapse into a single
  // adjacency constraint: with no comments, the declaration must be immediately
  // followed by the function.
  assert_query_matches(
    language,
    query,
    (
      #|
      #|const a = 1;
      #|const b = 2;
      #|function foo() {}
      #|
    ),
    [(0, [("a", "const b = 2;"), ("b", "function foo() {}")])],
  )

  // With a comment present the quantifier is non-zero, so the anchors apply
  // normally: the comment must sit immediately between the declaration and the
  // function.
  assert_query_matches(
    language,
    query,
    (
      #|
      #|const b = 2;
      #|// c
      #|function foo() {}
      #|
    ),
    [(0, [("a", "const b = 2;"), ("b", "function foo() {}")])],
  )
}

///|
async test "query_matches_with_leading_anchor_before_zero_quantifier" {
  guard get_parsing_language("c") is Some(language) else { return }
  let query = @api.Query::new(
    language, "(translation_unit . (comment)* (function_definition) @f)",
  )

  // The leading `.` anchors the comment run to the parent's first child. When the
  // run matches zero comments, that first-child requirement transfers to the
  // function, so it matches only when it is itself the first child.
  assert_query_matches(
    language,
    query,
    (
      #|
      #|int main() {}
      #|
    ),
    [(0, [("f", "int main() {}")])],
  )

  // The function is the second child, so with no leading comments it must not match.
  assert_query_matches(
    language,
    query,
    (
      #|
      #|int a;
      #|int main() {}
      #|
    ),
    [],
  )

  // With a leading comment the run starts at the first child and the function follows.
  assert_query_matches(
    language,
    query,
    (
      #|
      #|// c
      #|int main() {}
      #|
    ),
    [(0, [("f", "int main() {}")])],
  )
}

///|
async test "query_matches_with_last_named_child" {
  guard get_parsing_language("c") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|(compound_statement
      #|                (_)
      #|                (_)
      #|                (expression_statement
      #|                    (identifier) @last_id) .)
    ),
  )
  assert_query_matches(
    language,
    query,
    (
      #|
      #|            void one() { a; b; c; }
      #|            void two() { d; e; }
      #|            void three() { f; g; h; i; }
      #|            
    ),
    [(0, [("last_id", "c")]), (0, [("last_id", "i")])],
  )
}

///|
async test "query_matches_with_negated_fields" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|
      #|            (import_specifier
      #|                !alias
      #|                name: (identifier) @import_name)
      #|
      #|            (export_specifier
      #|                !alias
      #|                name: (identifier) @export_name)
      #|
      #|            (export_statement
      #|                !decorator
      #|                !source
      #|                (_) @exported)
      #|
      #|            ; This negated field list is an extension of a previous
      #|            ; negated field list. The order of the children and negated
      #|            ; fields doesn't matter.
      #|            (export_statement
      #|                !decorator
      #|                !source
      #|                (_) @exported_expr
      #|                !declaration)
      #|
      #|            ; This negated field list is a prefix of a previous
      #|            ; negated field list.
      #|            (export_statement
      #|                !decorator
      #|                (_) @export_child .)
      #|            
    ),
  )
  assert_query_matches(
    language,
    query,
    (
      #|
      #|            import {a as b, c} from 'p1';
      #|            export {g, h as i} from 'p2';
      #|
      #|            @foo
      #|            export default 1;
      #|
      #|            export var j = 1;
      #|
      #|            export default k;
      #|            
    ),
    [
      (0, [("import_name", "c")]),
      (1, [("export_name", "g")]),
      (4, [("export_child", "'p2'")]),
      (2, [("exported", "var j = 1;")]),
      (4, [("export_child", "var j = 1;")]),
      (2, [("exported", "k")]),
      (3, [("exported_expr", "k")]),
      (4, [("export_child", "k")]),
    ],
  )
}

///|
async test "query_matches_with_field_at_root" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(language, "name: (identifier) @name")
  assert_query_matches(
    language,
    query,
    (
      #|
      #|            a();
      #|            function b() {}
      #|            class c extends d {}
      #|            
    ),
    [(0, [("name", "b")]), (0, [("name", "c")])],
  )
}

///|
async test "query_matches_with_repeated_leaf_nodes" {
  guard get_parsing_language("javascript") is Some(language) else { return }

  let query = @api.Query::new(
    language,
    (
      #|
      #|            (
      #|                (comment)+ @doc
      #|                .
      #|                (class_declaration
      #|                    name: (identifier) @name)
      #|            )
      #|
      #|            (
      #|                (comment)+ @doc
      #|                .
      #|                (function_declaration
      #|                    name: (identifier) @name)
      #|            )
      #|            
    ),
  )

  assert_query_matches(
    language,
    query,
    (
      #|
      #|            // one
      #|            // two
      #|            a();
      #|
      #|            // three
      #|            {
      #|                // four
      #|                // five
      #|                // six
      #|                class B {}
      #|
      #|                // seven
      #|                c();
      #|
      #|                // eight
      #|                function d() {}
      #|            }
      #|            
    ),
    [
      (
        0,
        [
          ("doc", "// four"),
          ("doc", "// five"),
          ("doc", "// six"),
          ("name", "B"),
        ],
      ),
      (1, [("doc", "// eight"), ("name", "d")]),
    ],
  )
}

///|
async test "query_matches_optional_capture_before_uncaptured_required_sibling" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let query = @api.Query::new(
    language, "(block (line_comment)? @doc (line_comment))",
  )

  // The optional `(line_comment)? @doc` before an *uncaptured* required
  // `(line_comment)` yields two candidate completions at the block:
  //     - one where the optional captured `// a` (the required node is then `// b`),
  //     - one where the optional matched zero (the required node absorbs `// a`,
  //     leaving `@doc` unbound).
  // The zero-match completion's captures are a strict subset of the other's, so the
  // longest-match rule must drop it (there is exactly one match). This regressed when
  // the dedup pass gained an early-break. Without the accompanying capture-position
  // sort, the break skips the subset "loser" and it leaks as an extra empty match.
  assert_query_matches(
    language,
    query,
    (
      #|
      #|            fn f() {
      #|                // a
      #|                // b
      #|            }
      #|            
    ),
    [(0, [("doc", "// a")])],
  )
}

///|
async test "query_matches_with_optional_nodes_inside_of_repetitions" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(language, "(array (\",\"? (number) @num)+)")

  assert_query_matches(
    language,
    query,
    (
      #|
      #|            var a = [1, 2, 3, 4]
      #|            
    ),
    [(0, [("num", "1"), ("num", "2"), ("num", "3"), ("num", "4")])],
  )
}

///|
async test "query_matches_with_top_level_repetitions" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|
      #|            (comment)+ @doc
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
      #|            // c
      #|
      #|            d()
      #|
      #|            // e
      #|            
    ),
    [
      (0, [("doc", "// a"), ("doc", "// b"), ("doc", "// c")]),
      (0, [("doc", "// e")]),
    ],
  )
}

///|
async test "query_matches_with_non_terminal_repetitions_within_root" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(
    language, "(_ (expression_statement (identifier) @id)+)",
  )

  assert_query_matches(
    language,
    query,
    (
      #|
      #|            function f() {
      #|                d;
      #|                e;
      #|                f;
      #|                g;
      #|            }
      #|            a;
      #|            b;
      #|            c;
      #|            
    ),
    [
      (0, [("id", "d"), ("id", "e"), ("id", "f"), ("id", "g")]),
      (0, [("id", "a"), ("id", "b"), ("id", "c")]),
    ],
  )
}

///|
async test "query_matches_with_nested_repetitions" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|
      #|            (variable_declaration
      #|                (","? (variable_declarator name: (identifier) @x))+)+
      #|            
    ),
  )

  assert_query_matches(
    language,
    query,
    (
      #|
      #|            var a = b, c, d
      #|            var e, f
      #|
      #|            // more
      #|            var g
      #|            
    ),
    [
      (0, [("x", "a"), ("x", "c"), ("x", "d"), ("x", "e"), ("x", "f")]),
      (0, [("x", "g")]),
    ],
  )
}

///|
async test "query_matches_with_multiple_repetition_patterns_that_intersect_other_pattern" {
  guard get_parsing_language("javascript") is Some(language) else { return }

  // When this query sees a comment, it must keep track of several potential
  // matches: up to two for each pattern that begins with a comment.
  let query = @api.Query::new(
    language,
    (
      #|
      #|            (call_expression
      #|                function: (member_expression
      #|                    property: (property_identifier) @name)) @ref.method
      #|
      #|            ((comment)* @doc (function_declaration))
      #|            ((comment)* @doc (generator_function_declaration))
      #|            ((comment)* @doc (class_declaration))
      #|            ((comment)* @doc (lexical_declaration))
      #|            ((comment)* @doc (variable_declaration))
      #|            ((comment)* @doc (method_definition))
      #|
      #|            (comment) @comment
      #|            
    ),
  )

  // Here, a series of comments occurs in the middle of a match of the first
  // pattern. To avoid exceeding the storage limits and discarding that outer
  // match, the comment-related matches need to be managed efficiently.
  let source = "theObject\n\{"  // the comment\n".repeat(64)}\n.theMethod()"

  assert_query_matches(
    language,
    query,
    source,
    Array::make(64, (7, [("comment", "// the comment")]))
    .iter()
    .concat([(0, [("ref.method", source), ("name", "theMethod")])].iter())
    .to_array(),
  )
}

///|
async test "query_matches_with_trailing_repetitions_of_last_child" {
  guard get_parsing_language("javascript") is Some(language) else { return }

  let query = @api.Query::new(
    language,
    (
      #|
      #|            (unary_expression (primary_expression)+ @operand)
      #|            
    ),
  )

  assert_query_matches(
    language,
    query,
    (
      #|
      #|            a = typeof (!b && ~c);
      #|            
    ),
    [
      (0, [("operand", "b")]),
      (0, [("operand", "c")]),
      (0, [("operand", "(!b && ~c)")]),
    ],
  )
}

///|
async test "query_matches_with_leading_zero_or_more_repeated_leaf_nodes" {
  guard get_parsing_language("javascript") is Some(language) else { return }

  let query = @api.Query::new(
    language,
    (
      #|
      #|            (
      #|                (comment)* @doc
      #|                .
      #|                (function_declaration
      #|                    name: (identifier) @name)
      #|            )
      #|            
    ),
  )

  assert_query_matches(
    language,
    query,
    (
      #|
      #|            function a() {
      #|                // one
      #|                var b;
      #|
      #|                function c() {}
      #|
      #|                // two
      #|                // three
      #|                var d;
      #|
      #|                // four
      #|                // five
      #|                function e() {
      #|
      #|                }
      #|            }
      #|
      #|            // six
      #|            
    ),
    [
      (0, [("name", "a")]),
      (0, [("name", "c")]),
      (0, [("doc", "// four"), ("doc", "// five"), ("name", "e")]),
    ],
  )
}

///|
async test "matches_with_anchor_sibling_inside_parent" {
  guard get_parsing_language("rust") is Some(language) else { return }

  let query = @api.Query::new(
    language,
    (
      #|
      #|            (source_file
      #|                (line_comment)
      #|                .
      #|                (function_item
      #|                    name: (identifier) @name)
      #|            )
    ),
  )

  assert_query_matches(
    language,
    query,
    (
      #|
      #|            // A
      #|            fn a() {}
      #|
      #|            // B
      #|            fn b() {}
      #|            
    ),
    [(0, [("name", "a")]), (0, [("name", "b")])],
  )
}

///|
async test "matches_with_anchor_sibling_with_quantifier_inside_parent" {
  guard get_parsing_language("rust") is Some(language) else { return }

  let query = @api.Query::new(
    language,
    (
      #|
      #|            (source_file
      #|                (line_comment)+
      #|                .
      #|                (function_item
      #|                    name: (identifier) @name)
      #|            )
    ),
  )

  assert_query_matches(
    language,
    query,
    (
      #|
      #|            // A
      #|            fn a() {}
      #|
      #|            // B
      #|            fn b() {}
      #|            
    ),
    [(0, [("name", "a")]), (0, [("name", "b")])],
  )
}

///|
async test "matches_with_anchor_sibling_with_quantifier_captured_inside_parent" {
  guard get_parsing_language("rust") is Some(language) else { return }

  let query = @api.Query::new(
    language,
    (
      #|
      #|            (source_file
      #|                (line_comment)+ @doc
      #|                .
      #|                (function_item
      #|                    name: (identifier) @name)
      #|            )
    ),
  )

  assert_query_matches(
    language,
    query,
    (
      #|
      #|            // A
      #|            fn a() {}
      #|
      #|            // B
      #|            fn b() {}
      #|            
    ),
    [
      (0, [("doc", "// A"), ("name", "a")]),
      (0, [("doc", "// B"), ("name", "b")]),
    ],
  )
}

///|
async test "matches_anchored_quantified_sibling_inside_parent" {
  guard get_parsing_language("c") is Some(language) else { return }
  let query = @api.Query::new(
    language, "(translation_unit (comment)* @comment . (declaration) @decl)",
  )
  assert_query_matches(
    language,
    query,
    (
      #|
      #|void foo() {}
      #|
      #|// this one has
      #|// two comments
      #|extern int baz;
      #|
      #|// this one has a comment
      #|extern int bar;
      #|
    ),
    [
      (
        0,
        [
          ("comment", "// this one has"),
          ("comment", "// two comments"),
          ("decl", "extern int baz;"),
        ],
      ),
      (
        0,
        [("comment", "// this one has a comment"), ("decl", "extern int bar;")],
      ),
    ],
  )
}

///|
async test "query_matches_with_trailing_optional_nodes" {
  guard get_parsing_language("javascript") is Some(language) else { return }

  let query = @api.Query::new(
    language,
    (
      #|
      #|            (class_declaration
      #|                name: (identifier) @class
      #|                (class_heritage
      #|                  (identifier) @superclass)?)
      #|            
    ),
  )

  assert_query_matches(language, query, "class A {}", [(0, [("class", "A")])])

  assert_query_matches(
    language,
    query,
    (
      #|
      #|            class A {}
      #|            class B extends C {}
      #|            class D extends (E.F) {}
      #|            
    ),
    [
      (0, [("class", "A")]),
      (0, [("class", "B"), ("superclass", "C")]),
      (0, [("class", "D")]),
    ],
  )
}

///|
async test "query_matches_with_nested_optional_nodes" {
  guard get_parsing_language("javascript") is Some(language) else { return }

  // A function call, optionally containing a function call, which optionally contains a
  // number
  let query = @api.Query::new(
    language,
    (
      #|
      #|            (call_expression
      #|                function: (identifier) @outer-fn
      #|                arguments: (arguments
      #|                    (call_expression
      #|                        function: (identifier) @inner-fn
      #|                        arguments: (arguments
      #|                            (number)? @num))?))
      #|            
    ),
  )

  assert_query_matches(
    language,
    query,
    (
      #|
      #|            a(b, c(), d(null, 1, 2))
      #|            e()
      #|            f(g())
      #|            
    ),
    [
      (0, [("outer-fn", "a"), ("inner-fn", "c")]),
      (0, [("outer-fn", "c")]),
      (0, [("outer-fn", "a"), ("inner-fn", "d"), ("num", "1")]),
      (0, [("outer-fn", "a"), ("inner-fn", "d"), ("num", "2")]),
      (0, [("outer-fn", "d")]),
      (0, [("outer-fn", "e")]),
      (0, [("outer-fn", "f"), ("inner-fn", "g")]),
      (0, [("outer-fn", "g")]),
    ],
  )
}

///|
async test "query_matches_with_repeated_internal_nodes" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let query = @api.Query::new(
    language,
    (
      #|
      #|            (_
      #|                (method_definition
      #|                    (decorator (identifier) @deco)+
      #|                    name: (property_identifier) @name))
      #|            
    ),
  )

  assert_query_matches(
    language,
    query,
    (
      #|
      #|            class A {
      #|                @c
      #|                @d
      #|                e() {}
      #|            }
      #|            
    ),
    [(0, [("deco", "c"), ("deco", "d"), ("name", "e")])],
  )
}

///|
/// `.iter().cloned().cycle().take(n).collect()`.
fn[T] m1_cycle_take(items : Array[T], n : Int32) -> Array[T] {
  Array::makei(n, i => items[i % items.length()])
}

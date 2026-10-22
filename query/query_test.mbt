///|
fn fixture() -> @ts.Tree raise {
  let language = @generate.generate(
    @grammar.Grammar::new("assignments", [
      ("document", Repeat(Symbol("assignment"))),
      (
        "assignment",
        Seq([
          Field("name", Symbol("identifier")),
          Literal("="),
          Field("value", Symbol("number")),
          Literal(";"),
        ]),
      ),
      ("identifier", @grammar.pattern("[a-z]+")),
      ("number", @grammar.pattern("[0-9]+")),
    ]),
  )
  @ts.Parser::new(language).parse_string("a=1; bob=20; c=3;")
}

///|
test "query fields captures anonymous nodes and source order" {
  let tree = fixture()
  let query = @query.Query::new(
    tree.language,
    "(assignment name: (identifier) @name value: (number) @value) @definition\n\"=\" @operator",
  )
  let matches = query.matches(tree.root_node(), tree.source)
  assert_eq(matches.length(), 6)
  let captures = query.captures(tree.root_node(), tree.source)
  assert_eq(
    captures.filter(c => c.name == "name").map(c => c.node.text(tree.source)),
    ["a", "bob", "c"],
  )
  assert_eq(captures.filter(c => c.name == "operator").length(), 3)
}

///|
test "query predicates and properties filter captures" {
  let tree = fixture()
  let query = @query.Query::new(
    tree.language,
    (
      #|((assignment name: (identifier) @name) @definition
      #|  (#match? @name "^b")
      #|  (#not-eq? @name "bad")
      #|  (#set! kind "variable"))
    ),
  )
  let matches = query.matches(tree.root_node(), tree.source)
  assert_eq(matches.length(), 1)
  assert_eq(matches[0].captures.map(c => c.name), ["definition", "name"])
  assert_eq(matches[0].captures[1].node.text(tree.source), "bob")
  assert_eq(matches[0].properties["kind"], "variable")
  let anyof = @query.Query::new(
    tree.language,
    "((identifier) @id (#any-of? @id \"a\" \"c\"))",
  )
  assert_eq(anyof.matches(tree.root_node(), tree.source).length(), 2)
}

///|
test "anchors and greedy quantified captures" {
  let tree = fixture()
  let first = @query.Query::new(
    tree.language,
    "(document . (assignment) @first)",
  )
  assert_eq(
    first
    .captures(tree.root_node(), tree.source)
    .map(c => c.node.text(tree.source)),
    ["a=1;"],
  )
  let last = @query.Query::new(tree.language, "(document (assignment) @last .)")
  assert_eq(
    last
    .captures(tree.root_node(), tree.source)
    .map(c => c.node.text(tree.source)),
    ["c=3;"],
  )
  let repeated = @query.Query::new(
    tree.language,
    "(document (assignment)+ @items)",
  )
  let matches = repeated.matches(tree.root_node(), tree.source)
  assert_eq(matches.length(), 1)
  assert_eq(matches[0].captures.length(), 3)
  let alternative = @query.Query::new(
    tree.language,
    "[(identifier) (number)] @value",
  )
  assert_eq(alternative.captures(tree.root_node(), tree.source).length(), 6)
}

///|
test "query diagnostics reject invalid types fields captures and predicates" {
  let tree = fixture()
  for
    source in [
      "(unknown)", "(assignment nope: (_))", "((identifier) @x (#eq? @y \"a\"))",
      "((identifier) @x (#strip! @x))", "(identifier", "[]",
    ] {
    try @query.Query::new(tree.language, source) catch {
      InvalidQuery(_, _) => ()
      _ => fail("wrong error")
    } noraise {
      _ => fail("accepted invalid query: \{source}")
    }
  }
}

///|
test "query limits and cancellation do not silently truncate" {
  let tree = fixture()
  let query = @query.Query::new(tree.language, "(identifier) @id")
  try query.matches(tree.root_node(), tree.source, max_matches=1) catch {
    MatchLimit => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("ignored match limit")
  }
  try query.matches(tree.root_node(), tree.source, cancelled=() => true) catch {
    Cancelled => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("ignored cancellation")
  }
}

///|
test "sibling groups anchor adjacent roots and nest inside node patterns" {
  let tree = fixture()
  for
    source in [
      "((assignment) @a . (assignment) @b)", "(document ((assignment) @a . (assignment) @b))",
    ] {
    let query = @query.Query::new(tree.language, source)
    let matches = query.matches(tree.root_node(), tree.source)
    assert_eq(matches.length(), 2)
    assert_eq(matches[0].captures.map(c => c.node.text(tree.source)), [
      "a=1;", "bob=20;",
    ])
    assert_eq(matches[1].captures.map(c => c.node.text(tree.source)), [
      "bob=20;", "c=3;",
    ])
  }
}

///|
test "property predicates and custom predicate evaluators" {
  let tree = fixture()
  let query = @query.Query::new(
    tree.language,
    "((identifier) @name (#is? @name local) (#custom? @name))",
  )
  let matches = query.matches(
    tree.root_node(),
    tree.source,
    property=(key, _, node) => {
      key == "local" && node.unwrap().text(tree.source) == "bob"
    },
    predicate=(name, _, _, _) => name == "#custom?",
  )
  assert_eq(matches.length(), 1)
  assert_eq(matches[0].captures[0].node.text(tree.source), "bob")
}

///|
test "locals resolve nearest preceding definition and exclude initializer" {
  let language = @generate.generate(
    @grammar.Grammar::new("locals", [
      ("document", Repeat(Symbol("_statement"))),
      (
        "_statement",
        Choice([Symbol("binding"), Symbol("reference"), Symbol("block")]),
      ),
      (
        "binding",
        Seq([
          Literal("let"),
          Field("name", Symbol("identifier")),
          Literal("="),
          Field("value", Symbol("identifier")),
          Literal(";"),
        ]),
      ),
      ("reference", Seq([Symbol("identifier"), Literal(";")])),
      ("block", Seq([Literal("{"), Repeat(Symbol("_statement")), Literal("}")])),
      ("identifier", @grammar.pattern("[a-z]+")),
    ]),
  )
  let tree = @ts.Parser::new(language).parse_string(
    "let x=y; { let x=x; x; } x;",
  )
  let query = @query.Query::new(
    language, "(block) @local.scope\n(binding name: (identifier) @local.definition value: (identifier) @local.definition-value)\n(identifier) @local.reference",
  )
  let locals = @query.Locals::new(query, tree)
  let ids = @query.Query::new(language, "(identifier) @id")
    .captures(tree.root_node(), tree.source)
    .map(c => c.node)
  assert_eq(ids.map(n => locals.definition(n).map(d => d.start_byte())), [
    Some(4),
    None,
    Some(15),
    Some(4),
    Some(15),
    Some(4),
  ])
  let isolated = @query.Query::new(
    language, "((block) @local.scope (#set! local.scope-inherits false))\n(binding name: (identifier) @local.definition value: (identifier) @local.definition-value)\n(identifier) @local.reference",
  )
  assert_true(@query.Locals::new(isolated, tree).definition(ids[3]) is None)
}

///|
test "query cursors are lazy and restrict starting depth and points" {
  let tree = fixture()
  let query = @query.Query::new(tree.language, "(identifier) @id")
  let mut cancelled = false
  let cursor = query.cursor(tree.root_node(), tree.source, cancelled=() => {
    return cancelled
  })
  assert_eq(
    cursor.next_match().unwrap().captures[0].node.text(tree.source),
    "a",
  )
  cancelled = true
  try cursor.next_match() catch {
    Cancelled => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("ignored cancellation between matches")
  }
  assert_true(
    query.cursor(tree.root_node(), tree.source, max_start_depth=1).next_match()
    is None,
  )
  let bounded = query.cursor(
    tree.root_node(),
    tree.source,
    start_point={ row: 0, column: 5, },
    end_point={ row: 0, column: 12, },
  )
  assert_eq(
    bounded.next_match().unwrap().captures[0].node.text(tree.source),
    "bob",
  )
  assert_true(bounded.next_match() is None)
}

///|
test "MISSING patterns accept anonymous token names" {
  let language = @generate.generate(
    @grammar.Grammar::new("parens", [
      ("document", Seq([Literal("("), Literal(")")])),
    ]),
  )
  let tree = @ts.Parser::new(language).parse_string("(")
  let query = @query.Query::new(language, "(MISSING \")\") @missing")
  assert_eq(query.captures(tree.root_node(), tree.source).length(), 1)
}

///|
test "predicate regex anchors are scoped within alternatives" {
  let tree = fixture()
  let query = @query.Query::new(
    tree.language,
    "((identifier) @id (#match? @id \"^no|ob$\"))",
  )
  assert_eq(
    query
    .captures(tree.root_node(), tree.source)
    .map(c => c.node.text(tree.source)),
    ["bob"],
  )
}

///|
test "capture cursors interleave captures from enclosing and nested matches" {
  let language = @generate.generate(
    @grammar.Grammar::new("words", [
      ("document", Repeat(Symbol("word"))),
      ("word", @grammar.pattern("[a-z]+")),
    ]),
  )
  let tree = @ts.Parser::new(language).parse_string("alice bob carol")
  let query = @query.Query::new(
    language, "(document (word) @nested) @root\n(word) @leaf",
  )
  let cursor = query.capture_cursor(tree.root_node(), tree.source)
  let result = []
  while cursor.next_capture() is Some((matched, index)) {
    let capture = matched.captures[index]
    result.push((capture.name, capture.node.start_byte()))
  }
  assert_eq(result, [
    ("root", 0),
    ("root", 0),
    ("root", 0),
    ("nested", 0),
    ("leaf", 0),
    ("nested", 6),
    ("leaf", 6),
    ("nested", 10),
    ("leaf", 10),
  ])
}

///|
test "pattern ranges and disabled captures preserve predicate inputs" {
  let tree = fixture()
  let query = @query.Query::new(
    tree.language,
    "  (identifier) @name\n(number) @value",
  )
  assert_eq(query.pattern_range(0), Some((2, 20)))
  assert_true(query.disable_pattern(1))
  assert_eq(query.captures(tree.root_node(), tree.source).length(), 3)
  assert_true(query.disable_capture("name"))
  assert_eq(query.captures(tree.root_node(), tree.source).length(), 0)
  assert_false(query.disable_pattern(-1))
  assert_false(query.disable_capture("unknown"))
  let filtered = @query.Query::new(
    tree.language,
    "((identifier) @name (#eq? @name \"bob\"))",
  )
  assert_true(filtered.disable_capture("name"))
  assert_eq(filtered.matches(tree.root_node(), tree.source).length(), 1)
}

///|
test "query construction rejects impossible named children and field types" {
  let tree = fixture()
  for
    source in [
      "(identifier (number))", "(assignment name: (number))", "(number name: (identifier))",
    ] {
    let rejected = try {
      ignore(@query.Query::new(tree.language, source))
      false
    } catch {
      InvalidQuery(_, _) => true
      _ => false
    }
    assert_true(rejected, msg=source)
  }
  ignore(@query.Query::new(tree.language, "(assignment (identifier) (number))"))
}

///|
test "capture cursors restrict captures and cancel between results" {
  let tree = fixture()
  let query = @query.Query::new(tree.language, "(identifier) @name")
  let ranged = query.capture_cursor(
    tree.root_node(),
    tree.source,
    start_byte=5,
    end_byte=8,
  )
  let item = ranged.next_capture().unwrap()
  assert_eq(item.0.captures[item.1].node.text(tree.source), "bob")
  assert_true(ranged.next_capture() is None)
  let mut stop = false
  let cursor = query.capture_cursor(tree.root_node(), tree.source, cancelled=() => {
    return stop
  })
  assert_true(cursor.next_capture() is Some(_))
  stop = true
  let cancelled = try {
    ignore(cursor.next_capture())
    false
  } catch {
    Cancelled => true
    _ => false
  }
  assert_true(cancelled)
}

///|
test "group edges and single-valued fields are rejected at their source offsets" {
  let tree = fixture()
  let invalid = [
    ("\"unknown\"", 1),
    ("(unknown)", 1),
    ("(assignment wrong: (identifier))", 12),
    ("(assignment !wrong)", 13),
    (";é\n(identifier (number))", 16),
    ("((_) .)", 5),
    ("(document ((_)+ .)? (_))", 16),
    ("(assignment name: (number))", 12),
    ("(identifier (identifier))", 12),
    ("(assignment name: (identifier) name: (identifier))", 31),
  ]
  for (source, expected) in invalid {
    try @query.Query::new(tree.language, source) catch {
      InvalidQuery(offset, _) => assert_eq(offset, expected, msg=source)
      e => fail("unexpected query error: \{@debug.Repr(e)}")
    } noraise {
      _ => fail("accepted impossible query: \{source}")
    }
  }
  for
    source in [
      "((_) . (_))", "(document (_) (_) .)", "(assignment name: (identifier)? name: (identifier))",
    ] {
    ignore(@query.Query::new(tree.language, source))
  }
}

///|
fn list_fixture(source : String) -> @ts.Tree raise {
  let language = @generate.generate(
    @grammar.Grammar::new("list", [
      (
        "array",
        Seq([
          Literal("["),
          @grammar.sep(
            Choice([Symbol("number"), Symbol("string"), Symbol("true")]),
            Literal(","),
          ),
          Literal("]"),
        ]),
      ),
      ("number", @grammar.pattern("[0-9]+")),
      ("string", @grammar.pattern("[a-z]+")),
      ("true", Literal("true")),
    ]),
  )
  @ts.Parser::new(language).parse_string(source)
}

///|
test "anonymous groups and parent captures follow tree order" {
  let tree = list_fixture("[1,2]")
  let query = @query.Query::new(tree.language, "(\"[\" @left \"]\" @right)")
  let matches = query.matches(tree.root_node(), tree.source)
  assert_eq(matches.length(), 1)
  assert_eq(matches[0].captures.map(c => c.name), ["left", "right"])
  let query = @query.Query::new(tree.language, "(array (number) @n) @a @b")
  let matches = query.matches(tree.root_node(), tree.source)
  assert_eq(matches[0].captures.map(c => c.name), ["a", "b", "n"])
}

///|
test "quantified query patterns enumerate separate runs" {
  let tree = list_fixture("[1,2,true,3,4]")
  let query = @query.Query::new(tree.language, "(array (number)+ @n)")
  let matches = query.matches(tree.root_node(), tree.source)
  assert_eq(matches.map(m => m.captures.map(c => c.node.text(tree.source))), [
    ["1", "2"],
    ["3", "4"],
  ])
}

///|
// Frozen C-query behavior, also exercised by JavaScript's public tags query:
// a leading function without documentation must survive later documented ones.
test "optional prefixes can be absent and present in separate matches" {
  let tree = list_fixture("[true,word,true]")
  for
    source in [
      "(array (string)* @s . (true) @t)", "((string)* @s . (true) @t)", "(array (string)? @s (true) @t)",
    ] {
    let query = @query.Query::new(tree.language, source)
    assert_eq(
      query
      .matches(tree.root_node(), tree.source)
      .map(m => m.captures.map(c => c.node.text(tree.source))),
      [["true"], ["word", "true"]],
      msg=source,
    )
  }
}

///|
test "anchors survive a skipped optional predecessor in the correct direction" {
  let tree = list_fixture("[1,true]")
  let after = @query.Query::new(
    tree.language,
    "(array (string)* @s . (true) @t)",
  )
  assert_eq(after.matches(tree.root_node(), tree.source).length(), 1)
  let before = @query.Query::new(tree.language, "(array . (string)* (true) @t)")
  assert_eq(before.matches(tree.root_node(), tree.source).length(), 0)
  let predicate = @query.Query::new(
    tree.language,
    "((array (string)? @s) @a (#eq? @s \"x\"))",
  )
  assert_eq(predicate.matches(tree.root_node(), tree.source).length(), 1)
}

///|
test "predicates accept absent optional captures including empty pairs" {
  let tree = list_fixture("[1]")
  for
    predicate in [
      "#eq?", "#not-eq?", "#any-eq?", "#any-not-eq?", "#match?", "#not-match?", "#any-match?",
      "#any-not-match?", "#any-of?", "#not-any-of?",
    ] {
    let query = @query.Query::new(
      tree.language,
      "((array (string)? @s) @a (\{predicate} @s \"x\"))",
    )
    assert_eq(query.matches(tree.root_node(), tree.source).length(), 1)
  }
  for predicate in ["#eq?", "#not-eq?", "#any-eq?", "#any-not-eq?"] {
    let query = @query.Query::new(
      tree.language,
      "((array (string)? @s (true)? @t) @a (\{predicate} @s @t))",
    )
    assert_eq(query.matches(tree.root_node(), tree.source).length(), 1)
  }
  let query = @query.Query::new(
    tree.language,
    "((array (string)? @s (number) @n) @a (#eq? @s @n))",
  )
  assert_eq(query.matches(tree.root_node(), tree.source).length(), 0)
}

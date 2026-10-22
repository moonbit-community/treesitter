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
  assert_eq(matches[0].captures[0].node.text(tree.source), "bob")
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
      "((identifier) @x (#magic? @x))", "(identifier", "[]",
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

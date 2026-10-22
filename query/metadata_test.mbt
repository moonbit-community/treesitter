///|
test "capture quantifiers combine sequences alternatives and repetitions" {
  let tree = fixture()
  let query = @query.Query::new(
    tree.language,
    (
      #|(identifier) @one
      #|(document (assignment)? @optional)
      #|(document (assignment)* @many)
      #|(document (assignment)+ @some)
      #|(assignment (identifier) @both (number) @both)
      #|[(identifier) @choice (number)]
      #|[(identifier) @either (number) @either]
      #|(document [(assignment) @nested (assignment)]*)
    ),
  )
  let names = [
    "one", "optional", "many", "some", "both", "choice", "either", "nested",
  ]
  let expected : Array[@query.Quantifier] = [
    One,
    ZeroOrOne,
    ZeroOrMore,
    OneOrMore,
    OneOrMore,
    ZeroOrOne,
    One,
    ZeroOrMore,
  ]
  for i, name in names {
    let capture = query.capture_names.search(name).unwrap()
    assert_eq(query.capture_quantifier(i, capture), Some(expected[i]))
    assert_eq(
      query.capture_quantifier((i + 1) % names.length(), capture),
      Some(Zero),
    )
  }
  assert_eq(query.capture_quantifier(-1, 0), None)
  assert_eq(query.capture_quantifier(0, 999), None)
  assert_true(query.disable_capture("one"))
  assert_true(query.disable_pattern(0))
  assert_eq(query.capture_quantifier(0, 0), Some(One))
}

///|
test "predicate inspection preserves order and protects compiled arguments" {
  let tree = fixture()
  let query = @query.Query::new(
    tree.language,
    (
      #|((identifier) @name (#eq? @name "a") (#set! role "variable") (#custom! @name))
    ),
  )
  let predicates = query.predicates(0).unwrap()
  assert_eq(predicates.map(p => p.name), ["#eq?", "#set!", "#custom!"])
  predicates[0].args.clear()
  predicates.clear()
  assert_eq(query.predicates(0).unwrap()[0].args.length(), 2)
  assert_eq(
    query
    .matches(tree.root_node(), tree.source, predicate=(_, _, _, _) => true)
    .length(),
    1,
  )
  assert_true(query.predicates(9) is None)
}

///|
test "removing a match suppresses only its remaining captures" {
  let tree = fixture()
  let query = @query.Query::new(
    tree.language,
    (
      #|(assignment (identifier) @name (number) @value) @assignment
    ),
  )
  let cursor = query.capture_cursor(tree.root_node(), tree.source)
  let (first, index) = cursor.next_capture().unwrap()
  assert_eq(first.captures[index].name, "assignment")
  cursor.remove_match(first.id)
  cursor.remove_match(first.id)
  cursor.remove_match(-1)
  let remaining = []
  while cursor.next_capture() is Some((matched, index)) {
    assert_true(matched.id != first.id)
    remaining.push(matched.captures[index].node.text(tree.source))
  }
  assert_eq(remaining, ["bob=20;", "bob", "20", "c=3;", "c", "3"])
  let matches = query.matches(tree.root_node(), tree.source)
  assert_eq(matches.map(m => m.id), [0, 1, 2])
}

///|
test "containing ranges constrain matched nodes including uncaptured roots" {
  let tree = fixture()
  let query = @query.Query::new(
    tree.language,
    (
      #|(assignment (identifier) @name (number) @value)
      #|(document (assignment) @child)
    ),
  )
  let matches = query.matches(
    tree.root_node(),
    tree.source,
    containing_byte_range=(5, 12),
  )
  assert_eq(matches.length(), 1)
  assert_eq(matches[0].captures.map(c => c.node.text(tree.source)), [
    "bob", "20",
  ])
  assert_eq(
    query
    .matches(tree.root_node(), tree.source, containing_byte_range=(6, 12))
    .length(),
    0,
  )
  let cursor = query.capture_cursor(
    tree.root_node(),
    tree.source,
    start_byte=6,
    end_byte=10,
    containing_point_range=({ row: 0, column: 5, }, { row: 0, column: 12, }),
  )
  let captures = []
  while cursor.next_capture() is Some((matched, index)) {
    captures.push(matched.captures[index].node.text(tree.source))
  }
  assert_eq(captures, ["bob", "20"])
  assert_eq(
    query
    .matches(tree.root_node(), tree.source, containing_byte_range=(13, 0))
    .length(),
    1,
  )
}

///|
test "containing ranges apply to each sibling in an unrooted group" {
  let tree = fixture()
  let query = @query.Query::new(
    tree.language,
    (
      #|((assignment) @first (assignment) @second)
    ),
  )
  assert_eq(
    query
    .matches(tree.root_node(), tree.source, containing_byte_range=(5, 12))
    .length(),
    0,
  )
  let matches = query.matches(
    tree.root_node(),
    tree.source,
    containing_byte_range=(5, 17),
  )
  assert_eq(matches.length(), 1)
  assert_eq(matches[0].captures.map(c => c.node.text(tree.source)), [
    "bob=20;", "c=3;",
  ])
}

///|
test "zero range ends are unbounded" {
  let tree = fixture()
  let query = @query.Query::new(tree.language, "(assignment) @item")
  assert_eq(
    query
    .matches(tree.root_node(), tree.source, start_byte=5, end_byte=0)
    .length(),
    2,
  )
  let cursor = query.cursor(
    tree.root_node(),
    tree.source,
    start_point={ row: 0, column: 5, },
    end_point={ row: 0, column: 0, },
    containing_point_range=({ row: 0, column: 5, }, { row: 0, column: 0, }),
  )
  let nodes = []
  while cursor.next_match() is Some(matched) {
    nodes.push(matched.captures[0].node.text(tree.source))
  }
  assert_eq(nodes, ["bob=20;", "c=3;"])
}

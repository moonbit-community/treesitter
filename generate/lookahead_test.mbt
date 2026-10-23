///|
test "lookahead includes nonterminals and implicit terminal extras" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "lookahead",
      [
        ("document", Seq([Literal("a"), Literal("b")])),
        ("comment", Literal("#")),
      ],
      extras=[Symbol("comment")],
    ),
  )
  let names = language.lookahead(0).map(id => language.symbols[id].name)
  names.sort()
  assert_eq(names, ["a", "comment", "document"])
  let a = language.symbol_id("a", named=false).unwrap()
  let b = language.symbol_id("b", named=false).unwrap()
  let comment = language.symbol_id("comment").unwrap()
  let document = language.symbol_id("document").unwrap()
  let after_a = language.next_state(0, a).unwrap()
  assert_true(language.next_state(after_a, b) is Some(_))
  assert_eq(language.next_state(0, b), None)
  assert_eq(language.next_state(0, comment), Some(0))
  assert_eq(language.next_state(after_a, comment), Some(after_a))
  assert_true(language.next_state(0, document) is Some(_))
  assert_eq(language.next_state(-1, a), None)
  assert_eq(language.next_state(0, -1), None)
  assert_eq(language.next_state(language.states.length(), a), None)
  assert_eq(language.next_state(0, language.symbols.length()), None)
  let iterator = language.lookahead_iterator(0).unwrap()
  assert_eq(iterator.current_symbol(), None)
  assert_eq(iterator.current_symbol_name(), None)
  let visited = []
  while iterator.next() is Some(symbol) {
    visited.push(symbol)
    assert_eq(iterator.current_symbol(), Some(symbol))
    assert_eq(
      iterator.current_symbol_name(),
      Some(language.symbols[symbol].name),
    )
  }
  assert_eq(visited, language.lookahead(0))
  assert_eq(iterator.current_symbol(), None)
  assert_eq(iterator.current_symbol_name(), None)
  assert_eq(iterator.next(), None)
  assert_true(iterator.reset_state(after_a))
  assert_eq(iterator.current_symbol(), None)
  let first = iterator.next()
  assert_false(iterator.reset_state(-1))
  assert_eq(iterator.current_symbol(), first)
  let other = @generate.generate(
    @grammar.Grammar::new("other", [("root", Literal("x"))]),
  )
  assert_false(iterator.reset(other, other.states.length()))
  assert_eq(iterator.language().name, "lookahead")
  assert_eq(iterator.current_symbol(), first)
  assert_true(iterator.reset(other, 0))
  assert_eq(iterator.language().name, "other")
  assert_eq(iterator.current_symbol_name(), None)
  assert_true(iterator.next() is Some(_))
  assert_true(language.lookahead_iterator(-1) is None)
  assert_true(language.lookahead_iterator(language.states.length()) is None)
}

///|
test "lookahead transitions follow extra entry and the last conflict action" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "extra",
      [
        ("document", Literal("a")),
        ("comment", Seq([Literal("/"), Literal("/")])),
      ],
      extras=[Symbol("comment")],
    ),
  )
  let slash = language.symbol_id("/", named=false).unwrap()
  let next = language.next_state(0, slash).unwrap()
  assert_true(language.next_state(next, slash) is Some(_))
  // A reduction is not a direct shift, even if a conflict also offers a shift.
  let row = language.states[0]
  row.actions[slash] = [Shift(0), Reduce(0)]
  assert_eq(language.next_state(0, slash), None)
  row.actions[slash] = [Reduce(0), Shift(0)]
  assert_eq(language.next_state(0, slash), Some(0))
  row.actions[slash] = [EnterExtra(0)]
  assert_eq(language.next_state(0, slash), None)
  row.actions[slash] = []
  assert_false(language.lookahead(0).contains(slash))
}

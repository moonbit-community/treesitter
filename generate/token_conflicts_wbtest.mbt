// Ports of the tests in tree-sitter crates/generate/src/build_tables/token_conflicts.rs.
//
// Upstream builds each lexical grammar with `expand_tokens`. The NFAs below are
// the exact ones it produces (dumped from the pinned upstream crate), so the
// tests don't depend on the `expand_tokens` port.

///|
fn char_set(ranges : Array[(Int32, Int32)]) -> CharacterSet {
  let result = CharacterSet::empty()
  for range in ranges {
    result.add_range_in_place(range.0, range.1 - 1)
  }
  result
}

///|
fn test_lexical_grammar(
  pool : StrPool,
  names : Array[String],
  states : Array[NfaState],
  variables : Array[(Int32, Int32, Int32)],
) -> LexicalGrammar {
  {
    nfa: { states, },
    variables: variables.map(v => {
      name: pool.intern(names[v.0]),
      kind: Named,
      implicit_precedence: v.1,
      start_state: v.2,
    }),
  }
}

///|
fn index_of_var(
  pool : StrPool,
  grammar : LexicalGrammar,
  name : String,
) -> Int32 {
  grammar.variables.search_by(v => pool.resolve(v.name) == name).unwrap()
}

///|
test "starting characters" {
  // token_0: /[a-f]1|0x\d/, token_1: /d*ef/
  let pool = StrPool::new()
  let names = ["token_0", "token_1"]
  let states : Array[NfaState] = [
    Accept(variable_index=0, precedence=0),
    Advance(chars=char_set([(49, 50)]), state_id=0, is_sep=false, precedence=0),
    Advance(chars=char_set([(97, 103)]), state_id=1, is_sep=false, precedence=0),
    Advance(chars=char_set([(48, 58)]), state_id=0, is_sep=false, precedence=0),
    Advance(
      chars=char_set([(120, 121)]),
      state_id=3,
      is_sep=false,
      precedence=0,
    ),
    Advance(chars=char_set([(48, 49)]), state_id=4, is_sep=false, precedence=0),
    Split(2, 5),
    Accept(variable_index=1, precedence=0),
    Advance(
      chars=char_set([(102, 103)]),
      state_id=7,
      is_sep=false,
      precedence=0,
    ),
    Advance(
      chars=char_set([(101, 102)]),
      state_id=8,
      is_sep=false,
      precedence=0,
    ),
    Split(11, 9),
    Advance(
      chars=char_set([(100, 101)]),
      state_id=10,
      is_sep=false,
      precedence=0,
    ),
    Split(9, 11),
  ]
  let grammar = test_lexical_grammar(pool, names, states, [
    (0, 0, 6),
    (1, 0, 12),
  ])
  let token_map = TokenConflictMap::new(grammar, [])
  assert_eq(
    token_map.starting_chars_by_index[0],
    CharacterSet::empty()
    .add_range('a'.to_int(), 'f'.to_int())
    .add_char('0'.to_int()),
  )
  assert_eq(
    token_map.starting_chars_by_index[1],
    CharacterSet::empty().add_range('d'.to_int(), 'e'.to_int()),
  )
}

///|
test "token conflicts" {
  // in: "in", identifier: /\w+/, instanceof: "instanceof"
  let pool = StrPool::new()
  let names = ["in", "identifier", "instanceof"]
  let states : Array[NfaState] = [
    Accept(variable_index=0, precedence=0),
    Advance(
      chars=char_set([(110, 111)]),
      state_id=0,
      is_sep=false,
      precedence=0,
    ),
    Advance(
      chars=char_set([(105, 106)]),
      state_id=1,
      is_sep=false,
      precedence=0,
    ),
    Accept(variable_index=1, precedence=0),
    Split(5, 3),
    Advance(
      chars=char_set([(48, 58), (65, 91), (95, 96), (97, 123)]),
      state_id=4,
      is_sep=false,
      precedence=0,
    ),
    Accept(variable_index=2, precedence=0),
    Advance(
      chars=char_set([(102, 103)]),
      state_id=6,
      is_sep=false,
      precedence=0,
    ),
    Advance(
      chars=char_set([(111, 112)]),
      state_id=7,
      is_sep=false,
      precedence=0,
    ),
    Advance(
      chars=char_set([(101, 102)]),
      state_id=8,
      is_sep=false,
      precedence=0,
    ),
    Advance(chars=char_set([(99, 100)]), state_id=9, is_sep=false, precedence=0),
    Advance(
      chars=char_set([(110, 111)]),
      state_id=10,
      is_sep=false,
      precedence=0,
    ),
    Advance(chars=char_set([(97, 98)]), state_id=11, is_sep=false, precedence=0),
    Advance(
      chars=char_set([(116, 117)]),
      state_id=12,
      is_sep=false,
      precedence=0,
    ),
    Advance(
      chars=char_set([(115, 116)]),
      state_id=13,
      is_sep=false,
      precedence=0,
    ),
    Advance(
      chars=char_set([(110, 111)]),
      state_id=14,
      is_sep=false,
      precedence=0,
    ),
    Advance(
      chars=char_set([(105, 106)]),
      state_id=15,
      is_sep=false,
      precedence=0,
    ),
  ]
  let grammar = test_lexical_grammar(pool, names, states, [
    (0, 2, 2),
    (1, 0, 5),
    (2, 2, 16),
  ])
  let var_index = name => index_of_var(pool, grammar, name)
  let token_map = TokenConflictMap::new(grammar, [
    TokenSet::from_array([Symbol::terminal(var_index("identifier"))]),
    TokenSet::from_array([Symbol::terminal(var_index("in"))]),
    TokenSet::from_array([Symbol::terminal(var_index("identifier"))]),
  ])

  // Given the string "in", the `in` token is preferrred over the `identifier` token
  assert_true(
    token_map.does_match_same_string(var_index("in"), var_index("identifier")),
  )
  assert_false(
    token_map.does_match_same_string(var_index("identifier"), var_index("in")),
  )

  // Depending on what character follows, the string "in" may be treated as part of an
  // `identifier` token
  assert_true(token_map.does_conflict(var_index("identifier"), var_index("in")))

  // Depending on what character follows, the string "instanceof" may be treated as part
  // of an `identifier` token
  assert_true(
    token_map.does_conflict(var_index("identifier"), var_index("instanceof")),
  )
  assert_true(token_map.does_conflict(var_index("instanceof"), var_index("in")))
}

///|
test "token conflicts with separators" {
  // x: "x", newline: "\n", separators: [/\s/]
  let pool = StrPool::new()
  let names = ["x", "newline"]
  let states : Array[NfaState] = [
    Accept(variable_index=0, precedence=0),
    Advance(
      chars=char_set([(120, 121)]),
      state_id=0,
      is_sep=false,
      precedence=0,
    ),
    Split(4, 1),
    Advance(
      chars=char_set([(9, 14), (32, 33)]),
      state_id=2,
      is_sep=true,
      precedence=0,
    ),
    Split(2, 3),
    Accept(variable_index=1, precedence=0),
    Advance(chars=char_set([(10, 11)]), state_id=5, is_sep=false, precedence=0),
    Split(9, 6),
    Advance(
      chars=char_set([(9, 14), (32, 33)]),
      state_id=7,
      is_sep=true,
      precedence=0,
    ),
    Split(7, 8),
  ]
  let grammar = test_lexical_grammar(pool, names, states, [(0, 2, 4), (1, 2, 9)])
  let var_index = name => index_of_var(pool, grammar, name)
  let token_map = TokenConflictMap::new(
    grammar,
    Array::makei(4, _ => TokenSet::new()),
  )
  assert_true(token_map.does_conflict(var_index("newline"), var_index("x")))
  assert_false(token_map.does_conflict(var_index("x"), var_index("newline")))
}

///|
test "token conflicts with open ended tokens" {
  // x: "x", anything: prec(-1, /.*/), separators: [/\s/]
  let pool = StrPool::new()
  let names = ["x", "anything"]
  let states : Array[NfaState] = [
    Accept(variable_index=0, precedence=0),
    Advance(
      chars=char_set([(120, 121)]),
      state_id=0,
      is_sep=false,
      precedence=0,
    ),
    Split(4, 1),
    Advance(
      chars=char_set([(9, 14), (32, 33)]),
      state_id=2,
      is_sep=true,
      precedence=0,
    ),
    Split(2, 3),
    Accept(variable_index=1, precedence=-1),
    Split(7, 5),
    Advance(
      chars=char_set([(0, 10), (11, 1114112)]),
      state_id=6,
      is_sep=false,
      precedence=-1,
    ),
    Split(5, 7),
    Split(11, 8),
    Advance(
      chars=char_set([(9, 14), (32, 33)]),
      state_id=9,
      is_sep=true,
      precedence=0,
    ),
    Split(9, 10),
  ]
  let grammar = test_lexical_grammar(pool, names, states, [
    (0, 2, 4),
    (1, 0, 11),
  ])
  let var_index = name => index_of_var(pool, grammar, name)
  let token_map = TokenConflictMap::new(
    grammar,
    Array::makei(4, _ => TokenSet::new()),
  )
  assert_true(
    token_map.does_match_shorter_or_longer(
      var_index("anything"),
      var_index("x"),
    ),
  )
  assert_false(
    token_map.does_match_shorter_or_longer(
      var_index("x"),
      var_index("anything"),
    ),
  )
}

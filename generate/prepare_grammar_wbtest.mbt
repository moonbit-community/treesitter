// Tests ported from tree-sitter crates/generate/src/prepare_grammar.rs that do
// not need `expand_tokens`. The rest are in `prepare_grammar_e2e_wbtest.mbt`.

///|
fn prec(pool : RulePool, name : String, content : RuleId) -> RuleId {
  let p = Precedence::Name(pool.intern(name))
  pool.prec(p, content)
}

///|
fn prec_left(pool : RulePool, name : String, content : RuleId) -> RuleId {
  let p = Precedence::Name(pool.intern(name))
  pool.prec_left(p, content)
}

///|
fn name_entry(pool : RulePool, name : String) -> PrecedenceEntry {
  Name(pool.intern(name))
}

///|
test "validate_precedences_with_undeclared_precedences" {
  let pool = RulePool::new()

  // v1: seq(prec_left('b', "w"), prec('c', "x"))
  let v1 = {
    let w = leaf(pool, "w")
    let left = prec_left(pool, "b", w)
    let x = leaf(pool, "x")
    let right = prec(pool, "c", x)
    pool.seq([left, right])
  }
  // v2: repeat(choice(prec_left('omg', "y"), prec('c', "z")))
  let v2 = {
    let y = leaf(pool, "y")
    let left = prec_left(pool, "omg", y)
    let z = leaf(pool, "z")
    let right = prec(pool, "c", z)
    let choice = pool.choice([left, right])
    pool.repeat(choice)
  }
  let v1_name = pool.intern("v1")
  let v2_name = pool.intern("v2")
  let precedence_orderings = [
    [name_entry(pool, "a"), name_entry(pool, "b")],
    [name_entry(pool, "b"), name_entry(pool, "c"), name_entry(pool, "d")],
  ]
  let grammar = {
    ..pool_grammar(pool, [
      { name: v1_name, root: v1, },
      { name: v2_name, root: v2, },
    ]),
    precedence_orderings,
  }
  try validate_precedences(grammar) catch {
    err => {
      assert_eq(err, UndeclaredPrecedenceError(precedence="omg", rule="v2"))
      inspect(err, content="Undeclared precedence 'omg' in rule 'v2'")
    }
  } noraise {
    _ => fail("expected an error")
  }
}

///|
test "validate_precedences_with_conflicting_order" {
  let pool = RulePool::new()
  let precedence_orderings = [
    [name_entry(pool, "a"), name_entry(pool, "b")],
    [name_entry(pool, "b"), name_entry(pool, "c"), name_entry(pool, "a")],
  ]
  let grammar = { ..pool_grammar(pool, []), precedence_orderings, }
  try validate_precedences(grammar) catch {
    err => {
      assert_eq(
        err,
        ConflictingPrecedenceOrderingError(
          precedence_1="'a'",
          precedence_2="'b'",
        ),
      )
      inspect(err, content="Conflicting orderings for precedences 'a' and 'b'")
    }
  } noraise {
    _ => fail("expected an error")
  }
}

///|
test "prepare_grammar error texts" {
  inspect(
    IndirectRecursionError(["a", "b", "a"]),
    content="Grammar contains an indirectly recursive rule: a -> b -> a",
  )
  inspect(
    EmptyStringExtraError("comment"),
    content=(
      #|The extra rule `comment` matches the empty string.
      #|
      #|Tree-sitter does not support extras that match the empty string.
      #|
    ),
  )
}

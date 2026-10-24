// Ports of the tests in tree-sitter crates/generate/src/build_tables/build_parse_table.rs.

///|
test "auxiliary context lookup" {
  //   source_file: $ => seq(repeat('x'), $.block),
  //   block: $ => seq('{', repeat('y'), '}', repeat('x')),
  let variable = (kind : VariableType) => SyntaxVariable::{
    name: empty_str_id,
    kind,
  }
  let grammar : SyntaxGrammar = {
    variables: [
      variable(Named),
      variable(Named),
      variable(Auxiliary),
      variable(Auxiliary),
    ],
    extra_symbols: [],
    expected_conflicts: [],
    external_tokens: [],
    supertype_symbols: [],
    variables_to_inline: [],
    word_token: None,
    precedence_orderings: [],
    reserved_word_sets: [],
    steps: [],
    productions: [],
    var_prods: [],
  }
  let (source_file, block, x_repeat, y_repeat) = (0, 1, 2, 3)

  // The contexts of three states along one path through the grammar:
  //
  //   source_file: • repeat('x') block
  //   block: '{' • repeat('y') '}' repeat('x')
  //   block: '{' repeat('y') '}' • repeat('x')
  let contexts = AuxiliarySymbolContexts::new()
  let first = contexts.push(grammar, None, [
    auxiliary_use(x_repeat, source_file),
  ])
  let second = contexts.push(grammar, first, [auxiliary_use(y_repeat, block)])
  let third = contexts.push(grammar, second, [auxiliary_use(x_repeat, block)])
  let parents = (context, symbol) => {
    match contexts.parents(context, symbol) {
      Some(view) => Some(view.to_owned())
      None => None
    }
  }

  // The nearest context has the symbol.
  assert_eq(parents(second, y_repeat), Some([Symbol::non_terminal(block)]))
  // Only a predecessor has it.
  assert_eq(
    parents(second, x_repeat),
    Some([Symbol::non_terminal(source_file)]),
  )
  // A more recent entry hides an earlier one.
  assert_eq(parents(third, x_repeat), Some([Symbol::non_terminal(block)]))
  // Nothing along the path recorded it.
  assert_eq(parents(first, y_repeat), None)
}

///|
test "conflict error display" {
  let error : ParseTableBuilderError = Conflict({
    symbol_sequence: ["expression", "'+'", "expression"],
    conflicting_lookahead: "'+'",
    possible_interpretations: [
      {
        preceding_symbols: [],
        variable_name: "sum",
        production_step_symbols: ["expression", "'+'", "expression"],
        step_index: 3,
        done: true,
        conflicting_lookahead: "'+'",
        precedence: Some("1"),
        associativity: None,
        requires_eof_lookahead: false,
      },
      {
        preceding_symbols: ["expression", "'+'"],
        variable_name: "sum",
        production_step_symbols: ["expression", "'+'", "expression"],
        step_index: 1,
        done: false,
        conflicting_lookahead: "'+'",
        precedence: None,
        associativity: None,
        requires_eof_lookahead: false,
      },
    ],
    possible_resolutions: [
      Associativity(symbols=["sum"]),
      AddConflict(symbols=["sum"]),
    ],
  })
  inspect(
    error,
    content=(
      #|Unresolved conflict for symbol sequence:
      #|
      #|  expression  '+'  expression  •  '+'  …
      #|
      #|Possible interpretations:
      #|
      #|  1:  (sum  expression  '+'  expression)  •  '+'  …           (precedence: 1)
      #|  2:  expression  '+'  (sum  expression  •  '+'  expression)
      #|
      #|Possible resolutions:
      #|
      #|  1:  Specify a left or right associativity in `sum`
      #|  2:  Add a conflict for these rules: `sum`
      #|
    ),
  )
}

///|
test "rust_str_cmp orders by code point" {
  assert_true(rust_str_cmp("a", "b") < 0)
  assert_true(rust_str_cmp("ab", "b") < 0)
  assert_true(rust_str_cmp("b", "ab") > 0)
  assert_true(rust_str_cmp("a", "ab") < 0)
  assert_eq(rust_str_cmp("same", "same"), 0)
  // U+FF21 (one UTF-16 unit) sorts before U+1F600 (a surrogate pair).
  assert_true(rust_str_cmp("\u{FF21}", "\u{1F600}") < 0)
}

///|
/// Iteration orders of `FxHashSet<u32>`s, compared by FNV-1a hash with the
/// output of tools/next/build_tables_harness/fxset.rs built with Rust 1.97.1.
test "fx_hash_set_u32_order matches Rust" {
  let mut state : UInt64 = 12345
  let buf = StringBuilder()
  for len in 0..<60 {
    for modulus in [8U, 100, 3000] {
      let values = []
      for _ in 0..<len {
        state = state * 6364136223846793005UL + 1442695040888963407UL
        values.push(((state >> 33).to_uint() % modulus).reinterpret_as_int())
      }
      buf.write_string(
        fx_hash_set_u32_order(values).map(v => v.to_string()).join(" "),
      )
      buf.write_char('\n')
    }
  }
  let text = buf.to_string()
  let mut h : UInt64 = 0xcbf29ce484222325
  for i in 0..<text.length() {
    h = h ^ text[i].to_uint64()
    h = h * 0x100000001b3UL
  }
  inspect(text.length(), content="13291")
  assert_eq(h, 0x0c8a945c5c530226UL)
}

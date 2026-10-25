// Port of tree-sitter crates/cli/src/tests/language_test.rs.

///|
async test "lookahead_iterator" {
  let parser = @treesitter.Parser::new()
  guard get_parsing_language("rust") is Some(language) else { return }
  parser.set_language(language)
  let tree = parse(parser, "struct Stuff {}")
  let cursor = tree.walk()
  assert_true(cursor.goto_first_child()) // struct
  assert_true(cursor.goto_first_child()) // struct keyword
  let next_state = cursor.node().next_parse_state()
  assert_not_eq(next_state, 0)
  assert_eq(
    next_state,
    language.next_state(cursor.node().parse_state(), cursor.node().grammar_id()),
  )
  assert_true(next_state < language.parse_state_count())
  assert_true(cursor.goto_next_sibling()) // type_identifier
  assert_eq(next_state, cursor.node().parse_state())
  assert_eq(cursor.node().grammar_name(), "identifier")
  assert_not_eq(cursor.node().grammar_id(), cursor.node().kind_id())
  let expected_symbols = [
    "//", "/*", "identifier", "line_comment", "block_comment",
  ]
  let lookahead = language.lookahead_iterator(next_state).unwrap()
  assert_eq(lookahead.language(), language)
  assert_eq(lookahead.iter_names().to_array(), expected_symbols)
  assert_eq(lookahead.iter_names().count(), 0)
  assert_true(lookahead.reset_state(next_state))
  assert_eq(lookahead.iter_names().to_array(), expected_symbols)
  assert_true(lookahead.reset(language, next_state))
  assert_eq(
    lookahead.iter().map(s => language.node_kind_for_id(s).unwrap()).to_array(),
    expected_symbols,
  )
}

///|
async test "lookahead_iterator_modifiable_only_by_mut" {
  let parser = @treesitter.Parser::new()
  guard get_parsing_language("rust") is Some(language) else { return }
  parser.set_language(language)
  let tree = parse(parser, "struct Stuff {}")
  let cursor = tree.walk()
  assert_true(cursor.goto_first_child()) // struct
  assert_true(cursor.goto_first_child()) // struct keyword
  let next_state = cursor.node().next_parse_state()
  assert_not_eq(next_state, 0)
  let lookahead = language.lookahead_iterator(next_state).unwrap()
  let _ = lookahead.next()
  let names = lookahead.iter_names()
  let _ = names.next()
}

///|
async test "lookahead_iterator_exhaustion" {
  guard get_language("json") is Some(language) else { return }
  for state in 0..<language.parse_state_count() {
    let lookahead = language.lookahead_iterator(state).unwrap()

    // A fresh iterator is not positioned on a symbol.
    assert_eq(lookahead.current_symbol(), None)
    assert_eq(lookahead.current_symbol_name(), None)
    let count = lookahead.iter().count()

    // An exhausted iterator is not positioned on a symbol, and stays exhausted.
    assert_eq(lookahead.current_symbol(), None)
    assert_eq(lookahead.current_symbol_name(), None)
    assert_eq(lookahead.iter().count(), 0)
    assert_eq(lookahead.iter_names().count(), 0)

    // Resetting restores it exactly.
    assert_true(lookahead.reset_state(state))
    assert_eq(lookahead.current_symbol(), None)
    assert_eq(lookahead.iter().count(), count)
  }
}

///|
async test "id_for_node_kind_only_matches_the_whole_error_name" {
  guard get_language("javascript") is Some(language) else { return }
  assert_eq(language.id_for_node_kind("ERROR", true), 0xFFFF) // u16::MAX
  for name in ["", "E", "ER", "ERR", "ERRO"] {
    assert_eq(
      language.id_for_node_kind(name, true),
      0,
      msg=rust_debug_str(name),
    )
  }
}

///|
async test "symbol_metadata_checks" {
  guard get_language("rust") is Some(language) else { return }
  for i in 0..<language.node_kind_count() {
    let sym = i
    let name = language.node_kind_for_id(sym).unwrap()
    match name {
      "_type"
      | "_expression"
      | "_pattern"
      | "_literal"
      | "_literal_pattern"
      | "_declaration_statement" =>
        assert_true(language.node_kind_is_supertype(sym))
      "_raw_string_literal_start"
      | "_raw_string_literal_end"
      | "_line_doc_comment"
      | "_error_sentinel" => assert_false(language.node_kind_is_supertype(sym))
      "enum_item" | "struct_item" | "type_item" =>
        assert_true(language.node_kind_is_named(sym))
      "=>" | "[" | "]" | "(" | ")" | "{" | "}" =>
        assert_true(language.node_kind_is_visible(sym))
      _ => ()
    }
  }
}

///|
async test "supertypes" {
  guard get_language("rust") is Some(language) else { return }
  let supertypes = language.supertypes()
  if language.abi_version() < 15 {
    return
  }
  assert_eq(supertypes.length(), 5)
  assert_eq(
    supertypes.iter().filter_map(s => language.node_kind_for_id(s)).to_array(),
    ["_expression", "_literal", "_literal_pattern", "_pattern", "_type"],
  )
  for supertype in supertypes {
    let subtypes = language
      .subtypes_for_supertype(supertype)
      .iter()
      .filter_map(symbol => language.node_kind_for_id(symbol))
      .to_array()
    subtypes.sort_by(lex_compare)
    subtypes.dedup()
    match language.node_kind_for_id(supertype) {
      Some("_literal") =>
        assert_eq(subtypes, [
          "boolean_literal", "char_literal", "float_literal", "integer_literal",
          "raw_string_literal", "string_literal",
        ])
      Some("_pattern") =>
        assert_eq(subtypes, [
          "_", "_literal_pattern", "captured_pattern", "const_block", "generic_pattern",
          "identifier", "macro_invocation", "mut_pattern", "or_pattern", "range_pattern",
          "ref_pattern", "reference_pattern", "remaining_field_pattern", "scoped_identifier",
          "slice_pattern", "struct_pattern", "tuple_pattern", "tuple_struct_pattern",
        ])
      Some("_type") =>
        assert_eq(subtypes, [
          "abstract_type", "array_type", "bounded_type", "dynamic_type", "function_type",
          "generic_type", "macro_invocation", "metavariable", "never_type", "pointer_type",
          "primitive_type", "reference_type", "removed_trait_bound", "scoped_type_identifier",
          "tuple_type", "type_identifier", "unit_type",
        ])
      _ => ()
    }
  }
}

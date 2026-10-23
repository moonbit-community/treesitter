// Port of tree-sitter crates/cli/src/tests/language_test.rs.

///|
async test "lookahead_iterator" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let parser = parser_for(language)
  let tree = parse(parser, "struct Stuff {}")
  let cursor = tree.walk()
  assert_true(cursor.goto_first_child()) // struct
  assert_true(cursor.goto_first_child()) // struct keyword
  let next_state = cursor.node().next_parse_state()
  assert_true(next_state != 0)
  assert_eq(
    next_state,
    language.next_state(cursor.node().parse_state(), cursor.node().grammar_id()),
  )
  assert_true(next_state < language.parse_state_count())
  assert_true(cursor.goto_next_sibling()) // type_identifier
  assert_eq(next_state, cursor.node().parse_state())
  assert_eq(cursor.node().grammar_name(), "identifier")
  assert_true(cursor.node().grammar_id() != cursor.node().kind_id())
  let expected_symbols = [
    "//", "/*", "identifier", "line_comment", "block_comment",
  ]
  let lookahead = language.lookahead_iterator(next_state).unwrap()
  assert_true(lookahead.language() == language)
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
/// `lookahead_iterator` adapted to the C grammar (whose parser needs no
/// external scanner): the iterator, its names and a reset agree.
async test "lookahead_iterator (c)" {
  guard get_parsing_language("c") is Some(language) else { return }
  let parser = parser_for(language)
  let tree = parse(parser, "struct Stuff {};")
  let cursor = tree.walk()
  assert_true(cursor.goto_first_child()) // struct_specifier
  assert_true(cursor.goto_first_child()) // struct keyword
  let next_state = cursor.node().next_parse_state()
  assert_true(next_state != 0)
  assert_eq(
    next_state,
    language.next_state(cursor.node().parse_state(), cursor.node().grammar_id()),
  )
  assert_true(next_state < language.parse_state_count())
  assert_true(cursor.goto_next_sibling()) // type_identifier
  assert_eq(next_state, cursor.node().parse_state())
  assert_eq(cursor.node().kind(), "type_identifier")
  assert_eq(cursor.node().grammar_name(), "identifier")
  assert_true(cursor.node().grammar_id() != cursor.node().kind_id())
  let lookahead = language.lookahead_iterator(next_state).unwrap()
  assert_true(lookahead.language() == language)
  let names = lookahead.iter_names().to_array()
  assert_true(names.contains("identifier"))
  assert_eq(lookahead.iter_names().count(), 0)
  assert_true(lookahead.reset_state(next_state))
  assert_eq(lookahead.iter_names().to_array(), names)
  assert_true(lookahead.reset(language, next_state))
  assert_eq(
    lookahead.iter().map(s => language.node_kind_for_id(s).unwrap()).to_array(),
    names,
  )
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
  assert_true(language.lookahead_iterator(language.parse_state_count()) is None)
}

///|
async test "id_for_node_kind_only_matches_the_whole_error_name" {
  guard get_language("javascript") is Some(language) else { return }
  assert_eq(language.id_for_node_kind("ERROR", true), 0xFFFF)
  for name in ["", "E", "ER", "ERR", "ERRO"] {
    assert_eq(language.id_for_node_kind(name, true), 0)
  }
}

///|
async test "symbol_metadata_checks" {
  guard get_language("rust") is Some(language) else { return }
  for sym in 0..<language.node_kind_count() {
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
  // Out-of-range ids are rejected instead of indexing the tables.
  assert_false(language.node_kind_is_named(language.node_kind_count()))
  assert_true(language.node_kind_is_named(0xFFFF))
  assert_false(language.node_kind_is_visible(0xFFFE))
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
      .filter_map(s => language.node_kind_for_id(s))
      .to_array()
    subtypes.sort_by(lex_compare)
    subtypes.dedup()
    match language.node_kind_for_id(supertype) {
      Some("_literal") =>
        assert_eq(subtypes, [
          "boolean_literal", "char_literal", "float_literal", "integer_literal",
          "raw_string_literal", "string_literal",
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

///|
async test "language accessors" {
  guard get_language("json") is Some(language) else { return }
  assert_eq(language.name(), Some("json"))
  assert_eq(language.abi_version(), @api.language_version)
  assert_true(language.is_parseable())
  assert_eq(language.field_name_for_id(0), None)
  assert_eq(language.field_id_for_name("nope"), None)
  match language.field_id_for_name("key") {
    Some(id) => assert_eq(language.field_name_for_id(id), Some("key"))
    None => fail("json has a `key` field")
  }
  let pair = language.id_for_node_kind("pair", true)
  assert_eq(language.node_kind_for_id(pair), Some("pair"))
  assert_true(language.node_kind_is_named(pair))
  assert_true(language.node_kind_is_visible(pair))
  assert_false(language.node_kind_is_supertype(pair))
  assert_true(language.metadata() is Some(_))
  // A language with external tokens but no scanner cannot be used to parse.
  guard get_language("javascript") is Some(javascript) else { return }
  let unparseable = @api.Language::new(javascript.raw())
  assert_false(unparseable.is_parseable())
  let parser = @api.Parser::new()
  try parser.set_language(unparseable) catch {
    e => inspect(e, content="Language cannot be used for parsing.")
  } noraise {
    _ => fail("expected an error")
  }
  let old : @language.Language = { ..language.raw(), abi_version: 12, }
  try parser.set_language(@api.Language::new(old)) catch {
    e =>
      inspect(
        e,
        content="Incompatible language version 12. Expected minimum 13, maximum 15",
      )
  } noraise {
    _ => fail("expected an error")
  }
  assert_true(parser.language() is None)
}

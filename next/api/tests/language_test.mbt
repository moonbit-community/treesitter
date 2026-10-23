// Checks of the language API beyond the port of
// crates/cli/src/tests/language_test.rs (language_suite_test.mbt), and
// variants of its tests adapted to grammars whose scanners are ported.

///|
/// The iterator of a state past the last one is not created.
async test "lookahead_iterator past the last state" {
  guard get_language("json") is Some(language) else { return }
  assert_true(language.lookahead_iterator(language.parse_state_count()) is None)
}

///|
/// Out-of-range ids are rejected instead of indexing the tables.
async test "symbol metadata of out-of-range ids" {
  guard get_language("rust") is Some(language) else { return }
  assert_false(language.node_kind_is_named(language.node_kind_count()))
  assert_true(language.node_kind_is_named(0xFFFF))
  assert_false(language.node_kind_is_visible(0xFFFE))
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

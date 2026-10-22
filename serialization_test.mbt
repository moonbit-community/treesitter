///|
test "serialized language loads without grammar generation and preserves behavior" {
  let language = arithmetic()
  let encoded = Json(language).stringify()
  let loaded = @language.Language::parse(encoded)
  assert_eq(loaded, language)
  let original = @treesitter.Parser::new(language).parse_string("1 + 2 * 3")
  let restored = @treesitter.Parser::new(loaded).parse_string("1 + 2 * 3")
  assert_eq(original.root_node().to_sexp(), restored.root_node().to_sexp())
  assert_eq(Json(restored.language).stringify(), encoded)
}

///|
test "malformed tables fail validation before runtime use" {
  let language = arithmetic()
  let value = Json(language)
  guard value is Object(obj) else { fail("expected object") }
  obj["version"] = Json(99)
  try @language.Language::from_json(value) catch {
    _ => ()
  } noraise {
    _ => fail("accepted unknown schema version")
  }
  obj["version"] = Json(1)
  obj["start_symbol"] = Json(0.5)
  try @language.Language::from_json(value) catch {
    _ => ()
  } noraise {
    _ => fail("accepted fractional symbol id")
  }
  obj["start_symbol"] = Json(999999)
  try @language.Language::from_json(value) catch {
    _ => ()
  } noraise {
    _ => fail("accepted out-of-range start symbol")
  }
}

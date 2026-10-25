///|
test "c_string_literal_value decodes C escapes and stops at NUL" {
  inspect(c_string_literal_value("plain"), content="plain")
  inspect(c_string_literal_value("a\\0b"), content="a")
  // Octal escapes take up to three digits, so `\0` and a digit is not NUL.
  inspect(c_string_literal_value("\\01x") == "\u{1}x", content="true")
  inspect(c_string_literal_value("\\0123") == "\n3", content="true")
  // Hexadecimal escapes take every following hexadecimal digit.
  inspect(c_string_literal_value("\\x1fa") == "\u{fa}", content="false")
  inspect(c_string_literal_value("\\x1fa") == "\u{FFFD}", content="true")
  inspect(c_string_literal_value("\\x100") == "", content="true")
  inspect(c_string_literal_value("\\x41g") == "Ag", content="true")
  inspect(
    c_string_literal_value("\\\"\\?\\\\\\a\\b\\v\\f\\n\\r\\t") ==
    "\"?\\\u{7}\u{8}\u{b}\u{c}\n\r\t",
    content="true",
  )
  inspect(c_string_literal_value("\\u00e9\\U0001f600x"), content="é😀x")
  // The escapes `sanitize_string` emits round-trip, up to the first NUL.
  let name = "q\"?\\\u{1}\u{7f}é😀"
  inspect(
    c_string_literal_value(Generator::sanitize_str(name)) == name,
    content="true",
  )
  inspect(
    c_string_literal_value(Generator::sanitize_str("a\u{0}b")),
    content="a",
  )
  inspect(
    c_string_literal_value(Generator::sanitize_str("\u{0}1")) == "\u{1}",
    content="true",
  )
}

///|
test "c_lex_program converts states and symbols to uint16_t" {
  let program : @language.LexProgram = {
    states: [
      {
        accept_token: Some(65537),
        eof_advance: Some(65536),
        advance_map: [(97, 65538)],
        transitions: [
          {
            condition: { large_set: None, asserted: None, negated: None },
            state: 65536,
            skip: false,
          },
        ],
      },
    ],
    large_character_sets: [],
  }
  let converted = c_lex_program(program)
  debug_inspect(converted.states[0].accept_token, content="Some(1)")
  debug_inspect(converted.states[0].eof_advance, content="Some(0)")
  debug_inspect(converted.states[0].advance_map, content="[(97, 2)]")
  inspect(converted.states[0].transitions[0].state, content="0")
}

///|
test "render_language converts field locations to uint8_t" {
  // A field on the 257th step of a production: `child_index` 256 is 0 in
  // the C `uint8_t`, while parser.c keeps the literal 256.
  let steps = Array::make(256, "{\"type\":\"STRING\",\"value\":\"x\"}")
  steps.push(
    "{\"type\":\"FIELD\",\"name\":\"f\",\"content\":{\"type\":\"STRING\",\"value\":\"y\"}}",
  )
  let grammar =
    $|{"name":"wide","rules":{"s":{"type":"SEQ","members":[\{steps.join(",")}]}}}
  let generated = generate_from_grammar_json(grammar)
  inspect(generated.c_code.contains("{field_f, 256}"), content="true")
  debug_inspect(
    generated.language.field_map_entries,
    content="[{ field_id: 1, child_index: 0, inherited: false }]",
  )
}

///|
test "render_language symbol names are C string values" {
  let grammar =
    #|{"name":"nul","rules":{"s":{"type":"CHOICE","members":[
    #|  {"type":"STRING","value":"a\u0000b"},
    #|  {"type":"STRING","value":"\u00001"}]}}}
  let generated = generate_from_grammar_json(grammar)
  inspect(generated.c_code.contains("\"a\\0b\""), content="true")
  inspect(generated.c_code.contains("\"\\01\""), content="true")
  let names = generated.language.symbol_names
  inspect(names.contains("a"), content="true")
  inspect(names.contains("\u{1}"), content="true")
}

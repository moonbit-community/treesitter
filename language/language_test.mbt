///|
fn sample_language() -> @language.Language {
  let lex_fn : @language.LexProgram = {
    states: [
      {
        accept_token: None,
        eof_advance: Some(1),
        advance_map: [('a', 2), ('b', 3)],
        transitions: [
          {
            condition: {
              large_set: Some((0, true)),
              asserted: Some({
                ranges: [{ start: 0, end: 9, }],
                is_included: true,
              }),
              negated: Some({
                ranges: [{ start: 'x', end: 'z', }],
                is_included: false,
              }),
            },
            state: 4,
            skip: false,
          },
          {
            condition: { large_set: None, asserted: None, negated: None, },
            state: 0,
            skip: true,
          },
        ],
      },
      {
        accept_token: Some(1),
        eof_advance: None,
        advance_map: [],
        transitions: [],
      },
    ],
    large_character_sets: [
      [{ start: 0, end: 8, }, { start: 11, end: 0x10FFFF, }],
    ],
  }
  {
    abi_version: 15,
    symbol_count: 3,
    alias_count: 1,
    token_count: 2,
    external_token_count: 1,
    state_count: 3,
    large_state_count: 2,
    production_id_count: 1,
    field_count: 1,
    max_alias_sequence_length: 1,
    parse_table: [0, 1, 0, 0, 3, 2],
    small_parse_table: [1, 3, 1, 1],
    small_parse_table_map: [0],
    parse_actions: [
      Entry(count=0, reusable=false),
      Entry(count=1, reusable=true),
      Shift(state=2, extra=false, repetition=true),
      Entry(count=2, reusable=false),
      Reduce(symbol=2, child_count=1, dynamic_precedence=-3, production_id=0),
      Accept,
      Entry(count=1, reusable=false),
      Recover,
    ],
    symbol_names: ["end", "a\n\"b\"", "source", "alias"],
    field_names: ["", "name"],
    field_map_slices: [{ index: 0, length: 1, }],
    field_map_entries: [{ field_id: 1, child_index: 0, inherited: true, }],
    symbol_metadata: [
      { visible: false, named: true, supertype: false, },
      { visible: true, named: false, supertype: false, },
      { visible: true, named: true, supertype: true, },
      { visible: true, named: true, supertype: false, },
    ],
    public_symbol_map: [0, 1, 2, 3],
    alias_map: [2, 2, 2, 3, 0],
    alias_sequences: [3],
    lex_modes: [
      { lex_state: 0, external_lex_state: 1, reserved_word_set_id: 1, },
      { lex_state: 65535, external_lex_state: 0, reserved_word_set_id: 0, },
      { lex_state: 1, external_lex_state: 0, reserved_word_set_id: 0, },
    ],
    lex_fn,
    keyword_lex_fn: Some(lex_fn),
    keyword_capture_token: 1,
    external_scanner: { states: [false, true], symbol_map: [1], },
    primary_state_ids: [0, 1, 1],
    name: "sample",
    reserved_words: [0, 1],
    max_reserved_word_set_size: 1,
    supertype_count: 1,
    supertype_symbols: [2],
    supertype_map_slices: [
      { index: 0, length: 0, },
      { index: 0, length: 0, },
      { index: 0, length: 1, },
    ],
    supertype_map_entries: [1],
    metadata: { major_version: 1, minor_version: 2, patch_version: 3, },
  }
}

///|
test "Language round-trips through JSON" {
  let language = sample_language()
  let text = language.to_json().stringify()
  let decoded : @language.Language = @json.from_json(@json.parse(text))
  assert_eq(decoded, language)
  // Without a keyword lexer.
  let language = { ..language, keyword_lex_fn: None, keyword_capture_token: 0, }
  let decoded : @language.Language = @json.from_json(
    @json.parse(language.to_json().stringify()),
  )
  assert_eq(decoded, language)
}

///|
test "names are C strings" {
  // `symbol_names` and `field_names` are `const char *` tables upstream.
  let language = {
    ..sample_language(),
    symbol_names: ["end", "a\u{0}bc", "source", "alias"],
    field_names: ["", "a\u{0}b"],
  }
  // `CStr::from_ptr` stops at the NUL.
  debug_inspect(language.symbol_name(1), content="Some(\"a\")")
  debug_inspect(language.field_name_for_id(1), content="Some(\"a\")")
  // `strncmp(name, field_names[i], length) == 0 && !field_names[i][length]`.
  assert_eq(language.field_id_for_name("a"), 1)
  assert_eq(language.field_id_for_name("a\u{0}b"), 1)
  // `field_names[1][2]` is `b`.
  assert_eq(language.field_id_for_name("a\u{0}"), 0)
  assert_eq(language.field_id_for_name("ab"), 0)
  // `!strncmp(symbol_name, string, length) && !symbol_name[length]`: the
  // comparison stops at the NUL, but `symbol_name[3]` is `c`.
  assert_eq(language.symbol_for_name("a\u{0}x", false), 0)
  assert_eq(language.symbol_for_name("a\u{0}bc", false), 1)
  assert_eq(language.symbol_for_name("a", false), 1)
  assert_eq(language.symbol_for_name("a\u{0}b", false), 0)
  // `ts_language_name` is a `const char *` too; the stored value keeps the
  // whole string.
  let language = { ..language, name: "json\u{0}suffix" }
  debug_inspect(language.language_name(), content="Some(\"json\")")
  assert_eq(language.name, "json\u{0}suffix")
  let decoded = @language.Language::from_compact(language.to_compact())
  assert_eq(decoded.name, "json\u{0}suffix")
  debug_inspect(
    { ..language, abi_version: 14 }.language_name(),
    content="None",
  )
}

///|
test "LexProgram JSON form" {
  let program : @language.LexProgram = {
    states: [
      {
        accept_token: Some(3),
        eof_advance: None,
        advance_map: [],
        transitions: [
          {
            condition: {
              large_set: None,
              asserted: Some({
                ranges: [{ start: 97, end: 98, }],
                is_included: true,
              }),
              negated: None,
            },
            state: 1,
            skip: false,
          },
        ],
      },
    ],
    large_character_sets: [],
  }
  json_inspect(program, content={
    "states": [
      {
        "accept_token": 3,
        "advance_map": [],
        "transitions": [
          {
            "condition": {
              "asserted": {
                "ranges": [{ "start": 97, "end": 98 }],
                "is_included": true,
              },
            },
            "state": 1,
            "skip": false,
          },
        ],
      },
    ],
    "large_character_sets": [],
  })
}

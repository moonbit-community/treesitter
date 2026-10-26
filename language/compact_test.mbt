///|
test "compact round trip of the sample language" {
  let language = sample_language()
  let compact = language.to_compact()
  assert_eq(@language.Language::from_compact(compact), language)
  let text = language.to_compact_base64()
  assert_eq(@language.Language::from_compact_base64(text), language)
  // Line breaks and other ASCII whitespace are ignored.
  let wrapped = StringBuilder()
  for i, c in text.to_array() {
    if i % 7 == 0 {
      wrapped.write_string("\n  ")
    }
    wrapped.write_char(c)
  }
  wrapped.write_char('\n')
  assert_eq(
    @language.Language::from_compact_base64(wrapped.to_string()),
    language,
  )
  // The JSON form decodes to the same value.
  let json : @language.Language = @json.from_json(language.to_json())
  assert_eq(@language.Language::from_compact(json.to_compact()), language)
}

///|
test "compact round trip of edge values" {
  let base = sample_language()
  let language : @language.Language = {
    ..base,
    // Negative dynamic precedence, large values and a long run of zeros.
    parse_actions: [
      Entry(count=2, reusable=false),
      Reduce(
        symbol=65535,
        child_count=0,
        dynamic_precedence=-2147483648,
        production_id=0,
      ),
      Reduce(
        symbol=1,
        child_count=255,
        dynamic_precedence=2147483647,
        production_id=65535,
      ),
      Shift(state=0, extra=true, repetition=false),
      Shift(state=65535, extra=true, repetition=true),
      Accept,
      Recover,
    ],
    parse_table: Array::make(100000, 0)..push(7)..push(0)..push(2147483647),
    symbol_names: ["end", "\u{0}", "é😀\u{10FFFF}", ""],
    name: "",
    lex_modes: [
      { lex_state: 65535, external_lex_state: 0, reserved_word_set_id: 0, },
      { lex_state: 3, external_lex_state: 2, reserved_word_set_id: 1, },
    ],
    keyword_lex_fn: None,
    primary_state_ids: [0, 0, 5, 1],
  }
  assert_eq(@language.Language::from_compact(language.to_compact()), language)
  // Repetitive data compresses.
  let repeated : @language.Language = {
    ..base,
    small_parse_table: Array::makei(50000, i => i % 17),
  }
  let compact = repeated.to_compact()
  assert_true(compact.length() < 2000)
  assert_eq(@language.Language::from_compact(compact), repeated)
}

///|
test "compact rejects malformed data" {
  let compact = sample_language().to_compact()
  let bad_version = Bytes::from_array(
    [b'\x63'] + compact.to_array()[1:].to_owned(),
  )
  try @language.Language::from_compact(bad_version) catch {
    e =>
      inspect(
        e,
        content="invalid compact language: unsupported format version 99",
      )
  } noraise {
    _ => fail("expected an error")
  }
  let truncated = Bytes::from_array(compact.to_array()[:compact.length() - 1])
  try @language.Language::from_compact(truncated) catch {
    _ => ()
  } noraise {
    _ => fail("expected an error")
  }
  try @language.Language::from_compact_base64("not base64!") catch {
    e => inspect(e, content="invalid compact language: invalid base64 text")
  } noraise {
    _ => fail("expected an error")
  }
  let negative : @language.Language = { ..sample_language(), state_count: -1, }
  try negative.to_compact() catch {
    e =>
      inspect(
        e,
        content="invalid compact language: negative value -1 in an unsigned field",
      )
  } noraise {
    _ => fail("expected an error")
  }
}

///|
fn compact_error(data : Bytes) -> String {
  try @language.Language::from_compact(data) catch {
    e => e.to_string()
  } noraise {
    _ => "no error"
  }
}

///|
/// A container holding `raw` as a single literal run.
fn compact_container(raw : Array[Byte]) -> Bytes {
  let container : Array[Byte] = [b'\x01', raw.length().to_byte()]
  container.push(raw.length().to_byte())
  container.append(raw)
  Bytes::from_array(container)
}

///|
/// Encoded distances, lengths and index gaps near `Int::max_value()` must not
/// overflow past the range checks (they used to panic).
test "compact rejects out-of-range offsets" {
  // A match whose distance code is 0x7FFFFFFF.
  inspect(
    compact_error(b"\x01\x08\x01\x41\x00\xff\xff\xff\xff\x07\x00"),
    content="invalid compact language: match out of range",
  )
  // A match whose length code is 0x7FFFFFFF.
  inspect(
    compact_error(b"\x01\x08\x01\x41\xff\xff\xff\xff\x07\x00\x00"),
    content="invalid compact language: match out of range",
  )
  // A sparse array (the parse table, after the ten counts) whose second
  // index gap is 0x7FFFFFFF.
  let raw : Array[Byte] = Array::make(10, b'\x00')
  raw.append([b'\x02', b'\x02', b'\x00', b'\x01'])
  raw.append([b'\xff', b'\xff', b'\xff', b'\xff', b'\x07', b'\x01'])
  inspect(
    compact_error(compact_container(raw)),
    content="invalid compact language: sparse index out of range",
  )
  // An overlong signed varint, whose high bits used to be dropped: the first
  // element of the small parse table map, after an empty parse table and an
  // empty small parse table.
  let raw : Array[Byte] = Array::make(10, b'\x00')
  raw.append([b'\x00', b'\x00', b'\x00', b'\x01'])
  raw.append([b'\x80', b'\x80', b'\x80', b'\x80', b'\x80', b'\x00'])
  inspect(
    compact_error(compact_container(raw)),
    content="invalid compact language: varint out of range",
  )
}

///|
/// A field map child index that the packed encoding cannot represent is
/// rejected instead of being changed.
test "compact rejects out-of-range child indices" {
  for child_index in [-2147483648, -1, 0x40000000, 2147483647] {
    let language : @language.Language = {
      ..sample_language(),
      field_map_entries: [{ field_id: 1, child_index, inherited: false, }],
    }
    try language.to_compact() catch {
      e =>
        assert_eq(
          e.to_string(),
          "invalid compact language: child index \{child_index} out of range",
        )
    } noraise {
      _ => fail("expected an error for \{child_index}")
    }
  }
  let language : @language.Language = {
    ..sample_language(),
    field_map_entries: [
      { field_id: 1, child_index: 0x3FFFFFFF, inherited: true, },
      { field_id: 0, child_index: 0, inherited: false, },
    ],
  }
  assert_eq(@language.Language::from_compact(language.to_compact()), language)
}

// Expected texts come from serde_json 1.0.154 (through the pinned
// `tree-sitter generate`, or a Rust harness).

///|
fn value_error(input : String) -> String {
  try @serde_json.from_str(input, de => de.deserialize_value()) catch {
    e => e.to_string()
  } noraise {
    _ => "ok"
  }
}

///|
test "syntax errors carry serde_json's positions" {
  inspect(
    value_error("{\"a\":"),
    content="EOF while parsing a value at line 1 column 5",
  )
  inspect(value_error("[1,]"), content="trailing comma at line 1 column 4")
  inspect(value_error("{\"a\" 1}"), content="expected `:` at line 1 column 6")
  inspect(
    value_error("[1 2]"),
    content="expected `,` or `]` at line 1 column 4",
  )
  inspect(
    value_error("{1:2}"),
    content="key must be a string at line 1 column 2",
  )
  inspect(value_error("1 x"), content="trailing characters at line 1 column 3")
  inspect(
    value_error("nul"),
    content="EOF while parsing a value at line 1 column 3",
  )
  inspect(value_error("nulx"), content="expected ident at line 1 column 4")
  inspect(value_error("01"), content="invalid number at line 1 column 2")
  inspect(
    value_error("1."),
    content="EOF while parsing a value at line 1 column 2",
  )
  inspect(
    value_error("1e999"),
    content="number out of range at line 1 column 5",
  )
  inspect(value_error("\"\\q\""), content="invalid escape at line 1 column 3")
  inspect(
    value_error("\"\\uDC00\""),
    content="lone leading surrogate in hex escape at line 1 column 7",
  )
  inspect(
    value_error("\"\\uD800x\""),
    content="unexpected end of hex escape at line 1 column 8",
  )
  inspect(
    value_error("\"a\u{1}\""),
    content=(
      #|control character (\u0000-\u001F) found while parsing a string at line 1 column 3
    ),
  )
  inspect(value_error("\n\n  ]"), content="expected value at line 3 column 3")
  inspect(value_error("[".repeat(127) + "]".repeat(127)), content="ok")
  inspect(
    value_error("[".repeat(128)),
    content="recursion limit exceeded at line 1 column 128",
  )
}

///|
test "numbers are classified like serde_json" {
  let number = (s : String) => {
    @serde_json.from_str(s, de => de.deserialize_value())
  }
  debug_inspect(number("0"), content="Number(PosInt(0))")
  guard number("-0") is Number(Float(zero)) else { fail("-0 is a float") }
  inspect(zero.reinterpret_as_uint64() >> 63, content="1")
  debug_inspect(number("-5"), content="Number(NegInt(-5))")
  debug_inspect(
    number("18446744073709551615"),
    content="Number(PosInt(18446744073709551615))",
  )
  debug_inspect(
    number("18446744073709551616"),
    content="Number(Float(18446744073709552000))",
  )
  debug_inspect(
    number("-9223372036854775809"),
    content="Number(Float(-9223372036854776000))",
  )
  debug_inspect(number("1e-999"), content="Number(Float(0))")
  // Without `float_roundtrip`, serde_json scales the significand by powers of
  // ten, which is not always correctly rounded.
  guard number("123456789012345678901234567890e-10") is Number(Float(f)) else {
    fail("expected a float")
  }
  inspect(@serde_json.zmij_format(f), content="1.2345678901234567e+19")
}

///|
test "zmij and Rust Debug formatting" {
  inspect(@serde_json.zmij_format(1.0e20), content="1e+20")
  inspect(@serde_json.zmij_format(1.0), content="1.0")
  inspect(@serde_json.zmij_format(-0.0), content="-0.0")
  inspect(@serde_json.zmij_format(0.1), content="0.1")
  inspect(@serde_json.zmij_format(1.0e15), content="1000000000000000.0")
  inspect(@serde_json.zmij_format(1.0e16), content="1e+16")
  inspect(@serde_json.zmij_format(0.00001), content="0.00001")
  inspect(@serde_json.zmij_format(0.000001), content="1e-6")
  inspect(@serde_json.zmij_format(123.456), content="123.456")
  inspect(@serde_json.zmij_format(1.5e300), content="1.5e+300")
  inspect(@serde_json.zmij_format(5.0e-324), content="5e-324")
  inspect(
    @serde_json.rust_debug_str("a\"\\\n\t\r\u{0}\u{1}\u{85}\u{ad}\u{300}é'"),
    content=(
      #|"a\"\\\n\t\r\0\u{1}\u{85}\u{ad}\u{300}é'"
    ),
  )
}

///|
test "custom messages keep a trailing position" {
  let e = @serde_json.JsonError::custom("oops at line 3 column 7")
  inspect(e.line(), content="3")
  inspect(e, content="oops at line 3 column 7")
  let e = @serde_json.JsonError::custom("oops at line 3 column 7 x")
  inspect(e.line(), content="0")
}

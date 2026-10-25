// Expected values from serde_json 1.0.154, serde 1.0.229 and Rust 1.97.1.

///|
test "serde_json::Error display and custom positions" {
  inspect(
    @support.SerdeJsonError::syntax(EofWhileParsingObject, 1, 1),
    content="EOF while parsing an object at line 1 column 1",
  )
  inspect(
    @support.SerdeJsonError::custom("missing field `x`"),
    content="missing field `x`",
  )
  // `make_error` takes a trailing position out of a custom message.
  let e = @support.SerdeJsonError::custom("bad at line 3 column 14")
  inspect((e.line(), e.column()), content="(3, 14)")
  inspect(e, content="bad at line 3 column 14")
  let e = @support.SerdeJsonError::custom("bad at line 3 column 14x")
  inspect((e.line(), e.column()), content="(0, 0)")
  inspect(
    @support.SerdeJsonError::invalid_type(Float(1.0), "u8"),
    content="invalid type: floating point `1.0`, expected u8",
  )
  inspect(
    @support.SerdeJsonError::invalid_type(Unit, "a string"),
    content="invalid type: null, expected a string",
  )
  inspect(
    @support.SerdeJsonError::invalid_value(Signed(-1L), "u8"),
    content="invalid value: integer `-1`, expected u8",
  )
}

///|
fn struct_error(f : () -> Unit raise @support.SerdeJsonError) -> String {
  try f() catch {
    e => e.to_string()
  } noraise {
    _ => "ok"
  }
}

///|
/// A derived `struct S { a: String, b: Option<u8> }`.
fn deserialize_s(
  de : @support.Deserializer,
) -> (String, Byte?) raise @support.SerdeJsonError {
  let expecting = "struct S with 2 elements"
  de.deserialize_struct(
    "struct S",
    seq => {
      let a = seq.next_field(@support.deserialize_string, 0, expecting)
      let b = seq.next_field(
        de => de.deserialize_option(@support.Deserializer::deserialize_u8),
        1,
        expecting,
      )
      (a, b)
    },
    map => {
      let a : @support.StructField[String] = @support.StructField::new("a")
      let b : @support.StructField[Byte?] = @support.StructField::new("b")
      while map.next_key() is Some(key) {
        match key {
          "a" => a.next_value(map, @support.deserialize_string)
          "b" =>
            b.next_value(map, de => {
              de.deserialize_option(@support.Deserializer::deserialize_u8)
            })
          _ => map.next_value_ignored()
        }
      }
      let a = a.required()
      let b = b.optional()
      (a, b)
    },
  )
}

///|
test "derived struct deserialization from text" {
  let s = (text : String) => {
    struct_error(() => ignore(@support.from_str_with(text, deserialize_s)))
  }
  inspect(s("{\"a\": \"x\", \"b\": 7, \"c\": [[[1]]]}"), content="ok")
  inspect(
    s("{\"a\": \"x\", \"a\": \"y\"}"),
    content="duplicate field `a` at line 1 column 14",
  )
  inspect(s("{\"b\": 1}"), content="missing field `a` at line 1 column 8")
  inspect(
    s("{\"b\": 256, \"a\": 1}"),
    content="invalid value: integer `256`, expected u8 at line 1 column 9",
  )
  inspect(
    s("{\"b\": -1.5}"),
    content="invalid type: floating point `-1.5`, expected u8 at line 1 column 10",
  )
  inspect(
    s("{\"a\": [1]}"),
    content="invalid type: sequence, expected a string at line 1 column 6",
  )
  inspect(
    s("[\"x\"]"),
    content="invalid length 1, expected struct S with 2 elements at line 1 column 5",
  )
  inspect(
    s("[\"x\", null, 3]"),
    content="trailing characters at line 1 column 13",
  )
  inspect(
    s("5"),
    content="invalid type: integer `5`, expected struct S at line 1 column 1",
  )
  inspect(
    s("{\"a\": \"x\"} 1"),
    content="trailing characters at line 1 column 12",
  )
  inspect(
    s("{\"a\": \"x\" , \"a\" : 1}"),
    content="duplicate field `a` at line 1 column 16",
  )
  inspect(
    s("{\"a\": \"x\",\"b\":true}"),
    content="invalid type: boolean `true`, expected u8 at line 1 column 18",
  )
  inspect(
    s("\"x\""),
    content="invalid type: string \"x\", expected struct S at line 1 column 3",
  )
  inspect(
    s("{\"a\": \"x\" \"b\": 1}"),
    content="expected `,` or `}` at line 1 column 11",
  )
}

///|
test "derived struct deserialization from a Value" {
  let s = (text : String) => {
    struct_error(() => {
      ignore(@support.from_value(@support.from_str(text), deserialize_s))
    })
  }
  inspect(s("{\"a\": \"x\", \"b\": null}"), content="ok")
  inspect(s("{\"b\": 1}"), content="missing field `a`")
  inspect(
    s("{\"a\": \"x\", \"b\": 1e2}"),
    content="invalid type: floating point `100.0`, expected u8",
  )
  inspect(
    s("[\"x\", 1, 2]"),
    content="invalid length 3, expected fewer elements in array",
  )
  inspect(s("\"x\""), content="invalid type: string \"x\", expected struct S")
}

///|
test "Value conversions" {
  let v = @support.from_str(
    "{\"a\": 1, \"b\": -2, \"c\": 1.0, \"d\": 18446744073709551615, \"e\": -0}",
  )
  inspect(
    @support.to_string(v.to_json()),
    content="{\"a\":1,\"b\":-2,\"c\":1.0,\"d\":18446744073709551615,\"e\":-0.0}",
  )
  inspect(@support.Value::from_json(v.to_json()) == v, content="true")
  debug_inspect(
    @support.Value::from_json({ "n": Json::number(245.0), "f": 2.5 }),
    content=(
      #|Object({ "n": Number(PosInt(245)), "f": Number(Float(2.5)) })
    ),
  )
  inspect(
    @support.parse_json("[1.50, 1e2]").stringify() catch {
      e => e.to_string()
    },
    content="[1.5,100.0]",
  )
}

///|
test "Rust Debug of str and char" {
  inspect(
    @support.rust_debug_str("a\"b\\\n\t\u{0}\u{1}é\u{301}\u{200b}'"),
    content=(
      #|"a\"b\\\n\t\0\u{1}é\u{301}\u{200b}'"
    ),
  )
  inspect(@support.rust_debug_char("'"), content="'\\''")
  inspect(@support.rust_debug_char("\""), content="'\"'")
  inspect(@support.rust_debug_char("\u{301}"), content="'\\u{301}'")
}

///|
test "Rust str::to_lowercase" {
  inspect(@support.rust_to_lowercase("BLACK"), content="black")
  inspect(@support.rust_to_lowercase("BLAC\u{212A}"), content="black")
  inspect(@support.rust_to_lowercase("\u{3A3}"), content="\u{3C3}")
  inspect(@support.rust_to_lowercase("A\u{3A3}"), content="a\u{3C2}")
  inspect(@support.rust_to_lowercase("A\u{3A3}B"), content="a\u{3C3}b")
  inspect(@support.rust_to_lowercase("A.\u{3A3}"), content="a.\u{3C2}")
  inspect(
    @support.rust_to_lowercase("A\u{301}\u{3A3}"),
    content="a\u{301}\u{3C2}",
  )
  inspect(
    @support.rust_to_lowercase("\u{3A3}\u{3A3}\u{3A3}"),
    content="\u{3C3}\u{3C3}\u{3C2}",
  )
  inspect(@support.rust_to_lowercase("\u{130}X"), content="i\u{307}x")
  inspect(@support.rust_to_lowercase("#ÉABCD"), content="#éabcd")
  inspect(@support.rust_to_lowercase("\u{1F88}"), content="\u{1F80}")
}

///|
test "str::from_utf8 and u8::from_str_radix" {
  inspect(
    @support.from_utf8(b"\xef\xbb\xbf{}") == Some("\u{feff}{}"),
    content="true",
  )
  inspect(@support.from_utf8(b"\xc0\x80") is None, content="true")
  inspect(@support.from_utf8(b"\xed\xa0\x80") is None, content="true")
  inspect(@support.from_utf8(b"\xf4\x90\x80\x80") is None, content="true")
  inspect(@support.from_utf8(b"\xc3") is None, content="true")
  inspect(
    @support.from_utf8(b"\xf0\x9f\x98\x80") == Some("😀"),
    content="true",
  )
  let radix = (s : String) => @support.u8_from_str_radix(@support.utf8(s), 16)
  inspect(radix("ff"), content="Some(255)")
  inspect(radix("+f"), content="Some(15)")
  inspect(radix("-1"), content="None")
  inspect(radix("+"), content="None")
  inspect(radix("g0"), content="None")
  inspect(radix("é"), content="None")
}

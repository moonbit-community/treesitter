// serde_json behaviour of `parse_grammar`. The expected texts are those of
// the pinned `tree-sitter generate` (serde_json 1.0.154).

///|
test "parse_grammar reports duplicate struct fields" {
  inspect(
    parse_error(
      (
        #|{"name":"a","name":"b","rules":{"s":{"type":"STRING","value":"x"}}}
      ),
    ),
    content="duplicate field `name` at line 1 column 18",
  )
  // Inside a rule read from the stream (`extras`), and for the tag.
  inspect(
    parse_error(
      (
        #|{"name":"a","rules":{"s":{"type":"BLANK"}},"extras":[{"type":"STRING","value":"a","value":"b"}]}
      ),
    ),
    content=(
      #|duplicate field `value` at line 1 column 95
    ),
  )
  inspect(
    parse_error(
      (
        #|{"name":"a","rules":{"s":{"type":"BLANK"}},"extras":[{"type":"BLANK","type":"BLANK"}]}
      ),
    ),
    content="duplicate field `type` at line 1 column 75",
  )
  // `rules` holds `serde_json::Value`s: a repeated key replaces the value.
  inspect(
    parse_error(
      (
        #|{"name":"a","rules":{"s":{"type":"STRING","value":5,"value":"x"}}}
      ),
    ),
    content="ok",
  )
}

///|
test "parse_grammar classifies numbers like serde_json" {
  // `-0` is the float `-0.0`, which is not an `i32`.
  inspect(
    parse_error(
      (
        #|{"name":"a","rules":{"s":{"type":"PREC_DYNAMIC","value":-0,"content":{"type":"BLANK"}}}}
      ),
    ),
    content="invalid type: floating point `-0.0`, expected i32",
  )
  // Out-of-range numbers are rejected when a `Value` is read...
  inspect(
    parse_error(
      (
        #|{"name":"a","rules":{"s":{"type":"STRING","value":"x","ignored":1e999}}}
      ),
    ),
    content="number out of range at line 1 column 69",
  )
  // ...floats print as zmij formats them...
  inspect(
    parse_error(
      (
        #|{"name":1e20,"rules":{}}
      ),
    ),
    content="invalid type: floating point `1e+20`, expected a string at line 1 column 12",
  )
  // ...and an untagged precedence value that is a float matches no variant.
  inspect(
    parse_error(
      (
        #|{"name":"a","rules":{"s":{"type":"PREC","value":-0,"content":{"type":"BLANK"}}}}
      ),
    ),
    content="data did not match any variant of untagged enum PrecedenceValueJSON",
  )
}

///|
test "parse_grammar skips unknown fields without materializing them" {
  // `IgnoredAny` does not check that escapes form surrogate pairs, and has
  // no nesting limit.
  inspect(
    parse_error(
      (
        #|{"name":"a","unused":"\uD800","rules":{"s":{"type":"STRING","value":"x"}}}
      ),
    ),
    content="ok",
  )
  let deep = "[".repeat(300) + "]".repeat(300)
  inspect(
    parse_error(
      "{\"name\":\"a\",\"unused\":\{deep},\"rules\":{\"s\":{\"type\":\"BLANK\"}}}",
    ),
    content="ok",
  )
}

///|
test "parse_grammar has serde_json's recursion limit" {
  let nested = (depth : Int32) => {
    let mut rule = "{\"type\":\"BLANK\"}"
    for _ in 0..<depth {
      rule = "{\"type\":\"PREC\",\"value\":1,\"content\":\{rule}}"
    }
    "{\"name\":\"a\",\"rules\":{\"s\":\{rule}}}"
  }
  inspect(parse_error(nested(124)), content="ok")
  inspect(
    parse_error(nested(125)),
    content=(
      #|recursion limit exceeded at line 1 column 4401
    ),
  )
}

///|
test "parse_grammar syntax errors and error order" {
  inspect(
    parse_error(
      (
        #|{"name":
      ),
    ),
    content="EOF while parsing a value at line 1 column 8",
  )
  // Fields are validated as they are read.
  inspect(
    parse_error(
      (
        #|{"name":42,"rules":
      ),
    ),
    content="invalid type: integer `42`, expected a string at line 1 column 10",
  )
  inspect(
    parse_error(
      (
        #|{"name":"a","rules":{"s":{"type":"STRING","value":"x"}},"extras":[{"type":"STRING"},{"type":"BLANK"}]}
      ),
    ),
    content="missing field `value` at line 1 column 84",
  )
  // Rust's `{:?}` escapes in `invalid type` errors.
  inspect(
    parse_error(
      (
        #|{"name":"a","rules":"\u0085"}
      ),
    ),
    content=(
      #|invalid type: string "\u{85}", expected a map at line 1 column 28
    ),
  )
}

///|
test "parse_grammar reads structs and rules from sequences" {
  // serde reads a struct from the sequence of its fields, and an internally
  // tagged enum from a sequence that starts with the tag.
  inspect(
    parse_error(
      (
        #|["a",{"s":["STRING","x"]}]
      ),
    ),
    content="ok",
  )
  inspect(
    parse_error(
      (
        #|{"name":"a","rules":{"s":{"type":"STRING","value":"x"}},"extras":[["STRING","x","y"]]}
      ),
    ),
    content="invalid length 2, expected 1 element in sequence at line 1 column 85",
  )
  inspect(
    parse_error(
      (
        #|["a",{"s":{"type":"STRING","value":"x"}},[],[],[],[],[],[],null,{},1]
      ),
    ),
    content="trailing characters at line 1 column 68",
  )
}

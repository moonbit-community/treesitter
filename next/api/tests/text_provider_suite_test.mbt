// Port of tree-sitter crates/cli/src/tests/text_provider_test.rs. Rust's
// byte containers (`&str`, `String`, `Box<str>`, `Box<[u8]>`, `Vec<u8>`,
// `Arc<[u8]>`) all become `Bytes`/`BytesView`, and closures become
// `TextCallback`; each test keeps upstream's calls. The helpers
// (`check_parsing`, `check_parsing_callback`, ...) are in
// text_provider_test.mbt.

///|
async test "text_provider_for_str_slice" {
  let text : String = "// comment"
  check_parsing(utf8(text), utf8(text))
  check_parsing(utf8(text), utf8(text))
}

///|
async test "text_provider_for_string" {
  let text : String = "// comment"
  check_parsing(utf8(text), utf8(text))
  check_parsing(utf8(text), utf8(text))
  check_parsing(utf8(text)[:], utf8(text))
}

///|
async test "text_provider_for_box_of_str_slice" {
  let text = utf8("// comment")
  check_parsing(text, text)
  check_parsing(text[:], text)
  check_parsing(text[:], text[:])
  check_parsing(text[:], text)
}

///|
async test "text_provider_for_box_of_bytes_slice" {
  let text = utf8("// comment")
  check_parsing(text[:], text[:])
  check_parsing(text[:], text)
  check_parsing(text, text)
}

///|
async test "text_provider_for_vec_of_bytes" {
  let text = utf8("// comment").to_array()
  check_parsing(Bytes::from_array(text), Bytes::from_array(text))
}

///|
async test "text_provider_for_arc_of_bytes_slice" {
  let text : Bytes = utf8("// comment")
  check_parsing(text, text)
  check_parsing(text[:], text[:])
  check_parsing(text, text[:])
}

///|
async test "text_provider_for_vec_utf16_text" {
  let source_text = utf16("你好")
  guard get_parsing_language("c") is Some(language) else { return }
  let parser = @api.Parser::new()
  parser.set_language(language)
  let tree = parser.parse_utf16_le(source_text).unwrap()
  let tree_text = tree.root_node().utf16_text(source_text)
  assert_eq(source_text, tree_text.to_owned())
}

///|
async test "text_provider_callback_with_str_slice" {
  let text : String = "// comment"
  check_parsing(
    utf8(text),
    @api.TextCallback::new(_node => Iter::singleton(utf8(text)[:])),
  )
  check_parsing_callback(
    (offset, _point) => {
      if offset < utf8(text).length() {
        utf8(text)[:]
      } else {
        b""[:]
      }
    },
    @api.TextCallback::new(_node => Iter::singleton(utf8(text)[:])),
  )
}

///|
async test "text_provider_callback_with_owned_string_slice" {
  let text : String = "// comment"
  check_parsing_callback(
    (offset, _point) => {
      if offset < utf8(text).length() {
        utf8(text)[:]
      } else {
        b""[:]
      }
    },
    @api.TextCallback::new(_node => {
      let slice : String = text
      Iter::singleton(utf8(slice)[:])
    }),
  )
}

///|
async test "text_provider_callback_with_owned_bytes_vec_slice" {
  let text : String = "// comment"
  check_parsing_callback(
    (offset, _point) => {
      if offset < utf8(text).length() {
        utf8(text)[:]
      } else {
        b""[:]
      }
    },
    @api.TextCallback::new(_node => {
      let slice = utf8(text).to_array()
      Iter::singleton(Bytes::from_array(slice)[:])
    }),
  )
}

///|
async test "text_provider_callback_with_owned_arc_of_bytes_slice" {
  let text : String = "// comment"
  check_parsing_callback(
    (offset, _point) => {
      if offset < utf8(text).length() {
        utf8(text)[:]
      } else {
        b""[:]
      }
    },
    @api.TextCallback::new(_node => {
      let slice : Bytes = Bytes::from_array(utf8(text).to_array())
      Iter::singleton(slice[:])
    }),
  )
}

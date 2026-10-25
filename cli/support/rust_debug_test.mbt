///|
test "rust debug str and char" {
  inspect(@support.rust_debug_str("a\"b\\\n'"), content="\"a\\\"b\\\\\\n'\"")
  inspect(
    @support.rust_debug_str(
      "\u{0}\t\r\u{7}\u{7f}\u{85}\u{a0}\u{ad}é\u{301}\u{200b}",
    ),
    content="\"\\0\\t\\r\\u{7}\\u{7f}\\u{85}\\u{a0}\\u{ad}é\\u{301}\\u{200b}\"",
  )
  inspect(@support.rust_debug_char('\n'), content="'\\n'")
  inspect(@support.rust_debug_char('\u{85}'), content="'\\u{85}'")
  inspect(@support.rust_debug_char('\''), content="'\\''")
  inspect(@support.rust_debug_char('"'), content="'\"'")
  inspect(@support.rust_debug_char('\u{0}'), content="'\\0'")
  inspect(@support.rust_debug_char('\u{e0001}'), content="'\\u{e0001}'")
  inspect(@support.rust_debug_char('😀'), content="'😀'")
}

///|
/// FNV-1a 64 over the UTF-8 of `{:?}` of every char, then of `{:?}` of each
/// block of 256 consecutive scalar values as a str; the expected value was
/// computed with Rust 1.97.1.
test "rust debug escaping of every char" {
  let mut h = 0xcbf29ce484222325UL
  let feed = (s : String) => {
    for b in @support.utf8(s) {
      h = (h ^ b.to_uint64()) * 0x100000001b3UL
    }
  }
  for u in 0..<=0x10FFFF {
    if u >= 0xD800 && u <= 0xDFFF {
      continue
    }
    feed(@support.rust_debug_char(u.unsafe_to_char()))
  }
  let block = StringBuilder()
  for u in 0..<=0x10FFFF {
    if !(u >= 0xD800 && u <= 0xDFFF) {
      block.write_char(u.unsafe_to_char())
    }
    if u % 256 == 255 {
      feed(@support.rust_debug_str(block.to_string()))
      block.reset()
    }
  }
  inspect(h.to_string(radix=16), content="37674c9628814395")
}

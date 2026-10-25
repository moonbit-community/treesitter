///|
/// Expected values: Rust 1.97.1 `format!("{:?}", s)`.
test "debug_str follows Rust's Debug for str" {
  let lines = []
  for
    s in [
      "", "a b", "\u{0}\u{1}\u{7}\u{8}\u{b}\u{c}\u{1b}\u{1f}", "\u{80}\u{9f}\u{a0}\u{ad}\u{ae}",
      "\u{300}x\u{36f}\u{370}", "\u{378}\u{e000}\u{f8ff}\u{f900}\u{fffd}\u{fffe}\u{ffff}",
      "\u{10000}\u{1f600}\u{e0000}\u{e0001}\u{e0100}\u{e01ef}\u{e01f0}\u{10ffff}",
      "\u{200b}\u{200c}\u{200d}\u{2028}\u{2029}\u{202e}\u{2060}\u{3000}\u{feff}",
      "'\"\\\t\r\n", "\u{d7ff}\u{1100}\u{11a8}\u{ff9e}\u{1f3fb}",
    ] {
    lines.push(debug_str(s))
  }
  inspect(
    lines.join("\n"),
    content=(
      #|""
      #|"a b"
      #|"\0\u{1}\u{7}\u{8}\u{b}\u{c}\u{1b}\u{1f}"
      #|"\u{80}\u{9f}\u{a0}\u{ad}®"
      #|"\u{300}x\u{36f}Ͱ"
      #|"\u{378}\u{e000}\u{f8ff}豈�\u{fffe}\u{ffff}"
      #|"𐀀😀\u{e0000}\u{e0001}\u{e0100}\u{e01ef}\u{e01f0}\u{10ffff}"
      #|"\u{200b}\u{200c}\u{200d}\u{2028}\u{2029}\u{202e}\u{2060}\u{3000}\u{feff}"
      #|"'\"\\\t\r\n"
      #|"\u{d7ff}ᄀᆨ\u{ff9e}🏻"
    ),
  )
}

///|
test "the range table is sorted and disjoint" {
  let t = debug_unicode_escaped
  assert_true(t.length() % 2 == 0)
  for i in 0..<(t.length() / 2) {
    let lo = t[2 * i]
    let hi = t[2 * i + 1]
    assert_true(lo <= hi)
    if i > 0 {
      assert_true(t[2 * i - 1] + 1 < lo)
    }
    assert_true(in_ranges(t, lo.unsafe_to_char()))
    assert_true(in_ranges(t, hi.unsafe_to_char()))
    if lo > 0 && !(lo - 1 >= 0xD800 && lo - 1 <= 0xDFFF) {
      assert_true(!in_ranges(t, (lo - 1).unsafe_to_char()))
    }
    if hi < 0x10FFFF && !(hi + 1 >= 0xD800 && hi + 1 <= 0xDFFF) {
      assert_true(!in_ranges(t, (hi + 1).unsafe_to_char()))
    }
  }
}

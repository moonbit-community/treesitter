///|
// Frozen cases from crates/tags/src/tags.rs, including clipping inside a scalar.
test "upstream tag line trimming and UTF-8 clipping" {
  let text = @utf8.encode("abc\ndefg❤hij\nklmno")
  assert_eq(line_range(text, 4, 30), (4, 14))
  assert_eq(line_range(text, 4, 6), (4, 8))
  assert_eq(line_range(text, 15, 30), (15, 20))
  assert_eq(line_range(text, 15, 4), (15, 19))
  assert_eq(line_range(b"   foo\nbar\n", 0, 10), (3, 6))
  assert_eq(line_range(b"\t func foo \nbar\n", 0, 10), (2, 10))
  assert_eq(line_range(b"\t func foo \nbar\n", 0, 14), (2, 10))
  assert_eq(line_range(b"\t func foo \nbar\n", 12, 14), (12, 15))
  assert_eq(line_range(b" \r\n\tfoo \r\n", 0, 180), (4, 7))
  assert_eq(line_range(b" \t\r\n", 0, 180), (4, 4))
  assert_eq(line_range(b"", 0, 180), (0, 0))
  assert_eq(line_range(b"a\xffb", 0, 180), (0, 1))
  assert_eq(line_range(b"a\xffb\n", 0, 180), (0, 3))
}

///|
test "UTF-16 columns follow upstream lossy chunk handling" {
  let source = @utf8.encode("😀 a❤; b😀;")
  assert_eq(utf16_len(source, 0, source.length()), 11)
  assert_eq(utf16_len(source, 0, 5), 3)
  assert_eq(utf16_len(source, 5, 9), 2)
  assert_eq(utf16_len(b"a\xe2\x82z", 0, 4), 3)
  assert_eq(utf16_len(b"a\xed\xa0\x80z", 0, 5), 5)
  assert_eq(utf16_len(b"a\xe2\x82", 0, 3), 0)
  assert_eq(utf16_len(b"a\xffb\xe2", 0, 4), 2)
}

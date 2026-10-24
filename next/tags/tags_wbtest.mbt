// Port of the tests of tree-sitter crates/tags/src/tags.rs.

///|
test "get_line" {
  let text = @utf8.encode("abc\ndefg❤hij\nklmno")
  assert_eq(line_range(text, 5, @api.Point::new(1, 1), 30), (4, 14))
  assert_eq(line_range(text, 5, @api.Point::new(1, 1), 6), (4, 8))
  assert_eq(line_range(text, 17, @api.Point::new(2, 2), 30), (15, 20))
  assert_eq(line_range(text, 17, @api.Point::new(2, 2), 4), (15, 19))
}

///|
test "get_line_trims" {
  let text = b"   foo\nbar\n"
  assert_eq(line_range(text, 0, @api.Point::new(0, 0), 10), (3, 6))
  let text = b"\t func foo \nbar\n"
  assert_eq(line_range(text, 0, @api.Point::new(0, 0), 10), (2, 10))
  let r = line_range(text, 0, @api.Point::new(0, 0), 14)
  assert_eq(r, (2, 10))
  assert_eq(@utf8.decode_lossy(text[r.0:r.1]), "func foo")
  let r = line_range(text, 12, @api.Point::new(1, 0), 14)
  assert_eq(r, (12, 15))
  assert_eq(@utf8.decode_lossy(text[r.0:r.1]), "bar")
}

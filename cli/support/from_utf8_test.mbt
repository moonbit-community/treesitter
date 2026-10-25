///|
/// Expected texts from `std::str::from_utf8` under Rust 1.97.1.
test "utf8_error matches Rust's Utf8Error" {
  let cases : Array[(Bytes, String)] = [
    (b"abc", "ok"),
    (b"\xff", "invalid utf-8 sequence of 1 bytes from index 0"),
    (b"a\x80", "invalid utf-8 sequence of 1 bytes from index 1"),
    (b"\xc0\x80", "invalid utf-8 sequence of 1 bytes from index 0"),
    (b"\xc2", "incomplete utf-8 byte sequence from index 0"),
    (b"\xc2\x41", "invalid utf-8 sequence of 1 bytes from index 0"),
    (b"\xe0\x80\x80", "invalid utf-8 sequence of 1 bytes from index 0"),
    (b"\xe0\xa0", "incomplete utf-8 byte sequence from index 0"),
    (b"\xe0\xa0\x41", "invalid utf-8 sequence of 2 bytes from index 0"),
    (b"\xed\xa0\x80", "invalid utf-8 sequence of 1 bytes from index 0"),
    (b"\xf0\x9f\x98", "incomplete utf-8 byte sequence from index 0"),
    (b"\xf0\x9f\x98\x41", "invalid utf-8 sequence of 3 bytes from index 0"),
    (b"\xf0\x9f\x41", "invalid utf-8 sequence of 2 bytes from index 0"),
    (b"\xf4\x90\x80\x80", "invalid utf-8 sequence of 1 bytes from index 0"),
    (b"\xf5\x80", "invalid utf-8 sequence of 1 bytes from index 0"),
    (b"x\xe2\x82", "incomplete utf-8 byte sequence from index 1"),
    (b"\xf0\x9f\x98\x80\xff", "invalid utf-8 sequence of 1 bytes from index 4"),
  ]
  for case in cases {
    let (bytes, expected) = case
    assert_eq(@support.utf8_error(bytes).unwrap_or("ok"), expected)
    assert_eq(@support.from_utf8(bytes) is None, expected != "ok")
  }
}

///|
/// Expected values: `{:x}` of `DefaultHasher` over `PathBuf::from(..)`
/// with Rust 1.97.1.
test "Path hash matches Rust's DefaultHasher" {
  let cases : Array[(String, String)] = [
    ("", "bd60acb658c79e45"),
    ("a", "5efaa56e1b6d9df7"),
    ("/a/b", "e5f5d81d1bcc96f1"),
    ("/a//b/", "e5f5d81d1bcc96f1"),
    ("/a/./b", "e5f5d81d1bcc96f1"),
    ("./a", "d9127419e9f03fd2"),
    ("a/.", "5efaa56e1b6d9df7"),
    ("/x/lib/json.dylib", "94a72943e4f51a09"),
    ("abcdefghijklmnopqrstuvwxyz0123456789", "6e3dc374eb435fd"),
    ("/", "bd60acb658c79e45"),
    ("./", "d871ac6a1fbb80e5"),
    (".", "d871ac6a1fbb80e5"),
    ("..", "194f230b041e7602"),
    ("a/.b", "44f5649af71478e7"),
    ("a/..", "cee4f1bcc5920655"),
    ("/a/b/./", "e5f5d81d1bcc96f1"),
  ]
  for case in cases {
    assert_eq(path_hash_hex(case.0), case.1, msg=case.0)
  }
  // Raw `Hasher::write` streams.
  let h = DefaultHasher::new()
  h.write(b"abcdefghijklmnopqrstuvwxyz0123456789")
  inspect(h.finish().to_string(radix=16), content="fe9ee02c60cec362")
  let h = DefaultHasher::new()
  inspect(h.finish().to_string(radix=16), content="d1fba762150c532c")
}

///|
/// Whether `pattern` parses.
fn parses(pattern : String) -> Bool {
  try @ast.ParserBuilder::new().build().parse(pattern) |> ignore catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
test "capture names use Rust's char predicates (Unicode 17)" {
  // U+1E6C0 (Tai Yo, new in Unicode 17) is alphabetic for Rust 1.97.1's
  // `char::is_alphabetic`, which regex-syntax's `is_capture_char` calls.
  inspect(parses("(?P<\u{1E6C0}>a)"), content="true")
  inspect(parses("(?P<a\u{1E6C0}>a)"), content="true")
  // Numeric characters may follow the first one.
  inspect(parses("(?P<a\u{663}>a)"), content="true")
  inspect(parses("(?P<\u{663}>a)"), content="false")
  // Unassigned code points are neither.
  inspect(parses("(?P<\u{1E6B0}>a)"), content="false")
}

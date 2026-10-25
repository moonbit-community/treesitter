///|
/// The `Display` text of the error for `pattern`.
fn error_text(pattern : String) -> String raise {
  try @regex.Regex::new(pattern) catch {
    e => e.to_string()
  } noraise {
    _ => fail("expected \{pattern} to be rejected")
  }
}

///|
test "error text keeps a bare final carriage return" {
  // Rust's `str::lines` only strips the `\r` of a `\r\n` terminator; the
  // expected texts come from `regex` 1.13.1.
  assert_eq(
    error_text("[a\r"),
    "regex parse error:\n    [a\r\n    ^\nerror: unclosed character class",
  )
  let rule = "~".repeat(79)
  assert_eq(
    error_text("[a\r\n"),
    "regex parse error:\n\{rule}\n1: [a\n   ^\n\{rule}\nerror: unclosed character class",
  )
  assert_eq(
    error_text("a\rb\n(?P<1>x)\r"),
    "regex parse error:\n\{rule}\n1: a\rb\n2: (?P<1>x)\r\n       ^\n\{rule}\nerror: invalid capture group character",
  )
}

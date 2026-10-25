///|
test "rust_trim trims char::is_whitespace" {
  inspect(
    rust_trim("\u{0B}\u{0C}\u{3000} a b\u{85}\u{A0}\t\n\r "),
    content="a b",
  )
  inspect(rust_trim("\u{200B}x\u{200B}"), content="\u{200B}x\u{200B}")
  inspect(rust_trim(" \u{2028} "), content="")
}

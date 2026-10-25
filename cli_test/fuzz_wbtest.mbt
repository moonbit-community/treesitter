///|
test "example filters are regex::Regex patterns" {
  // `regex::Regex` (UTF-8 mode) rejects a pattern that can match invalid
  // UTF-8, so the filter is ignored rather than excluding every example.
  inspect(env_regex("(?-u:\\xFF)") is None, content="true")
  inspect(env_regex("(") is None, content="true")
  guard env_regex("^a.c$") is Some(regex) else { fail("expected a regex") }
  inspect(regex.is_match(@utf8.encode("abc")), content="true")
}

///|
test "str::lines keeps the \\r of an unterminated last line" {
  debug_inspect(
    rust_lines("a\r\nb\r"[:]).map(l => l.to_owned()),
    content=(
      #|["a", "b\r"]
    ),
  )
}

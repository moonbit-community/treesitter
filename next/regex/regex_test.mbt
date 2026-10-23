///|
fn m(pattern : String, haystack : String) -> Bool raise {
  @regex.Regex::new(pattern).is_match(@utf8.encode(haystack))
}

///|
fn mb(pattern : String, haystack : Bytes) -> Bool raise {
  @regex.Regex::new(pattern).is_match(haystack)
}

///|
test "literal and unanchored search" {
  assert_true(m("abc", "xxabcxx"))
  assert_false(m("abc", "ab c"))
  assert_true(m("", ""))
  assert_true(m("", "anything"))
  assert_true(m("a|", "zzz"))
}

///|
test "anchors" {
  assert_true(m("^abc$", "abc"))
  assert_false(m("^abc$", "abcd"))
  assert_false(m("^b$", "a\nb\nc"))
  assert_true(m("(?m)^b$", "a\nb\nc"))
  assert_true(m("\\A\\z", ""))
  assert_false(m("\\A\\z", "a"))
  assert_true(m("(?Rm)^b$", "a\r\nb\r\nc"))
  assert_false(m("(?m)^b$", "a\r\nb\r\nc"))
}

///|
test "word boundaries" {
  assert_true(m("\\bfoo\\b", "a foo b"))
  assert_false(m("\\bfoo\\b", "afoob"))
  assert_true(m("\\Bfoo\\B", "afoob"))
  // Unicode word characters by default, ASCII with (?-u).
  assert_true(m("\\bé\\b", " é "))
  assert_true(m("(?-u:\\b)x", "éx"))
  assert_false(m("\\bx", "éx"))
  assert_true(m("\\b{start}foo\\b{end}", "(foo)"))
  // \B is never satisfied inside invalid UTF-8.
  assert_false(mb("\\B", b"\xc3\xa9\x80"))
  assert_true(mb("\\b\\w+\\b", b"\xffabc\xff"))
}

///|
test "classes" {
  assert_true(m("^[A-Z][A-Z\\d_]+$", "SCREAMING_CASE_1"))
  assert_false(m("^[A-Z][A-Z\\d_]+$", "Camel"))
  assert_true(m("^\\w+$", "héllo_日本"))
  assert_false(m("^(?-u:\\w)+$", "héllo"))
  assert_true(m("^\\p{Greek}+$", "αβγ"))
  assert_true(m("^\\d+$", "١٢٣"))
  assert_true(m("^[[:alpha:]]+$", "abc"))
  assert_true(m("^[a-z--aeiou]+$", "bcd"))
  assert_false(m("^[a-z--aeiou]+$", "bad"))
  // `.` matches one encoded code point, not one byte, and not `\n`.
  assert_true(m("^.$", "😀"))
  assert_false(m("^.$", "\n"))
  assert_true(m("(?s)^.$", "\n"))
  assert_false(mb("^.$", b"\xff"))
  assert_true(mb("^(?-u:.)$", b"\xff"))
  assert_true(mb("(?-u:\\xFF)", b"a\xffb"))
}

///|
test "case insensitivity only via flags" {
  assert_false(m("foo", "FOO"))
  assert_true(m("(?i)foo", "FOO"))
  assert_true(m("(?i)straße", "STRAẞE"))
  assert_true(m("(?i)k", "\u{212A}"))
}

///|
test "repetition" {
  assert_true(m("^a{2,4}$", "aaa"))
  assert_false(m("^a{2,4}$", "aaaaa"))
  assert_true(m("^(a|b)*c$", "ababc"))
  assert_true(m("^(a*)*$", "aaaa"))
  assert_true(m("^(|a)+$", ""))
  assert_true(m("^a{0}$", ""))
}

///|
test "invalid patterns" {
  for
    p in [
      "(", "[", "a)", "a{2,1}", "\\p{Nope}", "(?z)", "[z-a]", "(?=a)", "(?<=a)",
      "\\1", "(?P<n>a)(?P<n>b)", "\\8",
    ] {
    try @regex.Regex::new(p) catch {
      Syntax(_) => ()
      e => fail("unexpected error for \{p}: \{e}")
    } noraise {
      _ => fail("expected \{p} to be rejected")
    }
  }
}

///|
test "size limit" {
  // `regex` rejects patterns whose NFA exceeds 10 MiB.
  assert_true(m("\\w{100}", "x".repeat(100)))
  try @regex.Regex::new("\\w{500}") catch {
    CompiledTooBig(_) => ()
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected the size limit to be exceeded")
  }
  try @regex.Regex::new("a{1000}{1000}") catch {
    CompiledTooBig(_) => ()
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected the size limit to be exceeded")
  }
}

///|
test "DFA matches longest alternatives and repetitions" {
  let lexer = @lex.compile(@lex.parse("ab|a(bc)+|d{2,4}"))
  assert_eq(lexer.match_prefix(b"abcbcx"), Some(5))
  assert_eq(lexer.match_prefix(b"abx"), Some(2))
  assert_eq(lexer.match_prefix(b"ddddd"), Some(4))
  assert_eq(lexer.match_prefix(b"d"), None)
  assert_eq(lexer.match_prefix(b"xabc", start=1), Some(4))
  assert_eq(lexer.match_prefix(b"abc", start=-1), None)
  assert_false(lexer.nullable())
  assert_true(@lex.compile(@lex.parse("x*")).nullable())
}

///|
test "UTF8 locations remain byte offsets and malformed input advances" {
  let lexer = @lex.compile(@lex.parse("[^\\n]+"))
  let source : Bytes = [0xe4, 0xb8, 0xad, 0xf0, 0x9f, 0x98, 0x80, 10]
  assert_eq(lexer.match_prefix(source), Some(7))
  assert_eq(@lex.decode(source, 0), (0x4e2d, 3))
  assert_eq(@lex.decode(source, 3), (0x1f600, 4))
  assert_eq(@lex.decode([0xed, 0xa0, 0x80], 0), (0xfffd, 1))
  assert_eq(@lex.decode([0xc0, 0x80], 0), (0xfffd, 1))
  assert_eq(@lex.decode([0xf4, 0x90, 0x80, 0x80], 0), (0xfffd, 1))
  assert_eq(@lex.decode(b"", 0), (0, 0))
  assert_eq(lexer.match_prefix([0xff, 0xfe]), Some(2))
}

///|
test "Unicode properties and upstream case folding" {
  let greek = @lex.compile(@lex.parse("\\p{Script=Greek}+"))
  assert_eq(greek.match_prefix(@utf8.encode("αβx")), Some(4))
  let digits = @lex.compile(@lex.parse("\\d+"))
  assert_eq(digits.match_prefix(@utf8.encode("١٢")), Some(4))
  let words = @lex.compile(@lex.parse("\\w+"))
  assert_eq(words.match_prefix(@utf8.encode("中文_12")), Some(9))
  let insensitive = @lex.compile(@lex.parse("[a-zα]+", flags="i"))
  assert_eq(insensitive.match_prefix(@utf8.encode("AZΑα")), Some(6))
  assert_eq(insensitive.match_prefix(@utf8.encode("ſ")), None)
  assert_eq(insensitive.match_prefix(@utf8.encode("K")), None)
  let negative = @lex.compile(@lex.parse("[^x]+", flags="i"))
  assert_eq(negative.match_prefix(b"abX"), Some(2))
  let escaped_range = @lex.compile(@lex.parse("[\\x61-\\x7a]+", flags="i"))
  assert_eq(escaped_range.match_prefix(b"AZ"), Some(2))
}

///|
test "invalid regexes fail without panicking or hanging" {
  for
    pattern in [
      "[", "(", "[z-a]", "a{3,2}", "a{1001}", "(?=x)", "\\1", "\\u{d800}", "\\p{NotAProperty}",
      "*", "a*?",
    ] {
    try @lex.parse(pattern) catch {
      InvalidRegex(_, _) => ()
    } noraise {
      _ => fail("accepted invalid regex: \{pattern}")
    }
  }
  let expr = @lex.parse("abcd")
  try @lex.compile(expr, max_states=2) catch {
    InvalidRegex(_, _) => ()
  } noraise {
    _ => fail("ignored DFA resource limit")
  }
}

///|
test "character set normalization and scalar complement" {
  let chars = @lex.CharSet::new([(5, 7), (1, 4), (3, 9), (9, 8)])
  assert_true(chars.contains(1))
  assert_true(chars.contains(9))
  assert_false(chars.contains(10))
  assert_false(chars.complement().contains(5))
  assert_true(chars.complement().contains(0x10ffff))
  assert_false(chars.complement().contains(0xd800))
  assert_eq(chars.complement().complement(), chars)
}

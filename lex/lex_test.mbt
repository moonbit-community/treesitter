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
      "*", "(?i-:a)", "(?ii:a)", "(?-u:[é])",
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

///|
test "upstream leaf folding precedes nested class algebra" {
  // From crates/generate/src/prepare_grammar/expand_tokens.rs at the pinned
  // upstream revision: preserve its nested-set and scoped-flag expectations.
  for
    (pattern, accepted, rejected) in [
      ("[^[a-c]]", "d", "aAC"),
      ("[[a-z]--[b-d]]", "aA", "bB"),
      ("[[a-z]&&[b-d]]", "bB", "eE"),
      ("[[a-c]~~[b-d]]", "aAdD", "bBcC"),
    ] {
    let lexer = @lex.compile(@lex.parse(pattern, flags="i"))
    for c in accepted {
      assert_eq(lexer.match_prefix(@utf8.encode(c.to_string())), Some(1))
    }
    for c in rejected {
      assert_eq(lexer.match_prefix(@utf8.encode(c.to_string())), None)
    }
  }
  let lexer = @lex.compile(@lex.parse("(?i)a(?-i)b"))
  assert_eq(lexer.match_prefix(b"ab"), Some(2))
  assert_eq(lexer.match_prefix(b"Ab"), Some(2))
  assert_eq(lexer.match_prefix(b"aB"), None)
}

///|
test "scoped flags restore groups and ASCII classes remain distinct" {
  let lexer = @lex.compile(@lex.parse("(?i:a(?-i:b))c"))
  assert_eq(lexer.match_prefix(b"Abc"), Some(3))
  assert_eq(lexer.match_prefix(b"ABc"), None)
  assert_eq(lexer.match_prefix(b"AbC"), None)
  assert_eq(@lex.compile(@lex.parse("(?s:.)x")).match_prefix(b"\nx"), Some(2))
  let digits = @lex.compile(@lex.parse("(?-u:\\d)+"))
  assert_eq(digits.match_prefix(b"123"), Some(3))
  assert_eq(digits.match_prefix(@utf8.encode("١")), None)
  let ascii = @lex.compile(@lex.parse("[[:alpha:]--[x]]+"))
  assert_eq(ascii.match_prefix(b"abcx"), Some(3))
  assert_eq(ascii.match_prefix(@utf8.encode("é")), None)
  assert_eq(@lex.compile(@lex.parse("[]]+?")).match_prefix(b"]]]"), Some(3))
  assert_eq(@lex.compile(@lex.parse("a*?b")).match_prefix(b"aaab"), Some(4))
  let deep = "(".repeat(130) + "x" + ")".repeat(130)
  try @lex.parse(deep) catch {
    InvalidRegex(_, _) => ()
  } noraise {
    _ => fail("accepted unbounded nesting")
  }
}

///|
test "extended flags skip comments and whitespace while preserving escapes" {
  let regex = @lex.compile(
    @lex.parse("(?x: a # comment\n b [ c d ] \\  \\#)(?-x: )"),
  )
  assert_eq(regex.match_prefix(b"abc # "), Some(6))
  assert_eq(regex.match_prefix(b"abd # "), Some(6))
  assert_eq(regex.match_prefix(b"ab  # "), None)
  let dot = @lex.compile(@lex.parse("(?mRU:.)"))
  assert_eq(dot.match_prefix(b"\r"), None)
  assert_eq(dot.match_prefix(b"a"), Some(1))
  assert_eq(@lex.compile(@lex.parse("(?Rs:.)")).match_prefix(b"\r"), Some(1))
}

///|
test "named capture groups have ordinary lexical group semantics" {
  let regex = @lex.compile(@lex.parse("(?P<head>a)(?<tail>b+)"))
  assert_eq(regex.match_prefix(b"abbb"), Some(4))
  for pattern in ["(?<x>a)(?<x>b)", "(?<0>a)", "(?<=a)b", "(?P<>)"] {
    try @lex.parse(pattern) catch {
      InvalidRegex(_, _) => ()
    } noraise {
      _ => fail("accepted invalid capture")
    }
  }
}

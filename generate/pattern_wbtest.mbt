// Tests for pattern.mbt (upstream pattern.rs has no tests of its own). The
// expected values were produced by upstream's `pattern::parse` (see the
// differential probe described in regex_syntax/probe).

///|
fn class_ranges(hir : @hir.Hir) -> Array[(Int32, Int32)] {
  match hir.kind() {
    Class(Unicode(c)) =>
      c.ranges().iter().map(r => (r.start(), r.end())).collect()
    Class(Bytes(c)) =>
      c
      .ranges()
      .iter()
      .map(r => (r.start().to_int(), r.end().to_int()))
      .collect()
    _ => abort("not a class")
  }
}

///|
fn pattern_error(pattern : String) -> String {
  try pattern_parse(pattern, false) |> ignore catch {
    e => e.to_string()
  } noraise {
    _ => "no error"
  }
}

///|
test "case-insensitive folding keeps long s and Kelvin sign out" {
  let hir = pattern_parse("[sk]+", true)
  guard hir.kind() is Repetition({ min: 1, max: None, greedy: true, sub, }) else {
    fail("expected a repetition")
  }
  assert_eq(class_ranges(sub), [
    (0x4b, 0x4b),
    (0x53, 0x53),
    (0x6b, 0x6b),
    (0x73, 0x73),
  ])
  // Folding at the leaves, before negation.
  assert_eq(class_ranges(pattern_parse("(?i)[^x]", false)), [
    (0, 0x57),
    (0x59, 0x77),
    (0x79, 0x10ffff),
  ])
  // An explicit `ſ`/`K` folds with nothing.
  assert_eq(class_ranges(pattern_parse("[\u{17f}\u{212a}]", true)), [
    (0x17f, 0x17f),
    (0x212a, 0x212a),
  ])
  // Byte folding is ASCII only.
  assert_eq(class_ranges(pattern_parse("(?-u:(?i)k)", false)), [
    (0x4b, 0x4b),
    (0x6b, 0x6b),
  ])
  // Folding the operands of the set algebra.
  assert_eq(class_ranges(pattern_parse("[a-z--b]", true)), [
    (0x41, 0x41),
    (0x43, 0x5a),
    (0x61, 0x61),
    (0x63, 0x7a),
  ])
  // Scoped flags.
  guard pattern_parse("(?i)a(?-i)b", false).kind() is Concat([a, b]) else {
    fail("expected a concatenation")
  }
  assert_eq(class_ranges(a), [(0x41, 0x41), (0x61, 0x61)])
  assert_eq(b, @hir.Hir::literal(b"b"))
}

///|
test "regex error display" {
  inspect(
    pattern_error("(?P<n>a)(?P<n>b)"),
    content=(
      #|regex parse error:
      #|    (?P<n>a)(?P<n>b)
      #|        ^       ^
      #|error: duplicate capture group name
    ),
  )
  inspect(
    pattern_error("(?i-i)"),
    content=(
      #|regex parse error:
      #|    (?i-i)
      #|      ^ ^
      #|error: duplicate flag
    ),
  )
  inspect(
    pattern_error("\u{e9}\u{e9}\\p{Foo}"),
    content=(
      #|regex parse error:
      #|    éé\p{Foo}
      #|      ^^^^^^^
      #|error: Unicode property not found
    ),
  )
  inspect(
    pattern_error("("),
    content=(
      #|regex parse error:
      #|    (
      #|    ^
      #|error: unclosed group
    ),
  )
  inspect(
    pattern_error("a{5,2}"),
    content=(
      #|regex parse error:
      #|    a{5,2}
      #|     ^^^^^
      #|error: invalid repetition count range, the start must be <= the end
    ),
  )
  inspect(
    pattern_error("\\x{110000}"),
    content=(
      #|regex parse error:
      #|    \x{110000}
      #|       ^^^^^^
      #|error: hexadecimal literal is not a Unicode scalar value
    ),
  )
}

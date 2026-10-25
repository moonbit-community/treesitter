// Port of the tests of tree-sitter crates/cli/src/query_testing.rs, and tests
// of the bstr helpers (expected values from bstr 1.13.1).

///|
test "assertion_after_multiline_capture_does_not_match" {
  let captures : Array[@query_testing.CaptureInfo] = [
    {
      name: "foo",
      start: @query_testing.Utf8Point::new(0, 0),
      end: @query_testing.Utf8Point::new(1, 1),
    },
  ]
  let assertions = [@query_testing.Assertion::new(2, 0, 1, false, "foo")]
  let result = Ok(@query_testing.assert_expected_captures(captures, assertions)) catch {
    e => Err(e)
  }
  assert_true(result is Err(_))
}

///|
test "grapheme_ends" {
  let ends = s => @query_testing.grapheme_ends(@utf8.encode(s))
  debug_inspect(ends("ab"), content="[1, 2]")
  // `y` + U+0306 COMBINING BREVE is one grapheme.
  debug_inspect(ends("y̆y̆"), content="[3, 6]")
  debug_inspect(ends("\r\na\n"), content="[2, 3, 4]")
  // A ZWJ emoji sequence and a flag.
  debug_inspect(ends("👨‍👩‍👦🇺🇸"), content="[18, 26]")
  // Invalid UTF-8 is consumed by maximal invalid prefixes.
  debug_inspect(
    @query_testing.grapheme_ends(b"\xe2\x82a\xffb"),
    content="[2, 3, 4, 5]",
  )
}

///|
test "lines_with_terminator" {
  let lines = @query_testing.lines_with_terminator(b"a\n\nb")
  debug_inspect(
    lines.map(l => @utf8.decode_lossy(l)),
    content="[\"a\\n\", \"\\n\", \"b\"]",
  )
}

///|
test "to_utf8_point" {
  let source = @utf8.encode("x\nvar y̆y̆ = 1\n")
  debug_inspect(
    @query_testing.to_utf8_point(@treesitter.Point::new(1, 12), source),
    content="{ row: 1, column: 8 }",
  )
  debug_inspect(
    @query_testing.to_utf8_point(@treesitter.Point::new(1, 0), source),
    content="{ row: 1, column: 0 }",
  )
}

///|
test "zero_length_assertion_end_column_wraps" {
  // `column + length - 1` is `usize` arithmetic: the release CLI wraps to
  // `usize::MAX` (0x7FFFFFFF here), so this assertion cannot match.
  let captures : Array[@query_testing.CaptureInfo] = [
    {
      name: "foo",
      start: @query_testing.Utf8Point::new(0, 0),
      end: @query_testing.Utf8Point::new(0, 1),
    },
  ]
  let check = assertion => {
    Ok(@query_testing.assert_expected_captures(captures, [assertion])) catch {
      e => Err(e)
    }
  }
  inspect(
    check(@query_testing.Assertion::new(0, 0, 0, false, "foo")),
    content="Err(Assertion failed: could not match foo at row 0, column 2147483647)",
  )
  // A zero-length assertion at a later column ends one column before it.
  inspect(
    check(@query_testing.Assertion::new(0, 1, 0, false, "foo")),
    content="Ok(1)",
  )
}

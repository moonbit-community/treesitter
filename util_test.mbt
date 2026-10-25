// Expected outputs below were produced by the Rust binding (lib.rs) of the
// pinned upstream checkout.

///|
test "format_sexp" {
  let sexp = "(document (array (number) (false) (object (pair key: (string (string_content)) value: (null)))))"
  inspect(
    @treesitter.format_sexp(sexp, 0),
    content=(
      #|(document
      #|  (array
      #|    (number)
      #|    (false)
      #|    (object
      #|      (pair
      #|        key: (string
      #|          (string_content))
      #|        value: (null)))))
    ),
  )
  inspect(
    @treesitter.format_sexp(sexp, 2),
    content=(
      #|
      #|    (document
      #|      (array
      #|        (number)
      #|        (false)
      #|        (object
      #|          (pair
      #|            key: (string
      #|              (string_content))
      #|            value: (null)))))
    ),
  )
  inspect(
    @treesitter.format_sexp("(document (ERROR (number)))", 0),
    content=(
      #|(document
      #|  (ERROR
      #|    (number)))
    ),
  )
  inspect(
    @treesitter.format_sexp(
      "(document (array (number) (ERROR (UNEXPECTED '@')) (number)))", 0,
    ),
    content=(
      #|(document
      #|  (array
      #|    (number)
      #|    (ERROR
      #|      (UNEXPECTED '@'))
      #|    (number)))
    ),
  )
  // Upstream's scanner drops the final `)` after a quoted MISSING name.
  inspect(
    @treesitter.format_sexp("(a (MISSING \"b\"))", 0),
    content=(
      #|(a
      #|  (MISSING "b")
    ),
  )
  inspect(
    @treesitter.format_sexp("(a (MISSING b) (c))", 0),
    content=(
      #|(a
      #|  (MISSING b)
      #|  (c))
    ),
  )
}

///|
test "LossyUtf8" {
  // An incomplete sequence at the end stops the iteration, as upstream.
  assert_eq(@treesitter.LossyUtf8::new(b"ab\xffcd\xe2\x82").iter().to_array(), [
    "ab", "\u{fffd}",
  ])
  assert_eq(@treesitter.LossyUtf8::new(b"\xff\xfe").iter().to_array(), [
    "\u{fffd}", "\u{fffd}",
  ])
  assert_eq(@treesitter.LossyUtf8::new(b"ok").iter().to_array(), ["ok"])
  assert_eq(@treesitter.LossyUtf8::new(b"").iter().to_array(), [])
}

///|
test "Point, Range and errors" {
  inspect(@treesitter.Point::new(1, 2), content="(1, 2)")
  assert_true(@treesitter.Point::new(1, 2) < @treesitter.Point::new(2, 0))
  assert_true(@treesitter.Point::new(1, 2) < @treesitter.Point::new(1, 3))
  inspect(@treesitter.IncludedRangesError(3), content="Incorrect range by index: 3")
  inspect(
    @treesitter.LanguageError::Version(16),
    content="Incompatible language version 16. Expected minimum 13, maximum 15",
  )
  inspect(
    @treesitter.LanguageError::NotParseable,
    content="Language cannot be used for parsing.",
  )
  // `Int::max_value()` stands for `u32::MAX` when converting to the runtime.
  let edit : @treesitter.InputEdit = {
    start_byte: 0,
    old_end_byte: 0,
    new_end_byte: 1,
    start_position: @treesitter.Point::new(0, 0),
    old_end_position: @treesitter.Point::new(0, 0),
    new_end_position: @treesitter.Point::new(0, 1),
  }
  let unbounded : @treesitter.Range = {
    start_byte: 0,
    end_byte: 0x7FFFFFFF,
    start_point: @treesitter.Point::new(0, 0),
    end_point: @treesitter.Point::new(0x7FFFFFFF, 0x7FFFFFFF),
  }
  assert_eq(edit.edit_range(unbounded).end_byte, 0x7FFFFFFF)
}

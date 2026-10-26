// `Debug` formats of the binding's data types and C-string accessors.
// Expected outputs were produced by the types' `#[derive(Debug)]`
// definitions copied from lib.rs of the pinned upstream checkout.

///|
test "Debug formats match Rust's derive(Debug)" {
  debug_inspect(
    @treesitter.Point::new(1, 2),
    content="Point { row: 1, column: 2 }",
  )
  debug_inspect(
    ({
      start_byte: 0,
      end_byte: 12,
      start_point: @treesitter.Point::new(0, 0),
      end_point: @treesitter.Point::new(3, 4),
    } : @treesitter.Range),
    content="Range { start_byte: 0, end_byte: 12, start_point: Point { row: 0, column: 0 }, end_point: Point { row: 3, column: 4 } }",
  )
  debug_inspect(
    ({
      start_byte: 1,
      old_end_byte: 2,
      new_end_byte: 3,
      start_position: @treesitter.Point::new(4, 5),
      old_end_position: @treesitter.Point::new(6, 7),
      new_end_position: @treesitter.Point::new(8, 9),
    } : @treesitter.InputEdit),
    content="InputEdit { start_byte: 1, old_end_byte: 2, new_end_byte: 3, start_position: Point { row: 4, column: 5 }, old_end_position: Point { row: 6, column: 7 }, new_end_position: Point { row: 8, column: 9 } }",
  )
  debug_inspect(
    @treesitter.QueryProperty::new("key\"\\\n", Some("v\u{0}é\u{301}\u{7f}"), None),
    content=(
      #|QueryProperty { key: "key\"\\\n", value: Some("v\0é\u{301}\u{7f}"), capture_id: None }
    ),
  )
  debug_inspect(
    @treesitter.QueryProperty::new("k", None, Some(3)),
    content=(
      #|QueryProperty { key: "k", value: None, capture_id: Some(3) }
    ),
  )
  debug_inspect(
    ({ operator: "is-not?", args: [Capture(0), String("it's\t")] } : @treesitter.QueryPredicate),
    content=(
      #|QueryPredicate { operator: "is-not?", args: [Capture(0), String("it's\t")] }
    ),
  )
  debug_inspect(
    ({ operator: "x", args: [] } : @treesitter.QueryPredicate),
    content=(
      #|QueryPredicate { operator: "x", args: [] }
    ),
  )
  debug_inspect(
    @treesitter.QueryPredicateArg::String("a"),
    content=(
      #|String("a")
    ),
  )
  debug_inspect(
    @treesitter.QueryError(
      row=1,
      column=2,
      offset=10,
      message="foo\nbar",
      kind=Syntax,
    ),
    content=(
      #|QueryError { row: 1, column: 2, offset: 10, message: "foo\nbar", kind: Syntax }
    ),
  )
  debug_inspect(
    @treesitter.QueryError(row=0, column=0, offset=0, message="", kind=NodeType),
    content=(
      #|QueryError { row: 0, column: 0, offset: 0, message: "", kind: NodeType }
    ),
  )
}

///|
test "Language::name is a C string" {
  let generated = @generate.generate_from_grammar_json(
    (
      #|{"name": "json", "rules": {"document": {"type": "STRING", "value": "x"}}}
    ),
  )
  // `CStr::from_ptr(ts_language_name(..))` stops at the NUL.
  let raw = { ..generated.language, name: "json\u{0}suffix" }
  let language = @treesitter.Language::new(raw)
  debug_inspect(language.name(), content="Some(\"json\")")
  // The stored value is unchanged.
  assert_eq(language.raw().name, "json\u{0}suffix")
}

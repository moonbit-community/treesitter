///|
test "cancelled parsing resumes the saved stacks without restarting" {
  let language = @generate.generate(
    @grammar.Grammar::new("resuming", [
      ("document", Repeat(Symbol("item"))),
      ("item", Seq([Literal("("), Literal(")")])),
    ]),
  )
  let parser = @treesitter.Parser::new(language)
  let source = b"() () () () () () () () () ()"
  let fresh = parser.parse(source)
  let mut calls = 0
  let stopped = try {
    ignore(
      parser.parse(source, cancelled=() => {
        calls += 1
        calls > 14
      }),
    )
    false
  } catch {
    Cancelled => true
    _ => false
  }
  assert_true(stopped)
  assert_true(parser.has_pending_parse())
  let mut interruptions = 0
  let mut complete : @treesitter.Tree? = None
  while complete is None {
    calls = 0
    try {
      complete = Some(
        parser.resume_parse(cancelled=() => {
          calls += 1
          calls > 14
        }),
      )
    } catch {
      Cancelled => interruptions += 1
      other => raise other
    }
    assert_true(interruptions < 20)
  }
  assert_true(interruptions > 0)
  assert_eq(
    complete.unwrap().root_node().to_sexp(),
    fresh.root_node().to_sexp(),
  )
  assert_eq(complete.unwrap().parse_steps, fresh.parse_steps)
  assert_false(parser.has_pending_parse())
}

///|
test "resuming included ranges restores original source coordinates" {
  let language = @generate.generate(
    @grammar.Grammar::new("ranged_resume", [
      ("document", Repeat(Symbol("word"))),
      ("word", @grammar.pattern("[a-z]+")),
    ]),
  )
  let parser = @treesitter.Parser::new(language)
  let source = b"xxabc yydef"
  let ranges : Array[@treesitter.Range] = [
    {
      start_byte: 2,
      end_byte: 5,
      start_point: { row: 0, column: 2, },
      end_point: { row: 0, column: 5, },
    },
    {
      start_byte: 8,
      end_byte: 11,
      start_point: { row: 0, column: 8, },
      end_point: { row: 0, column: 11, },
    },
  ]
  let fresh = parser.parse(source, included_ranges=ranges)
  let mut calls = 0
  let stopped = try {
    ignore(
      parser.parse(source, included_ranges=ranges, cancelled=() => {
        calls += 1
        calls > 8
      }),
    )
    false
  } catch {
    Cancelled => true
    _ => false
  }
  assert_true(stopped)
  let resumed = parser.resume_parse()
  assert_eq(resumed.root_node().range(), fresh.root_node().range())
  assert_eq(resumed.source, source)
  assert_eq(resumed.included_ranges(), ranges)
  parser.reset()
  assert_false(parser.has_pending_parse())
}

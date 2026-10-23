///|
test "parser diagnostics can be installed replaced and disabled" {
  let language = @generate.generate(
    @grammar.Grammar::new("logging", [("document", Literal("x"))]),
  )
  let parser = @treesitter.Parser::new(language)
  assert_true(parser.logger() is None)
  let events : Array[(@treesitter.LogType, String)] = []
  parser.set_logger(Some((kind, message) => events.push((kind, message))))
  assert_eq(parser.parse_string("x").root_node().to_sexp(), "(document)")
  assert_true(events.any(e => e.0 == Lex && e.1.has_prefix("lookahead")))
  assert_true(events.any(e => e.0 == Parse && e.1.has_prefix("reduce")))
  assert_true(events.any(e => e.0 == Parse && e.1.has_prefix("accept")))
  let installed = parser.logger().unwrap()
  installed(Parse, "saved callback")
  assert_eq(events.last().unwrap().1, "saved callback")
  parser.reset()
  assert_true(parser.logger() is Some(_))
  let length = events.length()
  ignore(parser.parse_string("x"))
  assert_true(events.length() > length)
  parser.set_logger(None)
  assert_true(parser.logger() is None)
  let length = events.length()
  ignore(parser.parse_string("x"))
  assert_eq(events.length(), length)
}

///|
test "parser diagnostics persist across cancellation and resumption" {
  let language = @generate.generate(
    @grammar.Grammar::new("logging", [("document", Literal("x"))]),
  )
  let parser = @treesitter.Parser::new(language)
  let events : Array[String] = []
  parser.set_logger(Some((_, message) => events.push(message)))
  let cancelled = try {
    ignore(parser.parse(b"x", cancelled=() => !events.is_empty()))
    false
  } catch {
    Cancelled => true
    _ => false
  }
  assert_true(cancelled)
  assert_true(parser.has_pending_parse())
  ignore(parser.resume_parse())
  assert_true(events.any(e => e.has_prefix("accept")))
}

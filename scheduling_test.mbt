///|
// The pinned C runtime discards the paused member interpretation after the
// conditional has advanced successfully. Keeping it until all stacks pause
// lets the earlier error swallow the first otherwise valid conditional.
test "recovery rounds discard stale paused alternatives" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "scheduling_fixture",
      [
        ("document", Repeat(Choice([Symbol("member"), Symbol("conditional")]))),
        (
          "member",
          Seq([
            Symbol("identifier"),
            Literal("."),
            Symbol("identifier"),
            Literal("{"),
            Literal("}"),
            Literal(";"),
          ]),
        ),
        (
          "conditional",
          Seq([
            Literal("if"),
            Symbol("identifier"),
            Literal(">"),
            Symbol("identifier"),
            Literal("{"),
            Literal("}"),
            Literal(";"),
          ]),
        ),
        ("identifier", @grammar.pattern("[a-z]+")),
        ("comment", @grammar.pattern("//[^\\n]*")),
      ],
      extras=[@grammar.pattern("\\s"), Symbol("comment")],
      word="identifier",
      reserved={ "global": [Literal("if")] },
    ),
  )
  let source = "a. // first error\nif b > c {}; a. // second error\nif b > c {};"
  let parser = @treesitter.Parser::new(language)
  let expected = "(document (ERROR (identifier)) (comment) (conditional (identifier) (identifier)) (ERROR (identifier)) (comment) (conditional (identifier) (identifier)))"
  let fresh = parser.parse_string(source)
  assert_eq(fresh.root_node().to_sexp(), expected)
  // Pause at successive callback boundaries, including recovery preparation,
  // queued competitors and round transitions. Resuming must do the same work.
  for limit in 2..<=100 {
    let mut calls = 0
    let tree = parser.parse(@utf8.encode(source), cancelled=() => {
      calls += 1
      calls > limit
    }) catch {
      Cancelled =>
        parser.resume_parse() catch {
          _ => fail("resumption failed at callback limit \{limit}")
        }
      other => raise other
    }
    assert_eq(tree.root_node().to_sexp(), expected)
    assert_eq(tree.parse_steps, fresh.parse_steps)
  }
}

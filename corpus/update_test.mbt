///|
test "format corpus expectations with fields and quoted recovery tokens" {
  // Frozen from the upstream CLI formatter regression suite (MIT licensed).
  inspect(
    @corpus.format_sexp("(a b: (c) (d) e: (f (g (h (MISSING i)))))"),
    content=(
      #|(a
      #|  b: (c)
      #|  (d)
      #|  e: (f
      #|    (g
      #|      (h
      #|        (MISSING i)))))
    ),
  )
  inspect(
    @corpus.format_sexp("(program (ERROR (UNEXPECTED ' ')) (identifier))"),
    content=(
      #|(program
      #|  (ERROR
      #|    (UNEXPECTED ' '))
      #|  (identifier))
    ),
  )
  inspect(
    @corpus.format_sexp("(source_file (MISSING \")\"))"),
    content=(
      #|(source_file
      #|  (MISSING ")"))
    ),
  )
  assert_eq(@corpus.format_sexp(""), "")
}

///|
fn update_language() -> @language.Language raise {
  @generate.generate(
    @grammar.Grammar::new("updates", [
      ("document", Repeat1(Symbol("word"))),
      ("word", @grammar.pattern("[a-zé]+")),
    ]),
  )
}

///|
test "corpus updating preserves inputs headers skips and passing expectations" {
  let language = update_language()
  let unchanged = "===\nAlready correct\n===\na\n---\n(document  (word)) ; retain comment\n\n===\nSkipped\n:skip\n===\n???\n---\nnot an expectation\n\n"
  let source = unchanged +
    "===\nUnicode é😀\n===\n  café b  \n---\n\n(document)\n\n"
  let expected = unchanged +
    "===\nUnicode é😀\n===\n  café b  \n---\n\n(document\n  (word)\n  (word))\n\n"
  let updated = @corpus.update(language, source)
  assert_eq(updated, expected)
  assert_eq(@corpus.update(language, updated), updated)
  assert_eq(@corpus.parse(updated)[2].input, "  café b  ")
  assert_true(@corpus.run(language, @corpus.parse(updated)).all(r => r.passed))
  let windows = source.replace_all(old="\n", new="\r\n")
  assert_eq(
    @corpus.update(language, windows),
    expected.replace_all(old="\n", new="\r\n"),
  )
}

///|
test "corpus updating refuses unexpected errors and failed error assertions" {
  let language = update_language()
  for
    source in [
      "===\nUnexpected error\n===\n@\n---\n(document)\n", "===\nNo error\n:error\n===\na\n---\n(ERROR)\n",
    ] {
    assert_true(
      try {
        ignore(@corpus.update(language, source))
        false
      } catch {
        @corpus.InvalidCorpus(_) => true
        _ => false
      },
    )
  }
  let error = "===\nExpected error\n:error\n===\n@\n---\nignored\n"
  assert_eq(@corpus.update(language, error), error)
  let empty = "===\nNo old expectation\n===\na\n---\n===\nLast\n===\nb\n---\n"
  let updated = @corpus.update(language, empty)
  assert_eq(@corpus.parse(updated).length(), 2)
  assert_true(@corpus.run(language, @corpus.parse(updated)).all(r => r.passed))
}

///|
test "corpus updates render concrete syntax expectations" {
  let language = update_language()
  let source = "===\nConcrete syntax\n:cst\n===\na\n---\nold\n"
  let updated = @corpus.update(language, source)
  assert_true(@corpus.run(language, @corpus.parse(updated))[0].passed)
  assert_eq(
    @corpus.parse(updated)[0].expected,
    @corpus.render_cst(
      @ts.Parser::new(language).parse_string("a").root_node(),
      "a",
    )
    .trim()
    .to_owned(),
  )
}

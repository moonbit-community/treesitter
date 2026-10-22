///|
test "corpus preserves input whitespace including newline-only tokens" {
  let source = "===\nnewline\n===\n\n\n---\n(root)\n===\nspaces\n===\n  x  \n---\n(root)\n"
  let cases = @corpus.parse(source)
  assert_eq(cases[0].input, "\n")
  assert_eq(cases[1].input, "  x  ")
  assert_eq(
    @corpus.normalize_sexp("(root\n (child) text: (other))"),
    "(root (child) text: (other))",
  )
  assert_eq(@corpus.normalize_sexp("(MISSING \"a  b\")"), "(MISSING \"a  b\")")
}

///|
test "a scanner failure reports its case and continues the corpus" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "scanner_failure",
      [("document", Symbol("word"))],
      externals=[Symbol("word")],
      extras=[],
    ),
  )
  let scanner = @ts.ExternalScanner::new((input, valid, _) => {
    if input.lookahead() == 33 {
      return Some({ token: 99, state: b"", })
    }
    if valid[0] && input.lookahead() == 120 {
      input.advance()
      return Some({ token: 0, state: b"", })
    }
    None
  })
  let cases = @corpus.parse(
    "===\ninvalid scanner\n:error\n===\n!\n---\n(ERROR)\n===\nvalid input\n===\nx\n---\n(document (word))\n",
  )
  let results = @corpus.run(language, cases, scanner~)
  assert_eq(results.length(), 2)
  assert_false(results[0].passed)
  assert_true(results[0].actual.has_prefix("parse failed: ScannerError"))
  assert_true(results[1].passed)
}

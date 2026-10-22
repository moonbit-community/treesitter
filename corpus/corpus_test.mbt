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

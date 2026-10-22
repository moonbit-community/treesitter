///|
test "seeded corpus fuzzing checks edits and reverses them" {
  let language = @generate.generate(
    @grammar.Grammar::new("fuzz_words", [
      ("document", Repeat(Symbol("word"))),
      ("word", @grammar.pattern("[a-z]+")),
    ]),
  )
  let case : @corpus.Case = {
    name: "words",
    input: "a b\nc",
    expected: "",
    skip: false,
    error: false,
    cst: false,
  }
  let options = fuzz_options([
    "--seed", "7", "--iterations", "10", "--edits", "3",
  ])
  let first = fuzz_case(language, case, options, None)
  assert_true(first >= 20 && first <= 60)
  assert_eq(fuzz_case(language, case, options, None), first)
}

///|
test "fuzz comparison detects field differences even with identical syntax" {
  fn language(field : String) -> @language.Language raise {
    @generate.generate(
      @grammar.Grammar::new("fuzz_fields", [
        ("root", Field(field, Symbol("word"))),
        ("word", @grammar.pattern("[a-z]+")),
      ]),
    )
  }
  let left = @ts.Parser::new(language("left")).parse_string("word")
  let right = @ts.Parser::new(language("right")).parse_string("word")
  assert_eq(fuzz_check_tree(left), None)
  assert_eq(fuzz_check_tree(right), None)
  assert_true(fuzz_compare(left, right) is Some(_))
}

///|
test "fuzz options reject invalid counts and unknown flags" {
  for
    args in [
      ["--iterations", "0"],
      ["--edits", "-1"],
      ["--seed", "x"],
      ["--iterations"],
      ["--unknown", "1"],
    ] {
    try fuzz_options(args) catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid fuzz options")
    }
  }
}

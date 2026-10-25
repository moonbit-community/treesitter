// Tests of fuzz.rs and fuzz/corpus_test.rs details.

///|
test "parse_usize is str::parse::<usize>" {
  let cases = [
    "0", "+7", "18446744073709551615", "18446744073709551616", "4294967296", "",
    "+", "-1", "-0", " 1", "1 ", "0x10", "٣", "007",
  ]
  let results = cases.map(s => {
    match @cli_test.parse_usize(s) {
      Some(n) => n.to_string()
      None => "-"
    }
  })
  inspect(
    results.join(","),
    content="0,7,18446744073709551615,-,4294967296,-,-,-,-,-,-,-,-,7",
  )
}

///|
fn included_ranges(
  input : String,
  delimiters : (String, String)?,
) -> String raise {
  let parser = @treesitter.Parser::new()
  @cli_test.set_included_ranges(parser, @utf8.encode(input), delimiters)
  parser
  .included_ranges()
  .map(r => {
    "\{r.start_byte}..\{r.end_byte} (\{r.start_point.row},\{r.start_point.column})-(\{r.end_point.row},\{r.end_point.column})"
  })
  .join(" ")
}

///|
test "set_included_ranges searches two-byte windows" {
  let whole = included_ranges("<x>", None)
  inspect(
    included_ranges("a<%b%>c\n<%d", Some(("<%", "%>"))),
    content="3..4 (0,3)-(0,4) 10..11 (1,2)-(1,3)",
  )
  inspect(
    included_ranges("<%%>", Some(("<%", "%>"))),
    content="2..2 (0,2)-(0,2)",
  )
  // Delimiters of another length never match: the whole document.
  assert_eq(included_ranges("<x>", Some(("<", ">"))), whole)
  assert_eq(included_ranges("<x>", Some(("", ""))), whole)
  assert_eq(included_ranges("a<<%b", Some(("<<%", "%>"))), whole)
}

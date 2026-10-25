// Generated from the `unwrap_err` assertions of the tests in regex-syntax
// 0.8.11 src/ast/parse.rs (those that call `parse()` and use single-line
// `span(a..b)` spans).

///|
fn sp(start : Int32, end : Int32) -> @ast.Span {
  @ast.Span::new(
    @ast.Position::new(start, 1, start + 1),
    @ast.Position::new(end, 1, end + 1),
  )
}

///|
fn parse_err(
  builder : @ast.ParserBuilder,
  pattern : String,
) -> (@ast.ErrorKind, @ast.Span) {
  try builder.build().parse(pattern) |> ignore catch {
    e => (e.kind(), e.span())
  } noraise {
    _ => abort("expected an error for \{pattern}")
  }
}

///|
test "parse errors" {
  assert_eq(
    parse_err(@ast.ParserBuilder::new().nest_limit(0), "a+"),
    (NestLimitExceeded(0), sp(0, 2)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new().nest_limit(1), "(a)+"),
    (NestLimitExceeded(1), sp(0, 3)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new().nest_limit(1), "a+*"),
    (NestLimitExceeded(1), sp(0, 2)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new().nest_limit(0), "ab"),
    (NestLimitExceeded(0), sp(0, 2)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new().nest_limit(0), "a|b"),
    (NestLimitExceeded(0), sp(0, 3)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new().nest_limit(0), "[a]"),
    (NestLimitExceeded(0), sp(0, 3)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new().nest_limit(1), "[ab]"),
    (NestLimitExceeded(1), sp(1, 3)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new().nest_limit(2), "[ab[cd]]"),
    (NestLimitExceeded(2), sp(3, 7)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new().nest_limit(3), "[ab[cd]]"),
    (NestLimitExceeded(3), sp(4, 6)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new().nest_limit(1), "[a--b]"),
    (NestLimitExceeded(1), sp(1, 5)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new().nest_limit(2), "[a--bc]"),
    (NestLimitExceeded(2), sp(4, 6)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "*"),
    (RepetitionMissing, sp(0, 0)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(?i)*"),
    (RepetitionMissing, sp(4, 4)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(*)"),
    (RepetitionMissing, sp(1, 1)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(?:?)"),
    (RepetitionMissing, sp(3, 3)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "+"),
    (RepetitionMissing, sp(0, 0)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "?"),
    (RepetitionMissing, sp(0, 0)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(?)"),
    (RepetitionMissing, sp(1, 1)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "|*"),
    (RepetitionMissing, sp(1, 1)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "|+"),
    (RepetitionMissing, sp(1, 1)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "|?"),
    (RepetitionMissing, sp(1, 1)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(?i){0}"),
    (RepetitionMissing, sp(4, 4)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(?m){1,1}"),
    (RepetitionMissing, sp(4, 4)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "a{]}"),
    (RepetitionCountDecimalEmpty, sp(2, 2)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "a{1,]}"),
    (RepetitionCountDecimalEmpty, sp(4, 4)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "a{"),
    (RepetitionCountUnclosed, sp(1, 2)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "a{}"),
    (RepetitionCountDecimalEmpty, sp(2, 2)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "a{a"),
    (RepetitionCountDecimalEmpty, sp(2, 2)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "a{9999999999}"),
    (DecimalInvalid, sp(2, 12)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "a{9"),
    (RepetitionCountUnclosed, sp(1, 3)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "a{9,a"),
    (RepetitionCountDecimalEmpty, sp(4, 4)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "a{9,9999999999}"),
    (DecimalInvalid, sp(4, 14)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "a{9,"),
    (RepetitionCountUnclosed, sp(1, 4)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "a{9,11"),
    (RepetitionCountUnclosed, sp(1, 6)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "a{2,1}"),
    (RepetitionCountInvalid, sp(1, 6)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "{5}"),
    (RepetitionMissing, sp(0, 0)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "|{5}"),
    (RepetitionMissing, sp(1, 1)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "a|b)"),
    (GroupUnopened, sp(3, 4)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(a|b"),
    (GroupUnclosed, sp(0, 1)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(?=a)"),
    (UnsupportedLookAround, sp(0, 3)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(?!a)"),
    (UnsupportedLookAround, sp(0, 3)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(?<=a)"),
    (UnsupportedLookAround, sp(0, 4)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(?<!a)"),
    (UnsupportedLookAround, sp(0, 4)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "("),
    (GroupUnclosed, sp(0, 1)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(?"),
    (GroupUnclosed, sp(0, 1)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(?P"),
    (FlagUnrecognized, sp(2, 3)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(?P<"),
    (GroupNameUnexpectedEof, sp(4, 4)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(a"),
    (GroupUnclosed, sp(0, 1)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(()"),
    (GroupUnclosed, sp(0, 1)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), ")"),
    (GroupUnopened, sp(0, 1)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "a)"),
    (GroupUnopened, sp(1, 2)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(?P<"),
    (GroupNameUnexpectedEof, sp(4, 4)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(?P<>z)"),
    (GroupNameEmpty, sp(4, 4)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(?P<a"),
    (GroupNameUnexpectedEof, sp(5, 5)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(?P<ab"),
    (GroupNameUnexpectedEof, sp(6, 6)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(?P<0a"),
    (GroupNameInvalid, sp(4, 5)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(?P<~"),
    (GroupNameInvalid, sp(4, 5)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(?P<abc~"),
    (GroupNameInvalid, sp(7, 8)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(?P<a>y)(?P<a>z)"),
    (GroupNameDuplicate(original=sp(4, 5)), sp(12, 13)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(?P<5>)"),
    (GroupNameInvalid, sp(4, 5)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "(?P<5a>)"),
    (GroupNameInvalid, sp(4, 5)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "\\b{ "),
    (RepetitionCountUnclosed, sp(2, 4)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "["),
    (ClassUnclosed, sp(0, 1)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "[["),
    (ClassUnclosed, sp(1, 2)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "[[-]"),
    (ClassUnclosed, sp(0, 1)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "[[[:alnum:]"),
    (ClassUnclosed, sp(1, 2)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "[\\b]"),
    (ClassEscapeInvalid, sp(1, 3)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "[\\w-a]"),
    (ClassRangeLiteral, sp(1, 3)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "[a-\\w]"),
    (ClassRangeLiteral, sp(3, 5)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "[z-a]"),
    (ClassRangeInvalid, sp(1, 4)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new().ignore_whitespace(true), "[a "),
    (ClassUnclosed, sp(0, 1)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new().ignore_whitespace(true), "[a- "),
    (ClassUnclosed, sp(0, 1)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "\\p\\{"),
    (UnicodeClassInvalid, sp(2, 3)),
  )
  assert_eq(
    parse_err(@ast.ParserBuilder::new(), "\\P\\{"),
    (UnicodeClassInvalid, sp(2, 3)),
  )
}

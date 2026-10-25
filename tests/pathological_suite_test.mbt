// Port of tree-sitter crates/cli/src/tests/pathological_test.rs (memory is
// garbage collected, so `allocations::record` is omitted).

///|
async test "pathological_example_1" {
  let language = "cpp"
  let source = "*ss<s\"ss<sqXqss<s._<s<sq<(qqX<sqss<s.ss<sqsssq<(qss<qssqXqss<s._<s<sq<(qqX<sqss<s.ss<sqsssq<(qss<sqss<sqss<s._<s<sq>(qqX<sqss<s.ss<sqsssq<(qss<sq&=ss<s<sqss<s._<s<sq<(qqX<sqss<s.ss<sqs"
  let parser = @treesitter.Parser::new()
  guard get_parsing_language(language) is Some(language) else { return }
  parser.set_language(language)
  ignore(parse(parser, source))
}

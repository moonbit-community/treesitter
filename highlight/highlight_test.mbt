///|
test "highlight events cover source and remain balanced" {
  let language = @arithmetic.language()
  let tree = @ts.Parser::new(language).parse_string("1 + 2")
  let config = @highlight.Configuration::new(
    language, "(number) @number\n\"+\" @operator",
  )
  assert_eq(
    config.html(tree),
    "<span class=\"number\">1</span> <span class=\"operator\">+</span> <span class=\"number\">2</span>",
  )
  let mut covered = 0
  let mut depth = 0
  for event in config.highlight(tree) {
    match event {
      Start(_) => depth += 1
      End => {
        depth -= 1
        assert_true(depth >= 0)
      }
      Source(start, end) => {
        assert_eq(start, covered)
        covered = end
      }
    }
  }
  assert_eq(covered, tree.source.length())
  assert_eq(depth, 0)
}

///|
test "highlight configuration resolves dotted names and earlier patterns" {
  let language = @arithmetic.language()
  let tree = @ts.Parser::new(language).parse_string("12")
  let config = @highlight.Configuration::new(
    language,
    "(number) @constant.numeric\n(number) @variable",
    names=["constant", "variable"],
  )
  assert_eq(config.html(tree), "<span class=\"constant\">12</span>")
}

///|
test "HTML escapes unhighlighted input and capture class names" {
  let language = @arithmetic.language()
  let tree = @ts.Parser::new(language).parse_string("<1")
  let config = @highlight.Configuration::new(language, "(number) @number")
  assert_eq(config.html(tree), "&lt;<span class=\"number\">1</span>")
}

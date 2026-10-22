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

///|
test "local references inherit definition highlights" {
  let language = @generate.generate(
    @grammar.Grammar::new("locals", [
      (
        "document",
        Seq([Symbol("binding"), Symbol("identifier"), Symbol("identifier")]),
      ),
      ("binding", Seq([Literal("let"), Symbol("identifier"), Literal(";")])),
      ("identifier", @grammar.pattern("[a-z]+")),
    ]),
  )
  let tree = @ts.Parser::new(language).parse_string("let x; x y")
  let config = @highlight.Configuration::new(
    language,
    "(binding (identifier) @variable.definition)\n((identifier) @constant (#is-not? local))\n(identifier) @variable",
    locals="(binding (identifier) @local.definition)\n(identifier) @local.reference",
  )
  assert_eq(
    config.html(tree),
    "let <span class=\"variable.definition\">x</span>; <span class=\"variable.definition\">x</span> <span class=\"constant\">y</span>",
  )
}

///|
test "injection content uses original ranges and clips combined captures" {
  let outer = @generate.generate(
    @grammar.Grammar::new("embedded", [
      ("document", Repeat(Symbol("embedded"))),
      ("embedded", Seq([Literal("`"), Symbol("content"), Literal("`")])),
      ("content", @grammar.pattern("[^`]+")),
    ]),
  )
  let inner = @highlight.Configuration::new(
    @arithmetic.language(),
    "(number) @number\n\"+\" @operator",
  )
  let config = @highlight.Configuration::new(
    outer,
    "",
    injections="((content) @injection.content (#set! injection.language arithmetic) (#set! injection.combined))",
  )
  let tree = @ts.Parser::new(outer).parse_string("`1 +` `2`")
  assert_eq(
    config.html(tree, injection=name => {
      if name == "arithmetic" {
        Some(inner)
      } else {
        None
      }
    }),
    "`<span class=\"number\">1</span> <span class=\"operator\">+</span>` `<span class=\"number\">2</span>`",
  )
}

///|
test "recognized highlight names match dotted components in any position" {
  let language = @arithmetic.language()
  let tree = @ts.Parser::new(language).parse_string("1")
  let config = @highlight.Configuration::new(
    language,
    "(number) @constant.numeric.builtin",
    names=["builtin", "constant.builtin"],
  )
  assert_eq(config.html(tree), "<span class=\"constant.builtin\">1</span>")
}

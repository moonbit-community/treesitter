// Tests ported from tree-sitter crates/generate/src/parse_grammar.rs, plus
// coverage of the serde-compatible decoding and `normalize`.

///|
test "parse_grammar" {
  let grammar = parse_grammar(
    (
      #|{
      #|  "name": "my_lang",
      #|  "rules": {
      #|    "file": {
      #|      "type": "REPEAT1",
      #|      "content": {
      #|        "type": "SYMBOL",
      #|        "name": "statement"
      #|      }
      #|    },
      #|    "statement": {
      #|      "type": "STRING",
      #|      "value": "foo"
      #|    }
      #|  }
      #|}
    ),
    [],
  )
  assert_eq(grammar.pool.resolve(grammar.name), "my_lang")
  let names = grammar.variables.map(v => grammar.pool.resolve(v.name))
  assert_eq(names, ["file", "statement"])

  // file = repeat(named_symbol "statement")
  guard grammar.pool.node(grammar.variables[0].root) is Repeat(inner) else {
    fail("Expected repeat")
  }
  guard grammar.pool.node(inner) is NamedSymbol(name) else {
    fail("Expected named symbol")
  }
  assert_eq(grammar.pool.resolve(name), "statement")

  // statement = string "foo"
  guard grammar.pool.node(grammar.variables[1].root) is String(value) else {
    fail("Expected string")
  }
  assert_eq(grammar.pool.resolve(value), "foo")
}

///|
fn parse_error(input : String) -> String {
  try parse_grammar(input, []) catch {
    e => e.to_string()
  } noraise {
    _ => "ok"
  }
}

///|
test "parse_grammar errors" {
  inspect(
    parse_error(
      (
        #|{"name": "x", "rules": {"a": {"type": "STRING", "value": ""}}, "extras": [{"type": "STRING", "value": ""}]}
      ),
    ),
    content="Rules in the `extras` array must not contain empty strings",
  )
  inspect(
    parse_error(
      (
        #|{"name": "x", "rules": {"a": {"type": "BLANK"}}, "precedences": [[{"type": "BLANK"}]]}
      ),
    ),
    content="Invalid rule in precedences array. Only strings and symbols are allowed",
  )
  inspect(
    parse_error(
      (
        #|{"name": "x", "rules": {"a": {"type": "BLANK"}}, "reserved": {"r": {}}}
      ),
    ),
    content="Reserved word sets must be arrays",
  )
  inspect(
    parse_error(
      (
        #|{"name": "x", "rules": {"a": {"type": "TOKEN", "content": {"type": "SYMBOL", "name": "b"}}}}
      ),
    ),
    content="Grammar Error: Unexpected rule `b` in `token()` call",
  )
  // serde's messages for rule bodies (read with `serde_json::from_value`)
  inspect(
    parse_error(
      (
        #|{"name": "x", "rules": {"a": {"type": "WHAT"}}}
      ),
    ),
    content="unknown variant `WHAT`, expected one of `ALIAS`, `BLANK`, `STRING`, `PATTERN`, `SYMBOL`, `CHOICE`, `FIELD`, `SEQ`, `REPEAT`, `REPEAT1`, `PREC_DYNAMIC`, `PREC_LEFT`, `PREC_RIGHT`, `PREC`, `TOKEN`, `IMMEDIATE_TOKEN`, `RESERVED`, `EOF`",
  )
  inspect(
    parse_error(
      (
        #|{"name": "x", "rules": {"a": {"type": "SEQ"}}}
      ),
    ),
    content="missing field `members`",
  )
  inspect(
    parse_error(
      (
        #|{"name": "x", "rules": {"a": {"value": "b"}}}
      ),
    ),
    content="missing field `type`",
  )
  inspect(
    parse_error(
      (
        #|{"name": "x", "rules": {"a": "b"}}
      ),
    ),
    content=(
      #|invalid type: string "b", expected internally tagged enum RuleJSON
    ),
  )
  inspect(
    parse_error(
      (
        #|{"name": "x", "rules": {"a": {"type": "PREC_DYNAMIC", "value": 1.5, "content": {"type": "BLANK"}}}}
      ),
    ),
    content="invalid type: floating point `1.5`, expected i32",
  )
  inspect(
    parse_error(
      (
        #|{"name": "x", "rules": {"a": {"type": "PREC_DYNAMIC", "value": 3000000000, "content": {"type": "BLANK"}}}}
      ),
    ),
    content="invalid value: integer `3000000000`, expected i32",
  )
  inspect(
    parse_error(
      (
        #|{"name": "x", "rules": {"a": {"type": "PREC", "value": true, "content": {"type": "BLANK"}}}}
      ),
    ),
    content="data did not match any variant of untagged enum PrecedenceValueJSON",
  )
  inspect(
    parse_error(
      (
        #|{"name": "x", "rules": {"a": {"type": "ALIAS", "named": 1, "value": "v", "content": {"type": "BLANK"}}}}
      ),
    ),
    content="invalid type: integer `1`, expected a boolean",
  )
  inspect(
    parse_error(
      (
        #|{"rules": {}}
      ),
    ),
    content=(
      #|missing field `name` at line 1 column 13
    ),
  )
  inspect(
    parse_error(
      (
        #|{"name": null, "rules": {}}
      ),
    ),
    content=(
      #|invalid type: null, expected a string at line 1 column 13
    ),
  )
}

///|
test "parse_grammar regex flags and interning order" {
  let diagnostics = []
  let grammar = parse_grammar(
    (
      #|{
      #|  "name": "flags",
      #|  "word": "id",
      #|  "rules": {
      #|    "source": {"type": "SEQ", "members": [
      #|      {"type": "SYMBOL", "name": "id"},
      #|      {"type": "FIELD", "name": "f", "content": {"type": "PATTERN", "value": "a+", "flags": "giu"}}
      #|    ]},
      #|    "id": {"type": "PREC", "value": "p", "content": {"type": "PATTERN", "value": "[a-z]+"}}
      #|  },
      #|  "precedences": [[{"type": "STRING", "value": "p"}]]
      #|}
    ),
    diagnostics,
  )
  assert_eq(diagnostics, [UnsupportedRegexFlag(flag='g', pattern="a+")])
  inspect(diagnostics[0], content="unsupported regex flag `g` in pattern `a+`")
  // Strings are interned in upstream's order: precedences, then each rule's
  // name followed by its body (content before the wrapper's own strings), the
  // word, and finally the grammar name.
  let strings = []
  for i in 0..<grammar.pool.str_pool.strings.length() {
    strings.push(grammar.pool.str_pool.strings[i])
  }
  assert_eq(strings, [
    "", "end", "p", "source", "id", "a+", "i", "f", "[a-z]+", "flags",
  ])
}

///|
test "parse_grammar normalize drops unused rules" {
  let grammar = parse_grammar(
    (
      #|{
      #|  "name": "n",
      #|  "rules": {
      #|    "a": {"type": "SYMBOL", "name": "b"},
      #|    "b": {"type": "STRING", "value": "b"},
      #|    "unused": {"type": "SYMBOL", "name": "c"},
      #|    "c": {"type": "STRING", "value": "c"},
      #|    "comment": {"type": "STRING", "value": "#"}
      #|  },
      #|  "extras": [{"type": "SYMBOL", "name": "comment"}],
      #|  "conflicts": [["a", "unused"], ["a", "b"]],
      #|  "inline": ["unused", "b"],
      #|  "supertypes": ["c"],
      #|  "precedences": [[{"type": "SYMBOL", "name": "c"}], [{"type": "STRING", "value": "x"}]]
      #|}
    ),
    [],
  )
  let pool = grammar.pool
  assert_eq(grammar.variables.map(v => pool.resolve(v.name)), [
    "a", "b", "comment",
  ])
  assert_eq(grammar.conflict_names.map(c => c.map(s => pool.resolve(s))), [
    ["a", "b"],
  ])
  assert_eq(grammar.inline_names.map(s => pool.resolve(s)), ["b"])
  inspect(grammar.supertype_names.length(), content="0")
  inspect(grammar.precedence_orderings.length(), content="1")
  inspect(grammar.extra_roots.length(), content="1")
}

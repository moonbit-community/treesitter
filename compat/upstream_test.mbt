// Ported from Tree-sitter 4a412a01a0147d0f50bf7e749572fa632d1ab203. See LICENSE.

///|
test "upstream associativity_left" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"associativity_left","rules":{"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"math_operation"},{"type":"SYMBOL","name":"identifier"}]},"math_operation":{"type":"PREC_LEFT","value":0,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"+"},{"type":"SYMBOL","name":"expression"}]}},"identifier":{"type":"PATTERN","value":"[a-z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "===================\nchained operations\n===================\nx+y+z\n---\n(expression (math_operation\n  (expression (math_operation (expression (identifier)) (expression (identifier))))\n  (expression (identifier))))"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="associativity_left: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream associativity_right" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"associativity_right","rules":{"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"math_operation"},{"type":"SYMBOL","name":"identifier"}]},"math_operation":{"type":"PREC_RIGHT","value":0,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"+"},{"type":"SYMBOL","name":"expression"}]}},"identifier":{"type":"PATTERN","value":"[a-z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "===================\nchained operations\n===================\nx+y+z\n---\n(expression (math_operation\n  (expression (identifier))\n  (expression (math_operation (expression (identifier)) (expression (identifier))))))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="associativity_right: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream aliases_in_root" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"aliases_in_root","rules":{"document":{"type":"SEQ","members":[{"type":"ALIAS","content":{"type":"SYMBOL","name":"foo"},"named":true,"value":"bar"},{"type":"SYMBOL","name":"foo"}]},"foo":{"type":"STRING","value":"foo"},"comment":{"type":"PATTERN","value":"#.*"}},"extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"comment"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "======================================\nAliases within the root node\n======================================\n\n# this is a comment\nfoo foo\n\n---\n\n(document\n  (comment)\n  (bar)\n  (foo))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="aliases_in_root: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream aliased_rules" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"aliased_rules","rules":{"statement":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"STRING","value":";"}]},"_expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"call_expression"},{"type":"SYMBOL","name":"member_expression"},{"type":"ALIAS","content":{"type":"SYMBOL","name":"identifier"},"named":true,"value":"variable_name"}]},"call_expression":{"type":"PREC_LEFT","value":0,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"STRING","value":"("},{"type":"SYMBOL","name":"_expression"},{"type":"STRING","value":")"}]}},"member_expression":{"type":"PREC_LEFT","value":1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"STRING","value":"."},{"type":"ALIAS","content":{"type":"SYMBOL","name":"identifier"},"named":true,"value":"property_name"}]}},"identifier":{"type":"PATTERN","value":"[a-z]+"},"star":{"type":"STRING","value":"*"},"unused":{"type":"ALIAS","content":{"type":"SYMBOL","name":"star"},"named":true,"value":"star_aliased"}},"extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"star"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "======================================\nMethod calls\n======================================\n\n*a.b(c(d.e));\n\n---\n\n(statement\n  (star)\n  (call_expression\n    (member_expression\n      (variable_name)\n      (property_name))\n    (call_expression\n      (variable_name)\n      (member_expression\n        (variable_name)\n        (property_name)))))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="aliased_rules: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream aliased_token_rules" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"aliased_token_rules","rules":{"expression":{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"ALIAS","content":{"type":"TOKEN","content":{"type":"SEQ","members":[{"type":"STRING","value":"b"},{"type":"STRING","value":"c"}]}},"named":true,"value":"X"},{"type":"ALIAS","content":{"type":"IMMEDIATE_TOKEN","content":{"type":"SEQ","members":[{"type":"STRING","value":"d"},{"type":"STRING","value":"e"}]}},"named":true,"value":"Y"}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "======================\nAliased token rules\n======================\n\nabcde\n\n---\n\n(expression (X) (Y))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="aliased_token_rules: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream dynamic_precedence" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"dynamic_precedence","rules":{"program":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"declaration"},{"type":"SYMBOL","name":"expression"}]},"expression":{"type":"CHOICE","members":[{"type":"PREC_LEFT","value":0,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"*"},{"type":"SYMBOL","name":"expression"}]}},{"type":"SYMBOL","name":"identifier"}]},"declaration":{"type":"SEQ","members":[{"type":"SYMBOL","name":"type"},{"type":"SYMBOL","name":"declarator"}]},"declarator":{"type":"CHOICE","members":[{"type":"PREC_DYNAMIC","value":1,"content":{"type":"SEQ","members":[{"type":"STRING","value":"*"},{"type":"SYMBOL","name":"identifier"}]}},{"type":"SYMBOL","name":"identifier"}]},"type":{"type":"SYMBOL","name":"identifier"},"identifier":{"type":"PATTERN","value":"[a-z-A-Z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[["expression","type"]],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "===============================\nDeclarations\n===============================\n\nT * x\n\n---\n\n(program (declaration\n  (type (identifier))\n  (declarator (identifier))))\n\n===============================\nExpressions\n===============================\n\nw * x * y\n\n---\n\n(program (expression\n  (expression\n    (expression (identifier))\n    (expression (identifier)))\n  (expression (identifier))))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="dynamic_precedence: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream field_on_hidden_rule" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"field_on_hidden_rule","rules":{"source_file":{"type":"REPEAT","content":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"binding"},{"type":"SYMBOL","name":"sum"},{"type":"SYMBOL","name":"call"}]}},"binding":{"type":"SEQ","members":[{"type":"STRING","value":"let"},{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"_binding"}},{"type":"STRING","value":";"}]},"_binding":{"type":"SEQ","members":[{"type":"FIELD","name":"inner","content":{"type":"SYMBOL","name":"name"}},{"type":"STRING","value":"="},{"type":"SYMBOL","name":"name"}]},"sum":{"type":"SEQ","members":[{"type":"STRING","value":"sum"},{"type":"SYMBOL","name":"_sum"},{"type":"STRING","value":";"}]},"_sum":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"name"},{"type":"SEQ","members":[{"type":"FIELD","name":"left","content":{"type":"SYMBOL","name":"_sum"}},{"type":"STRING","value":"+"},{"type":"SYMBOL","name":"name"}]}]},"call":{"type":"SEQ","members":[{"type":"STRING","value":"call"},{"type":"FIELD","name":"arg","content":{"type":"SYMBOL","name":"_call"}},{"type":"STRING","value":")"},{"type":"STRING","value":";"}]},"_call":{"type":"SEQ","members":[{"type":"STRING","value":"("},{"type":"FIELD","name":"arg","content":{"type":"SYMBOL","name":"name"}}]},"name":{"type":"PATTERN","value":"[a-z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "=============================================\nField on a hidden rule with a field inside it\n=============================================\n\nlet a = b;\n\n---\n\n(source_file\n  (binding\n    inner: (name)\n    outer: (name)))\n\n================================\nField on a recursive hidden rule\n================================\n\nsum a + b + c;\n\n---\n\n(source_file\n  (sum\n    left: (name)\n    left: (name)\n    (name)))\n\n=====================================================\nField on a hidden rule with the same field inside it\n=====================================================\n\ncall (a);\n\n---\n\n(source_file\n  (call\n    arg: (name)))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="field_on_hidden_rule: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream immediate_tokens" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"immediate_tokens","rules":{"program":{"type":"SYMBOL","name":"_expression"},"_expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"call"},{"type":"SYMBOL","name":"infix"},{"type":"SYMBOL","name":"prefix"},{"type":"SYMBOL","name":"identifier"}]},"call":{"type":"PREC_LEFT","value":-1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"SYMBOL","name":"_expression"}]}},"prefix":{"type":"SEQ","members":[{"type":"STRING","value":"::"},{"type":"SYMBOL","name":"identifier"}]},"infix":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"IMMEDIATE_TOKEN","content":{"type":"STRING","value":"::"}},{"type":"SYMBOL","name":"identifier"}]},"identifier":{"type":"PATTERN","value":"[a-z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "===============================\nprefix expressions as arguments\n===============================\n\na ::b ::c\n\n---\n\n(program\n  (call\n    (call\n      (identifier)\n      (prefix (identifier)))\n    (prefix (identifier))))\n\n===============================\ninfix expressions\n===============================\n\na::b::c\n\n---\n\n(program\n  (infix\n    (infix\n      (identifier)\n      (identifier))\n    (identifier)))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="immediate_tokens: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream inline_rules" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"inline_rules","rules":{"program":{"type":"REPEAT1","content":{"type":"SYMBOL","name":"statement"}},"statement":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":";"}]},"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"sum"},{"type":"SYMBOL","name":"product"},{"type":"SYMBOL","name":"number"},{"type":"SYMBOL","name":"parenthesized_expression"}]},"parenthesized_expression":{"type":"SEQ","members":[{"type":"STRING","value":"("},{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":")"}]},"sum":{"type":"PREC_LEFT","value":0,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"+"},{"type":"SYMBOL","name":"expression"}]}},"product":{"type":"PREC_LEFT","value":2,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"*"},{"type":"SYMBOL","name":"expression"}]}},"number":{"type":"PATTERN","value":"\\d+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":["expression"],"supertypes":[],"reserved":{}}
  let corpus = "==================================\nExpressions\n==================================\n\n1 + 2 * 3;\n4 * 5 + 6;\n7 * (8 + 9);\n\n---\n\n(program\n  (statement (sum\n    (number)\n    (product (number) (number))))\n  (statement (sum\n    (product (number) (number))\n    (number)))\n  (statement (product\n    (number)\n    (parenthesized_expression (sum (number) (number))))))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="inline_rules: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream start_rule_is_blank" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"start_rule_is_blank","rules":{"first_rule":{"type":"BLANK"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "========================\nthe empty string\n=======================\n\n---\n\n(first_rule)"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="start_rule_is_blank: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream start_rule_is_token" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"start_rule_is_token","rules":{"first_rule":{"type":"STRING","value":"the-value"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "===========================\nthe single token\n==========================\nthe-value\n---\n(first_rule)\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="start_rule_is_token: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream precedence_on_token" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"precedence_on_token","rules":{"program":{"type":"REPEAT","content":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"string"},{"type":"SYMBOL","name":"regex"},{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"slash"}]}},"comment":{"type":"TOKEN","content":{"type":"PREC","value":1,"content":{"type":"PATTERN","value":"\\/\\/.*|\\/\\*[^*]*\\*\\/"}}},"string":{"type":"SEQ","members":[{"type":"STRING","value":"\""},{"type":"REPEAT","content":{"type":"CHOICE","members":[{"type":"TOKEN","content":{"type":"PREC","value":2,"content":{"type":"PATTERN","value":"[^\\\"\\n\\\\]+"}}},{"type":"SYMBOL","name":"escape_sequence"}]}},{"type":"STRING","value":"\""}]},"escape_sequence":{"type":"PATTERN","value":"\\\\."},"regex":{"type":"PATTERN","value":"\\/[^\\/\\n]+\\/[a-z]*"},"identifier":{"type":"PATTERN","value":"[a-z]\\w*"},"slash":{"type":"STRING","value":"/"}},"extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"comment"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "==========================================\nobvious tokens\n==========================================\n\n// hi\n/* hi */\nhi\n/\n\"hi\"\n/hi/\n\n---\n\n(program\n  (comment)\n  (comment)\n  (identifier)\n  (slash)\n  (string)\n  (regex))\n\n==========================================\nstrings starting with double slashes\n==========================================\n\n/*\nThe lexer matches the string content correctly even though\na comment could match all the way until the end of the line,\nbecause the string content token has a higher precedence\nthan the comment token.\n*/\n\n\"//one\\n//two\"\n\n---\n\n(program\n  (comment)\n  (string (escape_sequence)))\n\n==========================================\ncomments that resemble regexes\n==========================================\n\n/*\nThe lexer matches this as a comment followed by an identifier\neven though a regex token could match the entire thing, because\nthe comment token has a higher precedence than the regex token\n*/\n\n/* hello */ui\n\n---\n\n(program\n  (comment)\n  (comment)\n  (identifier))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="precedence_on_token: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream anonymous_tokens_with_escaped_chars" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"anonymous_tokens_with_escaped_chars","rules":{"first_rule":{"type":"CHOICE","members":[{"type":"STRING","value":"\n"},{"type":"STRING","value":"\r\n"},{"type":"STRING","value":"'hello'"},{"type":"PATTERN","value":"\\d+"}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "================================================\nanonymous tokens defined with character classes\n================================================\n1234\n---\n\n(first_rule)\n\n=================================================\nanonymous tokens defined with LF escape sequence\n=================================================\n\n\n---\n\n(first_rule)\n\n=================================================\nanonymous tokens defined with CR escape sequence\n=================================================\n\r\n\n---\n\n(first_rule)\n\n================================================\nanonymous tokens with quotes\n================================================\n'hello'\n---\n\n(first_rule)\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="anonymous_tokens_with_escaped_chars: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream aliased_unit_reductions" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"aliased_unit_reductions","rules":{"statement":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_a"},{"type":"ALIAS","content":{"type":"SYMBOL","name":"_b"},"named":true,"value":"b_prime"},{"type":"ALIAS","content":{"type":"SYMBOL","name":"_c"},"named":true,"value":"c_prime"},{"type":"SYMBOL","name":"_c"},{"type":"STRING","value":";"}]},"_a":{"type":"SYMBOL","name":"_A"},"_b":{"type":"SYMBOL","name":"_B"},"_c":{"type":"SYMBOL","name":"_C"},"_A":{"type":"SYMBOL","name":"identifier"},"_B":{"type":"SYMBOL","name":"identifier"},"_C":{"type":"SYMBOL","name":"identifier"},"identifier":{"type":"PATTERN","value":"[a-z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "==========================================\nAliases on rules that are unit reductions\n==========================================\n\none two three four;\n\n---\n\n(statement\n  (identifier)\n  (b_prime (identifier))\n  (c_prime (identifier))\n  (identifier))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="aliased_unit_reductions: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

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

///|
test "upstream generation named_precedences" {
  // Upstream supplies no corpus expectations for this grammar.
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"named_precedences","rules":{"program":{"type":"REPEAT","content":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"expression_statement"},{"type":"SYMBOL","name":"declaration_statement"}]}},"expression_statement":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":";"}]},"declaration_statement":{"type":"SEQ","members":[{"type":"SYMBOL","name":"type"},{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":";"}]},"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"member_expression"},{"type":"SYMBOL","name":"binary_expression"},{"type":"SYMBOL","name":"identifier"}]},"member_expression":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"."},{"type":"SYMBOL","name":"identifier"}]},"binary_expression":{"type":"CHOICE","members":[{"type":"PREC_LEFT","value":"or","content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"||"},{"type":"SYMBOL","name":"expression"}]}},{"type":"PREC_LEFT","value":"and","content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"&&"},{"type":"SYMBOL","name":"expression"}]}}]},"type":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"nested_type"},{"type":"SYMBOL","name":"binary_type"},{"type":"SYMBOL","name":"identifier"}]},"nested_type":{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"STRING","value":"."},{"type":"SYMBOL","name":"identifier"}]},"binary_type":{"type":"CHOICE","members":[{"type":"PREC_LEFT","value":"type_union","content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"type"},{"type":"STRING","value":"||"},{"type":"SYMBOL","name":"type"}]}},{"type":"PREC_LEFT","value":"type_intersection","content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"type"},{"type":"STRING","value":"&&"},{"type":"SYMBOL","name":"type"}]}}]},"identifier":{"type":"PATTERN","value":"[a-z]\\w+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[["expression","type"],["expression","nested_type"]],"precedences":[[{"type":"SYMBOL","name":"member_expression"},{"type":"STRING","value":"and"},{"type":"STRING","value":"or"}],[{"type":"SYMBOL","name":"nested_type"},{"type":"STRING","value":"type_intersection"},{"type":"STRING","value":"type_union"}]],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  language.validate()
}

///|
test "upstream associativity_left_with_lower_precedence_shift" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"associativity_left_with_lower_precedence_shift","rules":{"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"addition"},{"type":"SYMBOL","name":"superaddition"},{"type":"SYMBOL","name":"number"}]},"addition":{"type":"PREC_LEFT","value":1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"+"},{"type":"SYMBOL","name":"expression"}]}},"superaddition":{"type":"PREC_RIGHT","value":0,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"+"},{"type":"STRING","value":"+"},{"type":"SYMBOL","name":"expression"}]}},"number":{"type":"STRING","value":"1"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "================================================================================\nAddition is left associative\n================================================================================\n\n1 + 1 + 1 + 1\n\n--------------------------------------------------------------------------------\n\n(expression\n  (addition\n    (expression\n      (addition\n        (expression\n          (addition\n            (expression\n              (number))\n            (expression\n              (number))))\n        (expression\n          (number))))\n    (expression\n      (number))))\n\n================================================================================\nSuperaddition still parses\n================================================================================\n\n1 + + 1\n\n--------------------------------------------------------------------------------\n\n(expression\n  (superaddition\n    (expression\n      (number))\n    (expression\n      (number))))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="associativity_left_with_lower_precedence_shift: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream associativity_right_with_lower_precedence_shift" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"associativity_right_with_lower_precedence_shift","rules":{"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"addition"},{"type":"SYMBOL","name":"superaddition"},{"type":"SYMBOL","name":"number"}]},"addition":{"type":"PREC_RIGHT","value":1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"+"},{"type":"SYMBOL","name":"expression"}]}},"superaddition":{"type":"PREC_RIGHT","value":0,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"+"},{"type":"STRING","value":"+"},{"type":"SYMBOL","name":"expression"}]}},"number":{"type":"STRING","value":"1"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "================================================================================\nAddition is right associative\n================================================================================\n\n1 + 1 + 1 + 1\n\n--------------------------------------------------------------------------------\n\n(expression\n  (addition\n    (expression\n      (number))\n    (expression\n      (addition\n        (expression\n          (number))\n        (expression\n          (addition\n            (expression\n              (number))\n            (expression\n              (number))))))))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="associativity_right_with_lower_precedence_shift: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream aliased_inlined_rules" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"aliased_inlined_rules","rules":{"statement":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"STRING","value":";"}]},"_expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"member_expression"},{"type":"ALIAS","content":{"type":"SYMBOL","name":"identifier"},"named":true,"value":"variable_name"}]},"member_expression":{"type":"PREC_LEFT","value":1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"STRING","value":"."},{"type":"ALIAS","content":{"type":"SYMBOL","name":"identifier"},"named":true,"value":"property_name"}]}},"identifier":{"type":"CHOICE","members":[{"type":"STRING","value":"a"},{"type":"STRING","value":"b"},{"type":"STRING","value":"c"}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":["identifier"],"supertypes":[],"reserved":{}}
  let corpus = "=========================\nOK\n=========================\n\na.b.c;\n\n---\n\n(statement\n  (member_expression\n    (member_expression\n      (variable_name)\n      (property_name))\n    (property_name)))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="aliased_inlined_rules: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream inlined_aliased_rules" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"inlined_aliased_rules","rules":{"statement":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":";"}]},"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"call_expression"},{"type":"SYMBOL","name":"member_expression"},{"type":"ALIAS","content":{"type":"SYMBOL","name":"identifier"},"named":true,"value":"variable_name"}]},"call_expression":{"type":"PREC_LEFT","value":0,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"("},{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":")"}]}},"member_expression":{"type":"PREC_LEFT","value":1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"."},{"type":"ALIAS","content":{"type":"SYMBOL","name":"identifier"},"named":true,"value":"property_name"}]}},"identifier":{"type":"PATTERN","value":"[a-z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":["expression"],"supertypes":[],"reserved":{}}
  let corpus = "======================================\nMethod calls\n======================================\n\na.b(c(d.e));\n\n---\n\n(statement\n  (call_expression\n    (member_expression\n      (variable_name)\n      (property_name))\n    (call_expression\n      (variable_name)\n      (member_expression\n        (variable_name)\n        (property_name)))))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="inlined_aliased_rules: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream nested_inlined_rules" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"nested_inlined_rules","rules":{"program":{"type":"REPEAT1","content":{"type":"SYMBOL","name":"top_level_item"}},"top_level_item":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"statement"},{"type":"STRING","value":"!"}]},"statement":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"expression_statement"},{"type":"SYMBOL","name":"return_statement"}]},"return_statement":{"type":"SEQ","members":[{"type":"STRING","value":"return"},{"type":"SYMBOL","name":"number"},{"type":"STRING","value":";"}]},"expression_statement":{"type":"SEQ","members":[{"type":"SYMBOL","name":"number"},{"type":"STRING","value":";"}]},"number":{"type":"PATTERN","value":"\\d+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":["top_level_item","statement"],"supertypes":[],"reserved":{}}
  let corpus = "==================================\nStatements\n==================================\n\nreturn 1;\nreturn 2;\n\n---\n\n(program\n  (return_statement (number))\n  (return_statement (number)))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="nested_inlined_rules: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream rejection precedence_on_single_child_missing" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"precedence_on_single_child_missing","rules":{"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"function_call"},{"type":"SYMBOL","name":"identifier"}]},"function_call":{"type":"PREC_RIGHT","value":0,"content":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"expression"}]},{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"block"}]},{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"expression"},{"type":"SYMBOL","name":"block"}]}]}},"block":{"type":"SEQ","members":[{"type":"STRING","value":"{"},{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"}"}]},"identifier":{"type":"PATTERN","value":"[a-zA-Z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let grammar = @grammar.Grammar::parse(grammar)
  try @generate.generate(grammar) catch {
    @generate.Conflict(_, _, _) => ()
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("accepted an upstream conflict fixture")
  }
}

///|
test "upstream precedence_on_single_child_negative" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"precedence_on_single_child_negative","rules":{"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"function_call"},{"type":"SYMBOL","name":"identifier"}]},"function_call":{"type":"PREC_RIGHT","value":-1,"content":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"expression"}]},{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"block"}]},{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"expression"},{"type":"SYMBOL","name":"block"}]}]}},"block":{"type":"SEQ","members":[{"type":"STRING","value":"{"},{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"}"}]},"identifier":{"type":"PATTERN","value":"[a-zA-Z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "===========================\nfunction calls with blocks\n===========================\n\nfoo bar { baz }\n\n---\n\n(expression (function_call\n  (identifier)\n  (expression (identifier))\n  (block (expression (identifier)))))"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="precedence_on_single_child_negative: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream precedence_on_single_child_positive" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"precedence_on_single_child_positive","rules":{"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"function_call"},{"type":"SYMBOL","name":"identifier"}]},"function_call":{"type":"PREC_RIGHT","value":1,"content":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"expression"}]},{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"block"}]},{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"expression"},{"type":"SYMBOL","name":"block"}]}]}},"block":{"type":"SEQ","members":[{"type":"STRING","value":"{"},{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"}"}]},"identifier":{"type":"PATTERN","value":"[a-zA-X]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "===========================\nfunction calls with blocks\n===========================\n\nfoo bar { baz }\n\n---\n\n(expression (function_call\n  (identifier)\n  (expression (function_call\n    (identifier)\n    (block (expression (identifier)))))))"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="precedence_on_single_child_positive: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream precedence_on_subsequence" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"precedence_on_subsequence","rules":{"expression":{"type":"PREC_LEFT","value":0,"content":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"function_call"},{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"scope_resolution"}]}},"function_call":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"expression"}]},{"type":"PREC","value":1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"block"}]}},{"type":"PREC","value":-1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"do_block"}]}},{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"PREC","value":1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"SYMBOL","name":"block"}]}}]},{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"PREC","value":-1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"SYMBOL","name":"do_block"}]}}]}]},"scope_resolution":{"type":"PREC_LEFT","value":1,"content":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"::"},{"type":"SYMBOL","name":"expression"}]},{"type":"SEQ","members":[{"type":"STRING","value":"::"},{"type":"SYMBOL","name":"expression"}]}]}},"block":{"type":"STRING","value":"{}"},"do_block":{"type":"STRING","value":"do end"},"identifier":{"type":"PATTERN","value":"[a-zA-Z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "==========================================\ncurly brace blocks with high precedence\n==========================================\n\na b {}\n\n---\n\n(expression (function_call\n  (identifier)\n  (expression (function_call (identifier) (block)))))\n\n==========================================\ndo blocks with low precedence\n==========================================\n\na b do end\n\n---\n\n(expression (function_call\n  (identifier)\n  (expression (identifier))\n  (do_block)))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="precedence_on_subsequence: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream unused_rules" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"unused_rules","rules":{"a":{"type":"SEQ","members":[{"type":"SYMBOL","name":"d"},{"type":"SYMBOL","name":"h"}]},"b":{"type":"STRING","value":"B"},"c":{"type":"STRING","value":"C"},"d":{"type":"SEQ","members":[{"type":"SYMBOL","name":"e"},{"type":"SYMBOL","name":"f"}]},"e":{"type":"STRING","value":"E"},"f":{"type":"STRING","value":"F"},"g":{"type":"STRING","value":"G"},"h":{"type":"SEQ","members":[{"type":"SYMBOL","name":"i"},{"type":"SYMBOL","name":"j"}]},"i":{"type":"STRING","value":"I"},"j":{"type":"STRING","value":"J"},"k":{"type":"STRING","value":"K"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "=========================\nthe language\n=========================\n\nE F I J\n\n---\n\n(a (d (e) (f)) (h (i) (j)))"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="unused_rules: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream lexical_conflicts_due_to_state_merging" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"lexical_conflicts_due_to_state_merging","rules":{"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"conditional"},{"type":"SYMBOL","name":"quotient"},{"type":"SYMBOL","name":"regex"},{"type":"SYMBOL","name":"number"},{"type":"SYMBOL","name":"parenthesized"}]},"conditional":{"type":"PREC_LEFT","value":1,"content":{"type":"SEQ","members":[{"type":"STRING","value":"if"},{"type":"SYMBOL","name":"parenthesized"},{"type":"SYMBOL","name":"expression"}]}},"quotient":{"type":"PREC_LEFT","value":0,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"/"},{"type":"SYMBOL","name":"expression"}]}},"regex":{"type":"PATTERN","value":"\\/[^/\\n]+\\/"},"number":{"type":"PATTERN","value":"\\d+"},"parenthesized":{"type":"SEQ","members":[{"type":"STRING","value":"("},{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":")"}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "========================\nregexes\n========================\n\n/a+/\n\n---\n\n(expression (regex))\n\n========================\nconditionals\n========================\n\n(if (1) /a+/)\n\n---\n\n(expression (parenthesized (expression (conditional\n  (parenthesized (expression (number)))\n  (expression (regex))))))\n\n========================\nquotients\n========================\n\n((1) / 2)\n\n---\n\n(expression (parenthesized (expression (quotient\n  (expression (parenthesized (expression (number))))\n  (expression (number))))))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="lexical_conflicts_due_to_state_merging: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream rejection terminal_supertype" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"terminal_supertype","rules":{"source_file":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"B"},{"type":"SYMBOL","name":"A"}]},"lineComment":{"type":"PATTERN","value":";;.*"},"lineComment2":{"type":"PATTERN","value":"##.*"},"A":{"type":"PATTERN","value":"xyz"},"C":{"type":"STRING","value":"xyz"},"B":{"type":"SEQ","members":[{"type":"STRING","value":"abc"},{"type":"SYMBOL","name":"C"}]}},"extras":[{"type":"SYMBOL","name":"lineComment"},{"type":"SYMBOL","name":"lineComment2"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":["A"],"reserved":{}}
  let grammar = @grammar.Grammar::parse(grammar)
  try @generate.generate(grammar) catch {
    @generate.InvalidGrammar(_) => ()
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("accepted an upstream conflict fixture")
  }
}

///|
test "upstream external_extra_tokens" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"external_extra_tokens","rules":{"assignment":{"type":"SEQ","members":[{"type":"SYMBOL","name":"variable"},{"type":"STRING","value":"="},{"type":"SYMBOL","name":"variable"}]},"variable":{"type":"PATTERN","value":"[a-z]+"}},"extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"comment"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"comment"}],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "========================\nextra external tokens\n========================\n\nx = # a comment\ny\n\n---\n\n(assignment (variable) (comment) (variable))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for
    result in @corpus.run(
      language,
      @corpus.parse(corpus),
      scanner=scanner_external_extra_tokens(),
    ) {
    assert_true(
      result.passed,
      msg="external_extra_tokens: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream epsilon_external_extra_tokens" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"epsilon_external_extra_tokens","rules":{"document":{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"STRING","value":"b"}]}},"extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"comment"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"comment"}],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "==========================\nA document\n==========================\n\na b\n\n---\n\n(document)\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for
    result in @corpus.run(
      language,
      @corpus.parse(corpus),
      scanner=scanner_epsilon_external_extra_tokens(),
    ) {
    assert_true(
      result.passed,
      msg="epsilon_external_extra_tokens: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream external_unicode_column_alignment" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"external_unicode_column_alignment","rules":{"expression":{"type":"REPEAT","content":{"type":"SYMBOL","name":"list"}},"list":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_start_list"},{"type":"REPEAT1","content":{"type":"SYMBOL","name":"list_item"}},{"type":"SYMBOL","name":"_end_list"}]}},"extras":[{"type":"PATTERN","value":"\\s"},{"type":"STRING","value":"□"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"_start_list"},{"type":"SYMBOL","name":"list_item"},{"type":"SYMBOL","name":"_end_list"}],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "========================\nSingle list, no boxes\n========================\n\n-\n-\n-\n\n----------------------\n\n(expression\n  (list\n    (list_item)\n    (list_item)\n    (list_item)\n  )\n)\n\n========================\nTwo lists, no boxes\n========================\n\n -\n -\n -\n  -\n  -\n\n----------------------\n\n(expression\n  (list\n    (list_item)\n    (list_item)\n    (list_item)\n  )\n  (list\n    (list_item)\n    (list_item)\n  )\n)\n\n========================\nList with boxes\n========================\n\n -\n□-\n -\n\n----------------------\n\n(expression\n  (list\n    (list_item)\n    (list_item)\n    (list_item)\n  )\n)\n\n========================\nMultiple lists with boxes\n========================\n\n   -\n□ □-\n □ -\n□□□□□□-\n□ □ □ -\n      -\n□□□   -\n□□□-\n□ □-\n\n----------------------\n\n(expression\n  (list\n    (list_item)\n    (list_item)\n    (list_item)\n  )\n  (list\n    (list_item)\n    (list_item)\n    (list_item)\n    (list_item)\n  )\n  (list\n    (list_item)\n    (list_item)\n  )\n)\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for
    result in @corpus.run(
      language,
      @corpus.parse(corpus),
      scanner=scanner_external_unicode_column_alignment(),
    ) {
    assert_true(
      result.passed,
      msg="external_unicode_column_alignment: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream epsilon_external_tokens" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"epsilon_external_tokens","rules":{"document":{"type":"SEQ","members":[{"type":"SYMBOL","name":"zero_width"},{"type":"STRING","value":"hello"}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"zero_width"}],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "==========================\nA leading zero-width token\n==========================\n\nhello\n\n---\n\n(document (zero_width))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for
    result in @corpus.run(
      language,
      @corpus.parse(corpus),
      scanner=scanner_epsilon_external_tokens(),
    ) {
    assert_true(
      result.passed,
      msg="epsilon_external_tokens: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream external_and_internal_anonymous_tokens" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"external_and_internal_anonymous_tokens","rules":{"statement":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"SYMBOL","name":"_expression"},{"type":"STRING","value":"\n"}]},"_expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"string"},{"type":"SYMBOL","name":"variable"},{"type":"SYMBOL","name":"number"}]},"variable":{"type":"PATTERN","value":"[a-z]+"},"number":{"type":"PATTERN","value":"\\d+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"string"},{"type":"STRING","value":"\n"}],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "=========================================\nsingle-line statements - internal tokens\n=========================================\n\na b\n\n---\n\n(statement (variable) (variable))\n\n=========================================\nmulti-line statements - internal tokens\n=========================================\n\na\nb\n\n---\n\n(statement (variable) (variable))\n\n=========================================\nsingle-line statements - external tokens\n=========================================\n\n'hello' 'world'\n\n---\n\n(statement (string) (string))\n\n=========================================\nmulti-line statements - external tokens\n=========================================\n\n'hello'\n'world'\n\n---\n\n(statement (string) (string))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for
    result in @corpus.run(
      language,
      @corpus.parse(corpus),
      scanner=scanner_external_and_internal_anonymous_tokens(),
    ) {
    assert_true(
      result.passed,
      msg="external_and_internal_anonymous_tokens: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream extra_non_terminals" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"extra_non_terminals","rules":{"module":{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"STRING","value":"b"},{"type":"STRING","value":"c"},{"type":"STRING","value":"d"}]},"comment":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"paren_comment"},{"type":"SYMBOL","name":"line_comment"}]},"paren_comment":{"type":"TOKEN","content":{"type":"SEQ","members":[{"type":"STRING","value":"("},{"type":"REPEAT","content":{"type":"PATTERN","value":"[a-z]+"}},{"type":"STRING","value":")"}]}},"line_comment":{"type":"TOKEN","content":{"type":"SEQ","members":[{"type":"STRING","value":"//"},{"type":"PATTERN","value":".*"}]}}},"extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"comment"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "==============\nNo extras\n==============\n\na b c d\n\n---\n\n(module)\n\n==============\nExtras\n==============\n\na (one) b (two) (three) c d // e\n\n---\n\n(module\n  (comment (paren_comment))\n  (comment (paren_comment))\n  (comment (paren_comment))\n  (comment (line_comment)))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="extra_non_terminals: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream extra_non_terminals_with_shared_rules" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"extra_non_terminals_with_shared_rules","rules":{"program":{"type":"REPEAT","content":{"type":"SYMBOL","name":"statement"}},"statement":{"type":"SEQ","members":[{"type":"REPEAT","content":{"type":"SYMBOL","name":"label_declaration"}},{"type":"STRING","value":";"}]},"macro_statement":{"type":"SEQ","members":[{"type":"STRING","value":"%"},{"type":"SYMBOL","name":"statement"}]},"label_declaration":{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"STRING","value":":"}]},"identifier":{"type":"PATTERN","value":"[a-zA-Z]+"}},"extras":[{"type":"PATTERN","value":"\\s+"},{"type":"SYMBOL","name":"macro_statement"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "=====\nExtras\n=====\n\n;\n%;\n%foo:;\n;\nbar: baz:;\n;\n\n---\n\n(program\n  (statement)\n  (macro_statement (statement))\n  (macro_statement (statement\n    (label_declaration (identifier))))\n  (statement)\n  (statement\n    (label_declaration (identifier))\n    (label_declaration (identifier)))\n  (statement))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="extra_non_terminals_with_shared_rules: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream field_lookup_through_hidden_nodes" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"field_lookup_through_hidden_nodes","rules":{"source_file":{"type":"REPEAT","content":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"list"},{"type":"SYMBOL","name":"binding"},{"type":"SYMBOL","name":"shadow"},{"type":"SYMBOL","name":"sum"},{"type":"SYMBOL","name":"aliased"},{"type":"SYMBOL","name":"alias_pair"},{"type":"SYMBOL","name":"multi"},{"type":"SYMBOL","name":"restored"},{"type":"SYMBOL","name":"back"},{"type":"SYMBOL","name":"maybe"},{"type":"SYMBOL","name":"order"},{"type":"SYMBOL","name":"skip"}]}},"list":{"type":"SEQ","members":[{"type":"STRING","value":"["},{"type":"CHOICE","members":[{"type":"SYMBOL","name":"_items"},{"type":"BLANK"}]},{"type":"STRING","value":"]"}]},"_items":{"type":"SEQ","members":[{"type":"SYMBOL","name":"item"},{"type":"REPEAT","content":{"type":"SEQ","members":[{"type":"STRING","value":","},{"type":"SYMBOL","name":"item"}]}}]},"item":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"name"},{"type":"FIELD","name":"spread","content":{"type":"SYMBOL","name":"spread"}}]},"spread":{"type":"SEQ","members":[{"type":"STRING","value":"..."},{"type":"SYMBOL","name":"name"}]},"aliased":{"type":"SEQ","members":[{"type":"STRING","value":"alias"},{"type":"ALIAS","content":{"type":"SYMBOL","name":"item"},"named":true,"value":"wrapped"},{"type":"STRING","value":";"}]},"alias_pair":{"type":"SEQ","members":[{"type":"STRING","value":"pair"},{"type":"ALIAS","content":{"type":"SYMBOL","name":"item"},"named":true,"value":"wrapped"},{"type":"STRING","value":","},{"type":"SYMBOL","name":"item"},{"type":"STRING","value":";"}]},"multi":{"type":"SEQ","members":[{"type":"STRING","value":"multi"},{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"_shadowed"}},{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"_binding"}},{"type":"STRING","value":";"}]},"binding":{"type":"SEQ","members":[{"type":"STRING","value":"let"},{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"_binding"}},{"type":"STRING","value":";"}]},"_binding":{"type":"SEQ","members":[{"type":"FIELD","name":"inner","content":{"type":"SYMBOL","name":"name"}},{"type":"STRING","value":"="},{"type":"SYMBOL","name":"name"}]},"shadow":{"type":"SEQ","members":[{"type":"STRING","value":"shadow"},{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"_shadowed"}},{"type":"STRING","value":";"}]},"_shadowed":{"type":"FIELD","name":"inner","content":{"type":"SYMBOL","name":"name"}},"restored":{"type":"SEQ","members":[{"type":"STRING","value":"restore"},{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"_restore"}},{"type":"STRING","value":";"}]},"_restore":{"type":"FIELD","name":"inner","content":{"type":"SYMBOL","name":"_restored"}},"_restored":{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"name"}},"back":{"type":"SEQ","members":[{"type":"STRING","value":"back"},{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"_back"}},{"type":"STRING","value":";"}]},"_back":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_shadowed"},{"type":"SYMBOL","name":"name"}]},"maybe":{"type":"SEQ","members":[{"type":"STRING","value":"maybe"},{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"_maybe"}},{"type":"STRING","value":";"}]},"_maybe":{"type":"FIELD","name":"inner","content":{"type":"SYMBOL","name":"_maybe_inner"}},"_maybe_inner":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_opt"},{"type":"STRING","value":"end"}]},"_opt":{"type":"CHOICE","members":[{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"name"}},{"type":"STRING","value":"none"}]},"order":{"type":"SEQ","members":[{"type":"STRING","value":"order"},{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"_order"}},{"type":"STRING","value":";"}]},"_order":{"type":"SEQ","members":[{"type":"FIELD","name":"zeta","content":{"type":"SYMBOL","name":"name"}},{"type":"FIELD","name":"alpha","content":{"type":"SYMBOL","name":"name"}},{"type":"SYMBOL","name":"name"}]},"skip":{"type":"SEQ","members":[{"type":"STRING","value":"skip"},{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"_skip"}},{"type":"STRING","value":";"}]},"_skip":{"type":"SEQ","members":[{"type":"FIELD","name":"inner","content":{"type":"SYMBOL","name":"_shadowed"}},{"type":"FIELD","name":"other","content":{"type":"SYMBOL","name":"name"}},{"type":"SYMBOL","name":"name"}]},"sum":{"type":"SEQ","members":[{"type":"STRING","value":"sum"},{"type":"SYMBOL","name":"_sum"},{"type":"STRING","value":";"}]},"_sum":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"name"},{"type":"SEQ","members":[{"type":"FIELD","name":"left","content":{"type":"SYMBOL","name":"_sum"}},{"type":"STRING","value":"+"},{"type":"SYMBOL","name":"name"}]}]},"name":{"type":"PATTERN","value":"[a-z0-9]+"},"comment":{"type":"TOKEN","content":{"type":"SEQ","members":[{"type":"STRING","value":"//"},{"type":"PATTERN","value":".*"}]}},"_note":{"type":"SEQ","members":[{"type":"STRING","value":"@"},{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"name"}}]},"_tag":{"type":"SEQ","members":[{"type":"STRING","value":"#"},{"type":"SYMBOL","name":"name"}]}},"extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"comment"},{"type":"SYMBOL","name":"_note"},{"type":"SYMBOL","name":"_tag"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":["item"],"reserved":{}}
  let corpus = "===============================================\nField inside a supertype, below a hidden rule\n===============================================\n\n[a, ...b]\n\n---\n\n(source_file\n  (list\n    (name)\n    spread: (spread\n      (name))))\n\n=============================================\nField on a hidden rule with a field inside it\n=============================================\n\nlet a = b;\n\n---\n\n(source_file\n  (binding\n    inner: (name)\n    outer: (name)))\n\n==================================================\nField on a hidden rule whose only node has a field\n==================================================\n\nshadow a;\n\n---\n\n(source_file\n  (shadow\n    inner: (name)))\n\n================================\nA visible alias keeps its fields\n================================\n\npair ...a, ...b;\n\n---\n\n(source_file\n  (alias_pair\n    (wrapped\n      spread: (spread (name)))\n    spread: (spread (name))))\n\n===========================================\nA comment inside a hidden rule with a field\n===========================================\n\nlet a // c\n= b;\n\n---\n\n(source_file\n  (binding\n    inner: (name)\n    (comment)\n    outer: (name)))\n\n==================================\nThe same field on two hidden rules\n==================================\n\nmulti a a = b;\n\n---\n\n(source_file\n  (multi\n    inner: (name)\n    inner: (name)\n    outer: (name)))\n\n============================================\nA field inside a field inside the same field\n============================================\n\nrestore a;\n\n---\n\n(source_file\n  (restored\n    outer: (name)))\n\n==================================================\nA field that reaches past a hidden rule without it\n==================================================\n\nback a b;\n\n---\n\n(source_file\n  (back\n    inner: (name)\n    outer: (name)))\n\n==================================================\nA hidden rule that can hold the field, but doesn't\n==================================================\n\nmaybe none end;\nmaybe a end;\n\n---\n\n(source_file\n  (maybe)\n  (maybe\n    outer: (name)))\n\n================================\nField on a recursive hidden rule\n================================\n\nsum a + b + c;\n\n---\n\n(source_file\n  (sum\n    left: (name)\n    left: (name)\n    (name)))\n\n=====================================\nA hidden extra with a field inside it\n=====================================\n\nlet a @x = b;\n\n---\n\n(source_file\n  (binding\n    inner: (name)\n    outer: (name)\n    outer: (name)))\n\n========================================\nA hidden extra without a field inside it\n========================================\n\nlet a #y = b;\n\n---\n\n(source_file\n  (binding\n    inner: (name)\n    (name)\n    outer: (name)))\n\n=====================================================\nFields out of alphabetical order inside a hidden rule\n=====================================================\n\norder a b c;\n\n---\n\n(source_file\n  (order\n    zeta: (name)\n    alpha: (name)\n    outer: (name)))\n\n============================================\nA field past a hidden child in another field\n============================================\n\nskip a b c;\n\n---\n\n(source_file\n  (skip\n    inner: (name)\n    other: (name)\n    outer: (name)))\n\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="field_lookup_through_hidden_nodes: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream anonymous_error" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"anonymous_error","rules":{"document":{"type":"REPEAT","content":{"type":"CHOICE","members":[{"type":"STRING","value":"ok"},{"type":"STRING","value":"ERROR"}]}}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "======================\nA simple error literal\n======================\n\nERROR\n\n---\n\n(document)\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="anonymous_error: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream duplicate_reduction_precedence" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"duplicate_reduction_precedence","rules":{"start":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"a"},{"type":"SYMBOL","name":"c"}]},"a":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"x"},{"type":"PREC","value":2,"content":{"type":"SYMBOL","name":"x"}}]},"c":{"type":"SYMBOL","name":"x"},"x":{"type":"STRING","value":"x"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "======================\nhigher precedence wins\n======================\n\nx\n---\n\n(start\n  (a\n    (x)))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="duplicate_reduction_precedence: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream eof_basic" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"eof_basic","rules":{"source_file":{"type":"REPEAT","content":{"type":"SYMBOL","name":"line"}},"line":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"STRING","value":"text"},{"type":"STRING","value":"\n"}]},{"type":"SEQ","members":[{"type":"STRING","value":"text"},{"type":"EOF"}]}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "============\ntrailing newline\n============\n\ntext\ntext\n\n---\n\n(source_file\n  (line)\n  (line))\n\n============\nno trailing newline\n============\n\ntext\ntext\n---\n\n(source_file\n  (line)\n  (line))\n\n============\nsingle line, no newline\n============\n\ntext\n---\n\n(source_file\n  (line))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="eof_basic: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream eof_dropped_branch" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"eof_dropped_branch","rules":{"source_file":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"STRING","value":"("},{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"SYMBOL","name":"item"},{"type":"REPEAT","content":{"type":"SEQ","members":[{"type":"CHOICE","members":[{"type":"STRING","value":"\n"},{"type":"STRING","value":";"},{"type":"EOF"}]},{"type":"SYMBOL","name":"item"}]}},{"type":"CHOICE","members":[{"type":"CHOICE","members":[{"type":"STRING","value":"\n"},{"type":"STRING","value":";"},{"type":"EOF"}]},{"type":"BLANK"}]}]},{"type":"BLANK"}]},{"type":"STRING","value":")"}]},{"type":"SYMBOL","name":"inline_test"}]},"item":{"type":"STRING","value":"x"},"inline_test":{"type":"CHOICE","members":[{"type":"STRING","value":"ok"},{"type":"SEQ","members":[{"type":"SYMBOL","name":"_inline_eof"},{"type":"STRING","value":"bad"}]}]},"_inline_eof":{"type":"EOF"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":["_inline_eof"],"supertypes":[],"reserved":{}}
  let corpus = "============\nno items\n============\n\n()\n---\n\n(source_file)\n\n============\nitems separated by newlines\n============\n\n(x\nx\nx)\n---\n\n(source_file (item) (item) (item))\n\n============\nitems separated by semicolons\n============\n\n(x;x;x)\n---\n\n(source_file (item) (item) (item))\n\n============\ntrailing separator\n============\n\n(x;)\n---\n\n(source_file (item))\n\n============\neof in an inline before a later symbol is unreachable\n============\n\nok\n---\n\n(source_file (inline_test))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="eof_dropped_branch: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream eof_duplicate_reduction" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"eof_duplicate_reduction","rules":{"source_file":{"type":"REPEAT","content":{"type":"SYMBOL","name":"line"}},"line":{"type":"CHOICE","members":[{"type":"STRING","value":"text"},{"type":"SEQ","members":[{"type":"STRING","value":"text"},{"type":"EOF"}]}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "===========================\nsingle line at end of input\n===========================\n\ntext\n---\n\n(source_file\n  (line))\n\n=============\nseveral lines\n=============\n\ntexttext\n---\n\n(source_file\n  (line)\n  (line))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="eof_duplicate_reduction: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream rejection eof_misplaced" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"eof_misplaced","rules":{"source_file":{"type":"SEQ","members":[{"type":"EOF"},{"type":"STRING","value":"after"}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let grammar = @grammar.Grammar::parse(grammar)
  try @generate.generate(grammar) catch {
    @generate.InvalidGrammar(_) => ()
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("accepted an upstream conflict fixture")
  }
}

///|
test "upstream rejection invisible_start_rule" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"invisible_start_rule","rules":{"_value":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"a"},{"type":"SYMBOL","name":"b"}]},"a":{"type":"STRING","value":"a"},"b":{"type":"STRING","value":"b"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let grammar = @grammar.Grammar::parse(grammar)
  try @generate.generate(grammar) catch {
    @generate.InvalidGrammar(_) => ()
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("accepted an upstream conflict fixture")
  }
}

///|
test "upstream last_child_anchor_past_hidden_repeat" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"last_child_anchor_past_hidden_repeat","rules":{"source_file":{"type":"REPEAT","content":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"trailing_sep"},{"type":"SYMBOL","name":"leading_sep"},{"type":"SYMBOL","name":"trailing_named"}]}},"trailing_sep":{"type":"SEQ","members":[{"type":"STRING","value":"T"},{"type":"REPEAT","content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"name"},{"type":"STRING","value":"."}]}},{"type":"SYMBOL","name":"name"}]},"leading_sep":{"type":"SEQ","members":[{"type":"STRING","value":"L"},{"type":"SYMBOL","name":"name"},{"type":"REPEAT","content":{"type":"SEQ","members":[{"type":"STRING","value":"."},{"type":"SYMBOL","name":"name"}]}}]},"trailing_named":{"type":"SEQ","members":[{"type":"STRING","value":"N"},{"type":"REPEAT","content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"name"},{"type":"SYMBOL","name":"tag"},{"type":"STRING","value":"."}]}},{"type":"SYMBOL","name":"name"}]},"tag":{"type":"STRING","value":"!"},"name":{"type":"PATTERN","value":"[a-z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "=========================================\nRepeat ending with an anonymous separator\n=========================================\n\nT a.b.c\n\n---\n\n(source_file\n  (trailing_sep\n    (name)\n    (name)\n    (name)))\n\n===============================\nRepeat ending with a named node\n===============================\n\nL a.b.c\n\n---\n\n(source_file\n  (leading_sep\n    (name)\n    (name)\n    (name)))\n\n============================================================\nRepeat ending with an anonymous separator, preceded by a tag\n============================================================\n\nN a!.b!.c\n\n---\n\n(source_file\n  (trailing_named\n    (name)\n    (tag)\n    (name)\n    (tag)\n    (name)))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="last_child_anchor_past_hidden_repeat: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream named_rule_aliased_as_anonymous" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"named_rule_aliased_as_anonymous","rules":{"a":{"type":"SEQ","members":[{"type":"ALIAS","content":{"type":"SYMBOL","name":"b"},"named":false,"value":"the-alias"},{"type":"SYMBOL","name":"c"},{"type":"SYMBOL","name":"b"}]},"b":{"type":"STRING","value":"B"},"c":{"type":"STRING","value":"C"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "================================================\nNamed rules that are aliased as anonymous tokens\n================================================\n\nB C B\n\n---\n\n(a (c) (b))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="named_rule_aliased_as_anonymous: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream next_sibling_from_zwt" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"next_sibling_from_zwt","rules":{"source":{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"SYMBOL","name":"_bc"},{"type":"STRING","value":"d"},{"type":"STRING","value":"e"},{"type":"STRING","value":"f"}]},"_bc":{"type":"SEQ","members":[{"type":"STRING","value":"b"},{"type":"STRING","value":"c"}]}},"extras":[{"type":"PATTERN","value":"\\s|\\\\\\r?\\n"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "===========================\nmissing c node\n===========================\n\nabdef\n\n---\n\n(source\n    (MISSING \"c\"))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="next_sibling_from_zwt: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream readme_grammar" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"readme_grammar","rules":{"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"sum"},{"type":"SYMBOL","name":"product"},{"type":"SYMBOL","name":"number"},{"type":"SYMBOL","name":"variable"},{"type":"SEQ","members":[{"type":"STRING","value":"("},{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":")"}]}]},"sum":{"type":"PREC_LEFT","value":1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"+"},{"type":"SYMBOL","name":"expression"}]}},"product":{"type":"PREC_LEFT","value":2,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"*"},{"type":"SYMBOL","name":"expression"}]}},"number":{"type":"PATTERN","value":"\\d+"},"comment":{"type":"PATTERN","value":"#.*"},"variable":{"type":"PATTERN","value":"(?i:[a-z])\\w*"}},"extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"comment"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "==================================\nthe readme example\n==================================\n\na + b * c\n\n---\n\n(expression (sum\n  (expression (variable))\n  (expression (product\n     (expression (variable))\n     (expression (variable))))))"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="readme_grammar: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream unicode_classes" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"unicode_classes","rules":{"program":{"type":"REPEAT","content":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"lower"},{"type":"SYMBOL","name":"upper"},{"type":"SYMBOL","name":"math_sym"},{"type":"SYMBOL","name":"letter_number"}]}},"lower":{"type":"PATTERN","value":"\\p{Ll}\\p{L}*"},"upper":{"type":"PATTERN","value":"\\p{Lu}\\p{L}*"},"math_sym":{"type":"PATTERN","value":"\\p{Sm}+"},"letter_number":{"type":"PATTERN","value":"\\p{Letter_Number}"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "===============\nUppercase words\n===============\n\nΔბㄱ  Ψ  Ɓƀ  Ƒ  Ɣ  Śřř\n\n---\n\n(program\n  (upper) (upper) (upper) (upper) (upper) (upper))\n\n================\nLowercase words\n================\n\nśś  ťť  ßß\n\n---\n\n(program\n  (lower) (lower) (lower))\n\n================\nMath symbols\n================\n\n≺ ≼ ≠ ≝ ⨔∑\n\n---\n\n(program\n  (math_sym) (math_sym) (math_sym) (math_sym) (math_sym))\n\n================================\nLetterlike numeric characters\n================================\n\nᛯ Ⅵ 〩\n\n---\n\n(program\n  (letter_number) (letter_number) (letter_number))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for result in @corpus.run(language, @corpus.parse(corpus)) {
    assert_true(
      result.passed,
      msg="unicode_classes: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream depends_on_column" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"depends_on_column","rules":{"x_is_at":{"type":"SEQ","members":[{"type":"PATTERN","value":"[ \\r\\n]*"},{"type":"CHOICE","members":[{"type":"SYMBOL","name":"odd_column"},{"type":"SYMBOL","name":"even_column"}]},{"type":"STRING","value":"x"}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"odd_column"},{"type":"SYMBOL","name":"even_column"}],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "==================\nX is at odd column\n==================\n\n x\n\n---\n\n(x_is_at\n  (odd_column))\n\n===================\nX is at even column\n===================\n\n  x\n\n---\n\n(x_is_at\n  (even_column))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for
    result in @corpus.run(
      language,
      @corpus.parse(corpus),
      scanner=scanner_depends_on_column(),
    ) {
    assert_true(
      result.passed,
      msg="depends_on_column: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream depends_on_column_failed_scan" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"depends_on_column_failed_scan","rules":{"document":{"type":"REPEAT","content":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"head"},{"type":"SYMBOL","name":"tail"},{"type":"SYMBOL","name":"letter"},{"type":"SYMBOL","name":"newline"}]}},"tail":{"type":"STRING","value":"x"},"letter":{"type":"STRING","value":"a"},"newline":{"type":"STRING","value":"\n"}},"extras":[],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"head"}],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "========================================\nColumn-dependent failed external scan\n========================================\n\nax\nx\n\n---\n\n(document (newline) (letter) (tail) (newline) (head) (newline))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for
    result in @corpus.run(
      language,
      @corpus.parse(corpus),
      scanner=scanner_depends_on_column_failed_scan(),
    ) {
    assert_true(
      result.passed,
      msg="depends_on_column_failed_scan: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream depends_on_column_repetition" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"depends_on_column_repetition","rules":{"document":{"type":"REPEAT","content":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"head"},{"type":"SYMBOL","name":"tail"},{"type":"SYMBOL","name":"word"},{"type":"SYMBOL","name":"newline"}]}},"word":{"type":"PATTERN","value":"[a-w]+"},"newline":{"type":"STRING","value":"\n"}},"extras":[],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"head"},{"type":"SYMBOL","name":"tail"}],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "===========================\nColumn-dependent repetition\n===========================\n\nax\nx\n\n---\n\n(document (newline) (word) (tail) (newline) (head) (newline))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for
    result in @corpus.run(
      language,
      @corpus.parse(corpus),
      scanner=scanner_depends_on_column_repetition(),
    ) {
    assert_true(
      result.passed,
      msg="depends_on_column_repetition: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream external_word_token" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"external_word_token","word":"identifier","rules":{"program":{"type":"REPEAT","content":{"type":"SYMBOL","name":"_item"}},"label_name":{"type":"PATTERN","value":"[a-z]+"},"_item":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"let_statement"},{"type":"SYMBOL","name":"label"}]},"let_statement":{"type":"SEQ","members":[{"type":"STRING","value":"let"},{"type":"SYMBOL","name":"identifier"},{"type":"STRING","value":"="},{"type":"SYMBOL","name":"identifier"},{"type":"STRING","value":";"}]},"label":{"type":"SEQ","members":[{"type":"STRING","value":"@"},{"type":"SYMBOL","name":"label_name"}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"identifier"}],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "================================================================================\nKeywords with an external word token\n================================================================================\n\nlet a = b;\n@ here\nlet c = d;\n\n--------------------------------------------------------------------------------\n\n(program\n  (let_statement\n    (identifier)\n    (identifier))\n  (label\n    (label_name))\n  (let_statement\n    (identifier)\n    (identifier)))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for
    result in @corpus.run(
      language,
      @corpus.parse(corpus),
      scanner=scanner_external_word_token(),
    ) {
    assert_true(
      result.passed,
      msg="external_word_token: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

///|
test "upstream external_and_internal_tokens" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"external_and_internal_tokens","rules":{"statement":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"SYMBOL","name":"_expression"},{"type":"SYMBOL","name":"line_break"}]},"_expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"string"},{"type":"SYMBOL","name":"variable"},{"type":"SYMBOL","name":"number"}]},"variable":{"type":"PATTERN","value":"[a-z]+"},"number":{"type":"PATTERN","value":"\\d+"},"line_break":{"type":"STRING","value":"\n"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"string"},{"type":"SYMBOL","name":"line_break"}],"inline":[],"supertypes":[],"reserved":{}}
  let corpus = "=========================================\nsingle-line statements - internal tokens\n=========================================\n\na b\n\n---\n\n(statement (variable) (variable) (line_break))\n\n=========================================\nmulti-line statements - internal tokens\n=========================================\n\na\nb\n\n---\n\n(statement (variable) (variable) (line_break))\n\n=========================================\nsingle-line statements - external tokens\n=========================================\n\n'hello' 'world'\n\n---\n\n(statement (string) (string) (line_break))\n\n=========================================\nmulti-line statements - external tokens\n=========================================\n\n'hello'\n'world'\n\n---\n\n(statement (string) (string) (line_break))\n"
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  for
    result in @corpus.run(
      language,
      @corpus.parse(corpus),
      scanner=scanner_external_and_internal_tokens(),
    ) {
    assert_true(
      result.passed,
      msg="external_and_internal_tokens: \{result.name}\nexpected: \{result.expected}\nactual: \{result.actual}",
    )
  }
}

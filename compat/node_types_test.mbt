// Node schemas from pinned Tree-sitter 4a412a01. See LICENSE.

///|
test "upstream node schema aliased_inlined_rules" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"aliased_inlined_rules","rules":{"statement":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"STRING","value":";"}]},"_expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"member_expression"},{"type":"ALIAS","content":{"type":"SYMBOL","name":"identifier"},"named":true,"value":"variable_name"}]},"member_expression":{"type":"PREC_LEFT","value":1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"STRING","value":"."},{"type":"ALIAS","content":{"type":"SYMBOL","name":"identifier"},"named":true,"value":"property_name"}]}},"identifier":{"type":"CHOICE","members":[{"type":"STRING","value":"a"},{"type":"STRING","value":"b"},{"type":"STRING","value":"c"}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":["identifier"],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "member_expression",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "member_expression", "named": true },
          { "type": "property_name", "named": true },
          { "type": "variable_name", "named": true },
        ],
      },
    },
    {
      "type": "statement",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "member_expression", "named": true },
          { "type": "variable_name", "named": true },
        ],
      },
    },
    { "type": ".", "named": false },
    { "type": ";", "named": false },
    { "type": "property_name", "named": true },
    { "type": "variable_name", "named": true },
  ])
}

///|
test "upstream node schema aliased_rules" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"aliased_rules","rules":{"statement":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"STRING","value":";"}]},"_expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"call_expression"},{"type":"SYMBOL","name":"member_expression"},{"type":"ALIAS","content":{"type":"SYMBOL","name":"identifier"},"named":true,"value":"variable_name"}]},"call_expression":{"type":"PREC_LEFT","value":0,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"STRING","value":"("},{"type":"SYMBOL","name":"_expression"},{"type":"STRING","value":")"}]}},"member_expression":{"type":"PREC_LEFT","value":1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"STRING","value":"."},{"type":"ALIAS","content":{"type":"SYMBOL","name":"identifier"},"named":true,"value":"property_name"}]}},"identifier":{"type":"PATTERN","value":"[a-z]+"},"star":{"type":"STRING","value":"*"},"unused":{"type":"ALIAS","content":{"type":"SYMBOL","name":"star"},"named":true,"value":"star_aliased"}},"extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"star"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "call_expression",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "call_expression", "named": true },
          { "type": "member_expression", "named": true },
          { "type": "variable_name", "named": true },
        ],
      },
    },
    {
      "type": "member_expression",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "call_expression", "named": true },
          { "type": "member_expression", "named": true },
          { "type": "property_name", "named": true },
          { "type": "variable_name", "named": true },
        ],
      },
    },
    {
      "type": "statement",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "call_expression", "named": true },
          { "type": "member_expression", "named": true },
          { "type": "variable_name", "named": true },
        ],
      },
    },
    { "type": "(", "named": false },
    { "type": ")", "named": false },
    { "type": ".", "named": false },
    { "type": ";", "named": false },
    { "type": "property_name", "named": true },
    { "type": "star", "named": true, "extra": true },
    { "type": "variable_name", "named": true },
  ])
}

///|
test "upstream node schema aliased_token_rules" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"aliased_token_rules","rules":{"expression":{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"ALIAS","content":{"type":"TOKEN","content":{"type":"SEQ","members":[{"type":"STRING","value":"b"},{"type":"STRING","value":"c"}]}},"named":true,"value":"X"},{"type":"ALIAS","content":{"type":"IMMEDIATE_TOKEN","content":{"type":"SEQ","members":[{"type":"STRING","value":"d"},{"type":"STRING","value":"e"}]}},"named":true,"value":"Y"}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "expression",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "X", "named": true },
          { "type": "Y", "named": true },
        ],
      },
    },
    { "type": "X", "named": true },
    { "type": "Y", "named": true },
    { "type": "a", "named": false },
  ])
}

///|
test "upstream node schema aliased_unit_reductions" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"aliased_unit_reductions","rules":{"statement":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_a"},{"type":"ALIAS","content":{"type":"SYMBOL","name":"_b"},"named":true,"value":"b_prime"},{"type":"ALIAS","content":{"type":"SYMBOL","name":"_c"},"named":true,"value":"c_prime"},{"type":"SYMBOL","name":"_c"},{"type":"STRING","value":";"}]},"_a":{"type":"SYMBOL","name":"_A"},"_b":{"type":"SYMBOL","name":"_B"},"_c":{"type":"SYMBOL","name":"_C"},"_A":{"type":"SYMBOL","name":"identifier"},"_B":{"type":"SYMBOL","name":"identifier"},"_C":{"type":"SYMBOL","name":"identifier"},"identifier":{"type":"PATTERN","value":"[a-z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "b_prime",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "identifier", "named": true }],
      },
    },
    {
      "type": "c_prime",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "identifier", "named": true }],
      },
    },
    {
      "type": "statement",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "b_prime", "named": true },
          { "type": "c_prime", "named": true },
          { "type": "identifier", "named": true },
        ],
      },
    },
    { "type": ";", "named": false },
    { "type": "identifier", "named": true },
  ])
}

///|
test "upstream node schema aliases_in_root" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"aliases_in_root","rules":{"document":{"type":"SEQ","members":[{"type":"ALIAS","content":{"type":"SYMBOL","name":"foo"},"named":true,"value":"bar"},{"type":"SYMBOL","name":"foo"}]},"foo":{"type":"STRING","value":"foo"},"comment":{"type":"PATTERN","value":"#.*"}},"extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"comment"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "document",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "bar", "named": true },
          { "type": "foo", "named": true },
        ],
      },
    },
    { "type": "bar", "named": true },
    { "type": "comment", "named": true, "extra": true },
    { "type": "foo", "named": true },
  ])
}

///|
test "upstream node schema anonymous_error" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"anonymous_error","rules":{"document":{"type":"REPEAT","content":{"type":"CHOICE","members":[{"type":"STRING","value":"ok"},{"type":"STRING","value":"ERROR"}]}}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    { "type": "document", "named": true, "root": true, "fields": {} },
    { "type": "ERROR", "named": false },
    { "type": "ok", "named": false },
  ])
}

///|
test "upstream node schema anonymous_tokens_with_escaped_chars" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"anonymous_tokens_with_escaped_chars","rules":{"first_rule":{"type":"CHOICE","members":[{"type":"STRING","value":"\n"},{"type":"STRING","value":"\r\n"},{"type":"STRING","value":"'hello'"},{"type":"PATTERN","value":"\\d+"}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    { "type": "first_rule", "named": true, "root": true, "fields": {} },
    { "type": "\n", "named": false },
    { "type": "\r\n", "named": false },
    { "type": "'hello'", "named": false },
  ])
}

///|
test "upstream node schema associativity_left" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"associativity_left","rules":{"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"math_operation"},{"type":"SYMBOL","name":"identifier"}]},"math_operation":{"type":"PREC_LEFT","value":0,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"+"},{"type":"SYMBOL","name":"expression"}]}},"identifier":{"type":"PATTERN","value":"[a-z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "expression",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "identifier", "named": true },
          { "type": "math_operation", "named": true },
        ],
      },
    },
    {
      "type": "math_operation",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [{ "type": "expression", "named": true }],
      },
    },
    { "type": "+", "named": false },
    { "type": "identifier", "named": true },
  ])
}

///|
test "upstream node schema associativity_left_with_lower_precedence_shift" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"associativity_left_with_lower_precedence_shift","rules":{"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"addition"},{"type":"SYMBOL","name":"superaddition"},{"type":"SYMBOL","name":"number"}]},"addition":{"type":"PREC_LEFT","value":1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"+"},{"type":"SYMBOL","name":"expression"}]}},"superaddition":{"type":"PREC_RIGHT","value":0,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"+"},{"type":"STRING","value":"+"},{"type":"SYMBOL","name":"expression"}]}},"number":{"type":"STRING","value":"1"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "addition",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [{ "type": "expression", "named": true }],
      },
    },
    {
      "type": "expression",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "addition", "named": true },
          { "type": "number", "named": true },
          { "type": "superaddition", "named": true },
        ],
      },
    },
    {
      "type": "superaddition",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [{ "type": "expression", "named": true }],
      },
    },
    { "type": "+", "named": false },
    { "type": "number", "named": true },
  ])
}

///|
test "upstream node schema associativity_right" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"associativity_right","rules":{"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"math_operation"},{"type":"SYMBOL","name":"identifier"}]},"math_operation":{"type":"PREC_RIGHT","value":0,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"+"},{"type":"SYMBOL","name":"expression"}]}},"identifier":{"type":"PATTERN","value":"[a-z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "expression",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "identifier", "named": true },
          { "type": "math_operation", "named": true },
        ],
      },
    },
    {
      "type": "math_operation",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [{ "type": "expression", "named": true }],
      },
    },
    { "type": "+", "named": false },
    { "type": "identifier", "named": true },
  ])
}

///|
test "upstream node schema associativity_right_with_lower_precedence_shift" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"associativity_right_with_lower_precedence_shift","rules":{"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"addition"},{"type":"SYMBOL","name":"superaddition"},{"type":"SYMBOL","name":"number"}]},"addition":{"type":"PREC_RIGHT","value":1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"+"},{"type":"SYMBOL","name":"expression"}]}},"superaddition":{"type":"PREC_RIGHT","value":0,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"+"},{"type":"STRING","value":"+"},{"type":"SYMBOL","name":"expression"}]}},"number":{"type":"STRING","value":"1"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "addition",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [{ "type": "expression", "named": true }],
      },
    },
    {
      "type": "expression",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "addition", "named": true },
          { "type": "number", "named": true },
          { "type": "superaddition", "named": true },
        ],
      },
    },
    {
      "type": "superaddition",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [{ "type": "expression", "named": true }],
      },
    },
    { "type": "+", "named": false },
    { "type": "number", "named": true },
  ])
}

///|
test "upstream node schema basic_cst" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"basic_cst","rules":{"document":{"type":"SYMBOL","name":"assignment"},"assignment":{"type":"SEQ","members":[{"type":"FIELD","name":"name","content":{"type":"SYMBOL","name":"identifier"}},{"type":"STRING","value":"="},{"type":"FIELD","name":"value","content":{"type":"SYMBOL","name":"number"}}]},"identifier":{"type":"PATTERN","value":"[a-z]+"},"number":{"type":"PATTERN","value":"[0-9]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "assignment",
      "named": true,
      "fields": {
        "name": {
          "multiple": false,
          "required": true,
          "types": [{ "type": "identifier", "named": true }],
        },
        "value": {
          "multiple": false,
          "required": true,
          "types": [{ "type": "number", "named": true }],
        },
      },
    },
    {
      "type": "document",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "assignment", "named": true }],
      },
    },
    { "type": "=", "named": false },
    { "type": "identifier", "named": true },
    { "type": "number", "named": true },
  ])
}

///|
test "upstream node schema depends_on_column" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"depends_on_column","rules":{"x_is_at":{"type":"SEQ","members":[{"type":"PATTERN","value":"[ \\r\\n]*"},{"type":"CHOICE","members":[{"type":"SYMBOL","name":"odd_column"},{"type":"SYMBOL","name":"even_column"}]},{"type":"STRING","value":"x"}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"odd_column"},{"type":"SYMBOL","name":"even_column"}],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "x_is_at",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "even_column", "named": true },
          { "type": "odd_column", "named": true },
        ],
      },
    },
    { "type": "even_column", "named": true },
    { "type": "odd_column", "named": true },
    { "type": "x", "named": false },
  ])
}

///|
test "upstream node schema depends_on_column_failed_scan" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"depends_on_column_failed_scan","rules":{"document":{"type":"REPEAT","content":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"head"},{"type":"SYMBOL","name":"tail"},{"type":"SYMBOL","name":"letter"},{"type":"SYMBOL","name":"newline"}]}},"tail":{"type":"STRING","value":"x"},"letter":{"type":"STRING","value":"a"},"newline":{"type":"STRING","value":"\n"}},"extras":[],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"head"}],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "document",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [
          { "type": "head", "named": true },
          { "type": "letter", "named": true },
          { "type": "newline", "named": true },
          { "type": "tail", "named": true },
        ],
      },
    },
    { "type": "head", "named": true },
    { "type": "letter", "named": true },
    { "type": "newline", "named": true },
    { "type": "tail", "named": true },
  ])
}

///|
test "upstream node schema depends_on_column_repetition" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"depends_on_column_repetition","rules":{"document":{"type":"REPEAT","content":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"head"},{"type":"SYMBOL","name":"tail"},{"type":"SYMBOL","name":"word"},{"type":"SYMBOL","name":"newline"}]}},"word":{"type":"PATTERN","value":"[a-w]+"},"newline":{"type":"STRING","value":"\n"}},"extras":[],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"head"},{"type":"SYMBOL","name":"tail"}],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "document",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [
          { "type": "head", "named": true },
          { "type": "newline", "named": true },
          { "type": "tail", "named": true },
          { "type": "word", "named": true },
        ],
      },
    },
    { "type": "head", "named": true },
    { "type": "newline", "named": true },
    { "type": "tail", "named": true },
    { "type": "word", "named": true },
  ])
}

///|
test "upstream node schema duplicate_reduction_precedence" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"duplicate_reduction_precedence","rules":{"start":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"a"},{"type":"SYMBOL","name":"c"}]},"a":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"x"},{"type":"PREC","value":2,"content":{"type":"SYMBOL","name":"x"}}]},"c":{"type":"SYMBOL","name":"x"},"x":{"type":"STRING","value":"x"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "a",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "x", "named": true }],
      },
    },
    {
      "type": "c",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "x", "named": true }],
      },
    },
    {
      "type": "start",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "a", "named": true },
          { "type": "c", "named": true },
        ],
      },
    },
    { "type": "x", "named": true },
  ])
}

///|
test "upstream node schema dynamic_precedence" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"dynamic_precedence","rules":{"program":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"declaration"},{"type":"SYMBOL","name":"expression"}]},"expression":{"type":"CHOICE","members":[{"type":"PREC_LEFT","value":0,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"*"},{"type":"SYMBOL","name":"expression"}]}},{"type":"SYMBOL","name":"identifier"}]},"declaration":{"type":"SEQ","members":[{"type":"SYMBOL","name":"type"},{"type":"SYMBOL","name":"declarator"}]},"declarator":{"type":"CHOICE","members":[{"type":"PREC_DYNAMIC","value":1,"content":{"type":"SEQ","members":[{"type":"STRING","value":"*"},{"type":"SYMBOL","name":"identifier"}]}},{"type":"SYMBOL","name":"identifier"}]},"type":{"type":"SYMBOL","name":"identifier"},"identifier":{"type":"PATTERN","value":"[a-z-A-Z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[["expression","type"]],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "declaration",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "declarator", "named": true },
          { "type": "type", "named": true },
        ],
      },
    },
    {
      "type": "declarator",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "identifier", "named": true }],
      },
    },
    {
      "type": "expression",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "expression", "named": true },
          { "type": "identifier", "named": true },
        ],
      },
    },
    {
      "type": "program",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "declaration", "named": true },
          { "type": "expression", "named": true },
        ],
      },
    },
    {
      "type": "type",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "identifier", "named": true }],
      },
    },
    { "type": "*", "named": false },
    { "type": "identifier", "named": true },
  ])
}

///|
test "upstream node schema eof_basic" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"eof_basic","rules":{"source_file":{"type":"REPEAT","content":{"type":"SYMBOL","name":"line"}},"line":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"STRING","value":"text"},{"type":"STRING","value":"\n"}]},{"type":"SEQ","members":[{"type":"STRING","value":"text"},{"type":"EOF"}]}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    { "type": "line", "named": true, "fields": {} },
    {
      "type": "source_file",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [{ "type": "line", "named": true }],
      },
    },
    { "type": "\n", "named": false },
    { "type": "text", "named": false },
  ])
}

///|
test "upstream node schema eof_dropped_branch" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"eof_dropped_branch","rules":{"source_file":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"STRING","value":"("},{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"SYMBOL","name":"item"},{"type":"REPEAT","content":{"type":"SEQ","members":[{"type":"CHOICE","members":[{"type":"STRING","value":"\n"},{"type":"STRING","value":";"},{"type":"EOF"}]},{"type":"SYMBOL","name":"item"}]}},{"type":"CHOICE","members":[{"type":"CHOICE","members":[{"type":"STRING","value":"\n"},{"type":"STRING","value":";"},{"type":"EOF"}]},{"type":"BLANK"}]}]},{"type":"BLANK"}]},{"type":"STRING","value":")"}]},{"type":"SYMBOL","name":"inline_test"}]},"item":{"type":"STRING","value":"x"},"inline_test":{"type":"CHOICE","members":[{"type":"STRING","value":"ok"},{"type":"SEQ","members":[{"type":"SYMBOL","name":"_inline_eof"},{"type":"STRING","value":"bad"}]}]},"_inline_eof":{"type":"EOF"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":["_inline_eof"],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    { "type": "inline_test", "named": true, "fields": {} },
    {
      "type": "source_file",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [
          { "type": "inline_test", "named": true },
          { "type": "item", "named": true },
        ],
      },
    },
    { "type": "\n", "named": false },
    { "type": "(", "named": false },
    { "type": ")", "named": false },
    { "type": ";", "named": false },
    { "type": "bad", "named": false },
    { "type": "item", "named": true },
    { "type": "ok", "named": false },
  ])
}

///|
test "upstream node schema eof_duplicate_reduction" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"eof_duplicate_reduction","rules":{"source_file":{"type":"REPEAT","content":{"type":"SYMBOL","name":"line"}},"line":{"type":"CHOICE","members":[{"type":"STRING","value":"text"},{"type":"SEQ","members":[{"type":"STRING","value":"text"},{"type":"EOF"}]}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    { "type": "line", "named": true, "fields": {} },
    {
      "type": "source_file",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [{ "type": "line", "named": true }],
      },
    },
    { "type": "text", "named": false },
  ])
}

///|
test "upstream node schema eof_repeat_terminated" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"eof_repeat_terminated","rules":{"source_file":{"type":"REPEAT","content":{"type":"SEQ","members":[{"type":"STRING","value":"text"},{"type":"EOF"}]}}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    { "type": "source_file", "named": true, "root": true, "fields": {} },
    { "type": "text", "named": false },
  ])
}

///|
test "upstream node schema eof_repeat_via_rule" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"eof_repeat_via_rule","rules":{"start":{"type":"SYMBOL","name":"body"},"body":{"type":"REPEAT1","content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"b"},{"type":"EOF"}]}},"b":{"type":"REPEAT1","content":{"type":"STRING","value":"a"}}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    { "type": "b", "named": true, "fields": {} },
    {
      "type": "body",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [{ "type": "b", "named": true }],
      },
    },
    {
      "type": "start",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "body", "named": true }],
      },
    },
    { "type": "a", "named": false },
  ])
}

///|
test "upstream node schema epsilon_external_extra_tokens" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"epsilon_external_extra_tokens","rules":{"document":{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"STRING","value":"b"}]}},"extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"comment"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"comment"}],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    { "type": "document", "named": true, "root": true, "fields": {} },
    { "type": "a", "named": false },
    { "type": "b", "named": false },
    { "type": "comment", "named": true, "extra": true },
  ])
}

///|
test "upstream node schema epsilon_external_tokens" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"epsilon_external_tokens","rules":{"document":{"type":"SEQ","members":[{"type":"SYMBOL","name":"zero_width"},{"type":"STRING","value":"hello"}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"zero_width"}],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "document",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "zero_width", "named": true }],
      },
    },
    { "type": "hello", "named": false },
    { "type": "zero_width", "named": true },
  ])
}

///|
test "upstream node schema error_recovery_loop" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"error_recovery_loop","rules":{"program":{"type":"REPEAT","content":{"type":"SYMBOL","name":"sequence"}},"sequence":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":","}]},"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"primary"},{"type":"SEQ","members":[{"type":"STRING","value":"<"},{"type":"STRING","value":"<"},{"type":"SYMBOL","name":"type"},{"type":"STRING","value":">"},{"type":"CHOICE","members":[{"type":"STRING","value":":"},{"type":"SEQ","members":[{"type":"STRING","value":"{"},{"type":"SYMBOL","name":"sequence"}]}]}]},{"type":"SYMBOL","name":"assignment"}]},"primary":{"type":"CHOICE","members":[{"type":"STRING","value":"let"},{"type":"SEQ","members":[{"type":"STRING","value":"/"},{"type":"IMMEDIATE_TOKEN","content":{"type":"REPEAT1","content":{"type":"PATTERN","value":"[^\\]\\n\\\\]"}}}]},{"type":"SEQ","members":[{"type":"STRING","value":"["},{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":","}]},{"type":"SYMBOL","name":"non_null"}]},"_lhs":{"type":"CHOICE","members":[{"type":"STRING","value":"let"},{"type":"SEQ","members":[{"type":"STRING","value":"["},{"type":"CHOICE","members":[{"type":"SYMBOL","name":"pattern"},{"type":"SEQ","members":[{"type":"SYMBOL","name":"pattern"},{"type":"STRING","value":"="}]}]},{"type":"STRING","value":","}]},{"type":"SYMBOL","name":"non_null"}]},"assignment":{"type":"SEQ","members":[{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"STRING","value":"("},{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":":"}]},{"type":"SYMBOL","name":"sequence"}]}]},{"type":"SYMBOL","name":"_lhs"}]},{"type":"STRING","value":"="}]},"pattern":{"type":"SYMBOL","name":"_lhs"},"non_null":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"!"}]},"type":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"STRING","value":"("},{"type":"SYMBOL","name":"type"}]},{"type":"PATTERN","value":"[a-z]"},{"type":"SEQ","members":[{"type":"STRING","value":"("},{"type":"SYMBOL","name":"pattern"},{"type":"CHOICE","members":[{"type":"STRING","value":":"},{"type":"BLANK"}]},{"type":"CHOICE","members":[{"type":"STRING","value":"="},{"type":"BLANK"}]},{"type":"STRING","value":","}]}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[["primary","pattern"],["assignment","pattern"]],"precedences":[],"externals":[],"inline":["_lhs"],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "assignment",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": false,
        "types": [
          { "type": "expression", "named": true },
          { "type": "non_null", "named": true },
          { "type": "pattern", "named": true },
          { "type": "sequence", "named": true },
        ],
      },
    },
    {
      "type": "expression",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "assignment", "named": true },
          { "type": "primary", "named": true },
          { "type": "sequence", "named": true },
          { "type": "type", "named": true },
        ],
      },
    },
    {
      "type": "non_null",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "expression", "named": true }],
      },
    },
    {
      "type": "pattern",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": false,
        "types": [
          { "type": "non_null", "named": true },
          { "type": "pattern", "named": true },
        ],
      },
    },
    {
      "type": "primary",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": false,
        "types": [
          { "type": "expression", "named": true },
          { "type": "non_null", "named": true },
        ],
      },
    },
    {
      "type": "program",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [{ "type": "sequence", "named": true }],
      },
    },
    {
      "type": "sequence",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "expression", "named": true }],
      },
    },
    {
      "type": "type",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": false,
        "types": [
          { "type": "pattern", "named": true },
          { "type": "type", "named": true },
        ],
      },
    },
    { "type": "!", "named": false },
    { "type": "(", "named": false },
    { "type": ",", "named": false },
    { "type": "/", "named": false },
    { "type": ":", "named": false },
    { "type": "<", "named": false },
    { "type": "=", "named": false },
    { "type": ">", "named": false },
    { "type": "[", "named": false },
    { "type": "let", "named": false },
    { "type": "{", "named": false },
  ])
}

///|
test "upstream node schema external_and_internal_anonymous_tokens" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"external_and_internal_anonymous_tokens","rules":{"statement":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"SYMBOL","name":"_expression"},{"type":"STRING","value":"\n"}]},"_expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"string"},{"type":"SYMBOL","name":"variable"},{"type":"SYMBOL","name":"number"}]},"variable":{"type":"PATTERN","value":"[a-z]+"},"number":{"type":"PATTERN","value":"\\d+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"string"},{"type":"STRING","value":"\n"}],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "statement",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "number", "named": true },
          { "type": "string", "named": true },
          { "type": "variable", "named": true },
        ],
      },
    },
    { "type": "\n", "named": false },
    { "type": "number", "named": true },
    { "type": "string", "named": true },
    { "type": "variable", "named": true },
  ])
}

///|
test "upstream node schema external_and_internal_tokens" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"external_and_internal_tokens","rules":{"statement":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"SYMBOL","name":"_expression"},{"type":"SYMBOL","name":"line_break"}]},"_expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"string"},{"type":"SYMBOL","name":"variable"},{"type":"SYMBOL","name":"number"}]},"variable":{"type":"PATTERN","value":"[a-z]+"},"number":{"type":"PATTERN","value":"\\d+"},"line_break":{"type":"STRING","value":"\n"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"string"},{"type":"SYMBOL","name":"line_break"}],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "statement",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "line_break", "named": true },
          { "type": "number", "named": true },
          { "type": "string", "named": true },
          { "type": "variable", "named": true },
        ],
      },
    },
    { "type": "line_break", "named": true },
    { "type": "number", "named": true },
    { "type": "string", "named": true },
    { "type": "variable", "named": true },
  ])
}

///|
test "upstream node schema external_extra_tokens" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"external_extra_tokens","rules":{"assignment":{"type":"SEQ","members":[{"type":"SYMBOL","name":"variable"},{"type":"STRING","value":"="},{"type":"SYMBOL","name":"variable"}]},"variable":{"type":"PATTERN","value":"[a-z]+"}},"extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"comment"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"comment"}],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "assignment",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [{ "type": "variable", "named": true }],
      },
    },
    { "type": "=", "named": false },
    { "type": "comment", "named": true, "extra": true },
    { "type": "variable", "named": true },
  ])
}

///|
test "upstream node schema external_lookahead_eof_boundary" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"external_lookahead_eof_boundary","rules":{"document":{"type":"REPEAT","content":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"span"},{"type":"SYMBOL","name":"unclosed_delim"}]}},"span":{"type":"SEQ","members":[{"type":"SYMBOL","name":"open_delim"},{"type":"SYMBOL","name":"close_delim"}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"open_delim"},{"type":"SYMBOL","name":"close_delim"},{"type":"SYMBOL","name":"unclosed_delim"}],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "document",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [
          { "type": "span", "named": true },
          { "type": "unclosed_delim", "named": true },
        ],
      },
    },
    {
      "type": "span",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "close_delim", "named": true },
          { "type": "open_delim", "named": true },
        ],
      },
    },
    { "type": "close_delim", "named": true },
    { "type": "open_delim", "named": true },
    { "type": "unclosed_delim", "named": true },
  ])
}

///|
test "upstream node schema external_tokens" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"external_tokens","rules":{"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"string"},{"type":"SYMBOL","name":"sum"},{"type":"SYMBOL","name":"identifier"}]},"sum":{"type":"PREC_LEFT","value":0,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"+"},{"type":"SYMBOL","name":"expression"}]}},"string":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"_percent_string"},{"type":"SEQ","members":[{"type":"SYMBOL","name":"_percent_string_start"},{"type":"SYMBOL","name":"expression"},{"type":"SYMBOL","name":"_percent_string_end"}]}]},"identifier":{"type":"PATTERN","value":"[a-z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"_percent_string"},{"type":"SYMBOL","name":"_percent_string_start"},{"type":"SYMBOL","name":"_percent_string_end"}],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "expression",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "identifier", "named": true },
          { "type": "string", "named": true },
          { "type": "sum", "named": true },
        ],
      },
    },
    {
      "type": "string",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": false,
        "types": [{ "type": "expression", "named": true }],
      },
    },
    {
      "type": "sum",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [{ "type": "expression", "named": true }],
      },
    },
    { "type": "+", "named": false },
    { "type": "identifier", "named": true },
  ])
}

///|
test "upstream node schema external_unicode_column_alignment" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"external_unicode_column_alignment","rules":{"expression":{"type":"REPEAT","content":{"type":"SYMBOL","name":"list"}},"list":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_start_list"},{"type":"REPEAT1","content":{"type":"SYMBOL","name":"list_item"}},{"type":"SYMBOL","name":"_end_list"}]}},"extras":[{"type":"PATTERN","value":"\\s"},{"type":"STRING","value":"□"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"_start_list"},{"type":"SYMBOL","name":"list_item"},{"type":"SYMBOL","name":"_end_list"}],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "expression",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [{ "type": "list", "named": true }],
      },
    },
    {
      "type": "list",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [{ "type": "list_item", "named": true }],
      },
    },
    { "type": "list_item", "named": true },
  ])
}

///|
test "upstream node schema external_word_token" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"external_word_token","word":"identifier","rules":{"program":{"type":"REPEAT","content":{"type":"SYMBOL","name":"_item"}},"label_name":{"type":"PATTERN","value":"[a-z]+"},"_item":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"let_statement"},{"type":"SYMBOL","name":"label"}]},"let_statement":{"type":"SEQ","members":[{"type":"STRING","value":"let"},{"type":"SYMBOL","name":"identifier"},{"type":"STRING","value":"="},{"type":"SYMBOL","name":"identifier"},{"type":"STRING","value":";"}]},"label":{"type":"SEQ","members":[{"type":"STRING","value":"@"},{"type":"SYMBOL","name":"label_name"}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"identifier"}],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "label",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "label_name", "named": true }],
      },
    },
    {
      "type": "let_statement",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [{ "type": "identifier", "named": true }],
      },
    },
    {
      "type": "program",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [
          { "type": "label", "named": true },
          { "type": "let_statement", "named": true },
        ],
      },
    },
    { "type": ";", "named": false },
    { "type": "=", "named": false },
    { "type": "@", "named": false },
    { "type": "identifier", "named": true },
    { "type": "label_name", "named": true },
    { "type": "let", "named": false },
  ])
}

///|
test "upstream node schema extra_non_terminals" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"extra_non_terminals","rules":{"module":{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"STRING","value":"b"},{"type":"STRING","value":"c"},{"type":"STRING","value":"d"}]},"comment":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"paren_comment"},{"type":"SYMBOL","name":"line_comment"}]},"paren_comment":{"type":"TOKEN","content":{"type":"SEQ","members":[{"type":"STRING","value":"("},{"type":"REPEAT","content":{"type":"PATTERN","value":"[a-z]+"}},{"type":"STRING","value":")"}]}},"line_comment":{"type":"TOKEN","content":{"type":"SEQ","members":[{"type":"STRING","value":"//"},{"type":"PATTERN","value":".*"}]}}},"extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"comment"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "comment",
      "named": true,
      "extra": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "line_comment", "named": true },
          { "type": "paren_comment", "named": true },
        ],
      },
    },
    { "type": "module", "named": true, "root": true, "fields": {} },
    { "type": "a", "named": false },
    { "type": "b", "named": false },
    { "type": "c", "named": false },
    { "type": "d", "named": false },
    { "type": "line_comment", "named": true },
    { "type": "paren_comment", "named": true },
  ])
}

///|
test "upstream node schema extra_non_terminals_with_shared_rules" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"extra_non_terminals_with_shared_rules","rules":{"program":{"type":"REPEAT","content":{"type":"SYMBOL","name":"statement"}},"statement":{"type":"SEQ","members":[{"type":"REPEAT","content":{"type":"SYMBOL","name":"label_declaration"}},{"type":"STRING","value":";"}]},"macro_statement":{"type":"SEQ","members":[{"type":"STRING","value":"%"},{"type":"SYMBOL","name":"statement"}]},"label_declaration":{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"STRING","value":":"}]},"identifier":{"type":"PATTERN","value":"[a-zA-Z]+"}},"extras":[{"type":"PATTERN","value":"\\s+"},{"type":"SYMBOL","name":"macro_statement"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "label_declaration",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "identifier", "named": true }],
      },
    },
    {
      "type": "macro_statement",
      "named": true,
      "extra": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "statement", "named": true }],
      },
    },
    {
      "type": "program",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [{ "type": "statement", "named": true }],
      },
    },
    {
      "type": "statement",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [{ "type": "label_declaration", "named": true }],
      },
    },
    { "type": "%", "named": false },
    { "type": ":", "named": false },
    { "type": ";", "named": false },
    { "type": "identifier", "named": true },
  ])
}

///|
test "upstream node schema field_lookup_through_hidden_nodes" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"field_lookup_through_hidden_nodes","rules":{"source_file":{"type":"REPEAT","content":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"list"},{"type":"SYMBOL","name":"binding"},{"type":"SYMBOL","name":"shadow"},{"type":"SYMBOL","name":"sum"},{"type":"SYMBOL","name":"aliased"},{"type":"SYMBOL","name":"alias_pair"},{"type":"SYMBOL","name":"multi"},{"type":"SYMBOL","name":"restored"},{"type":"SYMBOL","name":"back"},{"type":"SYMBOL","name":"maybe"},{"type":"SYMBOL","name":"order"},{"type":"SYMBOL","name":"skip"}]}},"list":{"type":"SEQ","members":[{"type":"STRING","value":"["},{"type":"CHOICE","members":[{"type":"SYMBOL","name":"_items"},{"type":"BLANK"}]},{"type":"STRING","value":"]"}]},"_items":{"type":"SEQ","members":[{"type":"SYMBOL","name":"item"},{"type":"REPEAT","content":{"type":"SEQ","members":[{"type":"STRING","value":","},{"type":"SYMBOL","name":"item"}]}}]},"item":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"name"},{"type":"FIELD","name":"spread","content":{"type":"SYMBOL","name":"spread"}}]},"spread":{"type":"SEQ","members":[{"type":"STRING","value":"..."},{"type":"SYMBOL","name":"name"}]},"aliased":{"type":"SEQ","members":[{"type":"STRING","value":"alias"},{"type":"ALIAS","content":{"type":"SYMBOL","name":"item"},"named":true,"value":"wrapped"},{"type":"STRING","value":";"}]},"alias_pair":{"type":"SEQ","members":[{"type":"STRING","value":"pair"},{"type":"ALIAS","content":{"type":"SYMBOL","name":"item"},"named":true,"value":"wrapped"},{"type":"STRING","value":","},{"type":"SYMBOL","name":"item"},{"type":"STRING","value":";"}]},"multi":{"type":"SEQ","members":[{"type":"STRING","value":"multi"},{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"_shadowed"}},{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"_binding"}},{"type":"STRING","value":";"}]},"binding":{"type":"SEQ","members":[{"type":"STRING","value":"let"},{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"_binding"}},{"type":"STRING","value":";"}]},"_binding":{"type":"SEQ","members":[{"type":"FIELD","name":"inner","content":{"type":"SYMBOL","name":"name"}},{"type":"STRING","value":"="},{"type":"SYMBOL","name":"name"}]},"shadow":{"type":"SEQ","members":[{"type":"STRING","value":"shadow"},{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"_shadowed"}},{"type":"STRING","value":";"}]},"_shadowed":{"type":"FIELD","name":"inner","content":{"type":"SYMBOL","name":"name"}},"restored":{"type":"SEQ","members":[{"type":"STRING","value":"restore"},{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"_restore"}},{"type":"STRING","value":";"}]},"_restore":{"type":"FIELD","name":"inner","content":{"type":"SYMBOL","name":"_restored"}},"_restored":{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"name"}},"back":{"type":"SEQ","members":[{"type":"STRING","value":"back"},{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"_back"}},{"type":"STRING","value":";"}]},"_back":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_shadowed"},{"type":"SYMBOL","name":"name"}]},"maybe":{"type":"SEQ","members":[{"type":"STRING","value":"maybe"},{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"_maybe"}},{"type":"STRING","value":";"}]},"_maybe":{"type":"FIELD","name":"inner","content":{"type":"SYMBOL","name":"_maybe_inner"}},"_maybe_inner":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_opt"},{"type":"STRING","value":"end"}]},"_opt":{"type":"CHOICE","members":[{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"name"}},{"type":"STRING","value":"none"}]},"order":{"type":"SEQ","members":[{"type":"STRING","value":"order"},{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"_order"}},{"type":"STRING","value":";"}]},"_order":{"type":"SEQ","members":[{"type":"FIELD","name":"zeta","content":{"type":"SYMBOL","name":"name"}},{"type":"FIELD","name":"alpha","content":{"type":"SYMBOL","name":"name"}},{"type":"SYMBOL","name":"name"}]},"skip":{"type":"SEQ","members":[{"type":"STRING","value":"skip"},{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"_skip"}},{"type":"STRING","value":";"}]},"_skip":{"type":"SEQ","members":[{"type":"FIELD","name":"inner","content":{"type":"SYMBOL","name":"_shadowed"}},{"type":"FIELD","name":"other","content":{"type":"SYMBOL","name":"name"}},{"type":"SYMBOL","name":"name"}]},"sum":{"type":"SEQ","members":[{"type":"STRING","value":"sum"},{"type":"SYMBOL","name":"_sum"},{"type":"STRING","value":";"}]},"_sum":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"name"},{"type":"SEQ","members":[{"type":"FIELD","name":"left","content":{"type":"SYMBOL","name":"_sum"}},{"type":"STRING","value":"+"},{"type":"SYMBOL","name":"name"}]}]},"name":{"type":"PATTERN","value":"[a-z0-9]+"},"comment":{"type":"TOKEN","content":{"type":"SEQ","members":[{"type":"STRING","value":"//"},{"type":"PATTERN","value":".*"}]}},"_note":{"type":"SEQ","members":[{"type":"STRING","value":"@"},{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"name"}}]},"_tag":{"type":"SEQ","members":[{"type":"STRING","value":"#"},{"type":"SYMBOL","name":"name"}]}},"extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"comment"},{"type":"SYMBOL","name":"_note"},{"type":"SYMBOL","name":"_tag"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":["item"],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "item",
      "named": true,
      "subtypes": [
        { "type": "name", "named": true },
        { "type": "spread", "named": true },
      ],
    },
    {
      "type": "alias_pair",
      "named": true,
      "fields": {
        "spread": {
          "multiple": false,
          "required": false,
          "types": [{ "type": "spread", "named": true }],
        },
      },
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "item", "named": true },
          { "type": "wrapped", "named": true },
        ],
      },
    },
    {
      "type": "aliased",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "wrapped", "named": true }],
      },
    },
    {
      "type": "back",
      "named": true,
      "fields": {
        "inner": {
          "multiple": false,
          "required": true,
          "types": [{ "type": "name", "named": true }],
        },
        "outer": {
          "multiple": true,
          "required": true,
          "types": [{ "type": "name", "named": true }],
        },
      },
    },
    {
      "type": "binding",
      "named": true,
      "fields": {
        "inner": {
          "multiple": false,
          "required": true,
          "types": [{ "type": "name", "named": true }],
        },
        "outer": {
          "multiple": true,
          "required": true,
          "types": [
            { "type": "=", "named": false },
            { "type": "name", "named": true },
          ],
        },
      },
    },
    {
      "type": "list",
      "named": true,
      "fields": {
        "spread": {
          "multiple": true,
          "required": false,
          "types": [{ "type": "spread", "named": true }],
        },
      },
      "children": {
        "multiple": true,
        "required": false,
        "types": [{ "type": "item", "named": true }],
      },
    },
    {
      "type": "maybe",
      "named": true,
      "fields": {
        "inner": {
          "multiple": true,
          "required": true,
          "types": [
            { "type": "end", "named": false },
            { "type": "name", "named": true },
            { "type": "none", "named": false },
          ],
        },
        "outer": {
          "multiple": true,
          "required": true,
          "types": [
            { "type": "end", "named": false },
            { "type": "name", "named": true },
            { "type": "none", "named": false },
          ],
        },
      },
    },
    {
      "type": "multi",
      "named": true,
      "fields": {
        "inner": {
          "multiple": true,
          "required": true,
          "types": [{ "type": "name", "named": true }],
        },
        "outer": {
          "multiple": true,
          "required": true,
          "types": [
            { "type": "=", "named": false },
            { "type": "name", "named": true },
          ],
        },
      },
    },
    {
      "type": "order",
      "named": true,
      "fields": {
        "alpha": {
          "multiple": false,
          "required": true,
          "types": [{ "type": "name", "named": true }],
        },
        "outer": {
          "multiple": true,
          "required": true,
          "types": [{ "type": "name", "named": true }],
        },
        "zeta": {
          "multiple": false,
          "required": true,
          "types": [{ "type": "name", "named": true }],
        },
      },
    },
    {
      "type": "restored",
      "named": true,
      "fields": {
        "inner": {
          "multiple": false,
          "required": true,
          "types": [{ "type": "name", "named": true }],
        },
        "outer": {
          "multiple": true,
          "required": true,
          "types": [{ "type": "name", "named": true }],
        },
      },
    },
    {
      "type": "shadow",
      "named": true,
      "fields": {
        "inner": {
          "multiple": false,
          "required": true,
          "types": [{ "type": "name", "named": true }],
        },
        "outer": {
          "multiple": false,
          "required": true,
          "types": [{ "type": "name", "named": true }],
        },
      },
    },
    {
      "type": "skip",
      "named": true,
      "fields": {
        "inner": {
          "multiple": true,
          "required": true,
          "types": [{ "type": "name", "named": true }],
        },
        "other": {
          "multiple": false,
          "required": true,
          "types": [{ "type": "name", "named": true }],
        },
        "outer": {
          "multiple": true,
          "required": true,
          "types": [{ "type": "name", "named": true }],
        },
      },
    },
    {
      "type": "source_file",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [
          { "type": "alias_pair", "named": true },
          { "type": "aliased", "named": true },
          { "type": "back", "named": true },
          { "type": "binding", "named": true },
          { "type": "list", "named": true },
          { "type": "maybe", "named": true },
          { "type": "multi", "named": true },
          { "type": "order", "named": true },
          { "type": "restored", "named": true },
          { "type": "shadow", "named": true },
          { "type": "skip", "named": true },
          { "type": "sum", "named": true },
        ],
      },
    },
    {
      "type": "spread",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "name", "named": true }],
      },
    },
    {
      "type": "sum",
      "named": true,
      "fields": {
        "left": {
          "multiple": true,
          "required": false,
          "types": [
            { "type": "+", "named": false },
            { "type": "name", "named": true },
          ],
        },
      },
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "name", "named": true }],
      },
    },
    {
      "type": "wrapped",
      "named": true,
      "fields": {
        "spread": {
          "multiple": false,
          "required": false,
          "types": [{ "type": "spread", "named": true }],
        },
      },
      "children": {
        "multiple": false,
        "required": false,
        "types": [{ "type": "name", "named": true }],
      },
    },
    { "type": "#", "named": false },
    { "type": "+", "named": false },
    { "type": ",", "named": false },
    { "type": "...", "named": false },
    { "type": ";", "named": false },
    { "type": "=", "named": false },
    { "type": "@", "named": false },
    { "type": "[", "named": false },
    { "type": "]", "named": false },
    { "type": "alias", "named": false },
    { "type": "back", "named": false },
    { "type": "comment", "named": true, "extra": true },
    { "type": "end", "named": false },
    { "type": "let", "named": false },
    { "type": "maybe", "named": false },
    { "type": "multi", "named": false },
    { "type": "name", "named": true },
    { "type": "none", "named": false },
    { "type": "order", "named": false },
    { "type": "pair", "named": false },
    { "type": "restore", "named": false },
    { "type": "shadow", "named": false },
    { "type": "skip", "named": false },
    { "type": "sum", "named": false },
  ])
}

///|
test "upstream node schema field_on_hidden_rule" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"field_on_hidden_rule","rules":{"source_file":{"type":"REPEAT","content":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"binding"},{"type":"SYMBOL","name":"sum"},{"type":"SYMBOL","name":"call"}]}},"binding":{"type":"SEQ","members":[{"type":"STRING","value":"let"},{"type":"FIELD","name":"outer","content":{"type":"SYMBOL","name":"_binding"}},{"type":"STRING","value":";"}]},"_binding":{"type":"SEQ","members":[{"type":"FIELD","name":"inner","content":{"type":"SYMBOL","name":"name"}},{"type":"STRING","value":"="},{"type":"SYMBOL","name":"name"}]},"sum":{"type":"SEQ","members":[{"type":"STRING","value":"sum"},{"type":"SYMBOL","name":"_sum"},{"type":"STRING","value":";"}]},"_sum":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"name"},{"type":"SEQ","members":[{"type":"FIELD","name":"left","content":{"type":"SYMBOL","name":"_sum"}},{"type":"STRING","value":"+"},{"type":"SYMBOL","name":"name"}]}]},"call":{"type":"SEQ","members":[{"type":"STRING","value":"call"},{"type":"FIELD","name":"arg","content":{"type":"SYMBOL","name":"_call"}},{"type":"STRING","value":")"},{"type":"STRING","value":";"}]},"_call":{"type":"SEQ","members":[{"type":"STRING","value":"("},{"type":"FIELD","name":"arg","content":{"type":"SYMBOL","name":"name"}}]},"name":{"type":"PATTERN","value":"[a-z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "binding",
      "named": true,
      "fields": {
        "inner": {
          "multiple": false,
          "required": true,
          "types": [{ "type": "name", "named": true }],
        },
        "outer": {
          "multiple": true,
          "required": true,
          "types": [
            { "type": "=", "named": false },
            { "type": "name", "named": true },
          ],
        },
      },
    },
    {
      "type": "call",
      "named": true,
      "fields": {
        "arg": {
          "multiple": true,
          "required": true,
          "types": [
            { "type": "(", "named": false },
            { "type": "name", "named": true },
          ],
        },
      },
    },
    {
      "type": "source_file",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [
          { "type": "binding", "named": true },
          { "type": "call", "named": true },
          { "type": "sum", "named": true },
        ],
      },
    },
    {
      "type": "sum",
      "named": true,
      "fields": {
        "left": {
          "multiple": true,
          "required": false,
          "types": [
            { "type": "+", "named": false },
            { "type": "name", "named": true },
          ],
        },
      },
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "name", "named": true }],
      },
    },
    { "type": "(", "named": false },
    { "type": ")", "named": false },
    { "type": "+", "named": false },
    { "type": ";", "named": false },
    { "type": "=", "named": false },
    { "type": "call", "named": false },
    { "type": "let", "named": false },
    { "type": "name", "named": true },
    { "type": "sum", "named": false },
  ])
}

///|
test "upstream node schema get_col_eof" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"get_col_eof","rules":{"source_file":{"type":"REPEAT","content":{"type":"SYMBOL","name":"char"}}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"char"}],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "source_file",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [{ "type": "char", "named": true }],
      },
    },
    { "type": "char", "named": true },
  ])
}

///|
test "upstream node schema get_col_should_hang_not_crash" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"get_col_should_hang_not_crash","rules":{"source_file":{"type":"SEQ","members":[{"type":"SYMBOL","name":"test"}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"test"}],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "source_file",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "test", "named": true }],
      },
    },
    { "type": "test", "named": true },
  ])
}

///|
test "upstream node schema immediate_tokens" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"immediate_tokens","rules":{"program":{"type":"SYMBOL","name":"_expression"},"_expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"call"},{"type":"SYMBOL","name":"infix"},{"type":"SYMBOL","name":"prefix"},{"type":"SYMBOL","name":"identifier"}]},"call":{"type":"PREC_LEFT","value":-1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"SYMBOL","name":"_expression"}]}},"prefix":{"type":"SEQ","members":[{"type":"STRING","value":"::"},{"type":"SYMBOL","name":"identifier"}]},"infix":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"IMMEDIATE_TOKEN","content":{"type":"STRING","value":"::"}},{"type":"SYMBOL","name":"identifier"}]},"identifier":{"type":"PATTERN","value":"[a-z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "call",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "call", "named": true },
          { "type": "identifier", "named": true },
          { "type": "infix", "named": true },
          { "type": "prefix", "named": true },
        ],
      },
    },
    {
      "type": "infix",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "call", "named": true },
          { "type": "identifier", "named": true },
          { "type": "infix", "named": true },
          { "type": "prefix", "named": true },
        ],
      },
    },
    {
      "type": "prefix",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "identifier", "named": true }],
      },
    },
    {
      "type": "program",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "call", "named": true },
          { "type": "identifier", "named": true },
          { "type": "infix", "named": true },
          { "type": "prefix", "named": true },
        ],
      },
    },
    { "type": "::", "named": false },
    { "type": "identifier", "named": true },
  ])
}

///|
test "upstream node schema inline_rules" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"inline_rules","rules":{"program":{"type":"REPEAT1","content":{"type":"SYMBOL","name":"statement"}},"statement":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":";"}]},"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"sum"},{"type":"SYMBOL","name":"product"},{"type":"SYMBOL","name":"number"},{"type":"SYMBOL","name":"parenthesized_expression"}]},"parenthesized_expression":{"type":"SEQ","members":[{"type":"STRING","value":"("},{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":")"}]},"sum":{"type":"PREC_LEFT","value":0,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"+"},{"type":"SYMBOL","name":"expression"}]}},"product":{"type":"PREC_LEFT","value":2,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"*"},{"type":"SYMBOL","name":"expression"}]}},"number":{"type":"PATTERN","value":"\\d+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":["expression"],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "parenthesized_expression",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "number", "named": true },
          { "type": "parenthesized_expression", "named": true },
          { "type": "product", "named": true },
          { "type": "sum", "named": true },
        ],
      },
    },
    {
      "type": "product",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "number", "named": true },
          { "type": "parenthesized_expression", "named": true },
          { "type": "product", "named": true },
          { "type": "sum", "named": true },
        ],
      },
    },
    {
      "type": "program",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [{ "type": "statement", "named": true }],
      },
    },
    {
      "type": "statement",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "number", "named": true },
          { "type": "parenthesized_expression", "named": true },
          { "type": "product", "named": true },
          { "type": "sum", "named": true },
        ],
      },
    },
    {
      "type": "sum",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "number", "named": true },
          { "type": "parenthesized_expression", "named": true },
          { "type": "product", "named": true },
          { "type": "sum", "named": true },
        ],
      },
    },
    { "type": "(", "named": false },
    { "type": ")", "named": false },
    { "type": "*", "named": false },
    { "type": "+", "named": false },
    { "type": ";", "named": false },
    { "type": "number", "named": true },
  ])
}

///|
test "upstream node schema inlined_aliased_rules" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"inlined_aliased_rules","rules":{"statement":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":";"}]},"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"call_expression"},{"type":"SYMBOL","name":"member_expression"},{"type":"ALIAS","content":{"type":"SYMBOL","name":"identifier"},"named":true,"value":"variable_name"}]},"call_expression":{"type":"PREC_LEFT","value":0,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"("},{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":")"}]}},"member_expression":{"type":"PREC_LEFT","value":1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"."},{"type":"ALIAS","content":{"type":"SYMBOL","name":"identifier"},"named":true,"value":"property_name"}]}},"identifier":{"type":"PATTERN","value":"[a-z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":["expression"],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "call_expression",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "call_expression", "named": true },
          { "type": "member_expression", "named": true },
          { "type": "variable_name", "named": true },
        ],
      },
    },
    {
      "type": "member_expression",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "call_expression", "named": true },
          { "type": "member_expression", "named": true },
          { "type": "property_name", "named": true },
          { "type": "variable_name", "named": true },
        ],
      },
    },
    {
      "type": "statement",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "call_expression", "named": true },
          { "type": "member_expression", "named": true },
          { "type": "variable_name", "named": true },
        ],
      },
    },
    { "type": "(", "named": false },
    { "type": ")", "named": false },
    { "type": ".", "named": false },
    { "type": ";", "named": false },
    { "type": "property_name", "named": true },
    { "type": "variable_name", "named": true },
  ])
}

///|
test "upstream node schema inverted_external_token" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"inverted_external_token","rules":{"program":{"type":"REPEAT","content":{"type":"SYMBOL","name":"statement"}},"statement":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"SYMBOL","name":"line_break"}]},"_expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"member_expression"}]},"member_expression":{"type":"PREC_LEFT","value":0,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"STRING","value":"."},{"type":"SYMBOL","name":"identifier"}]}},"identifier":{"type":"PATTERN","value":"[a-z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"line_break"}],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "member_expression",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "identifier", "named": true },
          { "type": "member_expression", "named": true },
        ],
      },
    },
    {
      "type": "program",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [{ "type": "statement", "named": true }],
      },
    },
    {
      "type": "statement",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "identifier", "named": true },
          { "type": "line_break", "named": true },
          { "type": "member_expression", "named": true },
        ],
      },
    },
    { "type": ".", "named": false },
    { "type": "identifier", "named": true },
    { "type": "line_break", "named": true },
  ])
}

///|
test "upstream node schema last_child_anchor_past_hidden_repeat" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"last_child_anchor_past_hidden_repeat","rules":{"source_file":{"type":"REPEAT","content":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"trailing_sep"},{"type":"SYMBOL","name":"leading_sep"},{"type":"SYMBOL","name":"trailing_named"}]}},"trailing_sep":{"type":"SEQ","members":[{"type":"STRING","value":"T"},{"type":"REPEAT","content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"name"},{"type":"STRING","value":"."}]}},{"type":"SYMBOL","name":"name"}]},"leading_sep":{"type":"SEQ","members":[{"type":"STRING","value":"L"},{"type":"SYMBOL","name":"name"},{"type":"REPEAT","content":{"type":"SEQ","members":[{"type":"STRING","value":"."},{"type":"SYMBOL","name":"name"}]}}]},"trailing_named":{"type":"SEQ","members":[{"type":"STRING","value":"N"},{"type":"REPEAT","content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"name"},{"type":"SYMBOL","name":"tag"},{"type":"STRING","value":"."}]}},{"type":"SYMBOL","name":"name"}]},"tag":{"type":"STRING","value":"!"},"name":{"type":"PATTERN","value":"[a-z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "leading_sep",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [{ "type": "name", "named": true }],
      },
    },
    {
      "type": "source_file",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [
          { "type": "leading_sep", "named": true },
          { "type": "trailing_named", "named": true },
          { "type": "trailing_sep", "named": true },
        ],
      },
    },
    {
      "type": "trailing_named",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "name", "named": true },
          { "type": "tag", "named": true },
        ],
      },
    },
    {
      "type": "trailing_sep",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [{ "type": "name", "named": true }],
      },
    },
    { "type": ".", "named": false },
    { "type": "L", "named": false },
    { "type": "N", "named": false },
    { "type": "T", "named": false },
    { "type": "name", "named": true },
    { "type": "tag", "named": true },
  ])
}

///|
test "upstream node schema lexical_conflicts_due_to_state_merging" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"lexical_conflicts_due_to_state_merging","rules":{"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"conditional"},{"type":"SYMBOL","name":"quotient"},{"type":"SYMBOL","name":"regex"},{"type":"SYMBOL","name":"number"},{"type":"SYMBOL","name":"parenthesized"}]},"conditional":{"type":"PREC_LEFT","value":1,"content":{"type":"SEQ","members":[{"type":"STRING","value":"if"},{"type":"SYMBOL","name":"parenthesized"},{"type":"SYMBOL","name":"expression"}]}},"quotient":{"type":"PREC_LEFT","value":0,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"/"},{"type":"SYMBOL","name":"expression"}]}},"regex":{"type":"PATTERN","value":"\\/[^/\\n]+\\/"},"number":{"type":"PATTERN","value":"\\d+"},"parenthesized":{"type":"SEQ","members":[{"type":"STRING","value":"("},{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":")"}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "conditional",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "expression", "named": true },
          { "type": "parenthesized", "named": true },
        ],
      },
    },
    {
      "type": "expression",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "conditional", "named": true },
          { "type": "number", "named": true },
          { "type": "parenthesized", "named": true },
          { "type": "quotient", "named": true },
          { "type": "regex", "named": true },
        ],
      },
    },
    {
      "type": "parenthesized",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "expression", "named": true }],
      },
    },
    {
      "type": "quotient",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [{ "type": "expression", "named": true }],
      },
    },
    { "type": "(", "named": false },
    { "type": ")", "named": false },
    { "type": "/", "named": false },
    { "type": "if", "named": false },
    { "type": "number", "named": true },
    { "type": "regex", "named": true },
  ])
}

///|
test "upstream node schema named_precedences" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"named_precedences","rules":{"program":{"type":"REPEAT","content":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"expression_statement"},{"type":"SYMBOL","name":"declaration_statement"}]}},"expression_statement":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":";"}]},"declaration_statement":{"type":"SEQ","members":[{"type":"SYMBOL","name":"type"},{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":";"}]},"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"member_expression"},{"type":"SYMBOL","name":"binary_expression"},{"type":"SYMBOL","name":"identifier"}]},"member_expression":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"."},{"type":"SYMBOL","name":"identifier"}]},"binary_expression":{"type":"CHOICE","members":[{"type":"PREC_LEFT","value":"or","content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"||"},{"type":"SYMBOL","name":"expression"}]}},{"type":"PREC_LEFT","value":"and","content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"&&"},{"type":"SYMBOL","name":"expression"}]}}]},"type":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"nested_type"},{"type":"SYMBOL","name":"binary_type"},{"type":"SYMBOL","name":"identifier"}]},"nested_type":{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"STRING","value":"."},{"type":"SYMBOL","name":"identifier"}]},"binary_type":{"type":"CHOICE","members":[{"type":"PREC_LEFT","value":"type_union","content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"type"},{"type":"STRING","value":"||"},{"type":"SYMBOL","name":"type"}]}},{"type":"PREC_LEFT","value":"type_intersection","content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"type"},{"type":"STRING","value":"&&"},{"type":"SYMBOL","name":"type"}]}}]},"identifier":{"type":"PATTERN","value":"[a-z]\\w+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[["expression","type"],["expression","nested_type"]],"precedences":[[{"type":"SYMBOL","name":"member_expression"},{"type":"STRING","value":"and"},{"type":"STRING","value":"or"}],[{"type":"SYMBOL","name":"nested_type"},{"type":"STRING","value":"type_intersection"},{"type":"STRING","value":"type_union"}]],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "binary_expression",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [{ "type": "expression", "named": true }],
      },
    },
    {
      "type": "binary_type",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [{ "type": "type", "named": true }],
      },
    },
    {
      "type": "declaration_statement",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "expression", "named": true },
          { "type": "type", "named": true },
        ],
      },
    },
    {
      "type": "expression",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "binary_expression", "named": true },
          { "type": "identifier", "named": true },
          { "type": "member_expression", "named": true },
        ],
      },
    },
    {
      "type": "expression_statement",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "expression", "named": true }],
      },
    },
    {
      "type": "member_expression",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "expression", "named": true },
          { "type": "identifier", "named": true },
        ],
      },
    },
    {
      "type": "nested_type",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [{ "type": "identifier", "named": true }],
      },
    },
    {
      "type": "program",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [
          { "type": "declaration_statement", "named": true },
          { "type": "expression_statement", "named": true },
        ],
      },
    },
    {
      "type": "type",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "binary_type", "named": true },
          { "type": "identifier", "named": true },
          { "type": "nested_type", "named": true },
        ],
      },
    },
    { "type": "&&", "named": false },
    { "type": ".", "named": false },
    { "type": ";", "named": false },
    { "type": "identifier", "named": true },
    { "type": "||", "named": false },
  ])
}

///|
test "upstream node schema named_rule_aliased_as_anonymous" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"named_rule_aliased_as_anonymous","rules":{"a":{"type":"SEQ","members":[{"type":"ALIAS","content":{"type":"SYMBOL","name":"b"},"named":false,"value":"the-alias"},{"type":"SYMBOL","name":"c"},{"type":"SYMBOL","name":"b"}]},"b":{"type":"STRING","value":"B"},"c":{"type":"STRING","value":"C"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "a",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "b", "named": true },
          { "type": "c", "named": true },
        ],
      },
    },
    { "type": "b", "named": true },
    { "type": "c", "named": true },
    { "type": "the-alias", "named": false },
  ])
}

///|
test "upstream node schema nested_inlined_rules" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"nested_inlined_rules","rules":{"program":{"type":"REPEAT1","content":{"type":"SYMBOL","name":"top_level_item"}},"top_level_item":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"statement"},{"type":"STRING","value":"!"}]},"statement":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"expression_statement"},{"type":"SYMBOL","name":"return_statement"}]},"return_statement":{"type":"SEQ","members":[{"type":"STRING","value":"return"},{"type":"SYMBOL","name":"number"},{"type":"STRING","value":";"}]},"expression_statement":{"type":"SEQ","members":[{"type":"SYMBOL","name":"number"},{"type":"STRING","value":";"}]},"number":{"type":"PATTERN","value":"\\d+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":["top_level_item","statement"],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "expression_statement",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "number", "named": true }],
      },
    },
    {
      "type": "program",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [
          { "type": "expression_statement", "named": true },
          { "type": "return_statement", "named": true },
        ],
      },
    },
    {
      "type": "return_statement",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "number", "named": true }],
      },
    },
    { "type": "!", "named": false },
    { "type": ";", "named": false },
    { "type": "number", "named": true },
    { "type": "return", "named": false },
  ])
}

///|
test "upstream node schema next_sibling_from_zwt" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"next_sibling_from_zwt","rules":{"source":{"type":"SEQ","members":[{"type":"STRING","value":"a"},{"type":"SYMBOL","name":"_bc"},{"type":"STRING","value":"d"},{"type":"STRING","value":"e"},{"type":"STRING","value":"f"}]},"_bc":{"type":"SEQ","members":[{"type":"STRING","value":"b"},{"type":"STRING","value":"c"}]}},"extras":[{"type":"PATTERN","value":"\\s|\\\\\\r?\\n"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    { "type": "source", "named": true, "root": true, "fields": {} },
    { "type": "a", "named": false },
    { "type": "b", "named": false },
    { "type": "c", "named": false },
    { "type": "d", "named": false },
    { "type": "e", "named": false },
    { "type": "f", "named": false },
  ])
}

///|
test "upstream node schema precedence_on_single_child_negative" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"precedence_on_single_child_negative","rules":{"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"function_call"},{"type":"SYMBOL","name":"identifier"}]},"function_call":{"type":"PREC_RIGHT","value":-1,"content":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"expression"}]},{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"block"}]},{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"expression"},{"type":"SYMBOL","name":"block"}]}]}},"block":{"type":"SEQ","members":[{"type":"STRING","value":"{"},{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"}"}]},"identifier":{"type":"PATTERN","value":"[a-zA-Z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "block",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "expression", "named": true }],
      },
    },
    {
      "type": "expression",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "function_call", "named": true },
          { "type": "identifier", "named": true },
        ],
      },
    },
    {
      "type": "function_call",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "block", "named": true },
          { "type": "expression", "named": true },
          { "type": "identifier", "named": true },
        ],
      },
    },
    { "type": "identifier", "named": true },
    { "type": "{", "named": false },
    { "type": "}", "named": false },
  ])
}

///|
test "upstream node schema precedence_on_single_child_positive" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"precedence_on_single_child_positive","rules":{"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"function_call"},{"type":"SYMBOL","name":"identifier"}]},"function_call":{"type":"PREC_RIGHT","value":1,"content":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"expression"}]},{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"block"}]},{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"expression"},{"type":"SYMBOL","name":"block"}]}]}},"block":{"type":"SEQ","members":[{"type":"STRING","value":"{"},{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"}"}]},"identifier":{"type":"PATTERN","value":"[a-zA-X]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "block",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "expression", "named": true }],
      },
    },
    {
      "type": "expression",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "function_call", "named": true },
          { "type": "identifier", "named": true },
        ],
      },
    },
    {
      "type": "function_call",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "block", "named": true },
          { "type": "expression", "named": true },
          { "type": "identifier", "named": true },
        ],
      },
    },
    { "type": "identifier", "named": true },
    { "type": "{", "named": false },
    { "type": "}", "named": false },
  ])
}

///|
test "upstream node schema precedence_on_subsequence" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"precedence_on_subsequence","rules":{"expression":{"type":"PREC_LEFT","value":0,"content":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"function_call"},{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"scope_resolution"}]}},"function_call":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"expression"}]},{"type":"PREC","value":1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"block"}]}},{"type":"PREC","value":-1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"do_block"}]}},{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"PREC","value":1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"SYMBOL","name":"block"}]}}]},{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"PREC","value":-1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"SYMBOL","name":"do_block"}]}}]}]},"scope_resolution":{"type":"PREC_LEFT","value":1,"content":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"::"},{"type":"SYMBOL","name":"expression"}]},{"type":"SEQ","members":[{"type":"STRING","value":"::"},{"type":"SYMBOL","name":"expression"}]}]}},"block":{"type":"STRING","value":"{}"},"do_block":{"type":"STRING","value":"do end"},"identifier":{"type":"PATTERN","value":"[a-zA-Z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "expression",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "function_call", "named": true },
          { "type": "identifier", "named": true },
          { "type": "scope_resolution", "named": true },
        ],
      },
    },
    {
      "type": "function_call",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "block", "named": true },
          { "type": "do_block", "named": true },
          { "type": "expression", "named": true },
          { "type": "identifier", "named": true },
        ],
      },
    },
    {
      "type": "scope_resolution",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [{ "type": "expression", "named": true }],
      },
    },
    { "type": "::", "named": false },
    { "type": "block", "named": true },
    { "type": "do_block", "named": true },
    { "type": "identifier", "named": true },
  ])
}

///|
test "upstream node schema precedence_on_token" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"precedence_on_token","rules":{"program":{"type":"REPEAT","content":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"string"},{"type":"SYMBOL","name":"regex"},{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"slash"}]}},"comment":{"type":"TOKEN","content":{"type":"PREC","value":1,"content":{"type":"PATTERN","value":"\\/\\/.*|\\/\\*[^*]*\\*\\/"}}},"string":{"type":"SEQ","members":[{"type":"STRING","value":"\""},{"type":"REPEAT","content":{"type":"CHOICE","members":[{"type":"TOKEN","content":{"type":"PREC","value":2,"content":{"type":"PATTERN","value":"[^\\\"\\n\\\\]+"}}},{"type":"SYMBOL","name":"escape_sequence"}]}},{"type":"STRING","value":"\""}]},"escape_sequence":{"type":"PATTERN","value":"\\\\."},"regex":{"type":"PATTERN","value":"\\/[^\\/\\n]+\\/[a-z]*"},"identifier":{"type":"PATTERN","value":"[a-z]\\w*"},"slash":{"type":"STRING","value":"/"}},"extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"comment"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "program",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [
          { "type": "identifier", "named": true },
          { "type": "regex", "named": true },
          { "type": "slash", "named": true },
          { "type": "string", "named": true },
        ],
      },
    },
    {
      "type": "string",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [{ "type": "escape_sequence", "named": true }],
      },
    },
    { "type": "\"", "named": false },
    { "type": "comment", "named": true, "extra": true },
    { "type": "escape_sequence", "named": true },
    { "type": "identifier", "named": true },
    { "type": "regex", "named": true },
    { "type": "slash", "named": true },
  ])
}

///|
test "upstream node schema readme_grammar" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"readme_grammar","rules":{"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"sum"},{"type":"SYMBOL","name":"product"},{"type":"SYMBOL","name":"number"},{"type":"SYMBOL","name":"variable"},{"type":"SEQ","members":[{"type":"STRING","value":"("},{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":")"}]}]},"sum":{"type":"PREC_LEFT","value":1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"+"},{"type":"SYMBOL","name":"expression"}]}},"product":{"type":"PREC_LEFT","value":2,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"*"},{"type":"SYMBOL","name":"expression"}]}},"number":{"type":"PATTERN","value":"\\d+"},"comment":{"type":"PATTERN","value":"#.*"},"variable":{"type":"PATTERN","value":"(?i:[a-z])\\w*"}},"extras":[{"type":"PATTERN","value":"\\s"},{"type":"SYMBOL","name":"comment"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "expression",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "expression", "named": true },
          { "type": "number", "named": true },
          { "type": "product", "named": true },
          { "type": "sum", "named": true },
          { "type": "variable", "named": true },
        ],
      },
    },
    {
      "type": "product",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [{ "type": "expression", "named": true }],
      },
    },
    {
      "type": "sum",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [{ "type": "expression", "named": true }],
      },
    },
    { "type": "(", "named": false },
    { "type": ")", "named": false },
    { "type": "*", "named": false },
    { "type": "+", "named": false },
    { "type": "comment", "named": true, "extra": true },
    { "type": "number", "named": true },
    { "type": "variable", "named": true },
  ])
}

///|
test "upstream node schema reserved_words" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"reserved_words","word":"identifier","rules":{"program":{"type":"REPEAT","content":{"type":"SYMBOL","name":"_statement"}},"block":{"type":"SEQ","members":[{"type":"STRING","value":"{"},{"type":"REPEAT","content":{"type":"SYMBOL","name":"_statement"}},{"type":"STRING","value":"}"}]},"_statement":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"var_declaration"},{"type":"SYMBOL","name":"if_statement"},{"type":"SYMBOL","name":"while_statement"},{"type":"SYMBOL","name":"expression_statement"}]},"var_declaration":{"type":"SEQ","members":[{"type":"STRING","value":"var"},{"type":"SYMBOL","name":"identifier"},{"type":"STRING","value":"="},{"type":"SYMBOL","name":"_expression"},{"type":"STRING","value":";"}]},"if_statement":{"type":"SEQ","members":[{"type":"STRING","value":"if"},{"type":"SYMBOL","name":"parenthesized_expression"},{"type":"SYMBOL","name":"block"}]},"while_statement":{"type":"SEQ","members":[{"type":"STRING","value":"while"},{"type":"SYMBOL","name":"parenthesized_expression"},{"type":"SYMBOL","name":"block"}]},"expression_statement":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"STRING","value":";"}]},"_expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"parenthesized_expression"},{"type":"SYMBOL","name":"call_expression"},{"type":"SYMBOL","name":"member_expression"},{"type":"SYMBOL","name":"object"},{"type":"SYMBOL","name":"regex"}]},"parenthesized_expression":{"type":"SEQ","members":[{"type":"STRING","value":"("},{"type":"SYMBOL","name":"_expression"},{"type":"STRING","value":")"}]},"member_expression":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"STRING","value":"."},{"type":"SYMBOL","name":"identifier"}]},"call_expression":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"STRING","value":"("},{"type":"REPEAT","content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"_expression"},{"type":"STRING","value":","}]}},{"type":"STRING","value":")"}]},"object":{"type":"SEQ","members":[{"type":"STRING","value":"{"},{"type":"REPEAT","content":{"type":"SEQ","members":[{"type":"CHOICE","members":[{"type":"SYMBOL","name":"pair"},{"type":"SYMBOL","name":"getter"}]},{"type":"STRING","value":","}]}},{"type":"STRING","value":"}"}]},"regex":{"type":"SEQ","members":[{"type":"STRING","value":"/"},{"type":"SYMBOL","name":"regex_pattern"},{"type":"STRING","value":"/"}]},"regex_pattern":{"type":"TOKEN","content":{"type":"PREC","value":-1,"content":{"type":"PATTERN","value":"[^/\\n]+"}}},"pair":{"type":"SEQ","members":[{"type":"RESERVED","content":{"type":"SYMBOL","name":"identifier"},"context_name":"property"},{"type":"STRING","value":":"},{"type":"SYMBOL","name":"_expression"}]},"getter":{"type":"SEQ","members":[{"type":"STRING","value":"get"},{"type":"RESERVED","content":{"type":"SYMBOL","name":"identifier"},"context_name":"property"},{"type":"STRING","value":"("},{"type":"STRING","value":")"},{"type":"SYMBOL","name":"block"}]},"identifier":{"type":"PATTERN","value":"[a-z_]\\w*"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{"global":[{"type":"STRING","value":"if"},{"type":"STRING","value":"while"},{"type":"STRING","value":"var"}],"property":[{"type":"STRING","value":"var"}]}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "block",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [
          { "type": "expression_statement", "named": true },
          { "type": "if_statement", "named": true },
          { "type": "var_declaration", "named": true },
          { "type": "while_statement", "named": true },
        ],
      },
    },
    {
      "type": "call_expression",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "call_expression", "named": true },
          { "type": "identifier", "named": true },
          { "type": "member_expression", "named": true },
          { "type": "object", "named": true },
          { "type": "parenthesized_expression", "named": true },
          { "type": "regex", "named": true },
        ],
      },
    },
    {
      "type": "expression_statement",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "call_expression", "named": true },
          { "type": "identifier", "named": true },
          { "type": "member_expression", "named": true },
          { "type": "object", "named": true },
          { "type": "parenthesized_expression", "named": true },
          { "type": "regex", "named": true },
        ],
      },
    },
    {
      "type": "getter",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "block", "named": true },
          { "type": "identifier", "named": true },
        ],
      },
    },
    {
      "type": "if_statement",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "block", "named": true },
          { "type": "parenthesized_expression", "named": true },
        ],
      },
    },
    {
      "type": "member_expression",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "call_expression", "named": true },
          { "type": "identifier", "named": true },
          { "type": "member_expression", "named": true },
          { "type": "object", "named": true },
          { "type": "parenthesized_expression", "named": true },
          { "type": "regex", "named": true },
        ],
      },
    },
    {
      "type": "object",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [
          { "type": "getter", "named": true },
          { "type": "pair", "named": true },
        ],
      },
    },
    {
      "type": "pair",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "call_expression", "named": true },
          { "type": "identifier", "named": true },
          { "type": "member_expression", "named": true },
          { "type": "object", "named": true },
          { "type": "parenthesized_expression", "named": true },
          { "type": "regex", "named": true },
        ],
      },
    },
    {
      "type": "parenthesized_expression",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [
          { "type": "call_expression", "named": true },
          { "type": "identifier", "named": true },
          { "type": "member_expression", "named": true },
          { "type": "object", "named": true },
          { "type": "parenthesized_expression", "named": true },
          { "type": "regex", "named": true },
        ],
      },
    },
    {
      "type": "program",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [
          { "type": "expression_statement", "named": true },
          { "type": "if_statement", "named": true },
          { "type": "var_declaration", "named": true },
          { "type": "while_statement", "named": true },
        ],
      },
    },
    {
      "type": "regex",
      "named": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "regex_pattern", "named": true }],
      },
    },
    {
      "type": "var_declaration",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "call_expression", "named": true },
          { "type": "identifier", "named": true },
          { "type": "member_expression", "named": true },
          { "type": "object", "named": true },
          { "type": "parenthesized_expression", "named": true },
          { "type": "regex", "named": true },
        ],
      },
    },
    {
      "type": "while_statement",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "block", "named": true },
          { "type": "parenthesized_expression", "named": true },
        ],
      },
    },
    { "type": "(", "named": false },
    { "type": ")", "named": false },
    { "type": ",", "named": false },
    { "type": ".", "named": false },
    { "type": "/", "named": false },
    { "type": ":", "named": false },
    { "type": ";", "named": false },
    { "type": "=", "named": false },
    { "type": "get", "named": false },
    { "type": "identifier", "named": true },
    { "type": "if", "named": false },
    { "type": "regex_pattern", "named": true },
    { "type": "var", "named": false },
    { "type": "while", "named": false },
    { "type": "{", "named": false },
    { "type": "}", "named": false },
  ])
}

///|
test "upstream node schema start_rule_is_blank" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"start_rule_is_blank","rules":{"first_rule":{"type":"BLANK"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    { "type": "first_rule", "named": true, "root": true, "fields": {} },
  ])
}

///|
test "upstream node schema start_rule_is_token" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"start_rule_is_token","rules":{"first_rule":{"type":"STRING","value":"the-value"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    { "type": "first_rule", "named": true, "root": true, "fields": {} },
    { "type": "the-value", "named": false },
  ])
}

///|
test "upstream node schema unicode_classes" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"unicode_classes","rules":{"program":{"type":"REPEAT","content":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"lower"},{"type":"SYMBOL","name":"upper"},{"type":"SYMBOL","name":"math_sym"},{"type":"SYMBOL","name":"letter_number"}]}},"lower":{"type":"PATTERN","value":"\\p{Ll}\\p{L}*"},"upper":{"type":"PATTERN","value":"\\p{Lu}\\p{L}*"},"math_sym":{"type":"PATTERN","value":"\\p{Sm}+"},"letter_number":{"type":"PATTERN","value":"\\p{Letter_Number}"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "program",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [
          { "type": "letter_number", "named": true },
          { "type": "lower", "named": true },
          { "type": "math_sym", "named": true },
          { "type": "upper", "named": true },
        ],
      },
    },
    { "type": "letter_number", "named": true },
    { "type": "lower", "named": true },
    { "type": "math_sym", "named": true },
    { "type": "upper", "named": true },
  ])
}

///|
test "upstream node schema unused_rules" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"unused_rules","rules":{"a":{"type":"SEQ","members":[{"type":"SYMBOL","name":"d"},{"type":"SYMBOL","name":"h"}]},"b":{"type":"STRING","value":"B"},"c":{"type":"STRING","value":"C"},"d":{"type":"SEQ","members":[{"type":"SYMBOL","name":"e"},{"type":"SYMBOL","name":"f"}]},"e":{"type":"STRING","value":"E"},"f":{"type":"STRING","value":"F"},"g":{"type":"STRING","value":"G"},"h":{"type":"SEQ","members":[{"type":"SYMBOL","name":"i"},{"type":"SYMBOL","name":"j"}]},"i":{"type":"STRING","value":"I"},"j":{"type":"STRING","value":"J"},"k":{"type":"STRING","value":"K"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "a",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "d", "named": true },
          { "type": "h", "named": true },
        ],
      },
    },
    {
      "type": "d",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "e", "named": true },
          { "type": "f", "named": true },
        ],
      },
    },
    {
      "type": "h",
      "named": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": true,
        "types": [
          { "type": "i", "named": true },
          { "type": "j", "named": true },
        ],
      },
    },
    { "type": "e", "named": true },
    { "type": "f", "named": true },
    { "type": "i", "named": true },
    { "type": "j", "named": true },
  ])
}

///|
test "upstream node schema utf16_surrogate_oob" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"utf16_surrogate_oob","rules":{"program":{"type":"REPEAT","content":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"surrogate"},{"type":"SYMBOL","name":"supplementary"}]}}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"surrogate"},{"type":"SYMBOL","name":"supplementary"}],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "program",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": true,
        "required": false,
        "types": [
          { "type": "supplementary", "named": true },
          { "type": "surrogate", "named": true },
        ],
      },
    },
    { "type": "supplementary", "named": true },
    { "type": "surrogate", "named": true },
  ])
}

///|
test "upstream node schema wasm_realloc_clobber_region" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"wasm_realloc_clobber_region","rules":{"document":{"type":"SEQ","members":[{"type":"SYMBOL","name":"zero_width"},{"type":"STRING","value":"hello"}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"zero_width"}],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "document",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "zero_width", "named": true }],
      },
    },
    { "type": "hello", "named": false },
    { "type": "zero_width", "named": true },
  ])
}

///|
test "upstream node schema wasm_realloc_overflow_heap" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"wasm_realloc_overflow_heap","rules":{"document":{"type":"SEQ","members":[{"type":"SYMBOL","name":"zero_width"},{"type":"STRING","value":"hello"}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[{"type":"SYMBOL","name":"zero_width"}],"inline":[],"supertypes":[],"reserved":{}}
  let language = @generate.generate(@grammar.Grammar::parse(grammar))
  assert_eq(language.node_types(), [
    {
      "type": "document",
      "named": true,
      "root": true,
      "fields": {},
      "children": {
        "multiple": false,
        "required": true,
        "types": [{ "type": "zero_width", "named": true }],
      },
    },
    { "type": "hello", "named": false },
    { "type": "zero_width", "named": true },
  ])
}

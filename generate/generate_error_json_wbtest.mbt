// Expected values: `tree-sitter generate --json-summary` of the pinned
// upstream (its `error` member).

///|
fn error_json(grammar : String) -> String {
  try generate_from_grammar_json(grammar) catch {
    e =>
      match generate_error_json(e) {
        Some(json) => json.stringify()
        None => "not a generate error: \{e}"
      }
  } noraise {
    _ => "ok"
  }
}

///|
test "generate_error_json 1" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"associativity_missing","rules":{"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"math_operation"},{"type":"SYMBOL","name":"identifier"}]},"math_operation":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"+"},{"type":"SYMBOL","name":"expression"}]},"identifier":{"type":"PATTERN","value":"[a-z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let expected =
    #|{"BuildTables":{"Conflict":{"symbol_sequence":["expression","'+'","expression"],"conflicting_lookahead":"'+'","possible_interpretations":[{"preceding_symbols":["expression","'+'"],"variable_name":"math_operation","production_step_symbols":["expression","'+'","expression"],"step_index":1,"done":false,"conflicting_lookahead":"'+'","precedence":null,"associativity":null,"requires_eof_lookahead":false},{"preceding_symbols":[],"variable_name":"math_operation","production_step_symbols":["expression","'+'","expression"],"step_index":3,"done":true,"conflicting_lookahead":"'+'","precedence":null,"associativity":null,"requires_eof_lookahead":false}],"possible_resolutions":[{"Associativity":{"symbols":["math_operation"]}},{"AddConflict":{"symbols":["math_operation"]}}]}}}
  assert_eq(error_json(grammar), @json.parse(expected).stringify())
}

///|
test "generate_error_json 2" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"conflicting_precedence","rules":{"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"sum"},{"type":"SYMBOL","name":"product"},{"type":"SYMBOL","name":"other_thing"}]},"sum":{"type":"PREC_LEFT","value":0,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"+"},{"type":"SYMBOL","name":"expression"}]}},"product":{"type":"PREC_LEFT","value":1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"*"},{"type":"SYMBOL","name":"expression"}]}},"other_thing":{"type":"PREC_LEFT","value":-1,"content":{"type":"SEQ","members":[{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"*"},{"type":"STRING","value":"*"}]}},"identifier":{"type":"PATTERN","value":"[a-zA-Z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let expected =
    #|{"BuildTables":{"Conflict":{"symbol_sequence":["expression","'+'","expression"],"conflicting_lookahead":"'*'","possible_interpretations":[{"preceding_symbols":["expression","'+'"],"variable_name":"product","production_step_symbols":["expression","'*'","expression"],"step_index":1,"done":false,"conflicting_lookahead":"'*'","precedence":"1","associativity":"Left","requires_eof_lookahead":false},{"preceding_symbols":["expression","'+'"],"variable_name":"other_thing","production_step_symbols":["expression","'*'","'*'"],"step_index":1,"done":false,"conflicting_lookahead":"'*'","precedence":"-1","associativity":"Left","requires_eof_lookahead":false},{"preceding_symbols":[],"variable_name":"sum","production_step_symbols":["expression","'+'","expression"],"step_index":3,"done":true,"conflicting_lookahead":"'*'","precedence":"0","associativity":"Left","requires_eof_lookahead":false}],"possible_resolutions":[{"Precedence":{"symbols":["product","other_thing"]}},{"Precedence":{"symbols":["sum"]}},{"AddConflict":{"symbols":["sum","product","other_thing"]}}]}}}
  assert_eq(error_json(grammar), @json.parse(expected).stringify())
}

///|
test "generate_error_json 3" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"eof_misplaced","rules":{"source_file":{"type":"SEQ","members":[{"type":"EOF"},{"type":"STRING","value":"after"}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let expected =
    #|{"Prepare":{"FlattenGrammar":{"NoReachableProductions":"source_file"}}}
  assert_eq(error_json(grammar), @json.parse(expected).stringify())
}

///|
test "generate_error_json 4" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"epsilon_rules","rules":{"rule_1":{"type":"SYMBOL","name":"rule_2"},"rule_2":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"rule_3"},{"type":"BLANK"}]},"rule_3":{"type":"STRING","value":"x"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let expected =
    #|{"Prepare":{"FlattenGrammar":{"EmptyString":"rule_2"}}}
  assert_eq(error_json(grammar), @json.parse(expected).stringify())
}

///|
test "generate_error_json 5" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"indirect_recursive_in_single_symbol_transitions","rules":{"source_file":{"type":"REPEAT","content":{"type":"SYMBOL","name":"_statement"}},"_statement":{"type":"SEQ","members":[{"type":"SYMBOL","name":"initialization_part"},{"type":"SYMBOL","name":"type_expression"}]},"type_expression":{"type":"CHOICE","members":[{"type":"STRING","value":"int"},{"type":"SYMBOL","name":"_expression"}]},"initialization_part":{"type":"SEQ","members":[{"type":"STRING","value":"="},{"type":"SYMBOL","name":"_expression"}]},"_expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"identifier_expression"},{"type":"SYMBOL","name":"type_expression"}]},"identifier_expression":{"type":"CHOICE","members":[{"type":"PATTERN","value":"[a-zA-Z_][a-zA-Z0-9_]*"},{"type":"SYMBOL","name":"type_expression"}]}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let expected =
    #|{"Prepare":{"ValidateIndirectRecursion":["type_expression","_expression","type_expression"]}}
  assert_eq(error_json(grammar), @json.parse(expected).stringify())
}

///|
test "generate_error_json 6" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"invisible_start_rule","rules":{"_value":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"a"},{"type":"SYMBOL","name":"b"}]},"a":{"type":"STRING","value":"a"},"b":{"type":"STRING","value":"b"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let expected =
    #|{"Prepare":{"InternSymbols":"HiddenStartRule"}}
  assert_eq(error_json(grammar), @json.parse(expected).stringify())
}

///|
test "generate_error_json 7" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"terminal_supertype","rules":{"source_file":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"B"},{"type":"SYMBOL","name":"A"}]},"lineComment":{"type":"PATTERN","value":";;.*"},"lineComment2":{"type":"PATTERN","value":"##.*"},"A":{"type":"PATTERN","value":"xyz"},"C":{"type":"STRING","value":"xyz"},"B":{"type":"SEQ","members":[{"type":"STRING","value":"abc"},{"type":"SYMBOL","name":"C"}]}},"extras":[{"type":"SYMBOL","name":"lineComment"},{"type":"SYMBOL","name":"lineComment2"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":["A"],"reserved":{}}
  let expected =
    #|{"Prepare":{"ExtractTokens":{"SupertypeTerminal":"A"}}}
  assert_eq(error_json(grammar), @json.parse(expected).stringify())
}

///|
test "generate_error_json 8" {
  let grammar =
    #|{"$schema":"https://tree-sitter.github.io/tree-sitter/assets/schemas/grammar.schema.json","name":"precedence_on_single_child_missing","rules":{"expression":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"function_call"},{"type":"SYMBOL","name":"identifier"}]},"function_call":{"type":"PREC_RIGHT","value":0,"content":{"type":"CHOICE","members":[{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"expression"}]},{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"block"}]},{"type":"SEQ","members":[{"type":"SYMBOL","name":"identifier"},{"type":"SYMBOL","name":"expression"},{"type":"SYMBOL","name":"block"}]}]}},"block":{"type":"SEQ","members":[{"type":"STRING","value":"{"},{"type":"SYMBOL","name":"expression"},{"type":"STRING","value":"}"}]},"identifier":{"type":"PATTERN","value":"[a-zA-Z]+"}},"extras":[{"type":"PATTERN","value":"\\s"}],"conflicts":[],"precedences":[],"externals":[],"inline":[],"supertypes":[],"reserved":{}}
  let expected =
    #|{"BuildTables":{"Conflict":{"symbol_sequence":["identifier","identifier"],"conflicting_lookahead":"'{'","possible_interpretations":[{"preceding_symbols":["identifier"],"variable_name":"expression","production_step_symbols":["identifier"],"step_index":1,"done":true,"conflicting_lookahead":"'{'","precedence":null,"associativity":null,"requires_eof_lookahead":false},{"preceding_symbols":["identifier"],"variable_name":"function_call","production_step_symbols":["identifier","block"],"step_index":1,"done":false,"conflicting_lookahead":"'{'","precedence":"0","associativity":"Right","requires_eof_lookahead":false}],"possible_resolutions":[{"Precedence":{"symbols":["function_call"]}},{"Precedence":{"symbols":["expression"]}},{"Associativity":{"symbols":["expression"]}},{"AddConflict":{"symbols":["expression","function_call"]}}]}}}
  assert_eq(error_json(grammar), @json.parse(expected).stringify())
}

///|
test "generate_error_json 9" {
  let grammar =
    #|{"name":"a","rules":{"s":{"type":"BLANK"}},"extras":[{"type":"STRING","value":""}]}
  let expected =
    #|{"ParseGrammar":"InvalidExtra"}
  assert_eq(error_json(grammar), @json.parse(expected).stringify())
}

///|
test "generate_error_json 10" {
  let grammar =
    #|{"name":"a","rules":{"s":{"type":"PATTERN","value":"[a"}}}
  let expected =
    #|{"Prepare":{"ExpandTokens":{"Processing":{"rule":"s_token1","error":{"Parse":{"pattern":"[a","kind":"ClassUnclosed","span":{"start":0,"end":1},"aux_span":null}}}}}}
  assert_eq(error_json(grammar), @json.parse(expected).stringify())
}

///|
test "generate_error_json 11" {
  let grammar =
    #|{"name":"a","rules":{"s":{"type":"TOKEN","content":{"type":"SYMBOL","name":"b"}}}}
  let expected =
    #|{"ParseGrammar":{"UnexpectedRule":"b"}}
  assert_eq(error_json(grammar), @json.parse(expected).stringify())
}

///|
test "generate_error_json 12" {
  let grammar =
    #|{"name":5}
  let expected =
    #|{"ParseGrammar":{"Serialization":"invalid type: integer `5`, expected a string at line 1 column 9"}}
  assert_eq(error_json(grammar), @json.parse(expected).stringify())
}

///|
test "generate_error_json 13" {
  let grammar =
    #|{"name":"a","rules":{"s":{"type":"PATTERN","value":"(?=a)"}}}
  let expected =
    #|{"Prepare":{"ExpandTokens":{"Processing":{"rule":"s_token1","error":{"Parse":{"pattern":"(?=a)","kind":"UnsupportedLookAround","span":{"start":0,"end":3},"aux_span":null}}}}}}
  assert_eq(error_json(grammar), @json.parse(expected).stringify())
}

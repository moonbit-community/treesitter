///|
test "generate_node_types_for_input_grammar keeps preparation diagnostics" {
  let diagnostics = []
  let grammar =
    #|{"name":"a","rules":{"s":{"type":"SYMBOL","name":"_v2"},"_v2":{"type":"STRING","value":"x"}},
    #| "inline":["_v2"],"supertypes":["_v2"]}
  let input_grammar = parse_grammar(grammar, diagnostics)
  ignore(generate_node_types_for_input_grammar(input_grammar, diagnostics))
  assert_eq(diagnostics, [SupertypeInlined(name="_v2")])
}

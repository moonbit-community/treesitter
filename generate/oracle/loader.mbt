// Development-only differential oracle for the generator port.
//
// Loads the prepared-grammar JSON written by the scratch upstream harness
// (`tools/oracle/node_types_oracle.sh`) and dumps this port's results in the
// same canonical shape, so both sides can be compared textually.

///|
suberror OracleError {
  OracleError(String)
}

///|
/// The inputs of `get_variable_info` / `generate_node_types_json`.
pub(all) struct PreparedInputs {
  syntax_grammar : @generate.SyntaxGrammar
  lexical_grammar : @generate.LexicalGrammar
  default_aliases : @generate.AliasMap
  inlines : @generate.InlinedProductionMap
  str_pool : @generate.StrPool
}

///|
fn as_array(json : Json) -> Array[Json] raise OracleError {
  guard json is Array(items) else { raise OracleError("expected array") }
  items
}

///|
fn as_int(json : Json) -> Int32 raise OracleError {
  guard json is Number(n, ..) else { raise OracleError("expected number") }
  n.to_int()
}

///|
fn as_bool(json : Json) -> Bool raise OracleError {
  match json {
    True => true
    False => false
    _ => raise OracleError("expected bool")
  }
}

///|
fn as_string(json : Json) -> String raise OracleError {
  guard json is String(s) else { raise OracleError("expected string") }
  s
}

///|
fn field(json : Json, name : String) -> Json raise OracleError {
  guard json is Object(map) && map.get(name) is Some(value) else {
    raise OracleError("missing field \{name}")
  }
  value
}

///|
fn str_id(json : Json) -> @generate.StrId raise OracleError {
  @generate.StrId(as_int(json))
}

///|
fn variable_type(json : Json) -> @generate.VariableType raise OracleError {
  match as_string(json) {
    "Hidden" => Hidden
    "Auxiliary" => Auxiliary
    "Anonymous" => Anonymous
    "Named" => Named
    other => raise OracleError("bad variable type \{other}")
  }
}

///|
fn symbol(json : Json) -> @generate.Symbol raise OracleError {
  let parts = as_array(json)
  let kind : @generate.SymbolType = match as_string(parts[0]) {
    "External" => External
    "End" => End
    "EndOfNonTerminalExtra" => EndOfNonTerminalExtra
    "Terminal" => Terminal
    "NonTerminal" => NonTerminal
    other => raise OracleError("bad symbol type \{other}")
  }
  { kind, index: as_int(parts[1]), }
}

///|
fn symbol_to_json(symbol : @generate.Symbol) -> Json {
  let kind = match symbol.kind {
    External => "External"
    End => "End"
    EndOfNonTerminalExtra => "EndOfNonTerminalExtra"
    Terminal => "Terminal"
    NonTerminal => "NonTerminal"
  }
  let index = match symbol.kind {
    External | Terminal | NonTerminal => symbol.index
    End | EndOfNonTerminalExtra => 0
  }
  [Json(kind), Json(index)]
}

///|
fn symbols(json : Json) -> Array[@generate.Symbol] raise OracleError {
  as_array(json).map(symbol)
}

///|
fn[T] optional(
  json : Json,
  f : (Json) -> T raise OracleError,
) -> T? raise OracleError {
  if json is Null {
    None
  } else {
    Some(f(json))
  }
}

///|
/// Parse the `*.input.json` written by the upstream harness.
pub fn load_prepared_inputs(text : String) -> PreparedInputs raise {
  let json = @json.parse(text)
  let str_pool = @generate.StrPool::new()
  for i, s in as_array(field(json, "strings")) {
    let id = str_pool.intern(as_string(s))
    if id.raw() != i + 1 {
      raise OracleError("string pool id mismatch at \{i}")
    }
  }
  let variables = as_array(field(json, "variables")).map(v => {
    let parts = as_array(v)
    (
      { name: str_id(parts[0]), kind: variable_type(parts[1]), } :
      @generate.SyntaxVariable)
  })
  let external_tokens = as_array(field(json, "external_tokens")).map(v => {
    let parts = as_array(v)
    (
      {
        name: str_id(parts[0]),
        kind: variable_type(parts[1]),
        corresponding_internal_token: optional(parts[2], symbol),
      } : @generate.ExternalToken)
  })
  let steps = as_array(field(json, "steps")).map(v => {
    let parts = as_array(v)
    let step_alias = optional(parts[1], a => {
      let a = as_array(a)
      ({ value: str_id(a[0]), is_named: as_bool(a[1]), } : @generate.Alias)
    })
    @generate.ProductionStep::pack(
      symbol(parts[0]),
      NoPrecedence,
      None,
      step_alias,
      optional(parts[2], str_id),
      0,
    )
  })
  let productions = as_array(field(json, "productions")).map(v => {
    let parts = as_array(v)
    (
      {
        steps_start: as_int(parts[0]),
        steps_len: as_int(parts[1]),
        dynamic_precedence: as_int(parts[2]),
        requires_eof_lookahead: as_bool(parts[3]),
      } : @generate.Production)
  })
  let var_prods = as_array(field(json, "var_prods")).map(v => {
    let parts = as_array(v)
    (as_int(parts[0]), as_int(parts[1]))
  })
  let syntax_grammar : @generate.SyntaxGrammar = {
    variables,
    extra_symbols: symbols(field(json, "extra_symbols")),
    expected_conflicts: [],
    external_tokens,
    supertype_symbols: symbols(field(json, "supertype_symbols")),
    variables_to_inline: symbols(field(json, "variables_to_inline")),
    word_token: None,
    precedence_orderings: [],
    reserved_word_sets: [],
    steps,
    productions,
    var_prods,
  }
  let lexical_grammar = @generate.LexicalGrammar::new()
  for v in as_array(field(json, "lexical_variables")) {
    let parts = as_array(v)
    lexical_grammar.variables.push({
      name: str_id(parts[0]),
      kind: variable_type(parts[1]),
      implicit_precedence: 0,
      start_state: 0,
    })
  }
  let default_aliases : @generate.AliasMap = @sorted_map.SortedMap([])
  for v in as_array(field(json, "default_aliases")) {
    let parts = as_array(v)
    default_aliases[symbol(parts[0])] = {
      value: str_id(parts[1]),
      is_named: as_bool(parts[2]),
    }
  }
  let inlines = @generate.InlinedProductionMap::new()
  for v in as_array(field(json, "fully_inlined")) {
    let parts = as_array(v)
    inlines.fully_inlined[as_int(parts[0])] = {
      start: as_int(parts[1]),
      end: as_int(parts[2]),
    }
  }
  for id in as_array(field(json, "fully_inlined_ids")) {
    inlines.fully_inlined_ids.push(as_int(id))
  }
  { syntax_grammar, lexical_grammar, default_aliases, inlines, str_pool, }
}

///|
fn child_type_to_json(t : @generate.ChildType) -> Json {
  match t {
    Normal(s) => [Json("Normal"), symbol_to_json(s)]
    Aliased(a) => [Json("Aliased"), Json(a.value.raw()), Json(a.is_named)]
  }
}

///|
fn field_info_to_json(f : @generate.FieldInfo) -> Json {
  {
    "quantity": [
      Json(f.quantity.exists),
      Json(f.quantity.required),
      Json(f.quantity.multiple),
    ],
    "types": Json(f.types.map(child_type_to_json)),
  }
}

///|
/// The same canonical dump as the upstream harness's `dump_variable_info`
/// (fields sorted by id, so the hash map order is irrelevant).
pub fn dump_variable_info(info : Array[@generate.VariableInfo]) -> Json {
  let dumped : Array[Json] = info.map(v => {
    let fields = v.fields.to_array()
    fields.sort_by_key(entry => entry.0.raw())
    {
      "fields": Json(
        fields.map(entry => [Json(entry.0.raw()), field_info_to_json(entry.1)]),
      ),
      "children": field_info_to_json(v.children),
      "children_without_fields": field_info_to_json(v.children_without_fields),
      "has_multi_step_production": Json(v.has_multi_step_production),
    }
  })
  Json(dumped)
}

///|
/// Run the port on loaded inputs and dump everything the harness dumps.
pub fn dump_results(inputs : PreparedInputs) -> Json {
  let info = @generate.get_variable_info(
    inputs.syntax_grammar,
    inputs.lexical_grammar,
    inputs.default_aliases,
    inputs.inlines,
    inputs.str_pool,
  ) catch {
    e => return { "variable_info_error": Json(e.to_string()) }
  }
  let map = @generate.get_supertype_symbol_map(
    inputs.syntax_grammar,
    inputs.default_aliases,
    info,
    inputs.inlines,
  )
  let node_types : Json = try
    @generate.generate_node_types_json(
      inputs.syntax_grammar,
      inputs.lexical_grammar,
      inputs.default_aliases,
      info,
      inputs.inlines,
      inputs.str_pool,
    )
  catch {
    e => { "error": Json(e.to_string()) }
  } noraise {
    text => { "ok": Json(text) }
  }
  let supertype_symbol_map : Array[Json] = map
    .to_array()
    .map(entry => {
      [symbol_to_json(entry.0), Json(entry.1.map(child_type_to_json))]
    })
  {
    "variable_info": dump_variable_info(info),
    "supertype_symbol_map": Json(supertype_symbol_map),
    "node_types": node_types,
  }
}

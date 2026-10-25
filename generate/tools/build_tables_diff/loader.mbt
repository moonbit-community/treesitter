// Loader for the `build_tables` inputs serialized by the upstream harness
// (`_build/tsgen/src/harness.rs`, see tools/oracle/build_tables_ref.sh).

///|
pub(all) struct BuildTablesInputs {
  syntax_grammar : @generate.SyntaxGrammar
  lexical_grammar : @generate.LexicalGrammar
  inlines : @generate.InlinedProductionMap
  simple_aliases : @generate.AliasMap
  variable_info : Array[@generate.VariableInfo]
  str_pool : @generate.StrPool
}

///|
suberror LoadError {
  LoadError(String)
}

///|
fn as_int(json : Json) -> Int32 raise LoadError {
  match json {
    Number(n, ..) => n.to_int()
    _ => raise LoadError("expected a number, got \{json.stringify()}")
  }
}

///|
fn as_array(json : Json) -> Array[Json] raise LoadError {
  match json {
    Array(a) => a
    _ => raise LoadError("expected an array, got \{json.stringify()}")
  }
}

///|
fn field(json : Json, name : String) -> Json raise LoadError {
  match json {
    Object(map) =>
      match map.get(name) {
        Some(value) => value
        None => raise LoadError("missing field \{name}")
      }
    _ => raise LoadError("expected an object")
  }
}

///|
fn str_id(json : Json) -> @generate.StrId raise LoadError {
  @generate.StrId(as_int(json))
}

///|
fn symbol(json : Json) -> @generate.Symbol raise LoadError {
  let a = as_array(json)
  let index = as_int(a[1])
  match as_int(a[0]) {
    0 => @generate.Symbol::external(index)
    1 => @generate.symbol_end
    2 => @generate.symbol_end_of_nonterminal_extra
    3 => @generate.Symbol::terminal(index)
    _ => @generate.Symbol::non_terminal(index)
  }
}

///|
fn symbols(json : Json) -> Array[@generate.Symbol] raise LoadError {
  as_array(json).map(symbol)
}

///|
fn variable_type(json : Json) -> @generate.VariableType raise LoadError {
  match as_int(json) {
    0 => Hidden
    1 => Auxiliary
    2 => Anonymous
    _ => Named
  }
}

///|
fn char_set(json : Json) -> @generate.CharacterSet raise LoadError {
  let a = as_array(json)
  let result = @generate.CharacterSet::empty()
  for i = 0; i < a.length(); i = i + 2 {
    result.add_range_in_place(as_int(a[i]), as_int(a[i + 1]) - 1)
  }
  result
}

///|
fn opt_symbol(json : Json) -> @generate.Symbol? raise LoadError {
  match json {
    Null => None
    _ => Some(symbol(json))
  }
}

///|
pub fn load_inputs(text : String) -> BuildTablesInputs raise {
  let json = @json.parse(text)
  let str_pool = @generate.StrPool::new()
  for s in as_array(field(json, "strings")) {
    match s {
      String(s) => ignore(str_pool.intern(s))
      _ => raise LoadError("expected a string")
    }
  }
  let syntax = field(json, "syntax")
  let steps = as_array(field(syntax, "steps")).map(step => {
    let a = as_array(step)
    let symbol = symbol(Json::array([a[0], a[1]]))
    let prec_value = as_int(a[3])
    let precedence : @generate.Precedence = match as_int(a[2]) {
      0 => NoPrecedence
      1 => Integer(prec_value)
      _ => Name(@generate.StrId(prec_value))
    }
    let associativity : @generate.Associativity? = match as_int(a[4]) {
      0 => None
      1 => Some(Left)
      _ => Some(Right)
    }
    let alias_value = as_int(a[5])
    let step_alias : @generate.Alias? = if alias_value == 0 {
      None
    } else {
      Some({ value: @generate.StrId(alias_value), is_named: as_int(a[6]) != 0, })
    }
    let field_value = as_int(a[7])
    let field = if field_value == 0 {
      None
    } else {
      Some(@generate.StrId(field_value))
    }
    @generate.ProductionStep::pack(
      symbol,
      precedence,
      associativity,
      step_alias,
      field,
      as_int(a[8]),
    )
  })
  let syntax_grammar : @generate.SyntaxGrammar = {
    variables: as_array(field(syntax, "variables")).map(v => {
      let a = as_array(v)
      { name: str_id(a[0]), kind: variable_type(a[1]), }
    }),
    extra_symbols: symbols(field(syntax, "extra_symbols")),
    expected_conflicts: as_array(field(syntax, "expected_conflicts")).map(
      symbols,
    ),
    external_tokens: as_array(field(syntax, "external_tokens")).map(t => {
      let a = as_array(t)
      {
        name: str_id(a[0]),
        kind: variable_type(a[1]),
        corresponding_internal_token: opt_symbol(a[2]),
      }
    }),
    supertype_symbols: symbols(field(syntax, "supertype_symbols")),
    variables_to_inline: symbols(field(syntax, "variables_to_inline")),
    word_token: opt_symbol(field(syntax, "word_token")),
    precedence_orderings: as_array(field(syntax, "precedence_orderings")).map(list => {
      as_array(list).map(entry => {
        let a = as_array(entry)
        let id = str_id(a[1])
        if as_int(a[0]) == 0 {
          @generate.PrecedenceEntry::Name(id)
        } else {
          @generate.PrecedenceEntry::Symbol(id)
        }
      })
    }),
    reserved_word_sets: as_array(field(syntax, "reserved_word_sets")).map(set => {
      @generate.TokenSet::from_array(symbols(set))
    }),
    steps,
    productions: as_array(field(syntax, "productions")).map(p => {
      let a = as_array(p)
      {
        steps_start: as_int(a[0]),
        steps_len: as_int(a[1]),
        dynamic_precedence: as_int(a[2]),
        requires_eof_lookahead: as_int(a[3]) != 0,
      }
    }),
    var_prods: as_array(field(syntax, "var_prods")).map(p => {
      let a = as_array(p)
      (as_int(a[0]), as_int(a[1]))
    }),
  }
  let lexical = field(json, "lexical")
  let lexical_grammar : @generate.LexicalGrammar = {
    nfa: {
      states: as_array(field(lexical, "nfa")).map(s => {
        let a = as_array(s)
        match as_int(a[0]) {
          0 =>
            @generate.NfaState::Advance(
              chars=char_set(a[1]),
              state_id=as_int(a[2]),
              is_sep=as_int(a[3]) != 0,
              precedence=as_int(a[4]),
            )
          1 => @generate.NfaState::Split(as_int(a[1]), as_int(a[2]))
          _ =>
            @generate.NfaState::Accept(
              variable_index=as_int(a[1]),
              precedence=as_int(a[2]),
            )
        }
      }),
    },
    variables: as_array(field(lexical, "variables")).map(v => {
      let a = as_array(v)
      {
        name: str_id(a[0]),
        kind: variable_type(a[1]),
        implicit_precedence: as_int(a[2]),
        start_state: as_int(a[3]),
      }
    }),
  }
  let inlines = @generate.InlinedProductionMap::new()
  for entry in as_array(field(json, "inlines")) {
    let a = as_array(entry)
    inlines.map[(as_int(a[0]), as_int(a[1]))] = as_array(a[2]).map(as_int)
  }
  let simple_aliases : @generate.AliasMap = @sorted_map.SortedMap([])
  for entry in as_array(field(json, "aliases")) {
    let a = as_array(entry)
    simple_aliases[symbol(a[0])] = {
      value: str_id(a[1]),
      is_named: as_int(a[2]) != 0,
    }
  }
  let variable_info = as_array(field(json, "variable_info_fields")).map(keys => {
    let empty_field_info = () => @generate.FieldInfo::{
      quantity: { exists: false, required: false, multiple: false, },
      types: [],
    }
    let fields = Map([])
    for key in as_array(keys) {
      fields[str_id(key)] = empty_field_info()
    }
    @generate.VariableInfo::{
      fields,
      children: empty_field_info(),
      children_without_fields: empty_field_info(),
      has_multi_step_production: false,
    }
  })
  {
    syntax_grammar,
    lexical_grammar,
    inlines,
    simple_aliases,
    variable_info,
    str_pool,
  }
}

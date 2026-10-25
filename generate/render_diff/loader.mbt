// Loader for the `render_c_code` inputs serialized by the differential
// harness (tools/oracle/render_harness/render_dump.rs). Tool-only.

///|
suberror LoadError {
  LoadError(String)
}

///|
/// The arguments of one `render_c_code` call.
struct RenderInput {
  name : @generate.StrId
  tables : @generate.Tables
  syntax_grammar : @generate.SyntaxGrammar
  lexical_grammar : @generate.LexicalGrammar
  default_aliases : @generate.AliasMap
  str_pool : @generate.StrPool
  abi_version : Int32
  semantic_version : (Int32, Int32, Int32)?
  supertype_symbol_map : @sorted_map.SortedMap[
    @generate.Symbol,
    Array[@generate.ChildType],
  ]
}

///|
fn field(json : Json, key : String) -> Json raise LoadError {
  guard json is Object(map) && map.get(key) is Some(value) else {
    raise LoadError("missing field `\{key}`")
  }
  value
}

///|
fn arr(json : Json) -> Array[Json] raise LoadError {
  guard json is Array(items) else { raise LoadError("expected an array") }
  items
}

///|
fn int(json : Json) -> Int32 raise LoadError {
  guard json is Number(n, ..) else { raise LoadError("expected a number") }
  n.to_int()
}

///|
fn bool(json : Json) -> Bool raise LoadError {
  match json {
    True => true
    False => false
    _ => raise LoadError("expected a boolean")
  }
}

///|
fn str(json : Json) -> String raise LoadError {
  guard json is String(s) else { raise LoadError("expected a string") }
  s
}

///|
fn str_id(json : Json) -> @generate.StrId raise LoadError {
  @generate.StrId(int(json))
}

///|
fn symbol(json : Json) -> @generate.Symbol raise LoadError {
  let items = arr(json)
  let kind : @generate.SymbolType = match int(items[0]) {
    0 => External
    1 => End
    2 => EndOfNonTerminalExtra
    3 => Terminal
    4 => NonTerminal
    k => raise LoadError("bad symbol kind \{k}")
  }
  { kind, index: int(items[1]), }
}

///|
fn opt_symbol(json : Json) -> @generate.Symbol? raise LoadError {
  if json is Null {
    None
  } else {
    Some(symbol(json))
  }
}

///|
fn variable_type(json : Json) -> @generate.VariableType raise LoadError {
  match int(json) {
    0 => Hidden
    1 => Auxiliary
    2 => Anonymous
    3 => Named
    k => raise LoadError("bad variable type \{k}")
  }
}

///|
fn alias_of(json : Json) -> @generate.Alias raise LoadError {
  let items = arr(json)
  { value: str_id(items[0]), is_named: bool(items[1]), }
}

///|
fn opt_alias(json : Json) -> @generate.Alias? raise LoadError {
  if json is Null {
    None
  } else {
    Some(alias_of(json))
  }
}

///|
fn symbols(json : Json) -> Array[@generate.Symbol] raise LoadError {
  arr(json).map(symbol)
}

///|
fn token_set(json : Json) -> @generate.TokenSet raise LoadError {
  @generate.TokenSet::from_array(symbols(json))
}

///|
fn character_set(json : Json) -> @generate.CharacterSet raise LoadError {
  let set = @generate.CharacterSet::empty()
  for range in arr(json) {
    let range = arr(range)
    set.add_range_in_place(int(range[0]), int(range[1]) - 1)
  }
  // The dumped ranges must be reproduced exactly.
  let raw = set.raw_ranges()
  let expected = arr(json)
  if raw.length() != expected.length() {
    raise LoadError("character set ranges were merged")
  }
  set
}

///|
fn parse_action(json : Json) -> @generate.ParseAction raise LoadError {
  let items = arr(json)
  match str(items[0]) {
    "Accept" => Accept
    "ShiftExtra" => ShiftExtra
    "Recover" => Recover
    "Shift" => Shift(state=int(items[1]), is_repetition=bool(items[2]))
    "Reduce" =>
      Reduce(
        symbol=symbol(items[1]),
        child_count=int(items[2]),
        dynamic_precedence=int(items[3]),
        production_id=int(items[4]),
      )
    other => raise LoadError("bad parse action \{other}")
  }
}

///|
fn lex_table(json : Json) -> @generate.LexTable raise LoadError {
  let states = []
  for state in arr(json) {
    let eof = field(state, "eof")
    let eof_action : @generate.AdvanceAction? = if eof is Null {
      None
    } else {
      let eof = arr(eof)
      Some({ state: int(eof[0]), in_main_token: bool(eof[1]), })
    }
    let advance_actions = []
    for entry in arr(field(state, "adv")) {
      let entry = arr(entry)
      let action : @generate.AdvanceAction = {
        state: int(entry[1]),
        in_main_token: bool(entry[2]),
      }
      advance_actions.push((character_set(entry[0]), action))
    }
    states.push(@generate.LexState::{
      accept_action: opt_symbol(field(state, "accept")),
      eof_action,
      advance_actions,
    })
  }
  { states, }
}

///|
fn parse_table(json : Json) -> @generate.ParseTable raise LoadError {
  let table = @generate.ParseTable::new()
  for state_json in arr(field(json, "states")) {
    let state = @generate.ParseState::new()
    state.id = int(field(state_json, "id"))
    for entry in arr(field(state_json, "t")) {
      let entry = arr(entry)
      state.terminal_entries.push(
        symbol(entry[0]),
        @generate.ActionListId::new(int(entry[1]), bool(entry[2])),
      )
    }
    for entry in arr(field(state_json, "n")) {
      let entry = arr(entry)
      let target = int(entry[1])
      state.nonterminal_entries.push(
        symbol(entry[0]),
        if target < 0 {
          ShiftExtra
        } else {
          Goto(target)
        },
      )
    }
    state.reserved_words = token_set(field(state_json, "reserved"))
    state.lex_state_id = int(field(state_json, "lex"))
    state.external_lex_state_id = int(field(state_json, "ext"))
    state.core_id = int(field(state_json, "core"))
    state.has_eof_gated_reduce = bool(field(state_json, "eofg"))
    table.states.push(state)
  }
  for list in arr(field(json, "action_lists")) {
    ignore(table.action_lists.push(arr(list).map(parse_action)))
  }
  table.symbols = symbols(field(json, "symbols"))
  table.production_infos = arr(field(json, "production_infos")).map(info => {
    let field_map = @sorted_map.SortedMap([])
    for entry in arr(field(info, "field_map")) {
      let entry = arr(entry)
      field_map.set(
        str_id(entry[0]),
        arr(entry[1]).map(location => {
          let location = arr(location)
          @generate.FieldLocation::{
            index: int(location[0]),
            inherited: bool(location[1]),
          }
        }),
      )
    }
    @generate.ProductionInfo::{
      alias_sequence: arr(field(info, "alias_sequence")).map(opt_alias),
      field_map,
    }
  })
  table.max_aliased_production_length = int(
    field(json, "max_aliased_production_length"),
  )
  table.external_lex_states = arr(field(json, "external_lex_states")).map(
    token_set,
  )
  table
}

///|
fn load_render_input(text : String) -> RenderInput raise {
  let json = @json.parse(text)
  let str_pool = @generate.StrPool::new()
  for i, s in arr(field(json, "strings")) {
    let id = str_pool.intern(str(s))
    if id.raw() != i + 1 {
      raise LoadError("string pool order mismatch at \{i}")
    }
  }
  let syntax = field(json, "syntax")
  let syntax_grammar : @generate.SyntaxGrammar = {
    variables: arr(field(syntax, "variables")).map(v => {
      let v = arr(v)
      @generate.SyntaxVariable::{
        name: str_id(v[0]),
        kind: variable_type(v[1]),
      }
    }),
    extra_symbols: symbols(field(syntax, "extra_symbols")),
    expected_conflicts: [],
    external_tokens: arr(field(syntax, "external_tokens")).map(t => {
      let t = arr(t)
      @generate.ExternalToken::{
        name: str_id(t[0]),
        kind: variable_type(t[1]),
        corresponding_internal_token: opt_symbol(t[2]),
      }
    }),
    supertype_symbols: symbols(field(syntax, "supertype_symbols")),
    variables_to_inline: [],
    word_token: opt_symbol(field(syntax, "word_token")),
    precedence_orderings: [],
    reserved_word_sets: [],
    steps: arr(field(syntax, "steps")).map(step => {
      let step = arr(step)
      @generate.ProductionStep::pack(
        symbol(step[0]),
        NoPrecedence,
        None,
        opt_alias(step[1]),
        None,
        0,
      )
    }),
    productions: [],
    var_prods: [],
  }
  let lexical_grammar : @generate.LexicalGrammar = {
    nfa: @generate.Nfa::new(),
    variables: arr(field(field(json, "lexical"), "variables")).map(v => {
      let v = arr(v)
      @generate.LexicalVariable::{
        name: str_id(v[0]),
        kind: variable_type(v[1]),
        implicit_precedence: int(v[2]),
        start_state: int(v[3]),
      }
    }),
  }
  let default_aliases = @sorted_map.SortedMap([])
  for entry in arr(field(json, "default_aliases")) {
    let entry = arr(entry)
    default_aliases.set(symbol(entry[0]), alias_of(entry[1]))
  }
  let supertype_symbol_map = @sorted_map.SortedMap([])
  for entry in arr(field(json, "supertype_symbol_map")) {
    let entry = arr(entry)
    supertype_symbol_map.set(
      symbol(entry[0]),
      arr(entry[1]).map(child => {
        let child = arr(child)
        let child_type : @generate.ChildType = if str(child[0]) == "N" {
          Normal(symbol(child[1]))
        } else {
          Aliased(alias_of(child[1]))
        }
        child_type
      }),
    )
  }
  let tables_json = field(json, "tables")
  let tables : @generate.Tables = {
    parse_table: parse_table(field(tables_json, "parse_table")),
    main_lex_table: lex_table(field(tables_json, "main_lex_table")),
    keyword_lex_table: lex_table(field(tables_json, "keyword_lex_table")),
    large_character_sets: arr(field(tables_json, "large_character_sets")).map(entry => {
      let entry = arr(entry)
      (opt_symbol(entry[0]), character_set(entry[1]))
    }),
  }
  let semantic_version = match field(json, "semantic_version") {
    Null => None
    version => {
      let v = arr(version)
      Some((int(v[0]), int(v[1]), int(v[2])))
    }
  }
  {
    name: str_id(field(json, "name")),
    tables,
    syntax_grammar,
    lexical_grammar,
    default_aliases,
    str_pool,
    abi_version: int(field(json, "abi_version")),
    semantic_version,
    supertype_symbol_map,
  }
}

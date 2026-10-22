///|
priv struct EncodedState {
  actions : Array[(Int32, Array[Action])]
  gotos : Array[(Int32, Int32)]
} derive(ToJson, @json.FromJson)

///|
priv struct EncodedLanguage {
  format : String
  version : Int32
  name : String
  symbols : Array[Symbol]
  tokens : Array[Token]
  productions : Array[Production]
  states : Array[EncodedState]
  start_symbol : Int32
  extras : Array[Int32]
  word_token : Int32?
  supertypes : Array[Int32]?
  externals : Array[Int32]?
} derive(ToJson, @json.FromJson)

///|
pub impl ToJson for Language with fn to_json(self) {
  let encoded : EncodedLanguage = {
    format: "treesitter.mbt",
    version: 1,
    name: self.name,
    symbols: self.symbols,
    tokens: self.tokens,
    productions: self.productions,
    start_symbol: self.start_symbol,
    extras: self.extras,
    word_token: self.word_token,
    supertypes: Some(self.supertypes),
    externals: Some(self.externals),
    states: self.states.map(s => {
      let actions = s.actions.iter().to_array()
      actions.sort_by_key(p => p.0)
      let gotos = s.gotos.iter().to_array()
      gotos.sort_by_key(p => p.0)
      { actions, gotos, }
    }),
  }
  Json(encoded)
}

///|
#deprecated
pub extend Language with ToJson::{to_json}

///|
fn check_numbers(value : Json) -> Unit raise LanguageError {
  match value {
    Number(n, ..) =>
      if n < -2147483648.0 || n > 2147483647.0 || n.to_int().to_double() != n {
        raise InvalidLanguage("table numbers must be 32-bit integers")
      }
    Array(a) =>
      for item in a {
        check_numbers(item)
      }
    Object(o) =>
      for item in o.values() {
        check_numbers(item)
      }
    _ => ()
  }
}

///|
pub fn Language::from_json(value : Json) -> Language raise {
  check_numbers(value)
  let decoded : EncodedLanguage = @json.from_json(value)
  if decoded.format != "treesitter.mbt" || decoded.version != 1 {
    raise InvalidLanguage("unsupported language format or version")
  }
  let states = decoded.states.map(row => {
    let actions = Map::from_array(row.actions)
    let gotos = Map::from_array(row.gotos)
    if actions.length() != row.actions.length() ||
      gotos.length() != row.gotos.length() {
      raise InvalidLanguage("duplicate table keys")
    }
    ParseState::{ actions, gotos, }
  })
  Language::new(
    decoded.name,
    decoded.symbols,
    decoded.tokens,
    decoded.productions,
    states,
    decoded.start_symbol,
    decoded.extras,
    word_token?=decoded.word_token,
    supertypes=decoded.supertypes.unwrap_or([]),
    externals=decoded.externals.unwrap_or([]),
  )
}

///|
pub fn Language::parse(source : StringView) -> Language raise {
  Language::from_json(@json.parse(source, reject_duplicate_keys=true))
}

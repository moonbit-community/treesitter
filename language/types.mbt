///|
pub(all) struct Symbol {
  name : String
  named : Bool
  visible : Bool
  terminal : Bool
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) struct Token {
  symbol : Int32
  lexer : @lex.Dfa
  precedence : Int32
  immediate : Bool
  literal : Bool
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) struct Step {
  symbol : Int32
  field : String?
  rename : (String, Bool)?
  precedence : Int32
  associativity : Int32
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) struct Production {
  lhs : Int32
  steps : Array[Step]
  precedence : Int32
  associativity : Int32
  dynamic_precedence : Int32
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) enum Action {
  Shift(Int32)
  Reduce(Int32)
  Accept
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) struct ParseState {
  actions : Map[Int32, Array[Action]]
  gotos : Map[Int32, Int32]
} derive(Debug, Eq)

///|
/// Portable generated tables; symbol 0 is EOF and state 0 is the initial state.
/// Constructed and validated by the generator; no C language ABI is involved.
pub struct Language {
  name : String
  symbols : Array[Symbol]
  tokens : Array[Token]
  productions : Array[Production]
  states : Array[ParseState]
  start_symbol : Int32
  extras : Array[Int32]
} derive(Debug, Eq)

///|
pub suberror LanguageError {
  InvalidLanguage(String)
} derive(Debug)

///|
pub fn Language::new(
  name : String,
  symbols : Array[Symbol],
  tokens : Array[Token],
  productions : Array[Production],
  states : Array[ParseState],
  start_symbol : Int32,
  extras : Array[Int32],
) -> Language raise LanguageError {
  let language : Language = {
    name,
    symbols,
    tokens,
    productions,
    states,
    start_symbol,
    extras,
  }
  language.validate()
  language
}

///|
pub fn Language::validate(self : Language) -> Unit raise LanguageError {
  fn invalid(message : String) raise LanguageError {
    raise InvalidLanguage(message)
  }
  let count = self.symbols.length()
  if count == 0 || self.states.is_empty() {
    invalid("empty symbol or state table")
  }
  if !self.symbols[0].terminal {
    invalid("symbol zero must be EOF")
  }
  if self.start_symbol <= 0 ||
    self.start_symbol >= count ||
    self.symbols[self.start_symbol].terminal {
    invalid("invalid start symbol")
  }
  for token in self.tokens {
    if token.symbol <= 0 ||
      token.symbol >= count ||
      !self.symbols[token.symbol].terminal {
      invalid("invalid token symbol")
    }
    if token.lexer.nullable() {
      invalid("lexical tokens must consume input")
    }
  }
  for production in self.productions {
    if production.lhs <= 0 ||
      production.lhs >= count ||
      self.symbols[production.lhs].terminal {
      invalid("invalid production lhs")
    }
    for step in production.steps {
      if step.symbol < 0 || step.symbol >= count {
        invalid("invalid production symbol")
      }
    }
  }
  for row in self.states {
    for symbol, actions in row.actions {
      if symbol < 0 || symbol >= count || !self.symbols[symbol].terminal {
        invalid("invalid action symbol")
      }
      for action in actions {
        match action {
          Shift(state) =>
            if state < 0 || state >= self.states.length() {
              invalid("invalid shift target")
            }
          Reduce(production) =>
            if production < 0 || production >= self.productions.length() {
              invalid("invalid reduction")
            }
          Accept => if symbol != 0 { invalid("accept action must use EOF") }
        }
      }
    }
    for symbol, target in row.gotos {
      if symbol <= 0 || symbol >= count || self.symbols[symbol].terminal {
        invalid("invalid goto symbol")
      }
      if target < 0 || target >= self.states.length() {
        invalid("invalid goto target")
      }
    }
  }
  for symbol in self.extras {
    if !self.tokens.any(t => t.symbol == symbol) {
      invalid("extra is not a lexical token")
    }
  }
}

///|
pub fn Language::symbol_id(
  self : Language,
  name : String,
  named~ : Bool = true,
) -> Int32? {
  for id, symbol in self.symbols {
    if symbol.name == name && symbol.named == named {
      return Some(id)
    }
  }
  None
}

///|
pub fn Language::lookahead(self : Language, state : Int32) -> Array[Int32] {
  match self.states.get(state) {
    None => []
    Some(row) => {
      let result = row.actions.keys().to_array()
      result.sort()
      result
    }
  }
}

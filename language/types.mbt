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
  reserved_set : Int32?
  symbol : Int32
  field : String?
  rename : (String, Bool)?
  precedence : Int32
  precedence_name : String?
  associativity : Int32
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) struct Production {
  requires_eof : Bool?
  lhs : Int32
  steps : Array[Step]
  precedence : Int32
  precedence_name : String?
  associativity : Int32
  dynamic_precedence : Int32
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) enum Action {
  Shift(Int32)
  Reduce(Int32)
  Accept
  EnterExtra(Int32)
  AcceptExtra
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) struct ParseState {
  reserved_words : Array[Int32]
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
  word_token : Int32?
  supertypes : Array[Int32]
  externals : Array[Int32]
  recovery_tokens : Array[Int32]
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
  word_token? : Int32,
  supertypes~ : Array[Int32] = [],
  externals~ : Array[Int32] = [],
  recovery_tokens? : Array[Int32],
) -> Language raise LanguageError {
  let language : Language = {
    name,
    symbols,
    tokens,
    productions,
    states,
    start_symbol,
    extras,
    word_token,
    supertypes,
    externals,
    recovery_tokens: recovery_tokens.unwrap_or_else(() => {
      tokens.map(t => t.symbol)
    }),
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
  if self.word_token is Some(id) &&
    !self.tokens.any(t => t.symbol == id) &&
    !self.externals.contains(id) {
    invalid("word symbol must be a lexical token")
  }
  for id in self.externals {
    if id <= 0 || id >= count || !self.symbols[id].terminal {
      invalid("external symbols must be terminals")
    }
  }
  for id in self.recovery_tokens {
    if !self.tokens.any(t => t.symbol == id) {
      invalid("recovery symbol must be a lexical token")
    }
  }
  for id in self.supertypes {
    if id <= 0 ||
      id >= count ||
      self.symbols[id].terminal ||
      self.symbols[id].visible {
      invalid("supertypes must be hidden nonterminal symbols")
    }
  }
  for token in self.tokens {
    if token.symbol <= 0 ||
      token.symbol >= count ||
      !self.symbols[token.symbol].terminal {
      invalid("invalid token symbol")
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
    for symbol in row.reserved_words {
      if !self.tokens.any(t => t.symbol == symbol) {
        invalid("reserved word is not a lexical token")
      }
    }
    for symbol, actions in row.actions {
      if symbol < 0 || symbol >= count || !self.symbols[symbol].terminal {
        invalid("invalid action symbol")
      }
      for action in actions {
        match action {
          Shift(state) | EnterExtra(state) =>
            if state < 0 || state >= self.states.length() {
              invalid("invalid shift target")
            }
          Reduce(production) =>
            if production < 0 || production >= self.productions.length() {
              invalid("invalid reduction")
            }
          Accept => if symbol != 0 { invalid("accept action must use EOF") }
          AcceptExtra => ()
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
    if symbol <= 0 || symbol >= count {
      invalid("invalid extra symbol")
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

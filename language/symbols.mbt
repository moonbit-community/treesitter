///|
pub(all) enum SymbolType {
  Regular
  Anonymous
  Supertype
  Auxiliary
} derive(Eq, Debug)

///|
pub extend SymbolType with Eq::{equal, not_equal}

///|
pub extend SymbolType with @debug.Debug::{to_repr}

///|
// Alias-only names follow the parser's symbol table. Keep parser ids unchanged:
// lexer/parse tables always use grammar symbols, not public alias identities.
fn collect_public_symbols(
  symbols : Array[Symbol],
  productions : Array[Production],
) -> Array[Symbol] {
  let result = symbols.copy()
  let identities : Map[(String, Bool), Unit] = Map([])
  for symbol in symbols {
    if symbol.visible {
      identities[(symbol.name, symbol.named)] = ()
    }
  }
  for production in productions {
    for step in production.steps {
      if step.rename is Some((name, named)) &&
        !identities.contains((name, named)) {
        identities[(name, named)] = ()
        result.push({ name, named, visible: true, terminal: false, })
      }
    }
  }
  result
}

///|
/// Count parser symbols and alias-only public symbols. ERROR (-1) is separate.
pub fn Language::symbol_count(self : Language) -> Int32 {
  self.public_symbols.length()
}

///|
pub fn Language::symbol_name(self : Language, id : Int32) -> String? {
  if id == -1 {
    Some("ERROR")
  } else {
    self.public_symbols.get(id).map(s => s.name)
  }
}

///|
/// Look up a visible node identity or a declared supertype. Hidden auxiliary
/// names are not public identities. ERROR has id -1 in the portable runtime.
pub fn Language::symbol_id(
  self : Language,
  name : String,
  named~ : Bool = true,
) -> Int32? {
  if name == "ERROR" && named {
    return Some(-1)
  }
  for id, symbol in self.public_symbols {
    if (symbol.visible || self.supertypes.contains(id)) &&
      symbol.name == name &&
      symbol.named == named {
      return Some(id)
    }
  }
  None
}

///|
pub fn Language::symbol_type(self : Language, id : Int32) -> SymbolType? {
  if id == -1 {
    return Some(Regular)
  }
  self.public_symbols
  .get(id)
  .map(s => {
    if s.visible {
      if s.named {
        Regular
      } else {
        Anonymous
      }
    } else if self.supertypes.contains(id) {
      Supertype
    } else {
      Auxiliary
    }
  })
}

///|
/// Direct subtype identities of a declared supertype, in symbol order.
/// Hidden intermediary rules are expanded; nested supertypes retain their ids.
pub fn Language::subtypes(self : Language, supertype : Int32) -> Array[Int32] {
  if !self.supertypes.contains(supertype) {
    return []
  }
  let identities = self.shapes()[supertype].unwrap_or(empty_shape()).all.types
  let result = []
  for (name, named) in identities {
    if self.symbol_id(name, named~) is Some(id) && !result.contains(id) {
      result.push(id)
    }
  }
  result.sort()
  result
}

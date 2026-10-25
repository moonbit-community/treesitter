// Port of tree-sitter crates/generate/src/prepare_grammar/intern_symbols.rs.

///|
pub(all) suberror InternSymbolsError {
  HiddenStartRule
  Undefined(String)
  UndefinedSupertype(String)
  UndefinedConflict(String)
  UndefinedWordToken(String)
} derive(Eq, Debug)

///|
pub impl Show for InternSymbolsError with fn output(self, logger) {
  match self {
    HiddenStartRule =>
      logger.write_string("A grammar's start rule must be visible.")
    Undefined(name) => logger.write_string("Undefined symbol `\{name}`")
    UndefinedSupertype(name) =>
      logger.write_string(
        "Undefined symbol `\{name}` in grammar's supertypes array",
      )
    UndefinedConflict(name) =>
      logger.write_string(
        "Undefined symbol `\{name}` in grammar's conflicts array",
      )
    UndefinedWordToken(name) =>
      logger.write_string("Undefined symbol `\{name}` as grammar's word token")
  }
}

///|
/// The non-pool outputs of the intern pass. The rule bodies are rewritten in place
/// (`NamedSymbol`->`Sym`). This carries the derived metadata that travels alongside
/// them.
priv struct InternedGrammarMeta {
  kinds : Array[VariableType]
  /// Per external token: its name (if a named symbol) and kind
  external_tokens : Array[(StrId?, VariableType)]
  supertypes : Array[Symbol]
  conflicts : Array[Array[Symbol]]
  inline : Array[Symbol]
  word : Symbol?
} derive(Debug)

///|
fn intern_symbols(
  grammar : InputGrammar,
  diagnostics : Array[Diagnostic],
) -> InternedGrammarMeta raise InternSymbolsError {
  let pool = grammar.pool
  let variables = grammar.variables
  let external_roots = grammar.external_roots
  let extra_roots = grammar.extra_roots
  let reserved_sets = grammar.reserved_sets

  // StrId -> the symbol for a variable or external token name. An external whose name
  // shadows a variable resolves to the variable (variables are inserted first).
  let name_of_symbol : Map[StrId, Symbol] = Map([])
  for i, v in variables {
    name_of_symbol[v.name] = Symbol::non_terminal(i)
  }
  for i, root in external_roots {
    if pool.node(root) is NamedSymbol(sid) && !name_of_symbol.contains(sid) {
      name_of_symbol[sid] = Symbol::external(i)
    }
  }
  if variable_type_for_name(pool.resolve(variables[0].name)) == Hidden {
    raise HiddenStartRule
  }

  // External names/kinds read before the in-place rewrite consumes them.
  let external_tokens : Array[(StrId?, VariableType)] = external_roots.map(root => {
    match pool.node(root) {
      NamedSymbol(sid) => (Some(sid), variable_type_for_name(pool.resolve(sid)))
      _ => (None, Anonymous)
    }
  })
  let kinds = variables.map(v => variable_type_for_name(pool.resolve(v.name)))
  let stack = []
  for v in variables {
    intern_root(pool, v.root, Some(v.name), name_of_symbol, diagnostics, stack)
  }
  for root in external_roots {
    intern_root(pool, root, None, name_of_symbol, diagnostics, stack)
  }
  for root in extra_roots {
    intern_root(pool, root, None, name_of_symbol, diagnostics, stack)
  }
  for set in reserved_sets {
    for root in set.roots {
      intern_root(pool, root, None, name_of_symbol, diagnostics, stack)
    }
  }
  let lookup = (sid : StrId) => name_of_symbol.get(sid)
  let supertypes = grammar.supertype_names.map(s => {
    guard lookup(s) is Some(symbol) else {
      raise UndefinedSupertype(pool.resolve(s))
    }
    symbol
  })
  let conflicts = grammar.conflict_names.map(c => {
    c.map(s => {
      guard lookup(s) is Some(symbol) else {
        raise UndefinedConflict(pool.resolve(s))
      }
      symbol
    })
  })

  // Unkown inline names are silently skipped.
  let inline = grammar.inline_names.filter_map(s => lookup(s))

  // An inlined rule never produces nodes, so a supertype entry for it makes
  // no sense and is dropped.
  let filtered_supertypes = []
  for i, name in grammar.supertype_names {
    let symbol = supertypes[i]
    if inline.contains(symbol) {
      diagnostics.push(SupertypeInlined(name=pool.resolve(name)))
    } else {
      filtered_supertypes.push(symbol)
    }
  }
  let supertypes = filtered_supertypes
  let word = match grammar.word_name {
    Some(s) =>
      match lookup(s) {
        Some(symbol) => Some(symbol)
        None => raise UndefinedWordToken(pool.resolve(s))
      }
    None => None
  }
  for s in supertypes {
    if s.non_terminal_index() is Some(index) {
      kinds[index] = Hidden
    }
  }
  { kinds, external_tokens, supertypes, conflicts, inline, word, }
}

///|
/// Iterative pre-order walk rewriting `NamedSymbol`->`Sym` in place.
fn intern_root(
  pool : RulePool,
  root : RuleId,
  var_name : StrId?,
  name_of_symbol : Map[StrId, Symbol],
  diagnostics : Array[Diagnostic],
  stack : Array[RuleId],
) -> Unit raise InternSymbolsError {
  stack.clear()
  stack.push(root)
  while stack.pop() is Some(id) {
    match pool.node(id) {
      NamedSymbol(sid) =>
        match name_of_symbol.get(sid) {
          Some(s) => pool.set_node(id, Sym(s))
          None => raise Undefined(pool.resolve(sid))
        }
      Seq(range) | Choice(range) as node => {
        let children = pool.child_slice(range)
        // In the case of a seq or choice rule of 1 element in a hidden rule, weird
        // inconsistent behavior with queries can occur. So we should warn the user about
        // it.
        if children.length() == 1 &&
          pool.node(children[0]) is (String(_) | Pattern(_, _)) {
          let name = match var_name {
            Some(s) => Some(pool.resolve(s))
            None => None
          }
          diagnostics.push(
            if node is Choice(_) {
              UnaryChoice(name~)
            } else {
              UnarySeq(name~)
            },
          )
        }
        for i = children.length() - 1; i >= 0; i = i - 1 {
          stack.push(children[i])
        }
      }
      Repeat(inner) | Metadata(rule=inner, ..) | Reserved(rule=inner, ..) =>
        stack.push(inner)
      _ => ()
    }
  }
}

///|
fn variable_type_for_name(name : String) -> VariableType {
  if name.has_prefix("_") {
    Hidden
  } else {
    Named
  }
}

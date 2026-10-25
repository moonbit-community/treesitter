// Port of tree-sitter crates/generate/src/prepare_grammar.rs.
//
// Upstream wraps each pass's error in a transparent `PrepareGrammarError` (and
// `ValidatePrecedenceError`); here each pass raises its own error type, which
// displays the same text.

///|
pub(all) suberror IndirectRecursionError {
  IndirectRecursionError(Array[String])
} derive(Eq, Debug)

///|
pub impl Show for IndirectRecursionError with fn output(self, logger) {
  let IndirectRecursionError(symbols) = self
  logger.write_string("Grammar contains an indirectly recursive rule: ")
  for i, symbol in symbols {
    if i > 0 {
      logger.write_string(" -> ")
    }
    logger.write_string(symbol)
  }
}

///|
pub(all) suberror EmptyStringExtraError {
  EmptyStringExtraError(String)
} derive(Eq, Debug)

///|
pub impl Show for EmptyStringExtraError with fn output(self, logger) {
  let EmptyStringExtraError(name) = self
  logger.write_string(
    (
      $|The extra rule `\{name}` matches the empty string.
      $|
      $|Tree-sitter does not support extras that match the empty string.
      $|
    ),
  )
}

///|
/// `ValidatePrecedenceError`: `Undeclared` or `Ordering`.
pub(all) suberror ValidatePrecedenceError {
  UndeclaredPrecedenceError(precedence~ : String, rule~ : String)
  ConflictingPrecedenceOrderingError(
    precedence_1~ : String,
    precedence_2~ : String
  )
} derive(Eq, Debug)

///|
pub impl Show for ValidatePrecedenceError with fn output(self, logger) {
  match self {
    UndeclaredPrecedenceError(precedence~, rule~) =>
      logger.write_string(
        "Undeclared precedence '\{precedence}' in rule '\{rule}'",
      )
    ConflictingPrecedenceOrderingError(precedence_1~, precedence_2~) =>
      logger.write_string(
        "Conflicting orderings for precedences \{precedence_1} and \{precedence_2}",
      )
  }
}

///|
/// Transform an input grammar into separate components that are ready
/// for parse table construction.
pub fn prepare_grammar(
  grammar : InputGrammar,
  diagnostics : Array[Diagnostic],
) -> PreparedGrammar raise {
  let g = grammar
  validate_precedences(g)
  let interned_meta = intern_symbols(g, diagnostics)
  let pending_tokens = extract_tokens(g, interned_meta)
  let (ext_meta, lexical_grammar) = pending_tokens.expand_and_commit()
  expand_repeats(g, ext_meta)
  let state = FlattenState::new()
  let out = ProductionStore::new()
  flatten_grammar(g, ext_meta, state, out)
  validate_indirect_recursion(g, out)
  validate_extras(g, ext_meta.extra_symbols, lexical_grammar, out)
  let default_aliases = extract_default_aliases(
    g,
    ext_meta,
    lexical_grammar.variables,
    out,
  )
  let inlines = process_inlines(g, ext_meta, lexical_grammar.variables, out)
  let (syntax_grammar, str_pool) = assemble_syntax_grammar(g, ext_meta, out)
  { syntax_grammar, lexical_grammar, inlines, default_aliases, str_pool, }
}

///|
/// Check for indirect recursion cycles in the grammar that can cause infinite loops while
/// parsing. An indirect recursion cycle occurs when a non-terminal can derive itself through
/// a chain of single-symbol productions (e.g., A -> B, B -> A).
fn validate_indirect_recursion(
  grammar : InputGrammar,
  productions : ProductionStore,
) -> Unit raise IndirectRecursionError {
  // `IndexMap<StrId, BTreeSet<StrId>>`: insertion-ordered keys, sorted values.
  let epsilon_transitions : Map[StrId, Array[StrId]] = Map([])
  for i, variable in grammar.variables {
    // `zip`: as long as the shorter of the two.
    guard productions.var_prods.get(i) is Some((start, end)) else { break }
    let symbols : Array[StrId] = []
    for p in productions.productions[start:end] {
      // Only a production containing exactly one nonterminal adds an edge
      if p.steps_len != 1 {
        continue
      }
      guard productions.steps[p.steps_start].non_terminal_index() is Some(index) else {
        continue
      }
      let name = grammar.variables[index].name
      // Rules that *directly* reference themselves don't cause a parsing loop.
      if name != variable.name {
        symbols.push(name)
      }
    }
    symbols.sort()
    dedup(symbols)
    // `IndexMap::insert` keeps an existing key's position.
    epsilon_transitions[variable.name] = symbols
  }
  let visited : @hashset.HashSet[StrId] = @hashset.HashSet([])
  for start_symbol, _ in epsilon_transitions {
    let path = []
    if get_cycle(start_symbol, epsilon_transitions, visited, path)
      is Some((start_idx, end_idx)) {
      let cycle_symbols = path[start_idx:end_idx + 1]
        .iter()
        .map(s => grammar.pool.resolve(s))
        .to_array()
      raise IndirectRecursionError(cycle_symbols)
    }
  }
}

///|
/// Perform a depth-first search to detect cycles in single state transitions.
fn get_cycle(
  current : StrId,
  transitions : Map[StrId, Array[StrId]],
  visited : @hashset.HashSet[StrId],
  path : Array[StrId],
) -> (Int32, Int32)? {
  if path.search(current) is Some(first_idx) {
    path.push(current)
    return Some((first_idx, path.length() - 1))
  }
  if visited.contains(current) {
    return None
  }
  path.push(current)
  visited.add(current)
  if transitions.get(current) is Some(next_symbols) {
    for next in next_symbols {
      if get_cycle(next, transitions, visited, path) is Some(cycle) {
        return Some(cycle)
      }
    }
  }
  ignore(path.pop())
  None
}

///|
/// Reject extras that can match the empty string through internal tokens and rules.
/// Parsing an extra doesn't change the parse state, so the parser could keep parsing
/// an empty one at the same position.
fn validate_extras(
  grammar : InputGrammar,
  extra_symbols : Array[Symbol],
  lexical_grammar : LexicalGrammar,
  productions : ProductionStore,
) -> Unit raise EmptyStringExtraError {
  let empty = EmptyMatches::new(lexical_grammar, productions)
  for symbol in extra_symbols {
    let (matches_empty, name) = match symbol.kind {
      Terminal =>
        (
          empty.token(symbol.index),
          lexical_grammar.variables[symbol.index].name,
        )
      NonTerminal =>
        (empty.rule(symbol.index), grammar.variables[symbol.index].name)
      // External scanners decide whether a token consumes input, so generation
      // cannot check them.
      External => continue
      // INVARIANT: Token extraction only resolves extras to terminals, non-terminals,
      // and external tokens.
      End | EndOfNonTerminalExtra => abort("unreachable")
    }
    if matches_empty {
      raise EmptyStringExtraError(grammar.pool.resolve(name))
    }
  }
}

///|
/// Which tokens and rules can match the empty string, checked as the extras reach them
priv struct EmptyMatches {
  lexical_grammar : LexicalGrammar
  productions : ProductionStore
  /// The NFA states reached so far while checking a token
  reached : Array[Int32]
  /// Rules that have been checked, or are being checked
  checked_rules : BitVec
  /// The checked rules that can match the empty string
  empty_rules : BitVec
  /// Rules found not to match while another rule was still being checked
  provisional : Array[Int32]
  /// How many rules are being checked
  mut depth : Int32
}

///|
fn EmptyMatches::new(
  lexical_grammar : LexicalGrammar,
  productions : ProductionStore,
) -> EmptyMatches {
  {
    lexical_grammar,
    productions,
    reached: [],
    checked_rules: BitVec::new(),
    empty_rules: BitVec::new(),
    provisional: [],
    depth: 0,
  }
}

///|
fn EmptyMatches::symbol(self : EmptyMatches, symbol : Symbol) -> Bool {
  match symbol.kind {
    Terminal => self.token(symbol.index)
    NonTerminal => self.rule(symbol.index)
    // External token nullability is unknown. Only reject empty matches
    // established by the internal grammar.
    External => false
    // INVARIANT: Flattening never leaves an `End` step in a production, and
    // `EndOfNonTerminalExtra` only appears in parse table lookaheads.
    End | EndOfNonTerminalExtra => abort("unreachable")
  }
}

///|
/// Whether the token's NFA can reach an accept state without consuming a character
fn EmptyMatches::token(self : EmptyMatches, index : Int32) -> Bool {
  self.reached.clear()
  self.reached.push(self.lexical_grammar.variables[index].start_state)
  let mut i = 0
  while self.reached.get(i) is Some(id) {
    match self.lexical_grammar.nfa.states[id] {
      Accept(..) => return true
      Split(left, right) =>
        for next in [left, right] {
          if !self.reached.contains(next) {
            self.reached.push(next)
          }
        }
      Advance(..) => ()
    }
    i += 1
  }
  false
}

///|
/// Whether every step of one of the rule's productions can match the empty string.
///
/// A rule that's still being checked counts as not matching, which cuts cycles. If it
/// turns out to match, answers found while it was open are dropped and rechecked.
fn EmptyMatches::rule(self : EmptyMatches, index : Int32) -> Bool {
  if self.checked_rules.len() == 0 {
    let rules = self.productions.var_prods.length()
    self.checked_rules.resize(rules, false)
    self.empty_rules.resize(rules, false)
  }
  if !self.checked_rules.at(index) {
    self.checked_rules.set(index, true)
    let since = self.provisional.length()
    self.depth += 1
    let (start, end) = self.productions.var_prods[index]
    let empty = self.productions.productions[start:end]
      .iter()
      .any(p => {
        self.productions.steps[p.steps_start:p.steps_start + p.steps_len]
        .iter()
        .all(step => self.symbol(step.symbol))
      })
    self.depth -= 1
    if empty {
      self.empty_rules.set(index, true)
      // These may have only failed because this rule was still open
      for rule in self.provisional[since:] {
        self.checked_rules.set(rule, false)
      }
      self.provisional.truncate(since)
    } else if self.depth > 0 {
      self.provisional.push(index)
    }
  }
  self.empty_rules.at(index)
}

///|
/// Upstream's `display` for a precedence entry in error messages.
fn display_precedence_entry(
  grammar : InputGrammar,
  e : PrecedenceEntry,
) -> String {
  match e {
    Name(sid) => "'\{grammar.pool.resolve(sid)}'"
    Symbol(sid) => "$.\{grammar.pool.resolve(sid)}"
  }
}

///|
fn compare_precedence_entries(
  grammar : InputGrammar,
  a : PrecedenceEntry,
  b : PrecedenceEntry,
) -> Int32 {
  match (a, b) {
    (Name(a), Name(b)) | (Symbol(a), Symbol(b)) =>
      compare_str_bytes(grammar.pool.resolve(a), grammar.pool.resolve(b))
    (Name(_), Symbol(_)) => -1
    (Symbol(_), Name(_)) => 1
  }
}

///|
/// Rust's `str::cmp`: lexicographic over the UTF-8 bytes, which is the same as
/// comparing code points.
fn compare_str_bytes(a : String, b : String) -> Int32 {
  let ai = a.iter()
  let bi = b.iter()
  for ;; {
    match (ai.next(), bi.next()) {
      (None, None) => return 0
      (None, Some(_)) => return -1
      (Some(_), None) => return 1
      (Some(x), Some(y)) => {
        let c = x.to_int().compare(y.to_int())
        if c != 0 {
          return c
        }
      }
    }
  }
}

///|
/// Check that all of the named precedences used in the grammar are declared
/// within the `precedences` lists, and also that there are no conflicting
/// precedence orderings declared in those lists.
fn validate_precedences(
  grammar : InputGrammar,
) -> Unit raise ValidatePrecedenceError {
  // For any two precedence names `a` and `b`, if `a` comes before `b`
  // in some list, then it cannot come *after* `b` in any list.
  // (`FxHashMap`, only used for lookups.)
  let pairs : Map[(PrecedenceEntry, PrecedenceEntry), Int32] = Map([])
  for list in grammar.precedence_orderings {
    for i, e1 in list {
      for e2 in list[i + 1:] {
        let mut entry1 = e1
        let mut entry2 = e2
        if entry1 == entry2 {
          continue
        }
        let mut ordering = 1 // Ordering::Greater
        if compare_precedence_entries(grammar, entry1, entry2) > 0 {
          ordering = -1 // Ordering::Less
          let tmp = entry1
          entry1 = entry2
          entry2 = tmp
        }
        match pairs.get((entry1, entry2)) {
          None => pairs[(entry1, entry2)] = ordering
          Some(existing) =>
            if existing != ordering {
              raise ConflictingPrecedenceOrderingError(
                precedence_1=display_precedence_entry(grammar, entry1),
                precedence_2=display_precedence_entry(grammar, entry2),
              )
            }
        }
      }
    }
  }
  let precedence_names : @hashset.HashSet[StrId] = @hashset.HashSet([])
  for list in grammar.precedence_orderings {
    for p in list {
      if p is Name(sid) {
        precedence_names.add(sid)
      }
    }
  }
  let stack = []
  for variable in grammar.variables {
    stack.clear()
    stack.push(variable.root)
    while stack.pop() is Some(id) {
      match grammar.pool.node(id) {
        Repeat(inner) => stack.push(inner)
        Seq(range) | Choice(range) =>
          for child in grammar.pool.child_slice(range) {
            stack.push(child)
          }
        Metadata(params~, rule~) => {
          if grammar.pool.params(params).precedence is Name(sid) &&
            !precedence_names.contains(sid) {
            raise UndeclaredPrecedenceError(
              precedence=grammar.pool.resolve(sid),
              rule=grammar.pool.resolve(variable.name),
            )
          }
          stack.push(rule)
        }
        _ => ()
      }
    }
  }
}

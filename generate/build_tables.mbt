// Port of tree-sitter crates/generate/src/build_tables.rs.

///|
/// Gives each of a grammar's symbols a position. Positions follow `Symbol` order:
/// - external tokens
/// - `Symbol::End`
/// - `Symbol::EndOfNonTerminalExtra`
/// - terminals
/// - non-terminals
priv struct SymbolIndexer {
  external_count : Int32
  terminal_count : Int32
  non_terminal_count : Int32
}

///|
fn SymbolIndexer::new(
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
) -> SymbolIndexer {
  {
    external_count: syntax_grammar.external_tokens.length(),
    terminal_count: lexical_grammar.variables.length(),
    non_terminal_count: syntax_grammar.variables.length(),
  }
}

///|
/// This symbol's position.
fn SymbolIndexer::index(self : SymbolIndexer, symbol : Symbol) -> Int32 {
  match symbol.kind {
    External => symbol.index
    End => self.external_count
    EndOfNonTerminalExtra => self.external_count + 1
    Terminal => self.external_count + 2 + symbol.index
    NonTerminal => self.token_count() + symbol.index
  }
}

///|
/// The symbol at a position, the inverse of `Self::index`.
fn SymbolIndexer::symbol(self : SymbolIndexer, index : Int32) -> Symbol {
  let position = index
  if position < self.external_count {
    Symbol::external(index)
  } else if position == self.external_count {
    symbol_end
  } else if position == self.external_count + 1 {
    symbol_end_of_nonterminal_extra
  } else if position < self.token_count() {
    Symbol::terminal(position - self.external_count - 2)
  } else {
    Symbol::non_terminal(position - self.token_count())
  }
}

///|
/// The terminal index of the symbol at a position, or `-1` if it isn't a terminal:
/// `self.symbol(index).terminal_index()`, without building the symbol.
fn SymbolIndexer::terminal_index_of(
  self : SymbolIndexer,
  index : Int32,
) -> Int32 {
  let first = self.external_count + 2
  if index >= first && index < self.token_count() {
    index - first
  } else {
    -1
  }
}

///|
/// How many positions `Self::index` gives to tokens _only_: one per external token, one
/// each for `End` and `EndOfNonTerminalExtra`, and one per terminal.
fn SymbolIndexer::token_count(self : SymbolIndexer) -> Int32 {
  self.external_count + 2 + self.terminal_count
}

///|
/// How many positions `Self::index` gives out in _total_: the tokens, then one per
/// non-terminal.
fn SymbolIndexer::symbol_count(self : SymbolIndexer) -> Int32 {
  self.token_count() + self.non_terminal_count
}

///|
/// `build_tables::build_tables`.
pub fn build_tables(
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  simple_aliases : AliasMap,
  variable_info : Array[VariableInfo],
  inlines : InlinedProductionMap,
  str_pool : StrPool,
  report_symbol_name : String?,
  optimizations : OptLevel,
  diagnostics : Array[Diagnostic],
) -> Tables raise {
  let item_key_map = ItemKeyMap::new(syntax_grammar, str_pool)
  let item_set_builder = ParseItemSetBuilder::new(
    syntax_grammar, lexical_grammar, inlines, item_key_map,
  )
  let following_tokens = get_following_tokens(
    syntax_grammar, lexical_grammar, item_set_builder,
  )
  let (parse_table, parse_state_info) = build_parse_table(
    syntax_grammar, lexical_grammar, item_set_builder, variable_info, str_pool, diagnostics,
  )
  let token_conflict_map = TokenConflictMap::new(
    lexical_grammar, following_tokens,
  )
  let coincident_token_index = CoincidentTokenIndex::new(
    parse_table,
    lexical_grammar,
    syntax_grammar.word_token,
  )
  let keywords = identify_keywords(
    lexical_grammar,
    syntax_grammar.word_token,
    token_conflict_map,
    coincident_token_index,
    str_pool,
  )
  populate_error_state(
    parse_table, syntax_grammar, lexical_grammar, coincident_token_index, token_conflict_map,
    keywords, str_pool,
  )
  populate_used_symbols(parse_table, syntax_grammar, lexical_grammar)
  minimize_parse_table(
    parse_table, syntax_grammar, lexical_grammar, simple_aliases, token_conflict_map,
    keywords, str_pool, optimizations,
  )
  let lex_tables = build_lex_table(
    parse_table, syntax_grammar, lexical_grammar, keywords, coincident_token_index,
    token_conflict_map, str_pool,
  )
  populate_external_lex_states(parse_table, syntax_grammar)
  mark_fragile_tokens(parse_table, token_conflict_map)
  parse_table.action_lists.canonicalize(parse_table.states)
  if report_symbol_name is Some(report_symbol_name) {
    report_state_info(
      syntax_grammar, lexical_grammar, parse_table, parse_state_info, str_pool, report_symbol_name,
    )
  }
  if parse_table.states.length() > 65535 {
    raise ParseTableBuilderError::StateCount(parse_table.states.length())
  }
  {
    parse_table,
    main_lex_table: lex_tables.main_lex_table,
    keyword_lex_table: lex_tables.keyword_lex_table,
    large_character_sets: lex_tables.large_character_sets,
  }
}

///|
fn get_following_tokens(
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  builder : ParseItemSetBuilder,
) -> Array[TokenSet] {
  let n_terminals = lexical_grammar.variables.length()
  let result = Array::makei(n_terminals, _ => TokenSet::new())
  let all_tokens = TokenSet::new()
  for i in 0..<result.length() {
    all_tokens.insert(Symbol::terminal(i))
  }
  for production in syntax_grammar.productions {
    let steps = production.contents(syntax_grammar.steps).steps
    for i in 1..<steps.length() {
      let left_tokens = builder.last_set(steps[i - 1].symbol)
      let right_tokens = builder.first_set(steps[i].symbol)
      let right_reserved_tokens = builder.reserved_first_set(steps[i].symbol)
      for left_token in left_tokens.iter() {
        if left_token.terminal_index() is Some(index) {
          ignore(result[index].insert_all_terminals(right_tokens))
          if right_reserved_tokens is Some(reserved_tokens) {
            ignore(result[index].insert_all_terminals(reserved_tokens))
          }
        }
      }
    }
  }
  for extra in syntax_grammar.extra_symbols {
    if extra.terminal_index() is Some(index) {
      for entry in result {
        entry.insert(extra)
      }
      result[index] = all_tokens.copy()
    }
  }
  result
}

///|
fn populate_error_state(
  parse_table : ParseTable,
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  coincident_token_index : CoincidentTokenIndex,
  token_conflict_map : TokenConflictMap,
  keywords : TokenSet,
  _str_pool : StrPool,
) -> Unit {
  let n = lexical_grammar.variables.length()

  // First identify the *conflict-free tokens*: tokens that do not overlap with
  // any other token in any way, besides matching exactly the same string.
  let conflict_free_tokens = TokenSet::new()
  for i in 0..<n {
    let mut conflicts_with_other_tokens = false
    for j in 0..<n {
      if j != i &&
        !coincident_token_index.contains(i, j) &&
        token_conflict_map.does_match_shorter_or_longer(i, j) {
        conflicts_with_other_tokens = true
        break
      }
    }
    if !conflicts_with_other_tokens {
      // (Upstream logs "error recovery - token {} has no conflicts" at debug level.)
      conflict_free_tokens.insert(Symbol::terminal(i))
    }
  }
  let recover_entry = ActionListId::new(
    parse_table.action_lists.push([Recover]),
    false,
  )
  let state = parse_table.states[0]

  // Exclude from the error-recovery state any token that conflicts with one of
  // the *conflict-free tokens* identified above.
  let conflict_free_terminals = conflict_free_tokens.terminals()
  for i in 0..<n {
    let symbol = Symbol::terminal(i)
    if !conflict_free_tokens.contains(symbol) &&
      !keywords.contains(symbol) &&
      syntax_grammar.word_token != Some(symbol) &&
      conflict_free_terminals
      .iter()
      .any(other => {
        !coincident_token_index.contains(i, other) &&
        token_conflict_map.does_conflict(i, other)
      }) {
      // (Upstream logs the excluded token at debug level.)
      continue
    }
    state.terminal_entries.insert_if_missing(symbol, recover_entry)
  }
  for i, external_token in syntax_grammar.external_tokens {
    if external_token.corresponding_internal_token is None {
      state.terminal_entries.insert_if_missing(
        Symbol::external(i),
        recover_entry,
      )
    }
  }
  state.terminal_entries.insert(symbol_end, recover_entry)
}

///|
fn populate_used_symbols(
  parse_table : ParseTable,
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
) -> Unit {
  let terminal_usages = Array::make(lexical_grammar.variables.length(), false)
  let non_terminal_usages = Array::make(
    syntax_grammar.variables.length(),
    false,
  )
  let external_usages = Array::make(
    syntax_grammar.external_tokens.length(),
    false,
  )
  for state in parse_table.states {
    for k in 0..<state.terminal_entries.len() {
      let symbol = state.terminal_entries.symbol_at(k)
      match symbol.kind {
        Terminal => terminal_usages[symbol.index] = true
        External => external_usages[symbol.index] = true
        End | EndOfNonTerminalExtra => ()
        NonTerminal => abort("unreachable")
      }
    }
    for k in 0..<state.nonterminal_entries.len() {
      guard state.nonterminal_entries.symbol_at(k).non_terminal_index() is Some(index) else {
        abort("unreachable")
      }
      non_terminal_usages[index] = true
    }
  }
  parse_table.symbols.push(symbol_end)
  for i, value in terminal_usages {
    if value {
      // Assign the grammar's word token a low numerical index. This ensures that
      // it can be stored in a subtree with no heap allocations, even for grammars with
      // very large numbers of tokens. This is an optimization, but it's also important to
      // ensure that a subtree's symbol can be successfully reassigned to the word token
      // without having to move the subtree to the heap.
      // See https://github.com/tree-sitter/tree-sitter/issues/258
      if syntax_grammar.word_token == Some(Symbol::terminal(i)) {
        parse_table.symbols.insert(1, Symbol::terminal(i))
      } else {
        parse_table.symbols.push(Symbol::terminal(i))
      }
    }
  }
  for i, value in external_usages {
    if value {
      parse_table.symbols.push(Symbol::external(i))
    }
  }
  for i, value in non_terminal_usages {
    if value {
      parse_table.symbols.push(Symbol::non_terminal(i))
    }
  }
}

///|
fn populate_external_lex_states(
  parse_table : ParseTable,
  syntax_grammar : SyntaxGrammar,
) -> Unit {
  let external_tokens_by_corresponding_internal_token : Map[Int32, Int32] = Map([],
  )
  for i, external_token in syntax_grammar.external_tokens {
    if external_token.corresponding_internal_token is Some(token) &&
      token.terminal_index() is Some(index) {
      external_tokens_by_corresponding_internal_token[index] = i
    }
  }

  // Ensure that external lex state 0 represents the absence of any
  // external tokens.
  parse_table.external_lex_states.push(TokenSet::new())
  for state in parse_table.states {
    let external_tokens = TokenSet::new()
    for k in 0..<state.terminal_entries.len() {
      let token = state.terminal_entries.symbol_at(k)
      match token.kind {
        External => external_tokens.insert(token)
        Terminal =>
          if external_tokens_by_corresponding_internal_token.get(token.index)
            is Some(index) {
            external_tokens.insert(Symbol::external(index))
          }
        End | EndOfNonTerminalExtra => ()
        NonTerminal => abort("unreachable")
      }
    }
    let mut id = -1
    for i, tokens in parse_table.external_lex_states {
      if tokens == external_tokens {
        id = i
        break
      }
    }
    if id == -1 {
      parse_table.external_lex_states.push(external_tokens)
      id = parse_table.external_lex_states.length() - 1
    }
    state.external_lex_state_id = id
  }
}

///|
fn identify_keywords(
  lexical_grammar : LexicalGrammar,
  word_token : Symbol?,
  token_conflict_map : TokenConflictMap,
  coincident_token_index : CoincidentTokenIndex,
  _str_pool : StrPool,
) -> TokenSet {
  let word_token_index = match word_token {
    Some({ kind: Terminal, index, }) => index
    // An external token has no lexical rule to compare with keywords.
    None | Some({ kind: External, .. }) => return TokenSet::new()
    // INVARIANT: Token extraction rejects a non-terminal word token.
    Some(_) => abort("unreachable")
  }
  let cursor = NfaCursor::new(lexical_grammar.nfa, [])

  // First find all of the candidate keyword tokens: tokens that start with
  // letters or underscore and can match the same string as a word token.
  let keyword_candidates = TokenSet::new()
  for i, variable in lexical_grammar.variables {
    cursor.reset([variable.start_state])
    if all_chars_are_alphabetical(cursor) &&
      token_conflict_map.does_match_same_string(i, word_token_index) &&
      !token_conflict_map.does_match_different_string(i, word_token_index) {
      // (Upstream logs "Keywords - add candidate {}" at debug level.)
      keyword_candidates.insert(Symbol::terminal(i))
    }
  }

  // Exclude keyword candidates that shadow another keyword candidate.
  let candidate_terminals = keyword_candidates.terminals()
  let keywords = TokenSet::new()
  for token in candidate_terminals {
    let mut shadows = false
    for other in candidate_terminals {
      if other != token &&
        token_conflict_map.does_match_same_string(other, token) {
        // (Upstream logs the exclusion at debug level.)
        shadows = true
        break
      }
    }
    if !shadows {
      keywords.insert(Symbol::terminal(token))
    }
  }

  // Exclude keyword candidates for which substituting the keyword capture
  // token would introduce new lexical conflicts with other tokens.
  let result = TokenSet::new()
  for token in keywords.terminals() {
    let token_index = token
    let mut include = true
    for other_index in 0..<lexical_grammar.variables.length() {
      if keyword_candidates.contains(Symbol::terminal(other_index)) {
        continue
      }

      // If the word token was already valid in every state containing
      // this keyword candidate, then substituting the word token won't
      // introduce any new lexical conflicts.
      if coincident_token_index.all_coincident_states_have_word(
          token, other_index,
        ) {
        continue
      }
      if !token_conflict_map.has_same_conflict_status(
          token_index, word_token_index, other_index,
        ) {
        // (Upstream logs the exclusion at debug level.)
        include = false
        break
      }
    }
    if include {
      // (Upstream logs "Keywords - include {}" at debug level.)
      result.insert(Symbol::terminal(token))
    }
  }
  result
}

///|
fn mark_fragile_tokens(
  parse_table : ParseTable,
  token_conflict_map : TokenConflictMap,
) -> Unit {
  let valid_terminal_indices : Array[Int32] = []
  for state in parse_table.states {
    valid_terminal_indices.clear()
    for k in 0..<state.terminal_entries.len() {
      if state.terminal_entries.symbol_at(k).terminal_index() is Some(index) {
        valid_terminal_indices.push(index)
      }
    }
    for k in 0..<state.terminal_entries.len() {
      let token = state.terminal_entries.symbol_at(k)
      if token.terminal_index() is Some(index) {
        for i in valid_terminal_indices {
          if token_conflict_map.does_overlap(i, index) {
            let id = state.terminal_entries.value_at(k)
            state.terminal_entries.set_value_at(k, id.with_reusable(false))
            break
          }
        }
      }
    }
  }
}

///|
/// Upstream logs this report at info level; it is printed here.
fn report_state_info(
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  parse_table : ParseTable,
  parse_state_info : ParseStateInfo,
  str_pool : StrPool,
  report_symbol_name : String,
) -> Unit {
  let all_state_indices : Array[Int32] = []
  // Upstream's `BTreeSet`s; indices are added in increasing order.
  let symbols_with_state_indices : Array[(Int32, Array[Int32])] = Array::makei(
    syntax_grammar.variables.length(),
    i => (i, []),
  )
  for i, state in parse_table.states {
    all_state_indices.push(i)
    let item_set = parse_state_info.item_set(state.id)
    for entry in item_set.entries {
      if !entry.item.is_augmented() {
        let indices = symbols_with_state_indices[entry.item.variable_index].1
        if indices.last() != Some(i) {
          indices.push(i)
        }
      }
    }
  }
  // Upstream sorts `(usize, BTreeSet<usize>)` elements (32 bytes) with
  // `sort_unstable_by_key`, and rules with as many states tie.
  rust_sort_unstable_by_key_large(symbols_with_state_indices, entry => {
    -entry.1.length()
  })
  let mut max_symbol_name_length = 0
  for v in syntax_grammar.variables {
    let len = utf8_len(str_pool.resolve(v.name))
    if len > max_symbol_name_length {
      max_symbol_name_length = len
    }
  }
  for entry in symbols_with_state_indices {
    let (index, states) = entry
    let name = str_pool.resolve(syntax_grammar.variables[index].name)
    let padding = max_symbol_name_length - char_count(name)
    eprintln(
      "\{name}\{" ".repeat(if padding > 0 { padding } else { 0 })}\t\{states.length()}",
    )
  }
  eprintln("")
  let state_indices : Array[Int32]? = if report_symbol_name == "*" {
    Some(all_state_indices)
  } else {
    let mut found = None
    for entry in symbols_with_state_indices {
      if str_pool.resolve(syntax_grammar.variables[entry.0].name) ==
        report_symbol_name {
        found = Some(entry.1)
        break
      }
    }
    found
  }
  if state_indices is Some(state_indices) {
    let state_indices = state_indices.copy()
    state_indices.sort_by_key(i => (parse_table.states[i].core_id, i))
    for state_index in state_indices {
      let id = parse_table.states[state_index].id
      let preceding_symbols = parse_state_info.preceding_symbols_by_id[id]
      let item_set = parse_state_info.item_set(id)
      eprintln("state index: \{state_index}")
      eprintln("state id: \{id}")
      let names = preceding_symbols.map(symbol => {
        match symbol.kind {
          Terminal =>
            str_pool.resolve(lexical_grammar.variables[symbol.index].name)
          External =>
            str_pool.resolve(syntax_grammar.external_tokens[symbol.index].name)
          NonTerminal =>
            str_pool.resolve(syntax_grammar.variables[symbol.index].name)
          End => "<EOF>"
          EndOfNonTerminalExtra => "<END_OF_NONTERMINAL_EXTRA>"
        }
      })
      eprintln("symbol sequence: \{names.join(" ")}")
      eprintln(
        "\nitems:\n\{item_set.display(syntax_grammar, lexical_grammar, str_pool, parse_state_info.lookaheads)}",
      )
    }
  }
}

///|
fn all_chars_are_alphabetical(cursor : NfaCursor) -> Bool {
  cursor
  .transition_chars()
  .iter()
  .all(transition => {
    let (chars, is_sep) = transition
    if is_sep {
      true
    } else {
      chars.ranges().iter().all(range => all_alphabetic_or_underscore(range))
    }
  })
}

///|
/// Whether every scalar value in the inclusive range is `char::is_alphabetic`
/// or `_`. (`CharacterSet::ranges` already skips surrogates at range ends.)
fn all_alphabetic_or_underscore(range : (Int32, Int32)) -> Bool {
  let mut c = range.0
  let last = range.1
  while c <= last {
    if c == '_'.to_int() {
      c += 1
      continue
    }
    if c >= 0xD800 && c <= 0xDFFF {
      c = 0xE000
      continue
    }
    match alphabetic_range_containing(c) {
      Some(end) => c = end + 1
      None => return false
    }
  }
  true
}

///|
/// The last code point of the `alphabetic_ranges` entry containing `c`.
fn alphabetic_range_containing(c : Int32) -> Int32? {
  let mut lo = 0
  let mut hi = alphabetic_ranges.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let (first, last) = alphabetic_ranges[mid]
    if last < c {
      lo = mid + 1
    } else if first > c {
      hi = mid
    } else {
      return Some(last)
    }
  }
  None
}

///|
/// The length of `s` in UTF-8 bytes, like Rust's `str::len`.
fn utf8_len(s : String) -> Int32 {
  let mut n = 0
  for c in s {
    let c = c.to_int()
    n += if c < 0x80 {
      1
    } else if c < 0x800 {
      2
    } else if c < 0x10000 {
      3
    } else {
      4
    }
  }
  n
}

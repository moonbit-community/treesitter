// Port of tree-sitter crates/generate/src/prepare_grammar/extract_tokens.rs.

///|
pub(all) suberror ExtractTokensError {
  EmptyString(String)
  SupertypeTerminal(String)
  ExternalTokenNonTerminal(String)
  NonSymbolExternalToken
  WordToken(NonTerminalWordTokenError)
  NonTokenReservedWord(String)
} derive(Eq, Debug)

///|
pub impl Show for ExtractTokensError with fn output(self, logger) {
  match self {
    EmptyString(name) =>
      logger.write_string(
        (
          $|The rule `\{name}` contains an empty string.
          $|
          $|Tree-sitter does not support syntactic rules that contain an empty string
          $|unless they are used only as the grammar's start rule.
          $|
        ),
      )
    SupertypeTerminal(name) =>
      logger.write_string(
        "Terminal rule '\{name}' cannot be used as a supertype",
      )
    ExternalTokenNonTerminal(name) =>
      logger.write_string(
        "Rule '\{name}' cannot be used as both an external token and a non-terminal rule",
      )
    NonSymbolExternalToken =>
      logger.write_string("Non-symbol rules cannot be used as external tokens")
    WordToken(error) => Show::output(error, logger)
    NonTokenReservedWord(name) =>
      logger.write_string("Reserved word '\{name}' must be a token")
  }
}

///|
pub(all) struct NonTerminalWordTokenError {
  symbol_name : String
  conflicting_symbol_name : String?
} derive(Eq, Debug)

///|
pub impl Show for NonTerminalWordTokenError with fn output(self, logger) {
  logger.write_string(
    "Non-terminal symbol '\{self.symbol_name}' cannot be used as the word token",
  )
  if self.conflicting_symbol_name is Some(conflicting_name) {
    logger.write_string(
      ", because its rule is duplicated in '\{conflicting_name}'\n",
    )
  } else {
    logger.write_string("\n")
  }
}

///|
/// Syntax grammar metadata produced during token extraction.
///
/// Its symbols are resolved to their final indices before deferred pool rewrites
/// are committed.
priv struct ExtractedGrammarMeta {
  kinds : Array[VariableType]
  extra_symbols : Array[Symbol]
  external_tokens : Array[ExternalToken]
  reserved_sets : Array[(StrId, Array[Symbol])]
  supertypes : Array[Symbol]
  conflicts : Array[Array[Symbol]]
  inline : Array[Symbol]
  word : Symbol?
}

///|
/// Token de-duper over pool subtrees
priv struct TokenExtractor {
  lexical : Array[LexicalToken]
  usage_counts : Array[Int32]
  /// Keyed by `subtree_hash`; only used for lookups. The tokens in a bucket are
  /// pairwise distinct, so at most one candidate can match.
  memo : Map[Int32, Array[Int32]]
  /// Terminal rewrites deferred until lexical expansion has consumed the original pool nodes.
  rewrites : Array[(RuleId, Int32)]
}

///|
fn TokenExtractor::new() -> TokenExtractor {
  { lexical: [], usage_counts: [], memo: Map([]), rewrites: [], }
}

///|
/// Find or create the lexical token for `token_root`. Returns the terminal index if found
fn TokenExtractor::extract_token(
  self : TokenExtractor,
  pool : RulePool,
  token_root : RuleId,
  string_name : StrId?,
  var_name : StrId?,
  aux_token_count : Ref[Int32],
  is_first : Bool,
) -> Int32 raise ExtractTokensError {
  let hash = pool.subtree_hash(token_root)
  if self.memo.get(hash) is Some(candidates) {
    for i in candidates {
      if pool.subtree_eq(self.lexical[i].root, token_root) {
        self.usage_counts[i] += 1
        return i
      }
    }
  }
  let (name, kind) = match string_name {
    Some(sid) => {
      if pool.resolve(sid).is_empty() && !is_first {
        raise EmptyString(
          match var_name {
            Some(v) => pool.resolve(v)
            None => ""
          },
        )
      }
      (sid, Anonymous)
    }
    None => {
      aux_token_count.val += 1
      let prefix = match var_name {
        Some(v) => pool.resolve(v)
        None => ""
      }
      let name = "\{prefix}_token\{aux_token_count.val}"
      (pool.intern(name), Auxiliary)
    }
  }
  // Shallow hoist: create a new token id pointing to the same pooled subtree.
  // The original `token_root` slot is overwritten by caller to be a token, but it still
  // points to the subtree. This new node becomes the token's root in the lexical grammar.
  let index = self.lexical.length()
  let root = pool.push_node(pool.node(token_root))
  self.lexical.push({ name, kind, root, })
  self.usage_counts.push(1)
  match self.memo.get(hash) {
    Some(candidates) => candidates.push(index)
    None => self.memo[hash] = [index]
  }
  index
}

///|
/// Token extraction over one root. Records each terminal rewrite so that all
/// roots are inspected before any shared pool node is mutated.
///  - `String`/`Pattern`: always extracted
///  - `token(...)`: metadata extracts the inner child when no other metadata params are set,
///    otherwise the whole metadata node
fn TokenExtractor::extract_in_root(
  self : TokenExtractor,
  pool : RulePool,
  root : RuleId,
  var_name : StrId?,
  is_first : Bool,
  stack : Array[RuleId],
) -> Unit raise ExtractTokensError {
  let aux_token_count : Ref[Int32] = { val: 0, }
  stack.clear()
  stack.push(root)
  while stack.pop() is Some(id) {
    match pool.node(id) {
      String(sid) => {
        let i = self.extract_token(
          pool,
          id,
          Some(sid),
          var_name,
          aux_token_count,
          is_first,
        )
        self.rewrites.push((id, i))
      }
      Pattern(_, _) => {
        let i = self.extract_token(
          pool,
          id,
          None,
          var_name,
          aux_token_count,
          is_first,
        )
        self.rewrites.push((id, i))
      }
      Metadata(params~, rule~) => {
        let p = pool.params(params)
        if p.is_token {
          let cleaned = { ..p, is_token: false, }
          let string_name = match pool.node(rule) {
            String(s) => Some(s)
            _ => None
          }
          let token_root = if cleaned == default_params {
            rule // Only a token, drop the wrapper
          } else {
            id
          }
          let i = self.extract_token(
            pool, token_root, string_name, var_name, aux_token_count, is_first,
          )
          self.rewrites.push((id, i))
        } else {
          stack.push(rule)
        }
      }
      Seq(range) | Choice(range) => {
        let children = pool.child_slice(range)
        for i = children.length() - 1; i >= 0; i = i - 1 {
          stack.push(children[i])
        }
      }
      Repeat(inner) | Reserved(rule=inner, ..) => stack.push(inner)
      _ => ()
    }
  }
}

///|
/// Find the lexical token whose body is structurally equal to `root`.
fn TokenExtractor::find(
  self : TokenExtractor,
  pool : RulePool,
  root : RuleId,
) -> Int32? {
  match self.memo.get(pool.subtree_hash(root)) {
    Some(candidates) =>
      for i in candidates {
        if pool.subtree_eq(self.lexical[i].root, root) {
          break Some(i)
        }
      } nobreak {
        None
      }
    None => None
  }
}

///|
/// Sort pending rewrites for lookup and coalesce duplicate visits to shared nodes.
fn TokenExtractor::finalize_rewrites(self : TokenExtractor) -> Unit {
  // Upstream uses `sort_unstable_by_key` on the whole `(id, token)` pair, so
  // ties are between identical elements and the result is deterministic.
  self.rewrites.sort_by_key(r => (r.0.index(), r.1))
  dedup(self.rewrites)
  // Discovery only observes unmodified subtrees, so a node can map to just
  // one terminal. The binary search in [`Self::symbol_after_rewrites`] and
  // the commit loop both rely on the keys being unique.
}

///|
/// Return the symbol `id` will contain after committing pending rewrites, without
/// mutating the pool.
fn TokenExtractor::symbol_after_rewrites(
  self : TokenExtractor,
  pool : RulePool,
  id : RuleId,
) -> Symbol? {
  let mut lo = 0
  let mut hi = self.rewrites.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let key = self.rewrites[mid].0.index()
    if key == id.index() {
      return Some(Symbol::terminal(self.rewrites[mid].1))
    } else if key < id.index() {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  pool.node(id).symbol()
}

///|
/// Token extraction's pending result.
///
/// Upstream holds a mutable borrow of the [`InputGrammar`] to prevent other
/// passes from changing the pool while token and separator roots still refer
/// to their original bodies. [`Self::expand_and_commit`] consumes this, expands
/// the bodies, and commits the deferred terminal rewrites and renumbers symbols.
priv struct PendingTokenExtraction {
  grammar : InputGrammar
  meta : ExtractedGrammarMeta
  lexical_variables : Array[LexicalToken]
  separator_roots : Array[RuleId]
  rewrites : Array[(RuleId, Int32)]
  syntax_variable_replacements : Map[Int32, Int32]
  syntax_variable_shift : Array[Int32]
  stack : Array[RuleId]
}

///|
/// Expand the token and separator roots, then commit the terminal rewrites and
/// renumber the remaining syntax symbols.
fn PendingTokenExtraction::expand_and_commit(
  self : PendingTokenExtraction,
) -> (ExtractedGrammarMeta, LexicalGrammar) raise {
  let {
    grammar,
    meta,
    lexical_variables,
    separator_roots,
    rewrites,
    syntax_variable_replacements,
    syntax_variable_shift,
    stack,
  } = self
  let lexical_grammar = expand_tokens(
    grammar.pool,
    lexical_variables,
    separator_roots,
  )
  for rewrite in rewrites {
    let (id, token_index) = rewrite
    grammar.pool.set_node(id, Sym(Symbol::terminal(token_index)))
  }
  let replace_symbol = (symbol : Symbol) => {
    guard symbol.non_terminal_index() is Some(index) else { return symbol }
    match syntax_variable_replacements.get(index) {
      Some(token_index) => Symbol::terminal(token_index)
      None => Symbol::non_terminal(index - syntax_variable_shift[index])
    }
  }
  if !syntax_variable_replacements.is_empty() {
    let renumbered_nodes = FixedArray::make(grammar.pool.node_count(), false)
    for variable in grammar.variables {
      renumber_root(
        grammar.pool,
        variable.root,
        replace_symbol,
        stack,
        renumbered_nodes,
      )
    }
    for root in grammar.external_roots {
      renumber_root(grammar.pool, root, replace_symbol, stack, renumbered_nodes)
    }
  }
  (meta, lexical_grammar)
}

///|
fn extract_tokens(
  g : InputGrammar,
  interned : InternedGrammarMeta,
) -> PendingTokenExtraction raise ExtractTokensError {
  let extractor = TokenExtractor::new()
  let stack = []
  for i, v in g.variables {
    extractor.extract_in_root(g.pool, v.root, Some(v.name), i == 0, stack)
  }
  for i, root in g.external_roots {
    let (name, _) = interned.external_tokens[i]
    extractor.extract_in_root(g.pool, root, name, false, stack)
  }
  extractor.finalize_rewrites()

  // If a variable's entire rule was extracted as a token and that token didn't
  // appear within any other rule, then remove that variable from the syntax
  // grammar, giving its name to the token in the lexical grammar. Any symbols
  // that pointed to that variable will need to be updated to point to the
  // token in the lexical grammar. Symbols that pointed to later variables
  // will need to have their indices decremented.
  let old_len = g.variables.length()
  let replacements : Map[Int32, Int32] = Map([])
  let retained = []
  let kinds = []

  // The start variable cannot be absorbed
  retained.push(g.variables[0])
  kinds.push(interned.kinds[0])
  for i in 1..<g.variables.length() {
    let v = g.variables[i]
    if extractor.symbol_after_rewrites(g.pool, v.root) is Some(symbol) &&
      symbol.terminal_index() is Some(index) &&
      extractor.usage_counts[index] == 1 {
      let lexical = extractor.lexical[index]
      if lexical.kind == Auxiliary || interned.kinds[i] != Hidden {
        extractor.lexical[index] = {
          ..lexical,
          kind: interned.kinds[i],
          name: v.name,
        }
        replacements[i] = index
        continue
      }
    }
    retained.push(v)
    kinds.push(interned.kinds[i])
  }
  g.variables = retained

  // Prefix-sum renumbering
  let shift = Array::make(old_len, 0)
  let mut removed = 0
  for i in 0..<old_len {
    shift[i] = removed
    if replacements.contains(i) {
      removed += 1
    }
  }
  let replace_symbol = (s : Symbol) => {
    guard s.non_terminal_index() is Some(index) else { return s }
    match replacements.get(index) {
      Some(r) => Symbol::terminal(r)
      None => Symbol::non_terminal(index - shift[index])
    }
  }

  // Renumber each conflict through absorption, then canonicalize
  let conflicts = interned.conflicts.map(c => {
    let result = c.map(s => replace_symbol(s))
    // `sort_unstable` on a total order over the whole value.
    result.sort()
    dedup(result)
    result
  })
  let supertypes = interned.supertypes.map(s => {
    let sym = replace_symbol(s)
    // A supertype that got absorbed into a token isn't allowed
    if sym.terminal_index() is Some(index) {
      raise SupertypeTerminal(g.pool.resolve(extractor.lexical[index].name))
    }
    sym
  })
  let inline = interned.inline.map(s => replace_symbol(s))

  // Resolve each metadata root to the symbol it will represent after token extraction.
  // If that symbol is still a non terminal, adjust its index for any grammar
  // variables removed above. The syntax rules are renumbered only after all metadata
  // roots have been resolved.
  let separator_roots = []
  let extra_symbols = []
  for root in g.extra_roots {
    if extractor.symbol_after_rewrites(g.pool, root) is Some(s) {
      extra_symbols.push(replace_symbol(s))
    } else if extractor.find(g.pool, root) is Some(i) {
      extra_symbols.push(Symbol::terminal(i))
    } else {
      separator_roots.push(root)
    }
  }
  let external_tokens = []
  for i, root in g.external_roots {
    let (name, kind) = interned.external_tokens[i]
    guard extractor.symbol_after_rewrites(g.pool, root) is Some(s) else {
      raise NonSymbolExternalToken
    }
    let s = replace_symbol(s)
    if s.non_terminal_index() is Some(index) {
      raise ExternalTokenNonTerminal(g.pool.resolve(g.variables[index].name))
    }
    external_tokens.push(
      match s.kind {
        External => {
          guard name is Some(name) else { raise NonSymbolExternalToken }
          { name, kind, corresponding_internal_token: None, }
        }
        Terminal =>
          {
            name: extractor.lexical[s.index].name,
            kind,
            corresponding_internal_token: Some(s),
          }
        NonTerminal | End | EndOfNonTerminalExtra => abort("unreachable")
      },
    )
  }
  let word = match interned.word {
    Some(w) => Some(replace_symbol(w))
    None => None
  }
  if word is Some(w) && w.non_terminal_index() is Some(token_index) {
    let word_root = g.variables[token_index].root
    let conflicting_symbol_name = for i, v in g.variables {
      if i != token_index && g.pool.subtree_eq(v.root, word_root) {
        break Some(g.pool.resolve(v.name))
      }
    } nobreak {
      None
    }
    raise WordToken({
      symbol_name: g.pool.resolve(g.variables[token_index].name),
      conflicting_symbol_name,
    })
  }
  let reserved_sets = []
  for set in g.reserved_sets {
    let symbols = []
    for root in set.roots {
      if extractor.symbol_after_rewrites(g.pool, root) is Some(s) {
        symbols.push(replace_symbol(s))
      } else if extractor.find(g.pool, root) is Some(i) {
        symbols.push(Symbol::terminal(i))
      } else {
        let inner = match g.pool.node(root) {
          Metadata(rule~, ..) => g.pool.node(rule)
          node => node
        }
        let token_name = match inner {
          String(s) | Pattern(s, _) => g.pool.resolve(s)
          _ => "unknown"
        }
        raise NonTokenReservedWord(token_name)
      }
    }
    reserved_sets.push((set.name, symbols))
  }
  let meta : ExtractedGrammarMeta = {
    kinds,
    extra_symbols,
    external_tokens,
    reserved_sets,
    supertypes,
    conflicts,
    inline,
    word,
  }
  {
    grammar: g,
    meta,
    lexical_variables: extractor.lexical,
    separator_roots,
    rewrites: extractor.rewrites,
    syntax_variable_replacements: replacements,
    syntax_variable_shift: shift,
    stack,
  }
}

///|
/// Renumber nodes reachable from `root`, skipping every node already reached via
/// another root in this renumbering pass.
fn renumber_root(
  pool : RulePool,
  root : RuleId,
  replace : (Symbol) -> Symbol,
  stack : Array[RuleId],
  visited : FixedArray[Bool],
) -> Unit {
  stack.clear()
  stack.push(root)
  while stack.pop() is Some(id) {
    if visited[id.index()] {
      continue
    }
    visited[id.index()] = true
    match pool.node(id) {
      Sym(symbol) => {
        let replaced = replace(symbol)
        pool.set_node(id, Sym(replaced))
      }
      Seq(range) | Choice(range) =>
        for child in pool.child_slice(range) {
          stack.push(child)
        }
      Repeat(inner) | Metadata(rule=inner, ..) | Reserved(rule=inner, ..) =>
        stack.push(inner)
      _ => ()
    }
  }
}

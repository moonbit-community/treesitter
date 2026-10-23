// Port of tree-sitter crates/generate/src/prepare_grammar/flatten_grammar.rs.

///|
pub(all) suberror FlattenGrammarError {
  NoReservedWordSet(String)
  TooManyReservedWordSets(Int32)
  EmptyString(String)
  RecursiveInline(String)
  NoReachableProductions(String)
} derive(Eq, Debug)

///|
pub impl Show for FlattenGrammarError with fn output(self, logger) {
  match self {
    NoReservedWordSet(name) =>
      logger.write_string("No such reserved word set: \{name}")
    TooManyReservedWordSets(count) =>
      logger.write_string(
        "Reserved word set count \{count} exceeds the maximum of 65535",
      )
    EmptyString(name) =>
      logger.write_string(
        (
          $|The rule `\{name}` matches the empty string.
          $|
          $|Tree-sitter does not support syntactic rules that match the empty string
          $|unless they are used only as the grammar's start rule.
          $|
        ),
      )
    RecursiveInline(name) =>
      logger.write_string(
        "Rule `\{name}` cannot be inlined because it contains a reference to itself",
      )
    NoReachableProductions(name) =>
      logger.write_string("Rule `\{name}` has no reachable productions.")
  }
}

///|
priv struct FlattenCtx {
  prec : Precedence
  assoc : Associativity?
  alias : Alias?
  field : StrId?
  reserved : Int32
}

///|
let flatten_ctx_default : FlattenCtx = {
  prec: NoPrecedence,
  assoc: None,
  alias: None,
  field: None,
  reserved: 0,
}

///|
/// Selects one branch at each choice encountered during a root-to-leaf walk. After
/// a production is emitted, `advance` increments this path like a mixed-radix counter.
/// Later decisions are discarded because choosing an earlier branch can expose a
/// different set of nested choices.
priv struct ChoiceCursor {
  decisions : Array[Int32]
  arities : Array[Int32]
  mut depth : Int32
}

///|
/// Begin a new walk for a new variable.
fn ChoiceCursor::reset(self : ChoiceCursor) -> Unit {
  self.decisions.clear()
  self.arities.clear()
  self.depth = 0
}

///|
/// Begin a new walk for the same variable as a previous walk
fn ChoiceCursor::begin_path(self : ChoiceCursor) -> Unit {
  self.arities.clear()
  self.depth = 0
}

///|
/// Called at each choice. Selects which path to take, and records the decision.
fn ChoiceCursor::select(self : ChoiceCursor, len : Int32) -> Int32 {
  let selected = self.decisions.get(self.depth).unwrap_or(0)
  self.arities.push(len)
  self.depth += 1
  selected
}

///|
/// Find the latest path that we can advance and discard every decision after it.
/// Returns whether a new path could be found.
fn ChoiceCursor::advance(self : ChoiceCursor) -> Bool {
  for depth = self.arities.length() - 1; depth >= 0; depth = depth - 1 {
    let selected = self.decisions.get(depth).unwrap_or(0)
    if selected + 1 < self.arities[depth] {
      // `Vec::resize(depth + 1, 0)`
      if self.decisions.length() > depth + 1 {
        self.decisions.truncate(depth + 1)
      }
      while self.decisions.length() < depth + 1 {
        self.decisions.push(0)
      }
      self.decisions[depth] = selected + 1
      return true
    }
  }
  false
}

///|
/// Reusable scratch for enumerating and flattening one production path at a time.
priv struct FlattenState {
  steps : Array[ProductionStep]
  choices : ChoiceCursor
  mut dyn_prec : Int32
  mut dead : Bool
  /// The positions in [`ProductionStore::productions`] of the current variable's
  /// productions, by the hash of their [`ProdRef`]. Only used for lookups.
  mut emitted : Map[Int32, Array[Int32]]
}

///|
fn FlattenState::new() -> FlattenState {
  {
    steps: [],
    choices: { decisions: [], arities: [], depth: 0, },
    dyn_prec: 0,
    dead: false,
    emitted: Map([]),
  }
}

///|
fn FlattenState::reset_variable(self : FlattenState) -> Unit {
  self.choices.reset()
  self.emitted = Map([])
  self.reset_path()
}

///|
fn FlattenState::reset_path(self : FlattenState) -> Unit {
  self.steps.clear()
  self.dyn_prec = 0
  self.dead = false
  self.choices.begin_path()
}

///|
fn FlattenState::push_step(
  self : FlattenState,
  symbol : Symbol,
  ctx : FlattenCtx,
) -> Unit {
  self.steps.push(
    ProductionStep::pack(
      symbol,
      ctx.prec,
      ctx.assoc,
      ctx.alias,
      ctx.field,
      ctx.reserved,
    ),
  )
}

///|
fn FlattenState::restore_outer_prec(
  self : FlattenState,
  outer : Precedence,
) -> Unit {
  let last = self.steps.length() - 1
  self.steps[last] = self.steps[last].with_precedence(outer)
}

///|
fn FlattenState::restore_outer_assoc(
  self : FlattenState,
  outer : Associativity?,
) -> Unit {
  let last = self.steps.length() - 1
  self.steps[last] = self.steps[last].with_associativity(outer)
}

///|
/// Flatten one deterministic path. Choices only select a child, the outer loop in
/// the caller enumerates subsequent paths from the root.
fn flatten_apply(
  pool : RulePool,
  reserved_ids : Map[StrId, Int32],
  node : RuleId,
  f_ctx : FlattenCtx,
  at_end : Bool,
  st : FlattenState,
) -> Bool raise FlattenGrammarError {
  match pool.node(node) {
    Sym(symbol) => {
      st.push_step(symbol, f_ctx)
      true
    }
    Seq(range) => {
      let children = pool.child_slice(range)
      let mut did_push = false
      for i, child in children {
        if flatten_apply(
            pool,
            reserved_ids,
            child,
            f_ctx,
            at_end && i + 1 == children.length(),
            st,
          ) {
          did_push = true
        }
        if st.dead {
          break
        }
      }
      did_push
    }
    Choice(range) => {
      // An empty choice matches nothing, so no production can contain it.
      if range.len == 0 {
        st.dead = true
        return false
      }
      let selected = st.choices.select(range.len)
      let child = pool.child_slice(range)[selected]
      flatten_apply(pool, reserved_ids, child, f_ctx, at_end, st)
    }
    Eof => {
      st.push_step(symbol_end, f_ctx)
      true
    }
    Metadata(params~, rule~) => {
      let params = pool.params(params)
      let inner_ctx = {
        prec: if params.precedence != NoPrecedence {
          params.precedence
        } else {
          f_ctx.prec
        },
        assoc: if params.associativity is Some(_) {
          params.associativity
        } else {
          f_ctx.assoc
        },
        alias: if params.alias is Some(_) {
          params.alias
        } else {
          f_ctx.alias
        },
        field: if params.field is Some(_) {
          params.field
        } else {
          f_ctx.field
        },
        reserved: f_ctx.reserved,
      }
      if params.dynamic_precedence.abs() > st.dyn_prec.abs() {
        st.dyn_prec = params.dynamic_precedence
      }
      let did_push = flatten_apply(
        pool, reserved_ids, rule, inner_ctx, at_end, st,
      )
      // A step's prec/assoc governs the parse position just _after_ it, so the
      // regions's last step owns the gap past it. If more steps follow, that gap
      // is outside the region and reverts to the outer context. At the production's
      // tail the gap is the reduce and keeps the region's own value.
      if did_push && !at_end {
        if params.precedence != NoPrecedence {
          st.restore_outer_prec(f_ctx.prec)
        }
        if params.associativity is Some(_) {
          st.restore_outer_assoc(f_ctx.assoc)
        }
      }
      did_push
    }
    Reserved(rule~, ctx~) => {
      guard reserved_ids.get(ctx) is Some(reserved) else {
        raise NoReservedWordSet(pool.resolve(ctx))
      }
      let inner = { ..f_ctx, reserved, }
      flatten_apply(pool, reserved_ids, rule, inner, at_end, st)
    }
    _ => false
  }
}

///|
/// Append the completed path as a production unless this variable already has an
/// identical one. A path with `eof()` anywhere but the final step is discarded,
/// since such a production could never be completed.
fn flatten_emit(st : FlattenState, out : ProductionStore) -> Bool {
  let last = if st.steps.length() > 0 { st.steps.length() - 1 } else { 0 }
  let eof_index = for i, step in st.steps {
    if step.symbol == symbol_end {
      break Some(i)
    }
  } nobreak {
    None
  }
  guard eof_index is Some(eof_index) else {
    return flatten_emit_ready(st, out, false)
  }
  if eof_index != last {
    return false
  }
  ignore(st.steps.pop())
  flatten_emit_ready(st, out, true)
}

///|
fn flatten_emit_ready(
  st : FlattenState,
  out : ProductionStore,
  requires_eof_lookahead : Bool,
) -> Bool {
  let production : ProdRef = {
    steps: st.steps[:],
    dynamic_precedence: st.dyn_prec,
    requires_eof_lookahead,
  }
  let hash = production.hash()
  match st.emitted.get(hash) {
    Some(candidates) =>
      for index in candidates {
        if out.production(index) == production {
          // This variable already has an identical production.
          return true
        }
      }
    None => ()
  }
  let index = out.productions.length()
  match st.emitted.get(hash) {
    Some(candidates) => candidates.push(index)
    None => st.emitted[hash] = [index]
  }
  let steps_start = out.steps.length()
  for step in st.steps {
    out.steps.push(step)
  }
  out.productions.push({
    steps_start,
    steps_len: st.steps.length(),
    dynamic_precedence: st.dyn_prec,
    requires_eof_lookahead,
  })
  true
}

///|
fn flatten_grammar(
  g : InputGrammar,
  meta : ExtractedGrammarMeta,
  st : FlattenState,
  out : ProductionStore,
) -> Unit raise FlattenGrammarError {
  if meta.reserved_sets.length() > 65535 {
    raise TooManyReservedWordSets(meta.reserved_sets.length())
  }
  // Last wins on duplicate names.
  let reserved_ids : Map[StrId, Int32] = Map([])
  for i, set in meta.reserved_sets {
    reserved_ids[set.0] = i
  }
  for v in g.variables {
    let prod_start = out.productions.length()
    let mut dropped_for_eof = false
    st.reset_variable()
    for ;; {
      ignore(
        flatten_apply(
          g.pool,
          reserved_ids,
          v.root,
          flatten_ctx_default,
          true,
          st,
        ),
      )
      if !st.dead {
        if !flatten_emit(st, out) {
          dropped_for_eof = true
        }
      }
      if !st.choices.advance() {
        break
      }
      st.reset_path()
    }
    if dropped_for_eof && prod_start == out.productions.length() {
      raise NoReachableProductions(g.pool.resolve(v.name))
    }
    out.var_prods.push((prod_start, out.productions.length()))
  }
  flatten_check(g, meta, out)
}

///|
/// Post-flatten checks. No empty productions used in variables, and no recursive inlines.
fn flatten_check(
  g : InputGrammar,
  meta : ExtractedGrammarMeta,
  out : ProductionStore,
) -> Unit raise FlattenGrammarError {
  // Which variables appear in some production, by index. A step naming a non-terminal
  // that has no variable (as in some hand-built test grammars) uses none of them.
  let used = Array::make(out.var_prods.length(), false)
  for step in out.steps {
    if step.symbol.non_terminal_index() is Some(index) && index < used.length() {
      used[index] = true
    }
  }
  for i, range in out.var_prods {
    let (p_start, p_end) = range
    let symbol = Symbol::non_terminal(i)
    let inlined = meta.inline.contains(symbol)
    for p in out.productions[p_start:p_end] {
      if used[i] && p.steps_len == 0 && !p.requires_eof_lookahead {
        raise EmptyString(g.pool.resolve(g.variables[i].name))
      }
      if inlined &&
        out.steps[p.steps_start:p.steps_start + p.steps_len]
        .iter()
        .any(s => s.symbol == symbol) {
        raise RecursiveInline(g.pool.resolve(g.variables[i].name))
      }
    }
  }
}

///|
fn assemble_syntax_grammar(
  g : InputGrammar,
  meta : ExtractedGrammarMeta,
  out : ProductionStore,
) -> (SyntaxGrammar, StrPool) {
  let reserved_word_sets = meta.reserved_sets.map(set => {
    TokenSet::from_array(set.1)
  })
  if reserved_word_sets.is_empty() {
    reserved_word_sets.push(TokenSet::new())
  }
  // `zip`: as long as the shorter of the two.
  let variables : Array[SyntaxVariable] = []
  for i, v in g.variables {
    guard meta.kinds.get(i) is Some(kind) else { break }
    variables.push({ name: v.name, kind, })
  }
  let interner = g.pool.str_pool
  (
    {
      variables,
      extra_symbols: meta.extra_symbols,
      expected_conflicts: meta.conflicts,
      external_tokens: meta.external_tokens,
      supertype_symbols: meta.supertypes,
      variables_to_inline: meta.inline,
      word_token: meta.word,
      precedence_orderings: g.precedence_orderings,
      reserved_word_sets,
      steps: out.steps,
      productions: out.productions,
      var_prods: out.var_prods,
    },
    interner,
  )
}

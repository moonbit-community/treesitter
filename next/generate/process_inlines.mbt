// Port of tree-sitter crates/generate/src/prepare_grammar/process_inlines.rs.

///|
priv struct InlineBuilder {
  out : ProductionStore
  first_inlined : Int32
  inline : Array[Symbol]
  map : Map[(Int32, Int32), Array[Int32]]
  /// Keyed by the hash of a production's contents; only used for lookups. The
  /// productions in a bucket are pairwise distinct, so at most one can match.
  memo : Map[Int32, Array[Int32]]
}

///|
priv struct ScratchProd {
  steps : Array[ProductionStep]
  mut dynamic_precedence : Int32
  mut requires_eof_lookahead : Bool
}

///|
/// Returns the inline map along with the ids of productions whose every expansion
/// was dropped.
fn InlineBuilder::build(
  self : InlineBuilder,
) -> (InlinedProductionMap, @hashset.HashSet[Int32]) {
  let dead = @hashset.HashSet([])
  let fully_inlined : Map[Int32, InlinedProductionRange] = Map([])
  let fully_inlined_ids = []
  let worklist : Array[(Int32, Int32)] = []
  let final_productions = []
  for prod_id in 0..<self.first_inlined {
    let mut survived = false
    let mut did_inline = false
    final_productions.clear()
    worklist.push((prod_id, 0))
    while !worklist.is_empty() {
      let mut i = 0
      while i < worklist.length() {
        let (prod_id, step_index) = worklist[i]
        if self.production_step_for_id(prod_id, step_index) is Some(step) {
          if self.inline.contains(step.symbol) {
            did_inline = true
            let ids = self.inline_production_at_step(prod_id, step_index)
            // `worklist.splice(i..=i, ids.map(|id| (id, step_index)))`
            ignore(worklist.remove(i))
            for k, id in ids {
              worklist.insert(i + k, (id, step_index))
            }
          } else {
            worklist[i] = (prod_id, step_index + 1)
            i += 1
          }
        } else {
          final_productions.push(prod_id)
          ignore(worklist.remove(i))
          survived = true
        }
      }
    }
    // An unchanged production always survives
    if !survived {
      dead.add(prod_id)
    } else if did_inline {
      let start = fully_inlined_ids.length()
      for id in final_productions {
        fully_inlined_ids.push(id)
      }
      let end = fully_inlined_ids.length()
      fully_inlined[prod_id] = { start, end, }
    }
  }
  ({ map: self.map, fully_inlined, fully_inlined_ids, }, dead)
}

///|
/// Expand inlining at one step of one production, dedup, and store the results
fn InlineBuilder::inline_production_at_step(
  self : InlineBuilder,
  prod_id : Int32,
  step_index : Int32,
) -> Array[Int32] {
  if self.map.get((prod_id, step_index)) is Some(ids) {
    return ids.copy()
  }
  let si = step_index
  let src = self.out.productions[prod_id]
  let scratch : Array[ScratchProd] = [
    {
      steps: self.out.steps[src.steps_start:src.steps_start + src.steps_len].to_owned(),
      dynamic_precedence: src.dynamic_precedence,
      requires_eof_lookahead: src.requires_eof_lookahead,
    },
  ]
  let mut i = 0
  while i < scratch.length() {
    let symbol = match scratch[i].steps.get(si) {
      Some(s) if self.inline.contains(s.symbol) => s.symbol
      _ => {
        i += 1
        continue
      }
    }
    let removed_prod = scratch[i]
    let removed_step = removed_prod.steps[si]
    guard symbol.non_terminal_index() is Some(index) else {
      abort("unreachable")
    }
    let (v_start, v_end) = self.out.var_prods[index]
    let replacements = []
    for p_idx in v_start..<v_end {
      let p = self.out.productions[p_idx]
      if p.requires_eof_lookahead && si + 1 < removed_prod.steps.length() {
        continue
      }
      let steps = []
      for k in 0..<si {
        steps.push(removed_prod.steps[k])
      }
      for k in 0..<p.steps_len {
        steps.push(self.out.steps[p.steps_start + k])
      }
      for k in (si + 1)..<removed_prod.steps.length() {
        steps.push(removed_prod.steps[k])
      }
      let production : ScratchProd = {
        steps,
        dynamic_precedence: removed_prod.dynamic_precedence,
        requires_eof_lookahead: removed_prod.requires_eof_lookahead,
      }
      if removed_step.alias is Some(removed_alias) {
        for k in si..<(si + p.steps_len) {
          production.steps[k] = production.steps[k].with_alias(
            Some(removed_alias),
          )
        }
      }
      if removed_step.field is Some(removed_field) {
        for k in si..<(si + p.steps_len) {
          production.steps[k] = production.steps[k].with_field(
            Some(removed_field),
          )
        }
      }
      if p.steps_len > 0 {
        let k = si + p.steps_len - 1
        let last = production.steps[k]
        let last = if last.precedence == NoPrecedence {
          last.with_precedence(removed_step.precedence)
        } else {
          last
        }
        let last = if last.associativity is None {
          last.with_associativity(removed_step.associativity)
        } else {
          last
        }
        production.steps[k] = last
      }
      if p.dynamic_precedence.abs() > production.dynamic_precedence.abs() {
        production.dynamic_precedence = p.dynamic_precedence
      }
      production.requires_eof_lookahead = production.requires_eof_lookahead ||
        p.requires_eof_lookahead
      replacements.push(production)
    }
    // `scratch.splice(i..=i, replacements)`
    ignore(scratch.remove(i))
    for k, r in replacements {
      scratch.insert(i + k, r)
    }
  }
  let result = []
  for sp in scratch {
    let hasher = Hasher()
    hasher.combine_int(sp.dynamic_precedence)
    hasher.combine_bool(sp.requires_eof_lookahead)
    hasher.combine_int(sp.steps.length())
    for step in sp.steps {
      hasher.combine(step)
    }
    let hash = hasher.finalize()
    let candidates = match self.memo.get(hash) {
      Some(candidates) => candidates
      None => {
        let candidates = []
        self.memo[hash] = candidates
        candidates
      }
    }
    let existing = for id in candidates {
      let p = self.out.productions[id]
      if p.dynamic_precedence == sp.dynamic_precedence &&
        p.requires_eof_lookahead == sp.requires_eof_lookahead &&
        steps_equal(
          self.out.steps[p.steps_start:p.steps_start + p.steps_len],
          sp.steps,
        ) {
        break Some(id)
      }
    } nobreak {
      None
    }
    result.push(
      match existing {
        Some(id) => id
        None => {
          let steps_start = self.out.steps.length()
          for step in sp.steps {
            self.out.steps.push(step)
          }
          self.out.productions.push({
            steps_start,
            steps_len: sp.steps.length(),
            dynamic_precedence: sp.dynamic_precedence,
            requires_eof_lookahead: sp.requires_eof_lookahead,
          })
          let id = self.out.productions.length() - 1
          candidates.push(id)
          id
        }
      },
    )
  }
  self.map[(prod_id, step_index)] = result.copy()
  result
}

///|
fn steps_equal(
  a : ArrayView[ProductionStep],
  b : Array[ProductionStep],
) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
fn InlineBuilder::production_step_for_id(
  self : InlineBuilder,
  prod_id : Int32,
  step : Int32,
) -> ProductionStep? {
  let p = self.out.productions[prod_id]
  if step < p.steps_len {
    Some(self.out.steps[p.steps_start + step])
  } else {
    None
  }
}

///|
pub(all) suberror ProcessInlinesError {
  ExternalToken(String)
  Token(String)
  FirstRule(String)
  NoReachableProductions(String)
} derive(Eq, Debug)

///|
pub impl Show for ProcessInlinesError with fn output(self, logger) {
  match self {
    ExternalToken(name) =>
      logger.write_string("External token `\{name}` cannot be inlined")
    Token(name) => logger.write_string("Token `\{name}` cannot be inlined")
    FirstRule(name) =>
      logger.write_string(
        "Rule `\{name}` cannot be inlined because it is the first rule",
      )
    NoReachableProductions(name) =>
      logger.write_string(
        "Rule `\{name}` has no reachable productions after inlining",
      )
  }
}

///|
fn process_inlines(
  g : InputGrammar,
  meta : ExtractedGrammarMeta,
  lexical_variables : Array[LexicalVariable],
  out : ProductionStore,
) -> InlinedProductionMap raise ProcessInlinesError {
  if meta.inline.is_empty() {
    return InlinedProductionMap::new()
  }
  for symbol in meta.inline {
    match symbol.kind {
      External =>
        raise ExternalToken(
          g.pool.resolve(meta.external_tokens[symbol.index].name),
        )
      Terminal =>
        raise Token(g.pool.resolve(lexical_variables[symbol.index].name))
      NonTerminal if symbol.index == 0 =>
        raise FirstRule(g.pool.resolve(g.variables[0].name))
      NonTerminal => ()
      End | EndOfNonTerminalExtra => abort("unreachable")
    }
  }
  let builder : InlineBuilder = {
    first_inlined: out.productions.length(),
    out,
    inline: meta.inline,
    map: Map([]),
    memo: Map([]),
  }
  let (map, dead) = builder.build()
  if dead.length() > 0 {
    for i, range in out.var_prods {
      let (p_start, p_end) = range
      if p_start == p_end {
        continue
      }
      let mut all_dead = true
      for p in p_start..<p_end {
        if !dead.contains(p) {
          all_dead = false
          break
        }
      }
      if !all_dead {
        continue
      }
      let symbol = Symbol::non_terminal(i)
      if i == 0 || out.steps.iter().any(s => s.symbol == symbol) {
        raise NoReachableProductions(g.pool.resolve(g.variables[i].name))
      }
    }
  }
  map
}

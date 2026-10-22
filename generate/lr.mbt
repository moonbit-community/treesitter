///|
priv struct Item {
  production : Int32
  dot : Int32
  lookahead : Int32
  reserved_lookahead : Int32
} derive(Eq, Hash, Compare)

///|
fn first_sets(builder : Builder) -> (Array[Map[Int32, Bool]], Array[Bool]) {
  let first : Array[Map[Int32, Bool]] = Array::makei(builder.symbols.length(), _ => {
    Map([])
  })
  let nullable = Array::make(builder.symbols.length(), false)
  for id, symbol in builder.symbols {
    if symbol.terminal {
      first[id][id] = true
    }
  }
  let mut changed = true
  while changed {
    changed = false
    for production in builder.productions {
      let mut empty = true
      for step in production.steps {
        for symbol in first[step.symbol].keys().to_array() {
          if !first[production.lhs].contains(symbol) {
            first[production.lhs][symbol] = true
            changed = true
          }
        }
        if !nullable[step.symbol] {
          empty = false
          break
        }
      }
      if empty && !nullable[production.lhs] {
        nullable[production.lhs] = true
        changed = true
      }
    }
  }
  (first, nullable)
}

///|
fn close_items(
  seeds : Array[Item],
  builder : Builder,
  first : Array[Map[Int32, Bool]],
  nullable : Array[Bool],
  by_lhs : Array[Array[Int32]],
  reserved_first : Array[Int32],
) -> Array[Item] {
  let seen : Map[Item, Bool] = Map([])
  let result = []
  for item in seeds {
    if !seen.contains(item) {
      seen[item] = true
      result.push(item)
    }
  }
  let mut index = 0
  while index < result.length() {
    let item = result[index]
    index += 1
    let production = builder.productions[item.production]
    if item.dot == production.steps.length() {
      continue
    }
    let symbol = production.steps[item.dot].symbol
    if builder.symbols[symbol].terminal {
      continue
    }
    let lookaheads : Map[Int32, Int32] = Map([])
    let mut empty = true
    for i in (item.dot + 1)..<production.steps.length() {
      let next = production.steps[i].symbol
      for token in first[next].keys() {
        lookaheads[token] = Int32::max(
          lookaheads.get(token).unwrap_or(0),
          if builder.grammar.word is Some(word) && next == builder.names[word] {
            production.steps[i].reserved_set.unwrap_or(0)
          } else {
            reserved_first[next]
          },
        )
      }
      if !nullable[next] {
        empty = false
        break
      }
    }
    if empty {
      let lookahead = if production.requires_eof == Some(true) {
        0
      } else {
        item.lookahead
      }
      lookaheads[lookahead] = Int32::max(
        lookaheads.get(lookahead).unwrap_or(0),
        item.reserved_lookahead,
      )
    }
    for pid in by_lhs[symbol] {
      for lookahead in lookaheads.keys() {
        let next : Item = {
          production: pid,
          dot: 0,
          lookahead,
          reserved_lookahead: lookaheads[lookahead],
        }
        if !seen.contains(next) {
          seen[next] = true
          result.push(next)
        }
      }
    }
  }
  result.sort()
  result
}

///|
fn resolve_actions(
  builder : Builder,
  state : Int32,
  token : Int32,
  actions : Array[@language.Action],
  items : Array[Item],
  first : Array[Map[Int32, Bool]],
) -> Array[@language.Action] raise GenerateError {
  if actions.length() <= 1 || actions.any(a => a is AcceptExtra) {
    return actions
  }
  let mut reductions : Array[Int32] = []
  for action in actions {
    if action is Reduce(id) {
      if reductions.is_empty() {
        reductions.push(id)
      } else {
        let comparison = compare_precedence(
          builder,
          builder.productions[id],
          reductions.map(i => builder.productions[i]),
        )
        if comparison > 0 {
          reductions = [id]
        } else if comparison == 0 {
          reductions.push(id)
        }
      }
    }
  }
  let mut remaining = actions.filter(a => {
    match a {
      Reduce(id) => reductions.contains(id)
      _ => true
    }
  })
  let shifts : Array[@language.Production] = []
  let shift_names : Map[String, Bool] = Map([])
  for item in items {
    let p = builder.productions[item.production]
    if item.dot > 0 &&
      p.steps.get(item.dot) is Some(step) &&
      first[step.symbol].contains(token) {
      let previous = p.steps[item.dot - 1]
      shifts.push({
        ..p,
        precedence: previous.precedence,
        precedence_name: previous.precedence_name,
      })
      shift_names[builder.symbols[p.lhs].name] = true
    }
  }
  if remaining.any(a => a is Shift(_)) && !reductions.is_empty() {
    let reduced = reductions.map(i => builder.productions[i])
    let comparisons = shifts.map(p => compare_precedence(builder, p, reduced))
    let less = comparisons.any(p => p < 0)
    let more = comparisons.any(p => p > 0)
    let equal = comparisons.any(p => p == 0)
    let left = reduced.all(p => p.associativity == -1)
    let right = reduced.all(p => p.associativity == 1)
    if more && !less {
      remaining = remaining.filter(a => !(a is Reduce(_)))
    } else if less && !more {
      if equal && right {
        remaining = remaining.filter(a => !(a is Reduce(_)))
      } else {
        remaining = remaining.filter(a => !(a is Shift(_)))
      }
    } else if !less && !more {
      if left {
        remaining = remaining.filter(a => !(a is Shift(_)))
      } else if right {
        remaining = remaining.filter(a => !(a is Reduce(_)))
      }
    }
  }
  if remaining.length() <= 1 {
    return remaining
  }
  let involved : Map[String, Bool] = Map([])
  for action in remaining {
    match action {
      Reduce(id) =>
        involved[builder.symbols[builder.productions[id].lhs].name] = true
      Shift(_) =>
        for name in shift_names.keys() {
          involved[name] = true
        }
      Accept | AcceptExtra | EnterExtra(_) => ()
    }
  }
  let names = involved.keys().to_array()
  if builder.grammar.conflicts.any(group => names.all(n => group.contains(n))) {
    return remaining
  }
  names.sort()
  raise Conflict(state, builder.symbols[token].name, names)
}

///|
fn compare_precedence(
  builder : Builder,
  left : @language.Production,
  right : Array[@language.Production],
) -> Int32 {
  if left.precedence_name is None &&
    right[0].precedence_name is None &&
    (left.precedence != 0 || right[0].precedence != 0) {
    return left.precedence.compare(right[0].precedence)
  }
  fn matches(rule : @grammar.Rule, production : @language.Production) {
    match rule {
      Literal(name) => production.precedence_name == Some(name)
      Symbol(name) => builder.symbols[production.lhs].name == name
      _ => false
    }
  }
  for group in builder.grammar.precedences {
    let mut saw_left = false
    let mut saw_right = false
    for rule in group {
      if matches(rule, left) {
        saw_left = true
        if saw_right {
          return -1
        }
      } else if right.any(p => matches(rule, p)) {
        saw_right = true
        if saw_left {
          return 1
        }
      }
    }
  }
  0
}

///|
/// Generate canonical LR(1) tables. Unresolved conflicts must be explicitly
/// declared; declared conflicts are retained for the GLR runtime.
pub fn generate(
  grammar : @grammar.Grammar,
  max_states~ : Int32 = 10000,
  max_productions~ : Int32 = 10000,
) -> @language.Language raise {
  if max_states < 1 || max_productions < 1 {
    raise ResourceLimit("limits must be positive")
  }
  let (builder, start, extras) = normalize(grammar, max_productions)
  let augmented = builder.symbol("_start", false, false, false)
  let aug_id = builder.productions.length()
  builder.productions.push({
    lhs: augmented,
    requires_eof: None,
    steps: [
      {
        symbol: start,
        reserved_set: None,
        field: None,
        rename: None,
        precedence: 0,
        precedence_name: None,
        associativity: 0,
      },
    ],
    precedence: 0,
    precedence_name: None,
    associativity: 0,
    dynamic_precedence: 0,
  })
  let extra_roots : Array[(Int32, Int32)] = []
  for extra in extras {
    if !builder.symbols[extra].terminal {
      let lhs = builder.symbol("_extra_start\{extra}", false, false, false)
      let pid = builder.productions.length()
      let step = { ..builder.productions[aug_id].steps[0], symbol: extra, }
      builder.productions.push({
        ..builder.productions[aug_id],
        lhs,
        steps: [step],
      })
      extra_roots.push((extra, pid))
    }
  }
  let (first, nullable) = first_sets(builder)
  for id, symbol in builder.symbols {
    if nullable[id] && id != start && id != augmented {
      raise InvalidGrammar(
        "non-start rule '\{symbol.name}' matches the empty string",
      )
    }
  }
  if first[start].is_empty() && !nullable[start] {
    raise InvalidGrammar("start rule has no finite derivation")
  }
  let by_lhs = Array::makei(builder.symbols.length(), _ => [])
  for id, p in builder.productions {
    by_lhs[p.lhs].push(id)
  }
  let reserved_first = reserved_first_sets(builder, first, nullable)
  let initial = close_items(
    [{ production: aug_id, dot: 0, lookahead: 0, reserved_lookahead: 0, }],
    builder,
    first,
    nullable,
    by_lhs,
    reserved_first,
  )
  let states = [initial]
  let ids : Map[Array[Item], Int32] = Map([])
  ids[initial] = 0
  let extra_states : Array[(Int32, Int32)] = []
  for (symbol, pid) in extra_roots {
    let seeds = []
    for token, meta in builder.symbols {
      if meta.terminal {
        seeds.push(Item::{
          production: pid,
          dot: 0,
          lookahead: token,
          reserved_lookahead: 0,
        })
      }
    }
    let state = close_items(
      seeds, builder, first, nullable, by_lhs, reserved_first,
    )
    let id = states.length()
    states.push(state)
    ids[state] = id
    extra_states.push((symbol, id))
  }
  let rows : Array[@language.ParseState] = []
  let mut index = 0
  while index < states.length() {
    if states.length() > max_states {
      raise ResourceLimit("LR state limit exceeded")
    }
    let items = states[index]
    let transitions : Map[Int32, Array[Item]] = Map([])
    let actions : Map[Int32, Array[@language.Action]] = Map([])
    let gotos : Map[Int32, Int32] = Map([])
    fn add(token, action) {
      let list = actions.get_or_init(token, () => [])
      if !list.contains(action) {
        list.push(action)
      }
    }
    for item in items {
      let p = builder.productions[item.production]
      if item.dot < p.steps.length() {
        transitions
        .get_or_init(p.steps[item.dot].symbol, () => [])
        .push({ ..item, dot: item.dot + 1, })
      } else if item.production == aug_id {
        add(0, Accept)
      } else if extra_roots.any(p => p.1 == item.production) {
        add(item.lookahead, AcceptExtra)
      } else if p.requires_eof != Some(true) || item.lookahead == 0 {
        add(item.lookahead, Reduce(item.production))
      }
    }
    let symbols = transitions.keys().to_array()
    symbols.sort()
    for symbol in symbols {
      let next = close_items(
        transitions[symbol],
        builder,
        first,
        nullable,
        by_lhs,
        reserved_first,
      )
      let target = match ids.get(next) {
        Some(id) => id
        None => {
          let id = states.length()
          states.push(next)
          ids[next] = id
          id
        }
      }
      if builder.symbols[symbol].terminal {
        add(symbol, Shift(target))
      } else {
        gotos[symbol] = target
      }
    }
    for token in actions.keys().to_array() {
      actions[token] = resolve_actions(
        builder,
        index,
        token,
        actions[token],
        items,
        first,
      )
    }
    let ordinary = actions.keys().to_array()
    for (extra, target) in extra_states {
      for token in first[extra].keys() {
        if !ordinary.contains(token) {
          add(token, EnterExtra(target))
        }
      }
    }
    let mut reserved = 0
    if grammar.word is Some(name) {
      let word = builder.names[name]
      for item in items {
        let p = builder.productions[item.production]
        if p.steps.get(item.dot) is Some(step) && step.symbol == word {
          reserved = Int32::max(reserved, step.reserved_set.unwrap_or(0))
        } else if item.dot == p.steps.length() && item.lookahead == word {
          reserved = Int32::max(reserved, item.reserved_lookahead)
        }
      }
    }
    rows.push({
      actions,
      gotos,
      reserved_words: builder.reserved_sets[reserved],
    })
    index += 1
  }
  @language.Language::new(
    grammar.name,
    builder.symbols,
    builder.tokens,
    builder.productions,
    rows,
    start,
    extras,
    word_token?=grammar.word.map(name => builder.names[name]),
    supertypes=grammar.supertypes.map(name => builder.names[name]),
    externals=builder.externals,
  )
}

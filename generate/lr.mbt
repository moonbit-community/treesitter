///|
priv struct Item {
  production : Int32
  dot : Int32
  lookahead : Int32
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
    let lookaheads : Map[Int32, Bool] = Map([])
    let mut empty = true
    for i in (item.dot + 1)..<production.steps.length() {
      let next = production.steps[i].symbol
      for token in first[next].keys() {
        lookaheads[token] = true
      }
      if !nullable[next] {
        empty = false
        break
      }
    }
    if empty {
      lookaheads[item.lookahead] = true
    }
    for pid in by_lhs[symbol] {
      for lookahead in lookaheads.keys() {
        let next : Item = { production: pid, dot: 0, lookahead, }
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
  if actions.length() <= 1 {
    return actions
  }
  let mut best = -2147483648
  for action in actions {
    if action is Reduce(id) {
      best = Int32::max(best, builder.productions[id].precedence)
    }
  }
  let mut remaining = actions.filter(a => {
    match a {
      Reduce(id) => builder.productions[id].precedence == best
      _ => true
    }
  })
  let shifts = []
  let shift_names : Map[String, Bool] = Map([])
  for item in items {
    let p = builder.productions[item.production]
    if item.dot > 0 &&
      p.steps.get(item.dot) is Some(step) &&
      first[step.symbol].contains(token) {
      shifts.push(p.steps[item.dot - 1].precedence)
      shift_names[builder.symbols[p.lhs].name] = true
    }
  }
  if remaining.any(a => a is Shift(_)) {
    let less = shifts.any(p => p < best)
    let more = shifts.any(p => p > best)
    let equal = shifts.any(p => p == best)
    let reductions = remaining.filter_map(a => {
      match a {
        Reduce(id) => Some(builder.productions[id])
        _ => None
      }
    })
    let left = !reductions.is_empty() &&
      reductions.all(p => p.associativity == -1)
    let right = !reductions.is_empty() &&
      reductions.all(p => p.associativity == 1)
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
      Accept => ()
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
    steps: [
      {
        symbol: start,
        field: None,
        rename: None,
        precedence: 0,
        associativity: 0,
      },
    ],
    precedence: 0,
    associativity: 0,
    dynamic_precedence: 0,
  })
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
  let initial = close_items(
    [{ production: aug_id, dot: 0, lookahead: 0, }],
    builder,
    first,
    nullable,
    by_lhs,
  )
  let states = [initial]
  let ids : Map[Array[Item], Int32] = Map([])
  ids[initial] = 0
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
      } else {
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
    rows.push({ actions, gotos, })
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
  )
}

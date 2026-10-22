///|
// Minimize canonical LR states without introducing action or lexical conflicts.
// States start grouped by their LR(0) kernel. Split incompatible action rows,
// then propagate differences in successor groups until the partition is stable.
fn Builder::compact_states(
  self : Builder,
  kernels : Array[Array[Item]],
  rows : Array[@language.ParseState],
  lexical : LexicalConflicts,
) -> Array[@language.ParseState] {
  let cores : Map[Array[(Int32, Int32)], Array[Int32]] = Map([])
  for id, kernel in kernels {
    let unique : Map[(Int32, Int32), Bool] = Map([])
    for item in kernel {
      unique[(item.production, item.dot)] = true
    }
    let core = unique.keys().to_array()
    core.sort()
    cores.get_or_init(core, () => []).push(id)
  }
  let mut groups = cores.values().to_array()
  let ids = Array::make(rows.length(), 0)
  for group, members in groups {
    for state in members {
      ids[state] = group
    }
  }
  for ;; {
    let next : Array[Array[Int32]] = []
    for members in groups {
      let partitions : Array[Array[Int32]] = []
      for state in members {
        let compatible = partitions.search_by(partition => {
          partition.all(other => {
            self.compatible_states(rows[state], rows[other], ids, lexical)
          })
        })
        match compatible {
          Some(index) => partitions[index].push(state)
          None => partitions.push([state])
        }
      }
      next.append(partitions)
    }
    let stable = next.length() == groups.length()
    groups = next
    for group, members in groups {
      for state in members {
        ids[state] = group
      }
    }
    if stable {
      break
    }
  }
  // The initial state remains state zero. Group iteration preserves the first
  // occurrence of every kernel, including the unique augmented start kernel.
  groups.map(members => {
    let actions : Map[Int32, Array[@language.Action]] = Map([])
    let gotos : Map[Int32, Int32] = Map([])
    let reserved : Map[Int32, Bool] = Map([])
    for id in members {
      for token in rows[id].reserved_words {
        reserved[token] = true
      }
      for (token, list) in rows[id].actions {
        if !actions.contains(token) {
          actions[token] = list.map(action => {
            match action {
              Shift(next) => Shift(ids[next])
              EnterExtra(next) => EnterExtra(ids[next])
              _ => action
            }
          })
        }
      }
      for (symbol, next) in rows[id].gotos {
        gotos[symbol] = ids[next]
      }
    }
    let reserved_words = reserved
      .keys()
      .filter(id => !actions.contains(id))
      .to_array()
    reserved_words.sort()
    { actions, gotos, reserved_words, }
  })
}

///|
fn Builder::compatible_states(
  self : Builder,
  left : @language.ParseState,
  right : @language.ParseState,
  groups : Array[Int32],
  lexical : LexicalConflicts,
) -> Bool {
  for (token, actions) in left.actions {
    match right.actions.get(token) {
      Some(other) => {
        if actions.length() != other.length() {
          return false
        }
        for i, action in actions {
          match (action, other[i]) {
            (Shift(a), Shift(b)) | (EnterExtra(a), EnterExtra(b)) =>
              if groups[a] != groups[b] {
                return false
              }
            (a, b) => if a != b { return false }
          }
        }
      }
      None =>
        if !self.can_add_lookahead(token, actions, right, lexical) {
          return false
        }
    }
  }
  for (token, actions) in right.actions {
    if !left.actions.contains(token) &&
      !self.can_add_lookahead(token, actions, left, lexical) {
      return false
    }
  }
  for (symbol, next) in left.gotos {
    if right.gotos.get(symbol) is Some(other) && groups[next] != groups[other] {
      return false
    }
  }
  true
}

///|
fn Builder::can_add_lookahead(
  self : Builder,
  token : Int32,
  actions : Array[@language.Action],
  state : @language.ParseState,
  lexical : LexicalConflicts,
) -> Bool {
  // End-of-extra uses synthetic terminal entries in these tables. It must not
  // broaden a state's lexical context. External validity is observable by the
  // scanner even when no internal token matches it.
  if actions.any(a => a is AcceptExtra) {
    return false
  }
  if self.externals.contains(token) {
    return false
  }
  if state.reserved_words.contains(token) {
    return true
  }
  guard lexical.indices.get(token) is Some(index) else { return token == 0 }
  let n = lexical.indices.length()
  for existing in state.actions.keys() {
    if lexical.indices.get(existing) is Some(other) {
      if (lexical.word == Some(existing) && lexical.keywords[index]) ||
        (lexical.word == Some(token) && lexical.keywords[other]) {
        continue
      }
      if (lexical.conflicts[index * n + other] & 7) != 0 {
        return false
      }
    }
  }
  true
}

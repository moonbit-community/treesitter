///|
// A symbol that never occurs unaliased has a default identity, including when
// error recovery uses it without a production. Prefer the most frequent alias,
// breaking ties by first occurrence, as extract_default_aliases does upstream.
fn Builder::aliased_symbols(
  self : Builder,
  extras : Array[Int32],
) -> Array[@language.Symbol] raise {
  // Alias frequencies are defined before inlining. In particular, an alias on
  // an inline rule must not become the default identity of its unaliased child.
  let (source, source_start, source_extras) = if self.grammar.inline_rules.is_empty() {
    (self, self.names[self.grammar.rules[0].0], extras)
  } else {
    normalize({ ..self.grammar, inline_rules: [], }, self.max_productions)
  }
  let source_ids : Map[Int32, Int32] = Map([])
  for (name, id) in self.names {
    if source.names.get(name) is Some(original) {
      source_ids[id] = original
    }
  }
  for (key, id) in self.token_ids {
    if source.token_ids.get(key) is Some(original) {
      source_ids[id] = original
    }
  }
  for (key, id) in self.repeats {
    if source.repeats.get(key) is Some(original) {
      source_ids[id] = original
    }
  }
  let unaliased : Map[Int32, Bool] = Map([])
  let aliases : Map[Int32, Map[(String, Bool), Int32]] = Map([])
  unaliased[source_start] = true
  for id in source_extras {
    unaliased[id] = true
  }
  for name in self.grammar.inline_rules {
    unaliased[source.names[name]] = true
  }
  for production in source.productions {
    for step in production.steps {
      match step.rename {
        None => unaliased[step.symbol] = true
        Some(identity) => {
          let counts = aliases.get_or_init(step.symbol, () => Map([]))
          counts[identity] = counts.get(identity).unwrap_or(0) + 1
        }
      }
    }
  }
  self.symbols.mapi((id, symbol) => {
    guard source_ids.get(id) is Some(id) else { return symbol }
    if unaliased.contains(id) {
      return symbol
    }
    let mut selected = None
    let mut frequency = 0
    for (identity, count) in aliases.get(id).unwrap_or(Map([])) {
      if count > frequency {
        frequency = count
        selected = Some(identity)
      }
    }
    match selected {
      Some((name, named)) => { ..symbol, name, named, visible: true, }
      None => symbol
    }
  })
}

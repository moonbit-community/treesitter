///|
priv struct LexicalConflicts {
  indices : Map[Int32, Int32]
  conflicts : Array[Int32]
  keywords : Array[Bool]
  word : Int32?
}

///|
fn Builder::lexical_analysis(
  self : Builder,
  contexts : Array[Array[Int32]],
  extras : Array[Int32],
  first : Array[Map[Int32, Bool]],
  nullable : Array[Bool],
) -> (Array[Int32], LexicalConflicts) raise {
  let tokens = self.tokens
  let n = tokens.length()
  let token_indices : Map[Int32, Int32] = Map([])
  for i, token in tokens {
    token_indices[token.symbol] = i
  }
  let separators = self.grammar.extras.filter_map(rule => {
    match rule {
      Symbol(_) => None
      _ => Some(expression(rule))
    }
  })
  let separator = @lex.compile(Many(Alt(separators)))
  let automata = tokens.map(token => conflict_automaton(token, separator))
  let starts = automata.map(states => {
    @lex.CharSet::new(states[0].edges.map(e => (e.lo, e.hi)))
  })
  let last : Array[Map[Int32, Bool]] = Array::makei(self.symbols.length(), i => {
    if self.symbols[i].terminal {
      Map([(i, true)])
    } else {
      Map([])
    }
  })
  let mut changed = true
  while changed {
    changed = false
    for production in self.productions {
      for i = production.steps.length() - 1; i >= 0; i = i - 1 {
        let symbol = production.steps[i].symbol
        for token in last[symbol].keys().to_array() {
          if !last[production.lhs].contains(token) {
            last[production.lhs][token] = true
            changed = true
          }
        }
        if !nullable[symbol] {
          break
        }
      }
    }
  }
  let following : Array[Map[Int32, Bool]] = Array::makei(n, _ => Map([]))
  for production in self.productions {
    for i in 1..<production.steps.length() {
      let before = production.steps[i - 1].symbol
      let after = production.steps[i].symbol
      for symbol in last[before].keys() {
        if token_indices.get(symbol) is Some(index) {
          for next in first[after].keys() {
            following[index][next] = true
          }
          if self.grammar.word is Some(name) &&
            first[after].contains(self.names[name]) {
            for set in self.reserved_sets {
              for next in set {
                following[index][next] = true
              }
            }
          }
        }
      }
    }
  }
  for extra in extras {
    if token_indices.get(extra) is Some(index) {
      for entry in following {
        entry[extra] = true
      }
      for token in tokens {
        following[index][token.symbol] = true
      }
    }
  }
  let following_chars = following.map(set => {
    let ranges = []
    for symbol in set.keys() {
      if token_indices.get(symbol) is Some(index) {
        ranges.append(starts[index].ranges)
      }
    }
    @lex.CharSet::new(ranges)
  })
  let word = self.grammar.word.map(name => self.names[name])
  let coincident = Array::make(n * n, false)
  let without_word = Array::make(n * n, false)
  let visited_rows : Map[(Array[Int32], Bool), Bool] = Map([])
  for context in contexts {
    let indices = context
      .iter()
      .filter_map(id => token_indices.get(id))
      .to_array()
    // Runtime rows store extras separately; upstream has explicit extra shifts
    // in each state, so they participate in coincidence with every lookahead.
    for extra in extras {
      if token_indices.get(extra) is Some(index) && !indices.contains(index) {
        indices.push(index)
      }
    }
    indices.sort()
    let has_word = word is Some(id) && context.contains(id)
    if !visited_rows.contains((indices, has_word)) {
      visited_rows[(indices, has_word)] = true
      for i in indices {
        for j in indices {
          coincident[i * n + j] = true
          if !has_word {
            without_word[i * n + j] = true
          }
        }
      }
    }
  }
  let conflicts = Array::make(n * n, 0)
  for i in 0..<n {
    for j in (i + 1)..<n {
      let (left, right) = token_conflicts(
        automata[i],
        automata[j],
        tokens[i],
        tokens[j],
        following_chars[i],
        following_chars[j],
      )
      conflicts[i * n + j] = left
      conflicts[j * n + i] = right
    }
  }
  let indices = Array::makei(n, i => i)
  let free = indices.map(i => {
    !indices.any(j => {
      i != j &&
      !coincident[i * n + j] &&
      (conflicts[i * n + j] & 3) != 0 &&
      (conflicts[j * n + i] & 2) == 0
    })
  })
  let keywords = Array::make(n, false)
  if word is Some(symbol) && token_indices.get(symbol) is Some(word_index) {
    let alphabetic = match @lex.parse("[\\p{Alphabetic}_]") {
      Concat([Chars(chars)]) | Chars(chars) => chars
      _ => raise InvalidGrammar("invalid alphabetic character class")
    }
    let candidates = indices.map(i => {
      (conflicts[i * n + word_index] & 4) != 0 &&
      (conflicts[i * n + word_index] & 32) == 0 &&
      tokens[i].lexer
      .transitions(0)
      .all(edge => edge.0.difference(alphabetic).ranges.is_empty())
    })
    for i in indices {
      keywords[i] = candidates[i] &&
        !indices.any(j => {
          j != i && candidates[j] && (conflicts[j * n + i] & 4) != 0
        }) &&
        !indices.any(j => {
          !candidates[j] &&
          without_word[i * n + j] &&
          conflicts[i * n + j] != conflicts[word_index * n + j]
        })
    }
  }
  let recovery = indices.filter_map(i => {
    if free[i] ||
      keywords[i] ||
      word == Some(tokens[i].symbol) ||
      !indices.any(j => {
        free[j] && !coincident[i * n + j] && (conflicts[i * n + j] & 7) != 0
      }) {
      Some(tokens[i].symbol)
    } else {
      None
    }
  })
  (recovery, { indices: token_indices, conflicts, keywords, word, })
}

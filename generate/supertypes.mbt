///|
// Count exposed children through hidden rules. Values saturate at two because
// only the distinction zero/one/multiple matters. A fixed point handles hidden
// recursive choices without recursion on the host stack.
fn Builder::validate_supertypes(self : Builder) -> Unit raise GenerateError {
  if self.grammar.supertypes.is_empty() {
    return
  }
  let counts : Array[Array[Int32]] = self.symbols.map(s => {
    if s.visible {
      [1]
    } else {
      []
    }
  })
  let mut changed = true
  while changed {
    changed = false
    for production in self.productions {
      if self.symbols[production.lhs].visible {
        continue
      }
      let mut totals = [0]
      for step in production.steps {
        let options = if step.rename is Some(_) {
          [1]
        } else if self.symbols[step.symbol].terminal &&
          !self.symbols[step.symbol].visible {
          [0]
        } else {
          counts[step.symbol]
        }
        let next = []
        for total in totals {
          for n in options {
            let sum = Int32::min(2, total + n)
            if !next.contains(sum) {
              next.push(sum)
            }
          }
        }
        totals = next
      }
      for total in totals {
        if !counts[production.lhs].contains(total) {
          counts[production.lhs].push(total)
          changed = true
        }
      }
    }
  }
  for name in self.grammar.supertypes {
    let id = self.names[name]
    if counts[id] != [1] {
      raise InvalidGrammar(
        "supertype '\{name}' must always have one visible child",
      )
    }
    if self.productions.any(p => {
        p.steps.any(s => s.rename == Some((name, true)))
      }) {
      raise InvalidGrammar("named alias conflicts with supertype '\{name}'")
    }
  }
}

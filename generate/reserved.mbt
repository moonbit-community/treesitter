///|
// The highest context id reaching the first word token wins, matching the
// upstream reserved-set merge rule. Context zero is the global set.
fn reserved_first_sets(
  builder : Builder,
  first : Array[Map[Int32, Bool]],
  nullable : Array[Bool],
) -> Array[Int32] {
  let result = Array::make(builder.symbols.length(), 0)
  guard builder.grammar.word is Some(name) else { return result }
  let word = builder.names[name]
  let mut changed = true
  while changed {
    changed = false
    for production in builder.productions {
      for step in production.steps {
        if first[step.symbol].contains(word) {
          let rank = if step.symbol == word {
            step.reserved_set.unwrap_or(0)
          } else {
            result[step.symbol]
          }
          if rank > result[production.lhs] {
            result[production.lhs] = rank
            changed = true
          }
        }
        if !nullable[step.symbol] {
          break
        }
      }
    }
  }
  result
}

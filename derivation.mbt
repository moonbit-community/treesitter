///|
// Upstream orders terminals first, then syntax variables in grammar order.
fn symbol_order(language : @language.Language, symbol : Int32) -> Int32 {
  if symbol < 0 {
    return -1
  }
  if language.symbols[symbol].terminal {
    for i, token in language.tokens {
      if token.symbol == symbol {
        return i
      }
    }
    return language.tokens.length() + symbol
  }
  language.tokens.length() + language.symbols.length() + symbol
}

///|
fn compare_derivations(
  language : @language.Language,
  left : Array[Derivation],
  right : Array[Derivation],
) -> Int32 {
  if left.length() != right.length() {
    return left.length().compare(right.length())
  }
  let pending : Array[(Derivation, Derivation)] = []
  for i = left.length() - 1; i >= 0; i = i - 1 {
    pending.push((left[i], right[i]))
  }
  while pending.pop() is Some((a, b)) {
    if physical_equal(a, b) {
      continue
    }
    if a.symbol != b.symbol {
      return symbol_order(language, a.symbol).compare(
        symbol_order(language, b.symbol),
      )
    }
    if a.children.length() != b.children.length() {
      return a.children.length().compare(b.children.length())
    }
    for i = a.children.length() - 1; i >= 0; i = i - 1 {
      pending.push((a.children[i], b.children[i]))
    }
  }
  0
}

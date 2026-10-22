///|
// Advance the active token DFAs together when a grammar uses scoped lexical
// precedence. A completion competes with the next transition, not only with
// another token's eventual longest match.
fn scan_weighted_tokens(
  tokens : Array[@language.Token],
  source : Bytes,
  start : Int32,
  word_end : Int32,
) -> ((@language.Token, Int32)?, Int32) {
  let mut active = tokens.map(token => (token, 0))
  let mut offset = start
  let mut accepted : (@language.Token, Int32)? = None
  while !active.is_empty() {
    let mut completion : @language.Token? = None
    for (token, state) in active {
      if token.lexer.accepts(state) && !(token.literal && word_end > offset) {
        if completion is None ||
          better_token(token, offset, completion.unwrap(), offset) {
          completion = Some(token)
        }
      }
    }
    if completion is Some(token) {
      accepted = Some((token, offset))
    }
    if offset == source.length() {
      break
    }
    let (cp, size) = @lex.decode(source, offset)
    let next : Array[(@language.Token, Int32)] = []
    let mut precedence = -2147483648
    for (token, state) in active {
      if token.lexer.transition(state, cp) is Some((target, scoped)) {
        next.push((token, target))
        precedence = Int32::max(precedence, scoped.unwrap_or(token.precedence))
      }
    }
    if next.is_empty() ||
      (completion is Some(token) && precedence < token.precedence) {
      break
    }
    active = next
    offset += size
  }
  (accepted, offset)
}

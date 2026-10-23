///|
// Retry the generated error lexer after an invalid run. Anonymous separators
// are skipped within an attempt; if that attempt fails after a separator or a
// partial token, the caller restarts at the failed position. A new attempt can
// therefore recognize immediate tokens there, just as the C lexer does.
fn recovery_restart(
  language : @language.Language,
  input : Bytes,
  start : Int32,
  weighted : Bool,
  cancelled : () -> Bool,
) -> (Bool, Int32, Int32) raise ParseError {
  let mut offset = start
  let mut skipped = false
  let mut dependency_end = start
  for ;; {
    if cancelled() {
      raise Cancelled
    }
    if offset == input.length() {
      return (true, offset, Int32::max(dependency_end, offset + 1))
    }
    let candidates = language.tokens.filter(token => {
      !(skipped && token.immediate) &&
      language.recovery_tokens.contains(token.symbol)
    })
    let mut stopped = offset
    let mut best : (@language.Token, Int32)? = None
    if weighted {
      let (found, end) = scan_weighted_tokens(candidates, input, offset, offset)
      stopped = end
      best = found
    } else {
      for token in candidates {
        let (accepted, end) = token.lexer.scan_prefix(input, start=offset)
        stopped = Int32::max(stopped, end)
        if accepted is Some(end) && end > offset {
          if best is None ||
            (
              best is Some((previous, previous_end)) &&
              better_token(token, end, previous, previous_end)
            ) {
            best = Some((token, end))
          }
        }
      }
    }
    dependency_end = Int32::max(
      dependency_end,
      if stopped == input.length() {
        stopped + 1
      } else {
        stopped + @lex.decode(input, stopped).1
      },
    )
    guard best is Some((token, end)) && end > offset else {
      return (false, stopped, dependency_end)
    }
    let symbol = language.symbols[token.symbol]
    if language.extras.contains(token.symbol) &&
      !symbol.visible &&
      !symbol.named {
      skipped = true
      offset = end
    } else {
      return (true, offset, dependency_end)
    }
  }
}

///|
fn better_token(
  candidate : @language.Token,
  end : Int32,
  previous : @language.Token,
  previous_end : Int32,
) -> Bool {
  if candidate.precedence != previous.precedence {
    candidate.precedence > previous.precedence
  } else if end != previous_end {
    end > previous_end
  } else if candidate.immediate != previous.immediate {
    candidate.immediate
  } else if candidate.literal != previous.literal {
    candidate.literal
  } else {
    candidate.symbol < previous.symbol
  }
}

///|
fn Parser::lex(
  self : Parser,
  input : Bytes,
  branch : Branch,
  lines : Array[Int32],
  projection : Projection?,
  cancelled : () -> Bool,
) -> Branch raise ParseError {
  let state = branch.states.last().unwrap()
  let valid = self.language.states[state].actions
  let mut offset = branch.offset
  let pending = branch.pending.copy()
  let mut skipped = false
  let mut scanner_state = branch.scanner_state
  let zero_width_states : Map[Bytes, Bool] = Map([])
  for ;; {
    if cancelled() {
      raise Cancelled
    }
    if self.scanner is Some(scanner) && !self.language.externals.is_empty() {
      let valid_tokens = self.language.externals.map(id => {
        valid.contains(id) || self.language.extras.contains(id)
      })
      if valid_tokens.any(x => x) && !zero_width_states.contains(scanner_state) {
        let input : ScannerInput = {
          source: input,
          offset,
          start: offset,
          marked_end: None,
          lines,
          projection,
          cancelled,
        }
        if (scanner.scan)(input, valid_tokens.copy(), scanner_state)
          is Some(result) {
          if result.token < 0 ||
            result.token >= valid_tokens.length() ||
            !valid_tokens[result.token] {
            raise ScannerError(
              "scanner returned a token that is not valid in this state",
            )
          }
          if result.state.length() > 1024 {
            raise ScannerError("serialized scanner state exceeds 1024 bytes")
          }
          let end = input.marked_end.unwrap_or(input.offset)
          // Upstream clamps inverted scanner ranges after skip advances
          // beyond a previously marked end (lexer.c: ts_lexer_finish).
          let start = Int32::min(input.start, end)
          let symbol = self.language.externals[result.token]
          if self.language.extras.contains(symbol) && !valid.contains(symbol) {
            if end == offset {
              if zero_width_states.length() >= 1024 {
                raise ParseLimit("zero-width scanner transition limit exceeded")
              }
              zero_width_states[scanner_state] = true
              if result.state == scanner_state {
                continue
              }
            } else {
              zero_width_states.clear()
            }
            if self.language.symbols[symbol].named {
              pending.push(
                self.node(
                  symbol,
                  start,
                  end,
                  lines,
                  [],
                  state,
                  state,
                  extra=true,
                  scan_before=scanner_state,
                  scan_after=result.state,
                ),
              )
            }
            offset = end
            scanner_state = result.state
            skipped = true
            continue
          }
          return {
            ..branch,
            offset: start,
            pending,
            scanner_state,
            lookahead: Some({
              symbol,
              start,
              end,
              missing: false,
              scanner_state: Some(result.state),
            }),
          }
        }
      }
    }
    let mut word_end = offset
    if self.language.word_token is Some(word) {
      for t in self.language.tokens {
        if t.symbol == word {
          word_end = t.lexer.match_prefix(input, start=offset).unwrap_or(offset)
          break
        }
      }
    }
    let mut best : (@language.Token, Int32)? = None
    for token in self.language.tokens {
      let extra = self.language.extras.contains(token.symbol)
      if (!valid.contains(token.symbol) && !extra) ||
        (skipped && token.immediate) {
        continue
      }
      if token.lexer.match_prefix(input, start=offset) is Some(end) &&
        (end > offset || valid.contains(token.symbol)) {
        if token.literal && word_end > end {
          continue
        }
        let replace = match best {
          None => true
          Some((previous, previous_end)) =>
            better_token(token, end, previous, previous_end)
        }
        if replace {
          best = Some((token, end))
        }
      }
    }
    if best is Some((token, end)) &&
      self.language.word_token == Some(token.symbol) {
      for reserved in self.language.states[state].reserved_words {
        for keyword in self.language.tokens {
          if keyword.symbol == reserved &&
            keyword.lexer.match_prefix(input, start=offset) == Some(end) {
            best = Some((keyword, end))
            break
          }
        }
      }
    }
    match best {
      Some((token, end)) =>
        if self.language.extras.contains(token.symbol) &&
          !valid.contains(token.symbol) {
          if self.language.symbols[token.symbol].named {
            pending.push(
              self.node(
                token.symbol,
                offset,
                end,
                lines,
                [],
                state,
                state,
                extra=true,
              ),
            )
          }
          skipped = true
          zero_width_states.clear()
          offset = end
        } else {
          return {
            ..branch,
            offset,
            pending,
            scanner_state,
            lookahead: Some({
              symbol: token.symbol,
              start: offset,
              end,
              missing: false,
              scanner_state: None,
            }),
          }
        }
      None => {
        let end = if offset == input.length() {
          offset
        } else {
          offset + @lex.decode(input, offset).1
        }
        return {
          ..branch,
          offset,
          pending,
          scanner_state,
          lookahead: Some({
            symbol: if offset == input.length() {
              0
            } else {
              -1
            },
            start: offset,
            end,
            missing: false,
            scanner_state: None,
          }),
        }
      }
    }
  }
}

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
  } else if candidate.literal != previous.literal {
    // Upstream implicit precedence: literal contributes 2, immediate adds 1.
    // A literal therefore wins even against an immediate regular expression.
    candidate.literal
  } else if candidate.immediate != previous.immediate {
    candidate.immediate
  } else {
    // Tokens are in grammar extraction order; keep the first equal match.
    false
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
  let mut dependency_end = offset
  fn scanned(lexer : @lex.Dfa, start : Int32) -> Int32? {
    let (accepted, stopped) = lexer.scan_prefix(input, start~)
    let observed = if stopped == input.length() {
      stopped + 1
    } else {
      stopped + @lex.decode(input, stopped).1
    }
    dependency_end = Int32::max(dependency_end, observed)
    accepted
  }
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
        let result = (scanner.scan)(input, valid_tokens.copy(), scanner_state)
        dependency_end = Int32::max(
          dependency_end,
          if input.eof() {
            input.offset + 1
          } else {
            input.offset + @lex.decode(input.source, input.offset).1
          },
        )
        if result is Some(result) {
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
            if self.language.symbols[symbol].visible {
              pending.push(
                self.node(
                  symbol,
                  start,
                  end,
                  lines,
                  [],
                  state,
                  state,
                  dependency_end~,
                  extra=true,
                  scan_before=scanner_state,
                  scan_after=result.state,
                ),
              )
            }
            offset = end
            scanner_state = result.state
            skipped = !(self.language.symbols[symbol].named ||
              self.language.symbols[symbol].visible)
            continue
          }
          return {
            ..branch,
            offset: start,
            pending,
            scanner_state,
            lookahead: Some({
              dependency_end,
              unexpected: None,
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
          word_end = scanned(t.lexer, offset).unwrap_or(offset)
          break
        }
      }
    }
    let mut best : (@language.Token, Int32)? = None
    let weighted = self.language.tokens.any(t => t.lexer.has_precedence())
    if weighted {
      let candidates = self.language.tokens.filter(token => {
        (
          valid.contains(token.symbol) ||
          self.language.extras.contains(token.symbol)
        ) &&
        !(skipped && token.immediate)
      })
      let (found, stopped) = scan_weighted_tokens(
        candidates, input, offset, word_end,
      )
      best = found
      dependency_end = Int32::max(
        dependency_end,
        if stopped == input.length() {
          stopped + 1
        } else {
          stopped + @lex.decode(input, stopped).1
        },
      )
    } else {
      for token in self.language.tokens {
        let extra = self.language.extras.contains(token.symbol)
        if (!valid.contains(token.symbol) && !extra) ||
          (skipped && token.immediate) {
          continue
        }
        if scanned(token.lexer, offset) is Some(end) &&
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
    }
    if best is Some((token, end)) &&
      self.language.word_token == Some(token.symbol) {
      for reserved in self.language.states[state].reserved_words {
        for keyword in self.language.tokens {
          if keyword.symbol == reserved &&
            scanned(keyword.lexer, offset) == Some(end) {
            best = Some((keyword, end))
            break
          }
        }
      }
    }
    // Recovery lexing recognizes otherwise valid tokens outside this state's
    // context, preserving token boundaries and names in skipped subtrees.
    if best is None && offset < input.length() {
      if weighted {
        let candidates = self.language.tokens.filter(token => {
          !(skipped && token.immediate) &&
          self.language.recovery_tokens.contains(token.symbol)
        })
        let (found, stopped) = scan_weighted_tokens(
          candidates, input, offset, offset,
        )
        best = found
        dependency_end = Int32::max(
          dependency_end,
          if stopped == input.length() {
            stopped + 1
          } else {
            stopped + @lex.decode(input, stopped).1
          },
        )
      } else {
        for token in self.language.tokens {
          if (skipped && token.immediate) ||
            !self.language.recovery_tokens.contains(token.symbol) {
            continue
          }
          if scanned(token.lexer, offset) is Some(end) && end > offset {
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
      }
    }
    match best {
      Some((token, end)) =>
        if self.language.extras.contains(token.symbol) &&
          !valid.contains(token.symbol) {
          if self.language.symbols[token.symbol].visible {
            pending.push(
              self.node(
                token.symbol,
                offset,
                end,
                lines,
                [],
                state,
                state,
                dependency_end~,
                extra=true,
              ),
            )
          }
          skipped = !(self.language.symbols[token.symbol].named ||
            self.language.symbols[token.symbol].visible)
          zero_width_states.clear()
          offset = end
        } else {
          return {
            ..branch,
            offset,
            pending,
            scanner_state,
            lookahead: Some({
              dependency_end,
              unexpected: None,
              symbol: token.symbol,
              start: offset,
              end,
              missing: false,
              scanner_state: None,
            }),
          }
        }
      None => {
        let mut end = if offset == input.length() {
          offset
        } else {
          offset + @lex.decode(input, offset).1
        }
        let mut failure = offset
        for token in self.language.tokens {
          if !(skipped && token.immediate) &&
            self.language.recovery_tokens.contains(token.symbol) {
            failure = Int32::max(
              failure,
              token.lexer.scan_prefix(input, start=offset).1,
            )
          }
        }
        end = Int32::max(end, failure)
        let unexpected = if failure == input.length() {
          0
        } else {
          @lex.decode(input, failure).0
        }
        // A lexical error spans the invalid run up to the next recognizable
        // token. Preserve the first failing code point, including EOF after
        // a partial token such as `nul`.
        while end < input.length() {
          let (recognized, stopped, observed) = recovery_restart(
            self.language,
            input,
            end,
            weighted,
            cancelled,
          )
          dependency_end = Int32::max(dependency_end, observed)
          if recognized {
            break
          }
          end = if stopped > end {
            stopped
          } else {
            end + @lex.decode(input, end).1
          }
        }
        dependency_end = Int32::max(
          dependency_end,
          if end == input.length() {
            end + 1
          } else {
            end + @lex.decode(input, end).1
          },
        )
        return {
          ..branch,
          offset,
          pending,
          scanner_state,
          lookahead: Some({
            dependency_end,
            unexpected: Some(unexpected),
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

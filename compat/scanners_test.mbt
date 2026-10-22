// Pure MoonBit ports of the pinned upstream fixture scanners. See LICENSE.

///|
fn scanner_external_extra_tokens() -> @ts.ExternalScanner {
  @ts.ExternalScanner::new((input, _, state) => {
    while input.lookahead() == 32 {
      input.advance(skip=true)
    }
    if input.lookahead() != 35 {
      return None
    }
    input.advance()
    while !input.eof() && input.lookahead() != 10 {
      input.advance()
    }
    Some({ token: 0, state, })
  })
}

///|
fn scanner_epsilon_external_extra_tokens() -> @ts.ExternalScanner {
  @ts.ExternalScanner::new((_, _, state) => Some({ token: 0, state, }))
}

///|
fn scanner_external_unicode_column_alignment() -> @ts.ExternalScanner {
  @ts.ExternalScanner::new((input, _, state) => {
    while input.lookahead() is (32 | 9 | 10 | 13 | 0x25a1) {
      input.advance(skip=true)
    }
    let column = if state.is_empty() {
      -1
    } else {
      state[0].to_int() |
      (state[1].to_int() << 8) |
      (state[2].to_int() << 16) |
      (state[3].to_int() << 24)
    }
    if input.lookahead() == 45 {
      let current = input.get_column()
      if column == -1 {
        return Some({
          token: 0,
          state: Bytes::from_array([
            current.to_byte(),
            (current >> 8).to_byte(),
            (current >> 16).to_byte(),
            (current >> 24).to_byte(),
          ]),
        })
      }
      if column == current {
        input.advance()
        return Some({ token: 1, state, })
      }
      return Some({ token: 2, state: b"", })
    }
    if input.eof() && column != -1 {
      return Some({ token: 2, state: b"", })
    }
    None
  })
}

///|
fn scanner_epsilon_external_tokens() -> @ts.ExternalScanner {
  scanner_epsilon_external_extra_tokens()
}

///|
fn scanner_external_and_internal_anonymous_tokens() -> @ts.ExternalScanner {
  @ts.ExternalScanner::new((input, valid, state) => {
    if valid[1] {
      while input.lookahead() is (32 | 13) {
        input.advance(skip=true)
      }
      if input.lookahead() == 10 {
        input.advance()
        return Some({ token: 1, state, })
      }
    }
    if valid[0] {
      while input.lookahead() is (32 | 13 | 10) {
        input.advance(skip=true)
      }
      if input.lookahead() == 39 {
        input.advance()
        while !input.eof() && input.lookahead() != 39 {
          input.advance()
        }
        if input.eof() {
          return None
        }
        input.advance()
        return Some({ token: 0, state, })
      }
    }
    None
  })
}

///|
fn scanner_depends_on_column() -> @ts.ExternalScanner {
  @ts.ExternalScanner::new((input, _, state) => {
    Some({ token: if input.get_column() % 2 == 1 { 0 } else { 1 }, state, })
  })
}

///|
fn scanner_depends_on_column_failed_scan() -> @ts.ExternalScanner {
  @ts.ExternalScanner::new((input, _, state) => {
    if input.lookahead() != 120 || input.get_column() != 0 {
      return None
    }
    input.advance()
    Some({ token: 0, state, })
  })
}

///|
fn scanner_depends_on_column_repetition() -> @ts.ExternalScanner {
  @ts.ExternalScanner::new((input, _, state) => {
    if input.lookahead() != 120 {
      return None
    }
    let token = if input.get_column() == 0 { 0 } else { 1 }
    input.advance()
    Some({ token, state, })
  })
}

///|
fn scanner_external_word_token() -> @ts.ExternalScanner {
  @ts.ExternalScanner::new((input, valid, state) => {
    if !valid[0] {
      return None
    }
    while input.lookahead() is (32 | 9 | 13 | 10) {
      input.advance(skip=true)
    }
    if input.lookahead() < 97 || input.lookahead() > 122 {
      return None
    }
    while input.lookahead() >= 97 && input.lookahead() <= 122 {
      input.advance()
    }
    Some({ token: 0, state, })
  })
}

///|
fn scanner_external_and_internal_tokens() -> @ts.ExternalScanner {
  scanner_external_and_internal_anonymous_tokens()
}

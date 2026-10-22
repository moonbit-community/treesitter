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

///|
fn scanner_inverted_external_token() -> @ts.ExternalScanner {
  @ts.ExternalScanner::new((input, _, state) => {
    while input.lookahead() is (32 | 13) {
      input.advance(skip=true)
    }
    if input.lookahead() != 10 {
      return None
    }
    input.advance()
    input.mark_end()
    while input.lookahead() is (32 | 10 | 13) {
      input.advance(skip=true)
    }
    if input.lookahead() == 46 {
      None
    } else {
      Some({ token: 0, state, })
    }
  })
}

///|
fn scanner_external_lookahead_eof_boundary() -> @ts.ExternalScanner {
  @ts.ExternalScanner::new((input, valid, state) => {
    if input.lookahead() != 96 {
      return None
    }
    input.advance()
    input.mark_end()
    if valid[1] {
      return Some({ token: 1, state, })
    }
    if valid[0] {
      while !input.eof() {
        if input.lookahead() == 96 {
          return Some({ token: 0, state, })
        }
        input.advance()
      }
      if valid[2] {
        return Some({ token: 2, state, })
      }
    }
    None
  })
}

///|
fn scanner_get_col_eof() -> @ts.ExternalScanner {
  @ts.ExternalScanner::new((input, valid, state) => {
    if input.eof() || !valid[0] {
      return None
    }
    input.advance()
    ignore(input.get_column())
    input.mark_end()
    Some({ token: 0, state, })
  })
}

///|
fn scanner_utf16_surrogate_oob() -> @ts.ExternalScanner {
  @ts.ExternalScanner::new((input, valid, state) => {
    let c = input.lookahead()
    let token = if c >= 0xD800 && c <= 0xDFFF && valid[0] {
      0
    } else if c > 0xFFFF && valid[1] {
      1
    } else {
      return None
    }
    input.advance()
    input.mark_end()
    Some({ token, state, })
  })
}

///|
fn scanner_external_tokens() -> @ts.ExternalScanner {
  @ts.ExternalScanner::new((input, valid, state) => {
    let mut open = if state.length() >= 3 { state[0].to_int() } else { 0 }
    let mut close = if state.length() >= 3 { state[1].to_int() } else { 0 }
    let mut depth = if state.length() >= 3 { state[2].to_int() } else { 0 }
    let token = if valid[0] {
      while input.lookahead() is (32 | 9 | 10 | 13) {
        input.advance(skip=true)
      }
      if input.lookahead() != 37 {
        return None
      }
      input.advance()
      open = input.lookahead()
      close = match open {
        40 => 41
        91 => 93
        123 => 125
        _ => return None
      }
      depth = 1
      input.advance()
      0
    } else if valid[2] {
      if input.lookahead() != 125 {
        return None
      }
      input.advance()
      2
    } else {
      return None
    }
    while depth > 0 {
      if input.eof() {
        return None
      }
      let c = input.lookahead()
      if c == open {
        depth += 1
      } else if c == close {
        depth -= 1
      }
      input.advance()
      if token == 0 && c == 35 && input.lookahead() == 123 {
        input.advance()
        return Some({
          token: 1,
          state: Bytes::from_array([
            open.to_byte(),
            close.to_byte(),
            depth.to_byte(),
          ]),
        })
      }
      if depth > 255 {
        return None
      }
    }
    Some({ token, state: b"", })
  })
}

///|
test "upstream get_column after advancing to EOF" {
  let grammar = @grammar.Grammar::new(
    "column_eof",
    [("root", Repeat(Symbol("char")))],
    externals=[Symbol("char")],
    extras=[],
  )
  let parser = @ts.Parser::new(
    @generate.generate(grammar),
    scanner=scanner_get_col_eof(),
  )
  assert_eq(parser.parse_string("界").root_node().to_sexp(), "(root (char))")
}

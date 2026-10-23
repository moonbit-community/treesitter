// Interpreter for `@language.LexProgram`, the portable form of the lex
// functions that upstream's `render.rs` emits into `parser.c`. Every
// expression below mirrors the C text the generator would have produced (see
// `add_lex_state` and `add_character_range_conditions` in render.rs and the
// lexer macros in lib/src/parser.h), including how a decode error (-1)
// lookahead compares.

///|
/// `set_contains` from lib/src/parser.h.
fn set_contains(
  ranges : Array[@language.CharacterRange],
  lookahead : Int32,
) -> Bool {
  let len = ranges.length()
  let mut index = 0
  let mut size = len - index
  while size > 1 {
    let half_size = size / 2
    let mid_index = index + half_size
    let range = ranges[mid_index]
    if lookahead >= range.start && lookahead <= range.end {
      return true
    } else if lookahead > range.end {
      index = mid_index
    }
    size -= half_size
  }
  let range = ranges[index]
  lookahead >= range.start && lookahead <= range.end
}

///|
fn range_condition(
  condition : @language.RangeCondition,
  lookahead : Int32,
  eof : Bool,
) -> Bool {
  if condition.is_included {
    for range in condition.ranges {
      let start = range.start
      let end = range.end
      let matched = if start == 0 {
        // `(!eof && lookahead == 0)` or `(!eof && lookahead <= end)`
        !eof && (if end == 0 { lookahead == 0 } else { lookahead <= end })
      } else if end == start {
        lookahead == start
      } else if end == start + 1 {
        lookahead == start || lookahead == end
      } else {
        start <= lookahead && lookahead <= end
      }
      if matched {
        return true
      }
    }
    false
  } else {
    for range in condition.ranges {
      let start = range.start
      let end = range.end
      let holds = if end == start {
        lookahead != start
      } else if end == start + 1 {
        lookahead != start && lookahead != end
      } else if start != 0 {
        lookahead < start || end < lookahead
      } else {
        lookahead > end
      }
      if !holds {
        return false
      }
    }
    true
  }
}

///|
fn lex_condition(
  program : @language.LexProgram,
  condition : @language.LexCondition,
  lookahead : Int32,
  eof : Bool,
) -> Bool {
  let has_positive = condition.large_set is Some(_) ||
    condition.asserted is Some(_)
  let positive = if has_positive {
    let large = match condition.large_set {
      Some((index, check_eof)) =>
        (!check_eof || !eof) &&
        set_contains(program.large_character_sets[index], lookahead)
      None => false
    }
    large ||
    (match condition.asserted {
      Some(asserted) => range_condition(asserted, lookahead, eof)
      None => false
    })
  } else {
    true
  }
  let negative = match condition.negated {
    Some(negated) => range_condition(negated, lookahead, eof)
    None => true
  }
  positive && negative
}

///|
/// Run a generated lex function (`ts_lex`/`ts_lex_keywords`) starting at
/// `state`, exactly as the emitted C would.
pub fn run_lex_program(
  program : @language.LexProgram,
  lexer : Lexer,
  start_state : Int32,
) -> Bool {
  // START_LEXER()
  let mut result = false
  let mut skip = false
  let mut state = start_state
  let mut first = true
  for ;; {
    if !first {
      // next_state:
      lexer.advance(skip)
    }
    first = false
    // start:
    skip = false
    let lookahead = lexer.lookahead
    let eof = lexer.eof()
    guard program.states.get(state) is Some(code) else {
      // default: return false;
      return false
    }
    if code.accept_token is Some(symbol) {
      // ACCEPT_TOKEN(symbol)
      result = true
      lexer.result_symbol = symbol
      lexer.mark_end()
    }
    if code.eof_advance is Some(next) && eof {
      state = next
      continue
    }
    let mut advanced = false
    for entry in code.advance_map {
      if entry.0 == lookahead {
        state = entry.1
        advanced = true
        break
      }
    }
    if advanced {
      continue
    }
    for transition in code.transitions {
      if lex_condition(program, transition.condition, lookahead, eof) {
        if transition.skip {
          skip = true
        }
        state = transition.state
        advanced = true
        break
      }
    }
    if advanced {
      continue
    }
    // END_STATE()
    return result
  }
}

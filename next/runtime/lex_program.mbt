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

///|
/// `run_lex_program` over a `LexProgram` flattened into integer arrays, so
/// that lexing a character touches no boxed values. `compile` and `run`
/// together are equivalent to `run_lex_program`; the parser compiles each lex
/// function once per language.
priv struct CompiledLexProgram {
  /// Indexed by state: whether `ACCEPT_TOKEN` is emitted, and its symbol.
  has_accept : FixedArray[Bool]
  accept : FixedArray[Int]
  /// Indexed by state: whether `if (eof) ADVANCE(s)` is emitted, and `s`.
  has_eof_advance : FixedArray[Bool]
  eof_advance : FixedArray[Int]
  /// `advance_map` pairs of state `s` are
  /// `map[2 * map_start[s]:2 * map_start[s + 1]]`, as `(char, state)`.
  map_start : FixedArray[Int]
  map : FixedArray[Int]
  /// Transitions of state `s` are `trans_start[s]..<trans_start[s + 1]`;
  /// each takes `transition_width` ints of `trans`: the next state, skip
  /// (0/1), the large set index (-1: none), whether the large set test is
  /// guarded by `!eof` (0/1), and the asserted and negated range condition
  /// indices (-1: none).
  trans_start : FixedArray[Int]
  trans : FixedArray[Int]
  /// Ranges of range condition `c` are
  /// `rc_ranges[2 * rc_start[c]:2 * rc_start[c + 1]]`, as `(start, end)`.
  rc_start : FixedArray[Int]
  rc_included : FixedArray[Bool]
  rc_ranges : FixedArray[Int]
  /// Ranges of large character set `i` are
  /// `set_ranges[2 * set_start[i]:2 * set_start[i + 1]]`.
  set_start : FixedArray[Int]
  set_ranges : FixedArray[Int]
}

///|
let transition_width : Int = 6

///|
fn CompiledLexProgram::compile(
  program : @language.LexProgram,
) -> CompiledLexProgram {
  let states = program.states
  let n = states.length()
  let has_accept = FixedArray::make(n, false)
  let accept = FixedArray::make(n, 0)
  let has_eof_advance = FixedArray::make(n, false)
  let eof_advance = FixedArray::make(n, 0)
  let map_start = FixedArray::make(n + 1, 0)
  let map : Array[Int] = []
  let trans_start = FixedArray::make(n + 1, 0)
  let trans : Array[Int] = []
  let rc_start : Array[Int] = [0]
  let rc_included : Array[Bool] = []
  let rc_ranges : Array[Int] = []
  let add_range_condition = (condition : @language.RangeCondition?) => {
    match condition {
      Some(condition) => {
        for range in condition.ranges {
          rc_ranges.push(range.start)
          rc_ranges.push(range.end)
        }
        rc_included.push(condition.is_included)
        rc_start.push(rc_ranges.length() / 2)
        rc_included.length() - 1
      }
      None => -1
    }
  }
  for s, code in states {
    if code.accept_token is Some(symbol) {
      has_accept[s] = true
      accept[s] = symbol
    }
    if code.eof_advance is Some(next) {
      has_eof_advance[s] = true
      eof_advance[s] = next
    }
    map_start[s] = map.length() / 2
    for entry in code.advance_map {
      map.push(entry.0)
      map.push(entry.1)
    }
    trans_start[s] = trans.length() / transition_width
    for transition in code.transitions {
      let condition = transition.condition
      trans.push(transition.state)
      trans.push(if transition.skip { 1 } else { 0 })
      match condition.large_set {
        Some((index, check_eof)) => {
          trans.push(index)
          trans.push(if check_eof { 1 } else { 0 })
        }
        None => {
          trans.push(-1)
          trans.push(0)
        }
      }
      trans.push(add_range_condition(condition.asserted))
      trans.push(add_range_condition(condition.negated))
    }
  }
  map_start[n] = map.length() / 2
  trans_start[n] = trans.length() / transition_width
  let set_start : Array[Int] = [0]
  let set_ranges : Array[Int] = []
  for set in program.large_character_sets {
    for range in set {
      set_ranges.push(range.start)
      set_ranges.push(range.end)
    }
    set_start.push(set_ranges.length() / 2)
  }
  {
    has_accept,
    accept,
    has_eof_advance,
    eof_advance,
    map_start,
    map: FixedArray::from_array(map),
    trans_start,
    trans: FixedArray::from_array(trans),
    rc_start: FixedArray::from_array(rc_start),
    rc_included: FixedArray::from_array(rc_included),
    rc_ranges: FixedArray::from_array(rc_ranges),
    set_start: FixedArray::from_array(set_start),
    set_ranges: FixedArray::from_array(set_ranges),
  }
}

///|
/// `set_contains` over large character set `set`.
fn CompiledLexProgram::set_contains(
  self : CompiledLexProgram,
  set : Int,
  lookahead : Int32,
) -> Bool {
  let ranges = self.set_ranges
  let base = self.set_start[set]
  let len = self.set_start[set + 1] - base
  let mut index = 0
  let mut size = len - index
  while size > 1 {
    let half_size = size / 2
    let mid_index = index + half_size
    let start = ranges[2 * (base + mid_index)]
    let end = ranges[2 * (base + mid_index) + 1]
    if lookahead >= start && lookahead <= end {
      return true
    } else if lookahead > end {
      index = mid_index
    }
    size -= half_size
  }
  let start = ranges[2 * (base + index)]
  let end = ranges[2 * (base + index) + 1]
  lookahead >= start && lookahead <= end
}

///|
/// `range_condition` for range condition `c`.
fn CompiledLexProgram::range_condition(
  self : CompiledLexProgram,
  c : Int,
  lookahead : Int32,
  eof : Bool,
) -> Bool {
  let ranges = self.rc_ranges
  let first = self.rc_start[c]
  let last = self.rc_start[c + 1]
  if self.rc_included[c] {
    for k in first..<last {
      let start = ranges[2 * k]
      let end = ranges[2 * k + 1]
      let matched = if start == 0 {
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
    for k in first..<last {
      let start = ranges[2 * k]
      let end = ranges[2 * k + 1]
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
/// `lex_condition` for the transition starting at `trans[t]`.
fn CompiledLexProgram::lex_condition(
  self : CompiledLexProgram,
  t : Int,
  lookahead : Int32,
  eof : Bool,
) -> Bool {
  let trans = self.trans
  let large_set = trans[t + 2]
  let asserted = trans[t + 4]
  let negated = trans[t + 5]
  let positive = if large_set >= 0 || asserted >= 0 {
    let large = large_set >= 0 &&
      (trans[t + 3] == 0 || !eof) &&
      self.set_contains(large_set, lookahead)
    large || (asserted >= 0 && self.range_condition(asserted, lookahead, eof))
  } else {
    true
  }
  positive && (negated < 0 || self.range_condition(negated, lookahead, eof))
}

///|
/// `run_lex_program` for a compiled program.
fn CompiledLexProgram::run(
  self : CompiledLexProgram,
  lexer : Lexer,
  start_state : Int32,
) -> Bool {
  // START_LEXER()
  let mut result = false
  let mut skip = false
  let mut state = start_state
  let mut first = true
  let state_count = self.has_accept.length()
  let map = self.map
  let trans = self.trans
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
    if state < 0 || state >= state_count {
      // default: return false;
      return false
    }
    if self.has_accept[state] {
      // ACCEPT_TOKEN(symbol)
      result = true
      lexer.result_symbol = self.accept[state]
      lexer.mark_end()
    }
    if eof && self.has_eof_advance[state] {
      state = self.eof_advance[state]
      continue
    }
    let mut advanced = false
    for k in self.map_start[state]..<self.map_start[state + 1] {
      if map[2 * k] == lookahead {
        state = map[2 * k + 1]
        advanced = true
        break
      }
    }
    if advanced {
      continue
    }
    for k in self.trans_start[state]..<self.trans_start[state + 1] {
      let t = k * transition_width
      if self.lex_condition(t, lookahead, eof) {
        if trans[t + 1] != 0 {
          skip = true
        }
        state = trans[t]
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

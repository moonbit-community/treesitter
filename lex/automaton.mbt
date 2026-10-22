///|
priv struct NfaState {
  edges : Array[(CharSet, Int32, Int32?)]
  epsilon : Array[Int32]
}

///|
fn state(states : Array[NfaState]) -> Int32 raise RegexError {
  if states.length() >= 100000 {
    raise InvalidRegex(0, "NFA state limit exceeded")
  }
  let id = states.length()
  states.push({ edges: [], epsilon: [], })
  id
}

///|
fn build(
  expr : Expr,
  states : Array[NfaState],
  start : Int32,
  end : Int32,
  precedence~ : Int32? = None,
) -> Unit raise RegexError {
  match expr {
    Precedence(value, child) =>
      build(child, states, start, end, precedence=Some(value))
    Assert(_) =>
      raise InvalidRegex(0, "assertions are not supported in lexical DFAs")
    Repeat(child, min, max, _) => {
      if min < 0 || min > 1000 || (max is Some(n) && (n < min || n > 1000)) {
        raise InvalidRegex(0, "invalid repetition bounds")
      }
      let parts = Array::make(min, child)
      match max {
        None => parts.push(Many(child))
        Some(n) =>
          for _ in min..<n {
            parts.push(Alt([child, Empty]))
          }
      }
      build(Concat(parts), states, start, end, precedence~)
    }
    Empty => states[start].epsilon.push(end)
    Chars(chars) => states[start].edges.push((chars, end, precedence))
    Concat(parts) => {
      let mut current = start
      for i, part in parts {
        let next = if i == parts.length() - 1 { end } else { state(states) }
        build(part, states, current, next, precedence~)
        current = next
      }
      if parts.is_empty() {
        states[start].epsilon.push(end)
      }
    }
    Alt(parts) =>
      for part in parts {
        let branch_start = state(states)
        let branch_end = state(states)
        states[start].epsilon.push(branch_start)
        build(part, states, branch_start, branch_end, precedence~)
        states[branch_end].epsilon.push(end)
      }
    Many(part) => {
      let inner_start = state(states)
      let inner_end = state(states)
      states[start].epsilon.push(end)
      states[start].epsilon.push(inner_start)
      build(part, states, inner_start, inner_end, precedence~)
      states[inner_end].epsilon.push(inner_start)
      states[inner_end].epsilon.push(end)
    }
  }
}

///|
fn closure(states : Array[NfaState], seeds : Array[Int32]) -> Array[Int32] {
  let seen = Array::make(states.length(), false)
  let pending = seeds.copy()
  let result = []
  while pending.pop() is Some(id) {
    if !seen[id] {
      seen[id] = true
      result.push(id)
      for target in states[id].epsilon {
        pending.push(target)
      }
    }
  }
  result.sort()
  result
}

///|
priv struct Transition {
  lo : Int32
  hi : Int32
  target : Int32
  precedence : Int32?
} derive(Debug, Eq)

///|
priv struct DfaState {
  accepting : Bool
  edges : Array[Transition]
} derive(Debug, Eq)

///|
/// Immutable deterministic Unicode lexer. Match offsets are UTF-8 byte offsets.
pub struct Dfa {
  priv states : Array[DfaState]
  priv weighted : Bool
} derive(Debug, Eq)

///|
pub extend Dfa with Eq::{equal, not_equal}

///|
pub extend Dfa with @debug.Debug::{to_repr}

///|
/// Thompson construction followed by canonical subset construction. The state
/// limit bounds exponential regex expansion rather than silently truncating it.
pub fn compile(
  expr : Expr,
  max_states~ : Int32 = 10000,
) -> Dfa raise RegexError {
  let nfa : Array[NfaState] = []
  let start = state(nfa)
  let end = state(nfa)
  build(expr, nfa, start, end)
  let subsets = [closure(nfa, [start])]
  let ids : Map[Array[Int32], Int32] = Map([])
  ids[subsets[0]] = 0
  let states : Array[DfaState] = []
  let mut index = 0
  while index < subsets.length() {
    if subsets.length() > max_states {
      raise InvalidRegex(0, "DFA state limit exceeded")
    }
    let subset = subsets[index]
    let boundaries : Array[Int32] = []
    for id in subset {
      for (chars, _, _) in nfa[id].edges {
        for (lo, hi) in chars.ranges {
          boundaries.push(lo)
          boundaries.push(hi + 1)
        }
      }
    }
    boundaries.sort()
    let edges : Array[Transition] = []
    for i in 0..<(boundaries.length() - 1) {
      let lo = boundaries[i]
      let hi = boundaries[i + 1] - 1
      if lo > hi {
        continue
      }
      let seeds : Array[Int32] = []
      let mut precedence : Int32? = None
      let mut has_precedence = false
      for id in subset {
        for (chars, target, weight) in nfa[id].edges {
          if chars.contains(lo) {
            seeds.push(target)
            has_precedence = has_precedence || weight is Some(_)
            precedence = Some(
              Int32::max(precedence.unwrap_or(-2147483648), weight.unwrap_or(0)),
            )
          }
        }
      }
      if seeds.is_empty() {
        continue
      }
      let precedence = if has_precedence { precedence } else { None }
      let next = closure(nfa, seeds)
      let target = match ids.get(next) {
        Some(id) => id
        None => {
          let id = subsets.length()
          subsets.push(next)
          ids[next] = id
          id
        }
      }
      if edges.last() is Some(previous) &&
        previous.target == target &&
        previous.precedence == precedence &&
        previous.hi + 1 == lo {
        edges[edges.length() - 1] = { lo: previous.lo, hi, target, precedence, }
      } else {
        edges.push({ lo, hi, target, precedence, })
      }
    }
    states.push({ accepting: subset.contains(end), edges, })
    index += 1
  }
  {
    weighted: states.any(s => s.edges.any(e => e.precedence is Some(_))),
    states,
  }
}

///|
pub fn Dfa::state_count(self : Dfa) -> Int32 {
  self.states.length()
}

///|
pub fn Dfa::nullable(self : Dfa) -> Bool {
  self.states[0].accepting
}

///|
pub fn Dfa::transition(
  self : Dfa,
  state : Int32,
  cp : Int32,
) -> (Int32, Int32?)? {
  if state < 0 || state >= self.states.length() {
    return None
  }
  let edges = self.states[state].edges
  for lo = 0, hi = edges.length(); lo < hi; {
    let mid = lo + (hi - lo) / 2
    let edge = edges[mid]
    if cp < edge.lo {
      continue lo, mid
    }
    if cp > edge.hi {
      continue mid + 1, hi
    }
    return Some((edge.target, edge.precedence))
  }
  None
}

///|
pub fn Dfa::accepts(self : Dfa, state : Int32) -> Bool {
  self.states.get(state).map(s => s.accepting).unwrap_or(false)
}

///|
pub fn Dfa::has_precedence(self : Dfa) -> Bool {
  self.weighted
}

///|
/// Returns the longest matching end position, including an empty match when
/// the expression is nullable. Invalid UTF-8 consumes one byte as U+FFFD.
pub fn Dfa::scan_prefix(
  self : Dfa,
  input : Bytes,
  start~ : Int32 = 0,
) -> (Int32?, Int32) {
  if start < 0 || start > input.length() {
    return (None, start)
  }
  let mut offset = start
  let mut state = 0
  let mut accepted = if self.states[0].accepting { Some(start) } else { None }
  while offset < input.length() {
    let (cp, size) = decode(input, offset)
    match self.transition(state, cp) {
      None => break
      Some((next, _)) => {
        state = next
        offset += size
      }
    }
    if self.states[state].accepting {
      accepted = Some(offset)
    }
  }
  (accepted, offset)
}

///|
/// Return the longest matching end offset, or None when no prefix matches.
pub fn Dfa::match_prefix(
  self : Dfa,
  input : Bytes,
  start~ : Int32 = 0,
) -> Int32? {
  self.scan_prefix(input, start~).0
}

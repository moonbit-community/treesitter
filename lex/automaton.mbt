///|
priv struct NfaState {
  edges : Array[(CharSet, Int32)]
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
) -> Unit raise RegexError {
  match expr {
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
      build(Concat(parts), states, start, end)
    }
    Empty => states[start].epsilon.push(end)
    Chars(chars) => states[start].edges.push((chars, end))
    Concat(parts) => {
      let mut current = start
      for i, part in parts {
        let next = if i == parts.length() - 1 { end } else { state(states) }
        build(part, states, current, next)
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
        build(part, states, branch_start, branch_end)
        states[branch_end].epsilon.push(end)
      }
    Many(part) => {
      let inner_start = state(states)
      let inner_end = state(states)
      states[start].epsilon.push(end)
      states[start].epsilon.push(inner_start)
      build(part, states, inner_start, inner_end)
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
      for (chars, _) in nfa[id].edges {
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
      for id in subset {
        for (chars, target) in nfa[id].edges {
          if chars.contains(lo) {
            seeds.push(target)
          }
        }
      }
      if seeds.is_empty() {
        continue
      }
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
        previous.hi + 1 == lo {
        edges[edges.length() - 1] = { lo: previous.lo, hi, target, }
      } else {
        edges.push({ lo, hi, target, })
      }
    }
    states.push({ accepting: subset.contains(end), edges, })
    index += 1
  }
  { states, }
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
fn Dfa::step(self : Dfa, state : Int32, cp : Int32) -> Int32? {
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
    return Some(edge.target)
  }
  None
}

///|
/// Returns the longest matching end position, including an empty match when
/// the expression is nullable. Invalid UTF-8 consumes one byte as U+FFFD.
pub fn Dfa::match_prefix(
  self : Dfa,
  input : Bytes,
  start~ : Int32 = 0,
) -> Int32? {
  if start < 0 || start > input.length() {
    return None
  }
  let mut offset = start
  let mut state = 0
  let mut accepted = if self.states[0].accepting { Some(start) } else { None }
  while offset < input.length() {
    let (cp, size) = decode(input, offset)
    match self.step(state, cp) {
      None => break
      Some(next) => {
        state = next
        offset += size
      }
    }
    if self.states[state].accepting {
      accepted = Some(offset)
    }
  }
  accepted
}

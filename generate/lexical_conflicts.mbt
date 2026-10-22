///|
// The generator's recovery lexer recognizes tokens outside normal parse states.
// Its vocabulary must exclude context-only tokens that swallow otherwise valid
// tokens. Analyze overlap as upstream build_tables/token_conflicts.rs does,
// including separator prefixes and characters that may follow a completion.
priv struct ConflictEdge {
  lo : Int32
  hi : Int32
  target : Int32
  precedence : Int32
  separator : Bool
}

///|
priv struct ConflictState {
  accepting : Bool
  has_separator : Bool
  edges : Array[ConflictEdge]
}

///|
fn conflict_automaton(
  token : @language.Token,
  separator : @lex.Dfa,
) -> Array[ConflictState] raise GenerateError {
  let offset = token.lexer.state_count()
  let edges = Array::makei(offset + separator.state_count(), index => {
    let sep = index >= offset
    let dfa = if sep { separator } else { token.lexer }
    dfa
    .transitions(if sep { index - offset } else { index })
    .map(edge => {
      let (chars, target, precedence) = edge
      // Dfa transitions each describe one contiguous range.
      let (lo, hi) = chars.ranges[0]
      ConflictEdge::{
        lo,
        hi,
        target: if sep {
          target + offset
        } else {
          target
        },
        precedence: precedence.unwrap_or(0),
        separator: sep,
      }
    })
  })
  fn closure(seeds : Array[Int32]) -> Array[Int32] {
    if seeds.any(id => id >= offset && separator.accepts(id - offset)) &&
      !seeds.contains(0) {
      seeds.push(0)
    }
    seeds.sort()
    seeds
  }
  let initial = closure(if token.immediate { [0] } else { [offset] })
  let subsets = [initial]
  let ids : Map[Array[Int32], Int32] = Map([(initial, 0)])
  let states = []
  let mut index = 0
  while index < subsets.length() {
    if subsets.length() > 100000 {
      raise ResourceLimit("recovery lexer state limit exceeded")
    }
    let subset = subsets[index]
    let boundaries = []
    for id in subset {
      for edge in edges[id] {
        boundaries.push(edge.lo)
        boundaries.push(edge.hi + 1)
      }
    }
    boundaries.sort()
    let transitions = []
    for i in 0..<(boundaries.length() - 1) {
      let lo = boundaries[i]
      let hi = boundaries[i + 1] - 1
      if lo > hi {
        continue
      }
      let targets = []
      let mut precedence = -2147483648
      let mut is_separator = true
      for id in subset {
        for edge in edges[id] {
          if edge.lo <= lo && edge.hi >= lo {
            if !targets.contains(edge.target) {
              targets.push(edge.target)
            }
            precedence = Int32::max(precedence, edge.precedence)
            is_separator = is_separator && edge.separator
          }
        }
      }
      if targets.is_empty() {
        continue
      }
      let next = closure(targets)
      let target = match ids.get(next) {
        Some(id) => id
        None => {
          let id = subsets.length()
          ids[next] = id
          subsets.push(next)
          id
        }
      }
      transitions.push(ConflictEdge::{
        lo,
        hi,
        target,
        precedence,
        separator: is_separator,
      })
    }
    states.push(ConflictState::{
      accepting: subset.any(id => id < offset && token.lexer.accepts(id)),
      has_separator: subset.any(id => id >= offset && !edges[id].is_empty()),
      edges: transitions,
    })
    index += 1
  }
  states
}

///|
fn conflict_transition(state : ConflictState, code : Int32) -> ConflictEdge? {
  for lo = 0, hi = state.edges.length(); lo < hi; {
    let mid = (lo + hi) / 2
    let edge = state.edges[mid]
    if code < edge.lo {
      continue lo, mid
    } else if code > edge.hi {
      continue mid + 1, hi
    } else {
      return Some(edge)
    }
  }
  None
}

///|
// Conflict bits: valid continuation=1, separator=2, same string=4,
// continuation=8, prefix=16, different string=32. Keep the full status for
// keyword substitution checks, not only the recovery exclusion mask.
fn token_conflicts(
  left : Array[ConflictState],
  right : Array[ConflictState],
  left_token : @language.Token,
  right_token : @language.Token,
  left_following : @lex.CharSet,
  right_following : @lex.CharSet,
) -> (Int32, Int32) {
  let mut left_flags = 0
  let mut right_flags = 0
  let pending = [(0, 0)]
  let visited : Map[(Int32, Int32), Bool] = Map([((0, 0), true)])
  while pending.pop() is Some((a, b)) {
    let a = left[a]
    let b = right[b]
    let within_separator = a.has_separator || b.has_separator
    if within_separator {
      if a.accepting {
        left_flags = left_flags | 2
      }
      if b.accepting {
        right_flags = right_flags | 2
      }
    }
    let completion = if a.accepting && b.accepting {
      let left_implicit = (if left_token.literal { 2 } else { 0 }) +
        (if left_token.immediate { 1 } else { 0 })
      let right_implicit = (if right_token.literal { 2 } else { 0 }) +
        (if right_token.immediate { 1 } else { 0 })
      // The caller puts the earlier token on the left.
      if left_token.precedence > right_token.precedence ||
        (
          left_token.precedence == right_token.precedence &&
          left_implicit >= right_implicit
        ) {
        left_flags = left_flags | 4
        Some(true)
      } else {
        right_flags = right_flags | 4
        Some(false)
      }
    } else if a.accepting {
      Some(true)
    } else if b.accepting {
      Some(false)
    } else {
      None
    }
    let boundaries = []
    for edge in a.edges {
      boundaries.push(edge.lo)
      boundaries.push(edge.hi + 1)
    }
    for edge in b.edges {
      boundaries.push(edge.lo)
      boundaries.push(edge.hi + 1)
    }
    boundaries.sort()
    for k in 0..<(boundaries.length() - 1) {
      let lo = boundaries[k]
      let hi = boundaries[k + 1] - 1
      if hi < lo {
        continue
      }
      let next_a = conflict_transition(a, lo)
      let next_b = conflict_transition(b, lo)
      match (next_a, next_b) {
        (Some(x), Some(y)) => {
          let pair = (x.target, y.target)
          if !visited.contains(pair) {
            visited[pair] = true
            pending.push(pair)
          }
        }
        (Some(edge), None) | (None, Some(edge)) => {
          let advancing_left = next_a is Some(_)
          if advancing_left {
            left_flags = left_flags | 32
          } else {
            right_flags = right_flags | 32
          }
          if completion is Some(completed_left) &&
            completed_left != advancing_left {
            let precedence = if completed_left {
              left_token.precedence
            } else {
              right_token.precedence
            }
            if edge.precedence > precedence ||
              (
                edge.precedence == precedence &&
                !edge.separator &&
                !within_separator
              ) {
              if advancing_left {
                left_flags = left_flags | 8
              } else {
                right_flags = right_flags | 8
              }
              let following = if completed_left {
                left_following
              } else {
                right_following
              }
              if following.ranges.any(range => range.0 <= hi && range.1 >= lo) {
                if advancing_left {
                  left_flags = left_flags | 1
                } else {
                  right_flags = right_flags | 1
                }
              }
            } else if completed_left {
              left_flags = left_flags | 16
            } else {
              right_flags = right_flags | 16
            }
          }
        }
        _ => ()
      }
    }
  }
  (left_flags, right_flags)
}

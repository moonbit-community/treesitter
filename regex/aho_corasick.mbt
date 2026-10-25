// The meta engine's literal-alternation strategy: a regex that is a plain
// alternation of at least 3000 literals (`meta/literal.rs`
// `alternation_literals`) is answered by an Aho-Corasick automaton with
// leftmost-first semantics instead of a regex engine
// (`Pre::from_alternation_literals` in `meta/strategy.rs`), so that searches
// take time linear in the haystack.
//
// This is aho-corasick 1.1's noncontiguous NFA (`nfa/noncontiguous.rs`) for
// `MatchKind::LeftmostFirst` and its unanchored forward search
// (`automaton.rs` `try_find_fwd_imp`). Leftmost-first semantics are those of
// the regex: the match that starts first, and among the literals matching
// there, the one listed first. Since the NFA only reports a state's first
// match, a state keeps the length of that match rather than a match list.

///|
/// `NFA::DEAD`: every transition loops back to it; entering it ends a
/// search.
const AC_DEAD : Int32 = 0

///|
/// The unanchored start state, whose missing transitions loop to itself.
const AC_START : Int32 = 1

///|
/// `NFA::FAIL`: the result of a lookup for a missing transition.
const AC_FAIL : Int32 = -1

///|
priv struct AhoCorasick {
  /// The transitions of the start state, by byte.
  start : FixedArray[Int32]
  /// The trie transitions of the other states, by `state << 8 | byte`.
  trans : Map[Int32, Int32]
  /// The trie transitions of each state, in insertion order.
  children : Array[Array[(Int32, Int32)]]
  /// The failure transition of each state.
  fail : Array[Int32]
  /// The length of the state's first match, or -1 if it is no match state.
  match_len : Array[Int32]
}

///|
/// `alternation_literals`: the literals of `hir` when the meta engine uses
/// Aho-Corasick for it (a single alternation of at least 3000 literals or
/// concatenations of literals, without look-around or explicit captures).
fn alternation_literals(hir : @hir.Hir) -> Array[Bytes]? {
  let props = hir.properties()
  if !props.look_set().is_empty() ||
    props.explicit_captures_len() > 0 ||
    !props.is_alternation_literal() {
    return None
  }
  guard hir.kind() is Alternation(alts) else { return None }
  if alts.length() < 3000 {
    return None
  }
  let lits = []
  for alt in alts {
    let lit = []
    match alt.kind() {
      Literal(Literal(bytes)) => lit.append(bytes.to_array())
      Concat(exprs) =>
        for e in exprs {
          match e.kind() {
            Literal(Literal(bytes)) => lit.append(bytes.to_array())
            _ => abort("expected literal")
          }
        }
      _ => abort("expected literal or concat")
    }
    lits.push(Bytes::from_array(lit))
  }
  Some(lits)
}

///|
fn AhoCorasick::follow(self : AhoCorasick, sid : Int32, byte : Int32) -> Int32 {
  if sid == AC_START {
    self.start[byte]
  } else if sid == AC_DEAD {
    AC_DEAD
  } else {
    self.trans.get((sid << 8) | byte).unwrap_or(AC_FAIL)
  }
}

///|
fn AhoCorasick::alloc_state(self : AhoCorasick) -> Int32 {
  self.children.push([])
  self.fail.push(AC_START)
  self.match_len.push(-1)
  self.fail.length() - 1
}

///|
/// Build the automaton for `patterns` in priority order (`Compiler::compile`
/// with leftmost-first match semantics).
fn AhoCorasick::new(patterns : Array[Bytes]) -> AhoCorasick {
  let ac : AhoCorasick = {
    start: FixedArray::make(256, AC_FAIL),
    trans: Map([]),
    children: [[], []],
    fail: [AC_DEAD, AC_START],
    match_len: [-1, -1],
  }
  // build_trie
  for pattern in patterns {
    let mut prev = AC_START
    let mut skip = false
    for b in pattern {
      // A pattern with an earlier pattern as a prefix can never match under
      // leftmost-first semantics, and must not be added.
      if ac.match_len[prev] >= 0 {
        skip = true
        break
      }
      let b = b.to_int()
      let next = ac.follow(prev, b)
      if next != AC_FAIL {
        prev = next
      } else {
        let next = ac.alloc_state()
        if prev == AC_START {
          ac.start[b] = next
        } else {
          ac.trans[(prev << 8) | b] = next
        }
        ac.children[prev].push((b, next))
        prev = next
      }
    }
    // `add_match`: the first pattern ending in a state is reported; all of
    // them have the state's depth as their length.
    if !skip && ac.match_len[prev] < 0 {
      ac.match_len[prev] = pattern.length()
    }
  }
  // add_unanchored_start_state_loop
  for b in 0..<256 {
    if ac.start[b] == AC_FAIL {
      ac.start[b] = AC_START
    }
  }
  // fill_failure_transitions, leftmost: match states (and so every state
  // after one) fail to the dead state; matches reachable through a failure
  // transition are copied to its source.
  let queue = []
  for child in ac.children[AC_START] {
    let next = child.1
    queue.push(next)
    if ac.match_len[next] >= 0 {
      ac.fail[next] = AC_DEAD
    }
  }
  for head = 0; head < queue.length(); head = head + 1 {
    let id = queue[head]
    for child in ac.children[id] {
      let (byte, next) = child
      queue.push(next)
      if ac.match_len[next] >= 0 {
        ac.fail[next] = AC_DEAD
        continue
      }
      let mut fail = ac.fail[id]
      while ac.follow(fail, byte) == AC_FAIL {
        fail = ac.fail[fail]
      }
      fail = ac.follow(fail, byte)
      ac.fail[next] = fail
      // copy_matches: `next` had no match of its own.
      ac.match_len[next] = ac.match_len[fail]
    }
  }
  ac
}

///|
/// The leftmost-first match in `hay[from:]`, as `(start, end)`.
fn AhoCorasick::find(
  self : AhoCorasick,
  hay : BytesView,
  from : Int32,
) -> (Int32, Int32)? {
  let mut sid = AC_START
  let mut mat = None
  for at in from..<hay.length() {
    let byte = hay[at].to_int()
    // next_state: follow failure transitions until a transition exists.
    for ;; {
      let next = self.follow(sid, byte)
      if next != AC_FAIL {
        sid = next
        break
      }
      sid = self.fail[sid]
    }
    if sid == AC_DEAD {
      return mat
    }
    let len = self.match_len[sid]
    if len >= 0 {
      mat = Some((at + 1 - len, at + 1))
    }
  }
  mat
}

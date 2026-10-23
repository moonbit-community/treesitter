///|
// A reduction after an inserted token is not enough: its resulting stack must
// eventually shift the real lookahead. Otherwise the fabricated token starts
// another recovery and can displace a viable branch. Check the reduction
// closure before allocating the missing leaf (parser.c: handle_error).
fn Parser::can_resume_after_missing(
  self : Parser,
  states : Array[Int32],
  lookahead : Int32,
  limit : Int32,
) -> Bool raise ParseError {
  // EOF completes a tree without a shift. Its insertion candidate remains
  // available to the main parse loop, which performs reductions and accepts.
  if lookahead == 0 {
    return true
  }
  let work = [states]
  let seen : Map[Array[Int32], Bool] = Map([(states, true)])
  let mut index = 0
  while index < work.length() {
    if work.length() > limit {
      raise ParseLimit("missing-token reduction limit exceeded")
    }
    let stack = work[index]
    index += 1
    let state = self.language.states[stack.last().unwrap()]
    let actions = state.actions.get(lookahead).unwrap_or([])
    for action in actions {
      match action {
        Shift(_) => return true
        Reduce(pid) => {
          let production = self.language.productions[pid]
          let count = production.steps.length()
          if count == 0 ||
            count >= stack.length() ||
            (production.requires_eof == Some(true) && lookahead != 0) {
            continue
          }
          let bottom = stack.length() - count - 1
          if self.language.states[stack[bottom]].gotos.get(production.lhs)
            is Some(next) {
            let reduced = stack[:bottom + 1].to_owned() + [next]
            if !seen.contains(reduced) {
              seen[reduced] = true
              work.push(reduced)
            }
          }
        }
        _ => ()
      }
    }
  }
  false
}

///|
// Materialize the reductions after a missing token before opening alternate
// recovery paths. The C runtime uses these ready states to avoid redundant
// recoveries at the same input position, even when their final costs differ.
fn Parser::reduce_after_missing(
  self : Parser,
  branch : Branch,
  lookahead : Int32,
  lines : Array[Int32],
  limit : Int32,
) -> Array[Branch] raise ParseError {
  let versions = [branch]
  let mut index = 0
  let mut iteration = 0
  while index < versions.length() {
    if versions.length() > limit || iteration > limit {
      raise ParseLimit("missing-token reduction limit exceeded")
    }
    let current = versions[index]
    let state = current.states.last().unwrap()
    let actions = self.language.states[state].actions
      .get(lookahead)
      .unwrap_or([])
    let can_shift = actions.any(a => a is Shift(_))
    let previous_count = versions.length()
    for action in actions {
      if action is Reduce(pid) &&
        !self.language.productions[pid].steps.is_empty() {
        if self.reduce(current, pid, lines) is Some(reduced) &&
          !versions.any(other => {
            other.states == reduced.states &&
            equivalent_top_link(other.entries, reduced.entries)
          }) {
          versions.push(reduced)
        }
      }
    }
    if !can_shift && versions.length() > previous_count && iteration < 6 {
      versions[index] = versions.pop().unwrap()
    } else if !can_shift {
      ignore(versions.remove(index))
    } else {
      index += 1
    }
    iteration += 1
  }
  versions
}

///|
// Anonymous separators skipped by lexing are lookahead padding, not part of
// the stack. Missing leaves are inserted before that padding, after any named
// extras that the parser has already consumed.
fn Branch::position(self : Branch) -> Int32 {
  self.pending
  .last()
  .map(n => n.end_byte())
  .unwrap_or_else(() => {
    self.entries.last().map(e => e.node.end_byte()).unwrap_or(0)
  })
}

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

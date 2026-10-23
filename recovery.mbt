///|
// A stack pop stops immediately before the first discarded non-extra subtree.
// Its leading extras remain on the stack. If the last one is ERROR, upstream
// pops it separately and folds its children into the new error, avoiding a
// second recovery charge. Other extras (including intervening comments) stay
// outside the new error.
fn Parser::recover_pending(
  self : Parser,
  branch : Branch,
  index : Int32,
  lines : Array[Int32],
) -> Array[Node] {
  let leading = branch.entries[index].leading.copy()
  let discarded : Array[Node] = []
  if leading.last() is Some(previous) && previous.is_error() {
    ignore(leading.pop())
    if previous.child_count() > 0 {
      discarded.push({
        context: None,
        data: { ..previous.data, error_repeat: true, },
      })
    }
  }
  for i in index..<branch.entries.length() {
    let entry = branch.entries[i]
    if i > index {
      discarded.append(entry.leading)
    }
    discarded.push(entry.node)
  }
  discarded.append(branch.pending)
  leading +
  self.error_pending(
    [],
    discarded,
    lines,
    branch.states[index],
    preserve_trailing_extras=true,
  )
}

///|
// Potential reductions use terminal lookaheads other than EOF. Empty
// productions cannot preserve consumed input during recovery and are excluded.
// Sorting by the reduced symbol makes the surviving version independent of
// parse-table map iteration order (parser.c: do_all_potential_reductions).
fn Parser::potential_reductions(
  self : Parser,
  branch : Branch,
) -> (Array[Int32], Bool) {
  let reductions : Map[Int32, Bool] = Map([])
  let mut can_shift = false
  if branch.status == Preparing {
    let state = branch.states.last().unwrap()
    for (symbol, actions) in self.language.states[state].actions {
      if symbol == 0 {
        continue
      }
      for action in actions {
        match action {
          // Entering a nonterminal extra is an ordinary shift into its
          // grammar. It keeps the unreduced history alive during recovery.
          Shift(_) | EnterExtra(_) => can_shift = true
          Reduce(pid) => {
            let production = self.language.productions[pid]
            if !production.steps.is_empty() &&
              production.requires_eof != Some(true) {
              reductions[pid] = true
            }
          }
          _ => ()
        }
      }
    }
  }
  let result = reductions.keys().to_array()
  result.sort_by((a, b) => {
    symbol_order(self.language, self.language.productions[b].lhs).compare(
      symbol_order(self.language, self.language.productions[a].lhs),
    )
  })
  (result, can_shift)
}

///|
// The discontinuity has one predecessor for every surviving potential
// reduction. Keep these histories on one recovering version: they share the
// skipped input, scanner state and scheduling position.
fn Parser::prepare_recovery(
  self : Parser,
  branch : Branch,
  lines : Array[Int32],
  max_branches : Int32,
) -> (Branch, Array[Branch]) raise ParseError {
  let versions = [branch]
  let mut index = 0
  let mut iteration = 0
  while index < versions.length() {
    if versions.length() > max_branches || iteration > max_branches {
      raise ParseLimit("recovery history limit exceeded")
    }
    let current = versions[index]
    let (reductions, can_shift) = self.potential_reductions(current)
    let previous_count = versions.length()
    for pid in reductions {
      if self.reduce(current, pid, lines) is Some(reduced) {
        if !versions.any(other => {
            other.states == reduced.states &&
            equivalent_top_link(other.entries, reduced.entries)
          }) {
          versions.push(reduced)
        }
      }
    }
    if !can_shift && versions.length() > previous_count && iteration < 6 {
      versions[index] = versions.pop().unwrap()
    } else {
      index += 1
    }
    iteration += 1
  }
  let inserted : Array[Branch] = []
  let token = branch.lookahead.unwrap()
  for current in versions {
    if branch.insertions > 0 || !inserted.is_empty() {
      break
    }
    let state = current.states.last().unwrap()
    let expected_tokens = self.language.states[state].actions.keys().to_array()
    expected_tokens.sort_by((a, b) => {
      symbol_order(self.language, a).compare(symbol_order(self.language, b))
    })
    for expected in expected_tokens {
      if expected == 0 || !inserted.is_empty() {
        continue
      }
      for action in self.language.states[state].actions[expected] {
        if action is Shift(next) &&
          next != state &&
          self.language.states[next].actions
          .get(token.symbol)
          .unwrap_or([])
          .any(a => a is Reduce(_)) &&
          self.can_resume_after_missing(
            current.states + [next],
            token.symbol,
            max_branches,
          ) {
          let position = current.position()
          if token.symbol == 0 {
            inserted.push({
              ..current,
              histories: [],
              lookahead: Some({
                dependency_end: token.dependency_end,
                unexpected: None,
                symbol: expected,
                start: position,
                end: position,
                missing: true,
                scanner_state: None,
              }),
              errors: current.errors + 1,
              insertions: 1,
            })
          } else {
            let missing = self.node(
              expected,
              position,
              position,
              lines,
              [],
              state,
              next,
              dependency_end=token.dependency_end,
              fragile=true,
              missing=true,
              scan_before=current.scanner_state,
              scan_after=current.scanner_state,
            )
            inserted.append(
              self.reduce_after_missing(
                {
                  ..current,
                  histories: [],
                  status: Active,
                  states: current.states + [next],
                  entries: current.entries +
                  [{ node: missing, leading: current.pending, }],
                  pending: [],
                  lookahead: Some(token),
                  errors: current.errors + 1,
                  insertions: 1,
                },
                token.symbol,
                lines,
                max_branches,
              ),
            )
          }
          if self.logger is Some(log) {
            log(
              Parse,
              "insert_missing symbol:\{self.language.symbols[expected].name} state:\{state}",
            )
          }
          break
        }
      }
    }
  }
  let first = versions[0]
  (
    {
      ..first,
      status: Recovering,
      histories: versions.map(v => {
        states: v.states,
        entries: v.entries,
        dynamic: v.dynamic,
      }),
    },
    inserted,
  )
}

///|
fn Parser::recover_history(
  self : Parser,
  branch : Branch,
  token : Lexeme,
  lines : Array[Int32],
  active : Array[Branch],
) -> Array[Branch] {
  let histories = if branch.histories.is_empty() {
    [
      {
        states: branch.states,
        entries: branch.entries,
        dynamic: branch.dynamic,
      },
    ]
  } else {
    branch.histories
  }
  let skipped = branch.pending.any(n => n.data.error_repeat)
  // Stack summaries are breadth first. The first viable state/depth wins;
  // different paths to that state remain available for subsequent reductions.
  // Upstream's depth budget of 16 includes the discontinuity, leaving at most
  // 15 ordinary entries below each retained history.
  for depth in (if skipped { 0 } else { 1 })..<16 {
    let result : Array[Branch] = []
    let mut goal = -1
    for history in histories {
      let index = history.entries.length() - depth
      if index < 0 {
        continue
      }
      let state = history.states[index]
      if active.any(other => {
          other.status == Active &&
          other.position() == branch.position() &&
          other.states.last() == Some(state)
        }) {
        continue
      }
      if goal >= 0 && state != goal {
        continue
      }
      if !self.language.states[state].actions.contains(token.symbol) {
        continue
      }
      goal = state
      let pending = if depth == 0 {
        branch.pending.map(n => {
          if n.data.error_repeat {
            {
              context: None,
              data: { ..n.data, error_repeat: false, extra: true, },
            }
          } else {
            n
          }
        })
      } else {
        self.recover_pending(
          { ..branch, states: history.states, entries: history.entries, },
          index,
          lines,
        )
      }
      let entries = history.entries[:index].to_owned()
      let states = history.states[:index + 1].to_owned()
      if result.any(other => {
          other.states == states &&
          (entries.is_empty() || equivalent_top_link(other.entries, entries))
        }) {
        continue
      }
      result.push({
        ..branch,
        histories: [],
        recovery_versions: 0,
        status: Active,
        states,
        entries,
        dynamic: history.dynamic,
        pending,
        lookahead: None,
        errors: branch.errors + (if depth == 0 { 0 } else { 1 }),
        insertions: 0,
      })
    }
    if !result.is_empty() {
      if self.logger is Some(log) {
        log(
          Parse,
          "recover state:\{goal} depth:\{depth} histories:\{result.length()}",
        )
      }
      return result
    }
  }
  []
}

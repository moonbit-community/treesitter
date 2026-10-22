///|
// Advance every current version before resolving paused competitors. Resolving
// on an individual shift drops versions too early; waiting until all work is
// empty resurrects stale errors after otherwise successful parses.
fn Parser::condense_round(
  self : Parser,
  work : Array[Branch],
  paused : Array[Branch],
) -> Bool {
  let versions : Array[(Branch, Bool, Int32)] = []
  for branch in work {
    versions.push(
      ({ ..branch, cost: branch_error_cost(branch), }, false, versions.length()),
    )
  }
  for branch in paused {
    versions.push(
      ({ ..branch, cost: branch_error_cost(branch), }, true, versions.length()),
    )
  }
  versions.sort_by((left, right) => {
    let left_error = left.1 || left.0.status != Active
    let right_error = right.1 || right.0.status != Active
    if left_error != right_error {
      return if left_error { 1 } else { -1 }
    }
    let cost = (left.0.cost + (if left.1 { 100 } else { 0 })).compare(
      right.0.cost + (if right.1 { 100 } else { 0 }),
    )
    if cost != 0 {
      return cost
    }
    let dynamic = right.0.dynamic.compare(left.0.dynamic)
    if dynamic != 0 {
      dynamic
    } else {
      left.2.compare(right.2)
    }
  })
  let mut removed = false
  work.clear()
  paused.clear()
  let retained : Array[(Branch, Bool)] = []
  for (branch, is_paused, _) in versions {
    // parser.c's TakeLeft/TakeRight rule: a cheaper non-error version makes
    // a recovering competitor obsolete, even before the latter pauses again.
    if (is_paused || branch.status != Active) &&
      versions.any(candidate => {
        !candidate.1 &&
        candidate.0.status == Active &&
        candidate.0.cost < branch.cost + (if is_paused { 100 } else { 0 })
      }) {
      removed = true
      continue
    }
    if retained.search_by(previous => {
        let other = previous.0
        previous.1 == is_paused &&
        other.status == branch.status &&
        other.insertions == branch.insertions &&
        other.errors == branch.errors &&
        other.states == branch.states &&
        other.offset == branch.offset &&
        other.scanner_state == branch.scanner_state &&
        other.lookahead == branch.lookahead &&
        other.extras.map(frame => (frame.states, frame.start)) ==
        branch.extras.map(frame => (frame.states, frame.start))
      })
      is Some(previous_index) {
      // Coalesce identical future configurations before applying the version
      // limit. Preserve the same live-link and derivation ordering as visited
      // configurations in the parser, rather than discarding by queue order.
      let other = retained[previous_index].0
      if other.cost == branch.cost &&
        other.dynamic == branch.dynamic &&
        !equivalent_top_link(other.entries, branch.entries) &&
        compare_derivations(
          self.language,
          other.entries.map(entry => entry.node.data.derivation),
          branch.entries.map(entry => entry.node.data.derivation),
        ) >
        0 {
        retained[previous_index] = (branch, is_paused)
      }
      removed = true
      continue
    }
    retained.push((branch, is_paused))
  }
  for i, (branch, is_paused) in retained {
    // Match the reference's MAX_VERSION_COUNT. The other retained versions
    // still count during the first recovery step, before paused ones disappear.
    if i >= 6 {
      removed = true
    } else if is_paused {
      if i == 0 {
        if self.logger is Some(log) {
          log(
            Parse,
            "resume round:\{branch.round} offset:\{branch.offset} cost:\{branch.cost}",
          )
        }
        work.push({
          ..branch,
          status: Preparing,
          recovery_versions: Int32::min(6, retained.length()),
        })
      } else {
        removed = true
      }
    } else {
      work.push(branch)
    }
  }
  removed
}

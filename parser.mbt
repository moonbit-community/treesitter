///|
pub suberror ParseError {
  Cancelled
  InvalidRanges(String)
  ScannerError(String)
  ParseLimit(String)
  NoParse(Int32)
} derive(Debug)

///|
pub extend ParseError with @debug.Debug::{to_repr}

///|
pub struct Parser {
  language : @language.Language
  priv mut next_id : Int32
  priv scanner : ExternalScanner?
  priv mut suspended : ParseContinuation?
  priv mut projection : Projection?
  priv mut logger : ((LogType, String) -> Unit)?
}

///|
pub fn Parser::new(
  language : @language.Language,
  scanner? : ExternalScanner,
) -> Parser raise @language.LanguageError {
  language.validate()
  {
    language,
    next_id: 0,
    scanner,
    suspended: None,
    projection: None,
    logger: None,
  }
}

///|
priv struct Lexeme {
  dependency_end : Int32
  unexpected : Int32?
  symbol : Int32
  start : Int32
  end : Int32
  missing : Bool
  scanner_state : Bytes?
} derive(Eq)

///|
priv struct Entry {
  node : Node
  leading : Array[Node]
}

///|
priv struct ExtraFrame {
  states : Array[Int32]
  entries : Array[Entry]
  pending : Array[Node]
  start : Int32
}

///|
priv enum BranchStatus {
  Active
  Preparing
  Recovering
} derive(Eq, Hash)

///|
priv struct BranchKey {
  status : BranchStatus
  states : Array[Int32]
  offset : Int32
  symbol : Int32
  missing : Bool
  insertions : Int32
  errors : Int32
  scanner_state : Bytes
  next_scanner_state : Bytes?
  extras : Array[(Array[Int32], Int32)]
  histories : Array[Array[Int32]]
} derive(Eq, Hash)

///|
priv struct RecoveryHistory {
  states : Array[Int32]
  entries : Array[Entry]
  dynamic : Int32
}

///|
priv struct Branch {
  histories : Array[RecoveryHistory]
  round : Int32
  recovery_versions : Int32
  status : BranchStatus
  extras : Array[ExtraFrame]
  states : Array[Int32]
  entries : Array[Entry]
  offset : Int32
  pending : Array[Node]
  lookahead : Lexeme?
  cost : Int32
  errors : Int32
  dynamic : Int32
  insertions : Int32
  scanner_state : Bytes
}

///|
priv struct ParseContinuation {
  frontier : Int32
  yielded : Bool
  round : Int32
  source : Bytes
  projection : Projection?
  lines : Array[Int32]
  reusable : Map[(Int32, Int32), Node]
  reused_subtrees : Int32
  work : Array[Branch]
  paused : Array[Branch]
  visited : Map[BranchKey, (Int32, Int32, Array[Entry])]
  best : (Node, Int32, Int32)?
  steps : Int32
  furthest : Int32
  max_steps : Int32
  max_branches : Int32
  max_errors : Int32
}

///|
fn Parser::node(
  self : Parser,
  symbol : Int32,
  start : Int32,
  end : Int32,
  lines : Array[Int32],
  children : Array[ChildPart],
  parse_state : Int32,
  next_state : Int32,
  unexpected? : Int32,
  dependency_end? : Int32,
  derivation_children? : Array[Derivation],
  fragile~ : Bool = false,
  error_repeat~ : Bool = false,
  extra~ : Bool = false,
  missing~ : Bool = false,
  dynamic_score~ : Int32 = 0,
  scan_before~ : Bytes = b"",
  scan_after~ : Bytes = b"",
) -> Node {
  let id = self.next_id
  self.next_id += 1
  let meta = if symbol < 0 {
    @language.Symbol::{
      name: "ERROR",
      named: true,
      visible: true,
      terminal: false,
    }
  } else {
    self.language.symbols[symbol]
  }
  let children = child_list(children)
  let error_extent = match self.projection {
    Some(p) => {
      let first = p.starts[start]
      let last = if start == end { first } else { p.ends[end] }
      500 +
      last -
      first +
      30 * (point_at(p.lines, last).row - point_at(p.lines, first).row)
    }
    None =>
      500 +
      end -
      start +
      30 * (point_at(lines, end).row - point_at(lines, start).row)
  }
  let mut error_cost = children.error_cost
  if missing {
    error_cost += 610
  }
  if symbol < 0 {
    error_cost += error_extent
    for (_, child) in children.entries() {
      if child.data.error_repeat {
        error_cost -= child.data.error_extent
      } else if !child.is_extra() &&
        !(child.is_error() && child.child_count() == 0) {
        error_cost += 100
      }
    }
  }
  {
    data: {
      id,
      continuation: None,
      fragile: fragile || children.fragile,
      derivation: {
        symbol,
        children: derivation_children.unwrap_or_else(() => {
          children.entries().map(c => c.1.data.derivation)
        }),
      },
      dependency_end: Int32::max(
        children.dependency_end,
        dependency_end.unwrap_or(end),
      ),
      encoding: Utf8,
      error_cost,
      error_extent,
      error_repeat,
      unexpected,
      changed: false,
      origin_start: start,
      origin_end: end,
      dynamic_score,
      supertypes: [],
      scan_before,
      scan_after,
      symbol,
      kind: meta.name,
      named: meta.named,
      extra,
      missing,
      error: symbol < 0,
      visible: meta.visible,
      start_byte: start,
      end_byte: end,
      start_point: point_at(lines, start),
      end_point: point_at(lines, end),
      children,
      parse_state,
      next_state,
    },
  }
}

///|
fn append_visible(
  output : Array[ChildPart],
  node : Node,
  field : String?,
) -> Unit {
  if node.data.visible || node.is_error() || node.is_missing() {
    output.push(Item(field, node))
  } else if node.data.children.length > 0 {
    output.push(Nested(field, node.data.children))
  }
}

///|
fn Parser::reduce(
  self : Parser,
  branch : Branch,
  pid : Int32,
  lines : Array[Int32],
  fragile~ : Bool = true,
) -> Branch? {
  let production = self.language.productions[pid]
  let count = production.steps.length()
  if branch.entries.length() < count {
    return None
  }
  let index = branch.entries.length() - count
  let previous_state = branch.states[index]
  guard self.language.states[previous_state].gotos.get(production.lhs)
    is Some(next_state) else {
    return None
  }
  let children : Array[ChildPart] = []
  let derivation_children : Array[Derivation] = []
  let leading = if count == 0 { [] } else { branch.entries[index].leading }
  for i in 0..<count {
    let entry = branch.entries[index + i]
    if i > 0 {
      for extra in entry.leading {
        append_visible(children, extra, None)
        derivation_children.push(extra.data.derivation)
      }
    }
    derivation_children.push(entry.node.data.derivation)
    let step = production.steps[i]
    let child = match step.rename {
      Some((name, named)) => entry.node.renamed(name, named)
      None => entry.node
    }
    append_visible(children, child, step.field)
  }
  if self.language.supertypes.contains(production.lhs) {
    let name = self.language.symbols[production.lhs].name
    let entries = child_list(children.copy()).entries()
    children.clear()
    for (field, child) in entries {
      let child = if child.is_extra() {
        child
      } else {
        { data: { ..child.data, supertypes: child.data.supertypes + [name], }, }
      }
      children.push(Item(field, child))
    }
  }

  let start = if count == 0 {
    branch.offset
  } else {
    branch.entries[index].node.start_byte()
  }
  let end = if count == 0 {
    branch.offset
  } else {
    branch.entries.last().unwrap().node.end_byte()
  }
  let score = branch.entries[index:].fold(init=production.dynamic_precedence, (
    total,
    e,
  ) => total + e.node.data.dynamic_score)
  let node = self.node(
    production.lhs,
    start,
    end,
    lines,
    children,
    previous_state,
    next_state,
    dependency_end=branch.entries[index:].fold(
      init=branch.lookahead.map(t => t.dependency_end).unwrap_or(end),
      (value, entry) => Int32::max(value, entry.node.data.dependency_end),
    ),
    fragile=fragile || branch.entries[index:].any(e => e.node.data.fragile),
    derivation_children~,
    dynamic_score=score,
    scan_before=if count == 0 {
      branch.scanner_state
    } else {
      branch.entries[index].node.data.scan_before
    },
    scan_after=branch.scanner_state,
  )
  let entries = branch.entries[:index].to_owned()
  let node = {
    data: {
      ..node.data,
      continuation: branch.lookahead.map(token => {
        (token, branch.pending, branch.offset)
      }),
    },
  }
  entries.push({ node, leading, })
  let states = branch.states[:index + 1].to_owned()
  states.push(next_state)
  Some({
    ..branch,
    states,
    entries,
    dynamic: branch.dynamic + production.dynamic_precedence,
  })
}

///|
fn Parser::finish(
  self : Parser,
  branch : Branch,
  lines : Array[Int32],
) -> Node? {
  guard branch.entries.last() is Some(entry) else { return None }
  let root = entry.node
  if entry.leading.is_empty() && branch.pending.is_empty() {
    // The accepted EOF includes skipped trailing input. It extends the root's
    // extent without changing the final syntax child's range.
    return Some({
      data: {
        ..root.data,
        end_byte: Int32::max(root.end_byte(), branch.offset),
        end_point: point_at(lines, Int32::max(root.end_byte(), branch.offset)),
        scan_after: branch.scanner_state,
      },
    })
  }
  let children : Array[ChildPart] = []
  for extra in entry.leading {
    append_visible(children, extra, None)
  }
  children.push(Nested(None, root.data.children))
  for extra in branch.pending {
    append_visible(children, extra, None)
  }
  let mut start = root.start_byte()
  let mut end = Int32::max(root.end_byte(), branch.offset)
  // Recovery can finish an empty root at EOF and attach an earlier ERROR as
  // pending syntax. The final root must enclose all attached children.
  for extra in entry.leading + branch.pending {
    start = Int32::min(start, extra.start_byte())
    end = Int32::max(end, extra.end_byte())
  }
  Some(
    self.node(
      root.symbol(),
      start,
      end,
      lines,
      children,
      root.parse_state(),
      root.next_parse_state(),
      fragile=root.data.fragile,
      dependency_end=root.data.dependency_end,
      dynamic_score=root.data.dynamic_score,
      derivation_children=entry.leading.map(n => n.data.derivation) +
        root.data.derivation.children +
        branch.pending.map(n => n.data.derivation),
      scan_before=root.data.scan_before,
      scan_after=branch.scanner_state,
    ),
  )
}

///|
/// Parse UTF-8 using generated tables. Declared conflicts explore separate
/// stacks; error recovery explores missing tokens and skipped input with costs.
/// Exhausted limits and cancellation are errors, never truncated success trees.
/// `max_steps=0` (the default) has no step limit; positive values bound work.
pub fn Parser::parse(
  self : Parser,
  source : Bytes,
  old_tree? : Tree,
  included_ranges~ : Array[Range] = [],
  max_steps~ : Int32 = 0,
  max_branches~ : Int32 = 10000,
  max_errors~ : Int32 = 20,
  cancelled~ : () -> Bool = () => false,
) -> Tree raise ParseError {
  self.suspended = None
  if cancelled() {
    raise Cancelled
  }
  if !included_ranges.is_empty() {
    return self.parse_ranges(
      source, included_ranges, max_steps, max_branches, max_errors, cancelled,
    )
  }
  self.parse_source(
    source,
    old_tree?,
    max_steps~,
    max_branches~,
    max_errors~,
    cancelled~,
  )
}

///|
fn Parser::parse_source(
  self : Parser,
  source : Bytes,
  old_tree? : Tree,
  projection~ : Projection? = None,
  continuation~ : ParseContinuation? = None,
  max_steps~ : Int32 = 0,
  max_branches~ : Int32 = 10000,
  max_errors~ : Int32 = 20,
  cancelled~ : () -> Bool = () => false,
) -> Tree raise ParseError {
  if max_steps < 0 {
    raise ParseLimit("max_steps must be non-negative")
  }
  if cancelled() {
    raise Cancelled
  }
  self.suspended = None
  self.projection = projection
  if !self.language.externals.is_empty() && self.scanner is None {
    raise ScannerError("language requires an external scanner")
  }
  let mut reused_subtrees = continuation
    .map(c => c.reused_subtrees)
    .unwrap_or(0)
  let reusable = if continuation is Some(saved) {
    saved.reusable
  } else {
    match old_tree {
      Some(tree) if physical_equal(tree.language, self.language) &&
        tree.encoding() == Utf8 &&
        tree.source_ranges.is_empty() &&
        same_scanner(tree.scanner, self.scanner) => {
        self.next_id = Int32::max(self.next_id, tree.root.id() + 1)
        if !tree.edited && tree.source == source {
          return {
            root: tree.root,
            source,
            language: self.language,
            edited: false,
            edited_length: source.length(),
            reused_subtrees: 1,
            parse_steps: 0,
            source_ranges: [],
            scanner: self.scanner,
          }
        }
        if tree.edited && tree.edited_length == source.length() {
          reuse_candidates(tree, source)
        } else {
          Map([])
        }
      }
      _ => Map([])
    }
  }
  let lines = continuation
    .map(c => c.lines)
    .unwrap_or_else(() => line_starts(source))
  let work : Array[Branch] = if continuation is Some(saved) {
    saved.work
  } else {
    [
      {
        histories: [],
        status: Active,
        round: 0,
        recovery_versions: 0,
        states: [0],
        extras: [],
        entries: [],
        offset: 0,
        pending: [],
        lookahead: None,
        cost: 0,
        errors: 0,
        dynamic: 0,
        insertions: 0,
        scanner_state: b"",
      },
    ]
  }
  let paused : Array[Branch] = continuation.map(c => c.paused).unwrap_or([])
  let visited : Map[BranchKey, (Int32, Int32, Array[Entry])] = continuation
    .map(c => c.visited)
    .unwrap_or(Map([]))
  let mut best : (Node, Int32, Int32)? = match continuation {
    Some(saved) => saved.best
    None => None
  }
  let mut steps = continuation.map(c => c.steps).unwrap_or(0)
  let mut furthest = continuation.map(c => c.furthest).unwrap_or(0)
  let mut round = continuation.map(c => c.round).unwrap_or(0)
  let mut frontier = continuation.map(c => c.frontier).unwrap_or(0)
  let mut yielded = continuation.map(c => c.yielded).unwrap_or(false)
  // A round advances each version to the furthest byte reached so far. A
  // version behind a long lexical token may take several steps to catch up.
  fn advance(next : Branch) {
    if next.offset > frontier || (yielded && next.offset == frontier) {
      frontier = next.offset
      yielded = true
      work.push({ ..next, round: round + 1, })
    } else {
      work.insert(0, next)
    }
  }
  while !work.is_empty() || !paused.is_empty() {
    if !work.is_empty() && work.all(branch => branch.round > round) {
      if self.condense_round(work, paused) {
        visited.clear()
      }
      yielded = false
      round = work.fold(init=work[0].round, (value, branch) => {
        Int32::min(value, branch.round)
      })
    }
    if work.is_empty() {
      let mut selected = paused[0]
      for candidate in paused[1:] {
        if candidate.cost < selected.cost ||
          (
            candidate.cost == selected.cost &&
            candidate.dynamic > selected.dynamic
          ) {
          selected = candidate
        }
      }
      let versions = Int32::min(paused.length(), 6)
      paused.clear()
      // Previously visited configurations can belong only to stacks discarded
      // above. They must not dominate the sole resumed recovery path.
      visited.clear()
      if self.logger is Some(log) {
        log(
          Parse,
          "resume offset:\{selected.offset} cost:\{selected.cost} versions:\{versions}",
        )
      }
      round = selected.round
      work.push({ ..selected, status: Preparing, recovery_versions: versions, })
    }
    if cancelled() {
      self.suspended = Some({
        frontier,
        yielded,
        round,
        source,
        projection,
        lines,
        reusable,
        reused_subtrees,
        work,
        paused,
        visited,
        best,
        steps,
        furthest,
        max_steps,
        max_branches,
        max_errors,
      })
      raise Cancelled
    }
    let initial = work.remove(
      work.search_by(branch => branch.round <= round).unwrap(),
    )
    let initial = { ..initial, cost: branch_error_cost(initial), }
    if self.logger is Some(log) {
      log(
        Parse,
        "process state:\{initial.states.last().unwrap()} offset:\{initial.offset} cost:\{initial.cost} versions:\{work.length() + paused.length() + 1}",
      )
    }
    steps += 1
    if max_steps > 0 && steps > max_steps {
      raise ParseLimit("parser step limit exceeded")
    }
    if work.length() > max_branches {
      raise ParseLimit("GLR branch limit exceeded")
    }
    if initial.errors > max_errors {
      continue
    }
    if best is Some((_, cost, _)) && initial.cost > cost {
      continue
    }
    let branch = if initial.lookahead is None {
      self.lex(source, initial, lines, projection, cancelled) catch {
        Cancelled => {
          work.insert(0, initial)
          self.suspended = Some({
            frontier,
            yielded,
            round,
            source,
            projection,
            lines,
            reusable,
            reused_subtrees,
            work,
            paused,
            visited,
            best,
            steps: steps - 1,
            furthest,
            max_steps,
            max_branches,
            max_errors,
          })
          raise Cancelled
        }
        error => raise error
      }
    } else {
      initial
    }
    let token = branch.lookahead.unwrap()
    if initial.lookahead is None && self.logger is Some(log) {
      let symbol = if token.symbol < 0 {
        "ERROR"
      } else {
        self.language.symbols[token.symbol].name
      }
      log(
        Lex,
        "lookahead symbol:\{symbol} start:\{token.start} end:\{token.end}",
      )
    }
    let preparing = branch.status == Preparing &&
      !token.missing &&
      !self.language.states[branch.states.last().unwrap()].actions.contains(
        token.symbol,
      )
    let branch = if preparing {
      let (prepared, inserted) = self.prepare_recovery(
        branch, lines, max_branches,
      )
      work.append(inserted)
      prepared
    } else {
      branch
    }
    furthest = Int32::max(furthest, branch.offset)
    let key : BranchKey = {
      status: branch.status,
      states: branch.states,
      offset: branch.offset,
      symbol: token.symbol,
      missing: token.missing,
      insertions: branch.insertions,
      errors: branch.errors,
      scanner_state: branch.scanner_state,
      next_scanner_state: token.scanner_state,
      extras: branch.extras.map(f => (f.states, f.start)),
      histories: branch.histories.map(h => h.states),
    }
    let derivations = branch.entries.map(e => e.node.data.derivation)
    if visited.get(key) is Some((cost, dynamic, previous)) &&
      (
        cost < branch.cost ||
        (
          cost == branch.cost &&
          (
            dynamic > branch.dynamic ||
            (
              dynamic == branch.dynamic &&
              (
                (
                  self.language.states[branch.states.last().unwrap()].actions
                  .get(token.symbol)
                  .unwrap_or([])
                  .any(a => a is Shift(_)) &&
                  equivalent_top_link(previous, branch.entries)
                ) ||
                compare_derivations(
                  self.language,
                  previous.map(e => e.node.data.derivation),
                  derivations,
                ) <=
                0
              )
            )
          )
        )
      ) {
      continue
    }
    visited[key] = (branch.cost, branch.dynamic, branch.entries)
    let state = branch.states.last().unwrap()
    if branch.status == Active &&
      work.is_empty() &&
      paused.is_empty() &&
      branch.extras.is_empty() &&
      !token.missing &&
      reusable.get((branch.offset, state)) is Some(candidate) &&
      candidate.data.scan_before == branch.scanner_state {
      let node = reset_origin(candidate, lines)
      let (lookahead, pending, offset) = match node.data.continuation {
        Some((token, pending, offset)) => (Some(token), pending, offset)
        None => (None, [], node.end_byte())
      }
      reused_subtrees += 1
      advance({
        ..branch,
        states: branch.states + [node.next_parse_state()],
        entries: branch.entries + [{ node, leading: branch.pending, }],
        pending,
        offset,
        lookahead,
        scanner_state: node.data.scan_after,
        dynamic: branch.dynamic + node.data.dynamic_score,
      })
      continue
    }
    let actions = self.language.states[state].actions
      .get(token.symbol)
      .unwrap_or(
        if !branch.extras.is_empty() && token.symbol < 0 {
          self.language.states[state].actions.get(0).unwrap_or([])
        } else {
          []
        },
      )
    if actions.is_empty() || branch.status == Recovering {
      if branch.status == Active && !token.missing {
        paused.push(branch)
        yielded = true
        continue
      }
      if token.missing {
        continue
      }
      let recovered = self.recover_history(branch, token, lines)
      let did_recover = !recovered.is_empty()
      work.append(recovered)
      if token.symbol == 0 && branch.extras.is_empty() && branch.insertions < 3 {
        // A damaged nonterminal can still complete an enclosing production.
        // Keep its consumed input as ERROR instead of inventing named syntax.
        for index = branch.entries.length(); index > 0; index = index - 1 {
          let previous = branch.states[index]
          let discarded = []
          for entry in branch.entries[index:] {
            discarded.append(entry.leading)
            discarded.push(entry.node)
          }
          discarded.append(branch.pending)
          if discarded.is_empty() {
            continue
          }
          for (symbol, next) in self.language.states[previous].gotos {
            if symbol == self.language.start_symbol ||
              !self.language.states[next].actions
              .get(0)
              .unwrap_or([])
              .any(a => a is Reduce(_)) {
              continue
            }
            let error = self.error_pending([], discarded, lines, previous)[0]
            work.push({
              ..branch,
              histories: [],
              status: Active,
              states: branch.states[:index + 1].to_owned() + [next],
              entries: branch.entries[:index].to_owned() +
              [{ node: error, leading: [], }],
              pending: [],
              errors: branch.errors + 1,
              insertions: branch.insertions + 1,
            })
          }
        }
      }
      if token.symbol == 0 && branch.extras.is_empty() {
        let discarded = []
        for entry in branch.entries {
          discarded.append(entry.leading)
          discarded.push(entry.node)
        }
        discarded.append(branch.pending)
        if !discarded.is_empty() {
          let root = self.error_pending([], discarded, lines, 0)[0]
          // EOF recovery pushes an empty error at the discontinuity before
          // accepting the enclosing error tree (parser.c: recover_eof).
          let cost = root.data.error_cost + 500
          if best is None || cost < best.unwrap().1 {
            best = Some((root, cost, branch.dynamic))
          }
        }
      }
      if token.end > token.start &&
        !(did_recover &&
        Int32::max(branch.recovery_versions, work.length() + paused.length()) +
        1 >
        6) {
        let skipped = self.node(
          token.symbol,
          token.start,
          token.end,
          lines,
          [],
          state,
          state,
          unexpected?=if token.symbol < 0 {
            Some(token.unexpected.unwrap_or(@lex.decode(source, token.start).0))
          } else {
            None
          },
        )
        let skipped_branch = {
          ..branch,
          recovery_versions: 0,
          status: Recovering,
          offset: token.end,
          lookahead: None,
          pending: self.error_pending(
            branch.pending,
            [skipped],
            lines,
            state,
            repeating=true,
          ),
          errors: branch.errors +
          (if branch.pending.last() is Some(n) && n.is_error() { 0 } else { 1 }),
          scanner_state: token.scanner_state.unwrap_or(branch.scanner_state),
          insertions: 0,
        }
        if preparing {
          // handle_error runs while condensing the previous round. Its first
          // skipped token must not advance the next round's byte frontier.
          work.insert(0, skipped_branch)
        } else {
          advance(skipped_branch)
        }
      }
      continue
    }
    let branch = {
      ..branch,
      pending: branch.pending.map(n => {
        if n.data.error_repeat {
          { data: { ..n.data, error_repeat: false, extra: true, }, }
        } else {
          n
        }
      }),
    }
    for action in actions {
      match action {
        EnterExtra(next) => {
          if branch.extras.length() >= 128 {
            raise ParseLimit("nested extra limit exceeded")
          }
          let frame : ExtraFrame = {
            states: branch.states,
            entries: branch.entries,
            pending: branch.pending,
            start: branch.offset,
          }
          work.push({
            ..branch,
            states: [next],
            entries: [],
            pending: [],
            extras: branch.extras + [frame],
          })
        }
        AcceptExtra =>
          if branch.extras.last() is Some(frame) &&
            self.finish(branch, lines) is Some(node) &&
            node.end_byte() > frame.start {
            work.push({
              ..branch,
              states: frame.states,
              entries: frame.entries,
              pending: frame.pending + [node.as_extra()],
              offset: node.end_byte(),
              lookahead: None,
              extras: branch.extras[:branch.extras.length() - 1].to_owned(),
            })
          }
        Shift(next) => {
          if self.logger is Some(log) {
            log(Parse, "shift state:\{next}")
          }
          let node = self.node(
            token.symbol,
            token.start,
            token.end,
            lines,
            [],
            state,
            next,
            dependency_end=token.dependency_end,
            fragile=actions.length() > 1 ||
              !work.is_empty() ||
              !paused.is_empty(),
            missing=token.missing,
            scan_before=branch.scanner_state,
            scan_after=token.scanner_state.unwrap_or(branch.scanner_state),
          )
          advance({
            ..branch,
            status: Active,
            states: branch.states + [next],
            entries: branch.entries + [{ node, leading: branch.pending, }],
            pending: [],
            offset: token.end,
            scanner_state: token.scanner_state.unwrap_or(branch.scanner_state),
            lookahead: None,
            insertions: if token.missing {
              branch.insertions
            } else {
              0
            },
          })
        }
        Reduce(pid) =>
          if self.reduce(
              branch,
              pid,
              lines,
              fragile=actions.length() > 1 ||
                !work.is_empty() ||
                !paused.is_empty() ||
                branch.status != Active,
            )
            is Some(reduced) {
            if self.logger is Some(log) {
              log(
                Parse,
                "reduce symbol:\{self.language.symbols[self.language.productions[pid].lhs].name} children:\{self.language.productions[pid].steps.length()}",
              )
            }
            work.insert(0, reduced)
          }
        Accept =>
          if branch.extras.is_empty() &&
            self.finish(branch, lines) is Some(root) {
            if self.logger is Some(log) {
              log(Parse, "accept cost:\{branch.cost} dynamic:\{branch.dynamic}")
            }
            let replace = match best {
              None => true
              Some((previous, cost, dynamic)) =>
                branch.cost < cost ||
                (
                  branch.cost == cost &&
                  (
                    branch.dynamic > dynamic ||
                    (
                      branch.dynamic == dynamic &&
                      (
                        branch.cost > 0 ||
                        compare_derivations(
                          self.language,
                          [previous.data.derivation],
                          [root.data.derivation],
                        ) >
                        0
                      )
                    )
                  )
                )
            }
            if replace {
              best = Some((root, branch.cost, branch.dynamic))
            }
          }
      }
    }
  }
  self.projection = None
  match best {
    Some((root, _, _)) =>
      {
        root,
        source,
        language: self.language,
        edited: false,
        edited_length: source.length(),
        reused_subtrees,
        parse_steps: steps,
        source_ranges: [],
        scanner: self.scanner,
      }
    None => raise NoParse(furthest)
  }
}

///|
pub fn Parser::parse_string(
  self : Parser,
  source : String,
) -> Tree raise ParseError {
  self.parse(@utf8.encode(source))
}

///|
fn Parser::error_pending(
  self : Parser,
  pending : Array[Node],
  discarded : Array[Node],
  lines : Array[Int32],
  state : Int32,
  repeating~ : Bool = false,
  preserve_trailing_extras~ : Bool = false,
) -> Array[Node] {
  let result = pending.copy()
  let mut count = discarded.length()
  if preserve_trailing_extras {
    while count > 0 && discarded[count - 1].is_extra() {
      count -= 1
    }
  }
  if count == 0 {
    result.append(discarded)
    return result
  }
  let trailing = discarded[count:].to_owned()
  let discarded = discarded[:count]
  let children : Array[ChildPart] = []
  let mut start = discarded[0].start_byte()
  if result.last() is Some(previous) && previous.data.error_repeat {
    ignore(result.pop())
    start = previous.start_byte()
    children.push(Nested(None, previous.data.children))
  }
  for node in discarded {
    if node.data.error_repeat {
      children.push(Nested(None, node.data.children))
    } else {
      append_visible(children, node, None)
    }
  }
  result.push(
    self.node(
      -1,
      start,
      discarded.last().unwrap().end_byte(),
      lines,
      children,
      state,
      state,
      error_repeat=repeating,
      extra=!repeating,
    ),
  )
  result.append(trailing)
  result
}

///|
fn branch_error_cost(branch : Branch) -> Int32 {
  let mut cost = 0
  for entry in branch.entries {
    cost += entry.node.data.error_cost
    for node in entry.leading {
      cost += node.data.error_cost
    }
  }
  for node in branch.pending {
    cost += node.data.error_cost
  }
  for frame in branch.extras {
    for entry in frame.entries {
      cost += entry.node.data.error_cost
      for node in entry.leading {
        cost += node.data.error_cost
      }
    }
    for node in frame.pending {
      cost += node.data.error_cost
    }
  }
  cost
}

///|
/// Discard a suspended parse before starting unrelated work.
pub fn Parser::reset(self : Parser) -> Unit {
  self.suspended = None
  self.projection = None
}

///|
pub fn Parser::has_pending_parse(self : Parser) -> Bool {
  self.suspended is Some(_)
}

///|
/// Continue the exact input and options saved by a cancelled parse. Calling
/// parse instead starts a new parse. Scanner callbacks must keep their mutable
/// state in the serialized snapshots, just as during ordinary GLR execution.
pub fn Parser::resume_parse(
  self : Parser,
  cancelled~ : () -> Bool = () => false,
) -> Tree raise ParseError {
  guard self.suspended is Some(saved) else { raise NoParse(0) }
  if cancelled() {
    raise Cancelled
  }
  let tree = self.parse_source(
    saved.source,
    projection=saved.projection,
    continuation=Some(saved),
    max_steps=saved.max_steps,
    max_branches=saved.max_branches,
    max_errors=saved.max_errors,
    cancelled~,
  )
  match saved.projection {
    None => tree
    Some(projection) =>
      {
        ..tree,
        root: project_node(
          tree.root,
          projection.starts,
          projection.ends,
          projection.lines,
          encoding=projection.encoding,
        ),
        source: projection.source,
        edited_length: projection.source.length(),
        source_ranges: projection.ranges,
      }
  }
}

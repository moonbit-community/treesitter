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
}

///|
pub fn Parser::new(
  language : @language.Language,
  scanner? : ExternalScanner,
) -> Parser raise @language.LanguageError {
  language.validate()
  { language, next_id: 0, scanner, }
}

///|
priv struct Lexeme {
  symbol : Int32
  start : Int32
  end : Int32
  missing : Bool
  scanner_state : Bytes?
}

///|
priv struct Entry {
  node : Node
  leading : Array[Node]
}

///|
priv struct Branch {
  states : Array[Int32]
  entries : Array[Entry]
  offset : Int32
  pending : Array[Node]
  lookahead : Lexeme?
  cost : Int32
  dynamic : Int32
  insertions : Int32
  scanner_state : Bytes
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
  {
    data: {
      id,
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
      children: child_list(children),
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
  let leading = if count == 0 { [] } else { branch.entries[index].leading }
  for i in 0..<count {
    let entry = branch.entries[index + i]
    if i > 0 {
      for extra in entry.leading {
        append_visible(children, extra, None)
      }
    }
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
    dynamic_score=score,
    scan_before=if count == 0 {
      branch.scanner_state
    } else {
      branch.entries[index].node.data.scan_before
    },
    scan_after=branch.scanner_state,
  )
  let entries = branch.entries[:index].to_owned()
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
    return Some({ data: { ..root.data, scan_after: branch.scanner_state, }, })
  }
  let children : Array[ChildPart] = []
  for extra in entry.leading {
    append_visible(children, extra, None)
  }
  children.push(Nested(None, root.data.children))
  for extra in branch.pending {
    append_visible(children, extra, None)
  }
  let start = if entry.leading.is_empty() {
    root.start_byte()
  } else {
    entry.leading[0].start_byte()
  }
  let end = if branch.pending.is_empty() {
    root.end_byte()
  } else {
    branch.pending.last().unwrap().end_byte()
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
      scan_before=root.data.scan_before,
      scan_after=branch.scanner_state,
    ),
  )
}

///|
/// Parse UTF-8 using generated tables. Declared conflicts explore separate
/// stacks; error recovery explores missing tokens and skipped input with costs.
/// Exhausted limits and cancellation are errors, never truncated success trees.
pub fn Parser::parse(
  self : Parser,
  source : Bytes,
  old_tree? : Tree,
  included_ranges~ : Array[Range] = [],
  max_steps~ : Int32 = 100000,
  max_branches~ : Int32 = 10000,
  max_errors~ : Int32 = 20,
  cancelled~ : () -> Bool = () => false,
) -> Tree raise ParseError {
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
  max_steps~ : Int32 = 100000,
  max_branches~ : Int32 = 10000,
  max_errors~ : Int32 = 20,
  cancelled~ : () -> Bool = () => false,
) -> Tree raise ParseError {
  if cancelled() {
    raise Cancelled
  }
  if !self.language.externals.is_empty() && self.scanner is None {
    raise ScannerError("language requires an external scanner")
  }
  let mut reused_subtrees = 0
  let reusable = match old_tree {
    Some(tree) if physical_equal(tree.language, self.language) &&
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
  let lines = line_starts(source)
  let work : Array[Branch] = [
    {
      states: [0],
      entries: [],
      offset: 0,
      pending: [],
      lookahead: None,
      cost: 0,
      dynamic: 0,
      insertions: 0,
      scanner_state: b"",
    },
  ]
  let visited : Map[
    (Array[Int32], Int32, Int32, Bool, Int32, Bytes, Bytes?),
    (Int32, Int32),
  ] = Map([])
  let mut best : (Node, Int32, Int32)? = None
  let mut steps = 0
  let mut furthest = 0
  while work.pop() is Some(initial) {
    steps += 1
    if cancelled() {
      raise Cancelled
    }
    if steps > max_steps {
      raise ParseLimit("parser step limit exceeded")
    }
    if work.length() > max_branches {
      raise ParseLimit("GLR branch limit exceeded")
    }
    if initial.cost > max_errors {
      continue
    }
    if best is Some((_, cost, _)) && initial.cost > cost {
      continue
    }
    let branch = if initial.lookahead is None {
      self.lex(source, initial, lines, projection, cancelled)
    } else {
      initial
    }
    let token = branch.lookahead.unwrap()
    furthest = Int32::max(furthest, branch.offset)
    let key = (
      branch.states,
      branch.offset,
      token.symbol,
      token.missing,
      branch.insertions,
      branch.scanner_state,
      token.scanner_state,
    )
    if visited.get(key) is Some((cost, dynamic)) &&
      (cost < branch.cost || (cost == branch.cost && dynamic >= branch.dynamic)) {
      continue
    }
    visited[key] = (branch.cost, branch.dynamic)
    let state = branch.states.last().unwrap()
    if !token.missing && reusable.get((branch.offset, state)) is Some(candidate) {
      let node = reset_origin(candidate)
      reused_subtrees += 1
      work.push({
        ..branch,
        states: branch.states + [node.next_parse_state()],
        entries: branch.entries + [{ node, leading: branch.pending, }],
        pending: [],
        offset: node.end_byte(),
        lookahead: None,
        dynamic: branch.dynamic + node.data.dynamic_score,
      })
      continue
    }
    let actions = self.language.states[state].actions
      .get(token.symbol)
      .unwrap_or([])
    if actions.is_empty() {
      // Recovery is bounded and never inserts EOF. Try insertion at this
      // position and deletion independently, preserving visible ERROR nodes.
      if !token.missing && branch.insertions < 3 {
        for expected in self.language.lookahead(state) {
          if expected != 0 {
            work.push({
              ..branch,
              lookahead: Some({
                symbol: expected,
                start: token.start,
                end: token.start,
                missing: true,
                scanner_state: None,
              }),
              cost: branch.cost + 1,
              insertions: branch.insertions + 1,
            })
          }
        }
      }
      if !token.missing && token.end > token.start {
        let error = self.node(
          -1,
          token.start,
          token.end,
          lines,
          [],
          state,
          state,
        )
        work.push({
          ..branch,
          offset: token.end,
          lookahead: None,
          pending: branch.pending + [error],
          cost: branch.cost + 1,
          scanner_state: token.scanner_state.unwrap_or(branch.scanner_state),
          insertions: 0,
        })
      }
      continue
    }
    for action in actions {
      match action {
        Shift(next) => {
          let node = self.node(
            token.symbol,
            token.start,
            token.end,
            lines,
            [],
            state,
            next,
            missing=token.missing,
            scan_before=branch.scanner_state,
            scan_after=token.scanner_state.unwrap_or(branch.scanner_state),
          )
          work.push({
            ..branch,
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
          if self.reduce(branch, pid, lines) is Some(reduced) {
            work.push(reduced)
          }
        Accept =>
          if self.finish(branch, lines) is Some(root) {
            let replace = match best {
              None => true
              Some((_, cost, dynamic)) =>
                branch.cost < cost ||
                (branch.cost == cost && branch.dynamic > dynamic)
            }
            if replace {
              best = Some((root, branch.cost, branch.dynamic))
            }
          }
      }
    }
  }
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

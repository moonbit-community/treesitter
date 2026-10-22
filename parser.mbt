///|
pub suberror ParseError {
  Cancelled
  ParseLimit(String)
  NoParse(Int32)
} derive(Debug)

///|
pub extend ParseError with @debug.Debug::{to_repr}

///|
pub struct Parser {
  language : @language.Language
  priv mut next_id : Int32
}

///|
pub fn Parser::new(
  language : @language.Language,
) -> Parser raise @language.LanguageError {
  language.validate()
  { language, next_id: 0, }
}

///|
priv struct Lexeme {
  symbol : Int32
  start : Int32
  end : Int32
  missing : Bool
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
}

///|
fn Parser::node(
  self : Parser,
  symbol : Int32,
  start : Int32,
  end : Int32,
  lines : Array[Int32],
  children : Array[(String?, Node)],
  parse_state : Int32,
  next_state : Int32,
  extra~ : Bool = false,
  missing~ : Bool = false,
  dynamic_score~ : Int32 = 0,
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
fn better_token(
  candidate : @language.Token,
  end : Int32,
  previous : @language.Token,
  previous_end : Int32,
) -> Bool {
  if candidate.precedence != previous.precedence {
    candidate.precedence > previous.precedence
  } else if end != previous_end {
    end > previous_end
  } else if candidate.immediate != previous.immediate {
    candidate.immediate
  } else if candidate.literal != previous.literal {
    candidate.literal
  } else {
    candidate.symbol < previous.symbol
  }
}

///|
fn Parser::lex(
  self : Parser,
  input : Bytes,
  branch : Branch,
  lines : Array[Int32],
) -> Branch {
  let state = branch.states.last().unwrap()
  let valid = self.language.states[state].actions
  let mut offset = branch.offset
  let pending = branch.pending.copy()
  let mut skipped = false
  for ;; {
    let mut best : (@language.Token, Int32)? = None
    for token in self.language.tokens {
      let extra = self.language.extras.contains(token.symbol)
      if (!valid.contains(token.symbol) && !extra) ||
        (skipped && token.immediate) {
        continue
      }
      if token.lexer.match_prefix(input, start=offset) is Some(end) &&
        end > offset {
        let replace = match best {
          None => true
          Some((previous, previous_end)) =>
            better_token(token, end, previous, previous_end)
        }
        if replace {
          best = Some((token, end))
        }
      }
    }
    match best {
      Some((token, end)) =>
        if self.language.extras.contains(token.symbol) &&
          !valid.contains(token.symbol) {
          if self.language.symbols[token.symbol].named {
            pending.push(
              self.node(
                token.symbol,
                offset,
                end,
                lines,
                [],
                state,
                state,
                extra=true,
              ),
            )
          }
          skipped = true
          offset = end
        } else {
          return {
            ..branch,
            offset,
            pending,
            lookahead: Some({
              symbol: token.symbol,
              start: offset,
              end,
              missing: false,
            }),
          }
        }
      None => {
        let end = if offset == input.length() {
          offset
        } else {
          offset + @lex.decode(input, offset).1
        }
        return {
          ..branch,
          offset,
          pending,
          lookahead: Some({
            symbol: if offset == input.length() {
              0
            } else {
              -1
            },
            start: offset,
            end,
            missing: false,
          }),
        }
      }
    }
  }
}

///|
fn append_visible(
  output : Array[(String?, Node)],
  node : Node,
  field : String?,
) -> Unit {
  if node.data.visible || node.is_error() || node.is_missing() {
    output.push((field, node))
  } else {
    for (inner_field, child) in node.data.children {
      output.push(
        (
          match inner_field {
            Some(_) => inner_field
            None => if child.is_extra() { None } else { field }
          },
          child,
        ),
      )
    }
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
  let children : Array[(String?, Node)] = []
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
    return Some(root)
  }
  let children : Array[(String?, Node)] = []
  for extra in entry.leading {
    append_visible(children, extra, None)
  }
  children.append(root.data.children)
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
  max_steps~ : Int32 = 100000,
  max_branches~ : Int32 = 10000,
  max_errors~ : Int32 = 20,
  cancelled~ : () -> Bool = () => false,
) -> Tree raise ParseError {
  if cancelled() {
    raise Cancelled
  }
  let mut reused_subtrees = 0
  let reusable = match old_tree {
    Some(tree) if physical_equal(tree.language, self.language) => {
      if !tree.edited && tree.source == source {
        return {
          root: tree.root,
          source,
          language: self.language,
          edited: false,
          edited_length: source.length(),
          reused_subtrees: 1,
          parse_steps: 0,
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
    },
  ]
  let visited : Map[(Array[Int32], Int32, Int32, Bool, Int32), (Int32, Int32)] = Map([],
  )
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
      self.lex(source, initial, lines)
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
          )
          work.push({
            ..branch,
            states: branch.states + [next],
            entries: branch.entries + [{ node, leading: branch.pending, }],
            pending: [],
            offset: token.end,
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

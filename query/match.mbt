///|
priv struct Budget {
  mut steps : Int32
  limit : Int32
  cancelled : () -> Bool
}

///|
fn Budget::tick(self : Budget) -> Unit raise QueryError {
  self.steps += 1
  if (self.cancelled)() {
    raise Cancelled
  }
  if self.steps > self.limit {
    raise MatchLimit
  }
}

///|
fn match_pattern(
  pattern : Pattern,
  node : @ts.Node,
  budget : Budget,
) -> Array[Array[Capture]] raise QueryError {
  budget.tick()
  match pattern {
    Capture(inner, name) =>
      match_pattern(inner, node, budget).map(captures => {
        captures + [{ name, node, }]
      })
    Either(alternatives) => {
      let result = []
      for alternative in alternatives {
        result.append(match_pattern(alternative, node, budget))
      }
      result
    }
    Group(children, trailing) =>
      match_children(children, trailing, node, 0, 0, [], budget).map(m => m.0)
    Node(p) => {
      if p.supertype is Some(name) && !node.supertypes().contains(name) {
        return []
      }
      if p.kind is Some(kind) && kind != node.kind() {
        return []
      }
      if p.named is Some(named) && named != node.is_named() {
        return []
      }
      if p.missing && !node.is_missing() {
        return []
      }
      if p.absent_fields.any(f => node.child_by_field_name(f) is Some(_)) {
        return []
      }
      match_children(p.children, p.trailing_anchor, node, 0, 0, [], budget).map(m => {
          m.0
        },
      )
    }
  }
}

///|
fn match_at(
  pattern : Pattern,
  parent : @ts.Node,
  index : Int32,
  budget : Budget,
) -> Array[(Array[Capture], Int32)] raise QueryError {
  match pattern {
    Group(children, trailing) => {
      let children = children.copy()
      if !children.is_empty() {
        children[0] = { ..children[0], anchor: true, }
      }
      match_children(children, trailing, parent, 0, index, [], budget)
    }
    Either(items) => {
      let results = []
      for item in items {
        results.append(match_at(item, parent, index, budget))
      }
      results
    }
    Capture(inner, name) =>
      match_at(inner, parent, index, budget).map(m => {
        (m.0 + [{ name, node: parent.child(index).unwrap(), }], m.1)
      })
    _ =>
      match_pattern(pattern, parent.child(index).unwrap(), budget).map(c => {
        (c, index + 1)
      })
  }
}

///|
fn match_children(
  children : Array[Child],
  trailing_anchor : Bool,
  parent : @ts.Node,
  pi : Int32,
  from : Int32,
  captures : Array[Capture],
  budget : Budget,
) -> Array[(Array[Capture], Int32)] raise QueryError {
  budget.tick()
  if pi == children.length() {
    if trailing_anchor {
      for i in from..<parent.child_count() {
        if parent.child(i).unwrap().is_named() {
          return []
        }
      }
    }
    return [(captures, from)]
  }
  let spec = children[pi]
  let result = []
  for i in from..<parent.child_count() {
    let node = parent.child(i).unwrap()
    let matches = if spec.field is None ||
      spec.field == parent.field_name_for_child(i) {
      match_at(spec.pattern, parent, i, budget)
    } else {
      []
    }
    for (matched, after) in matches {
      if spec.max == Some(1) {
        result.append(
          match_children(
            children,
            trailing_anchor,
            parent,
            pi + 1,
            after,
            captures + matched,
            budget,
          ),
        )
      } else {
        let runs = [(after, 1, captures + matched)]
        let stops = []
        while runs.pop() is Some((next, count, accumulated)) {
          budget.tick()
          stops.push((next, count, accumulated))
          for j in next..<parent.child_count() {
            let sibling = parent.child(j).unwrap()
            if spec.field is None ||
              spec.field == parent.field_name_for_child(j) {
              let found = match_at(spec.pattern, parent, j, budget)
              for (additional, after) in found {
                if after > next {
                  runs.push((after, count + 1, accumulated + additional))
                }
              }
              if !found.is_empty() || sibling.is_named() {
                break
              }
            } else if sibling.is_named() {
              break
            }
          }
        }
        stops.sort_by((a, b) => b.1.compare(a.1))
        for (next, _, accumulated) in stops {
          let found = match_children(
            children,
            trailing_anchor,
            parent,
            pi + 1,
            next,
            accumulated,
            budget,
          )
          if !found.is_empty() {
            result.append(found)
            break
          }
        }
      }
    }
    if !result.is_empty() && spec.max is None {
      return result
    }
    if spec.anchor && node.is_named() {
      break
    }
  }
  if result.is_empty() && spec.min == 0 {
    match_children(
      children,
      trailing_anchor,
      parent,
      pi + 1,
      from,
      captures,
      budget,
    )
  } else {
    result
  }
}

///|
fn values(
  arg : Argument,
  captures : Array[Capture],
  source : Bytes,
) -> Array[String] {
  match arg {
    Text(s) => [s]
    Capture(name) =>
      captures.filter(c => c.name == name).map(c => c.node.text(source))
  }
}

///|
fn regex_matches(
  predicate : Predicate,
  text : String,
  budget : Budget,
) -> Bool raise QueryError {
  let result = predicate.regex
    .unwrap()
    .find(@utf8.encode(text), max_steps=budget.limit, tick=() => {
      budget.steps += 1
      budget.steps <= budget.limit && !(budget.cancelled)()
    }) catch {
      _ => if (budget.cancelled)() { raise Cancelled } else { raise MatchLimit }
    }
  result is Some(_)
}

///|
fn predicates_match(
  predicates : Array[Predicate],
  captures : Array[Capture],
  source : Bytes,
  budget : Budget,
  property : (String, String?, @ts.Node?) -> Bool,
  custom : ((String, Array[Argument], Array[Capture], Bytes) -> Bool)?,
) -> Bool raise QueryError {
  for predicate in predicates {
    budget.tick()
    if predicate.name is ("#set!" | "#strip!" | "#select-adjacent!") {
      continue
    }
    if predicate.name is ("#is?" | "#is-not?") {
      let texts = predicate.args.filter_map(a => {
        match a {
          Text(s) => Some(s)
          _ => None
        }
      })
      let names = predicate.args.filter_map(a => {
        match a {
          Capture(s) => Some(s)
          _ => None
        }
      })
      let targets = if names.is_empty() {
        if captures.is_empty() {
          [None]
        } else {
          captures.map(c => Some(c.node))
        }
      } else {
        captures.filter(c => c.name == names[0]).map(c => Some(c.node))
      }
      if !targets.all(node => {
          property(texts[0], texts.get(1), node) == (predicate.name == "#is?")
        }) {
        return false
      }
      continue
    }
    if !(predicate.name
      is ("#eq?"
      | "#not-eq?"
      | "#any-eq?"
      | "#any-not-eq?"
      | "#match?"
      | "#not-match?"
      | "#any-match?"
      | "#any-not-match?"
      | "#any-of?"
      | "#not-any-of?")) {
      guard custom is Some(callback) else {
        raise InvalidQuery(0, "no evaluator for predicate '\{predicate.name}'")
      }
      if !callback(predicate.name, predicate.args, captures, source) {
        return false
      }
      continue
    }
    let left = values(predicate.args[0], captures, source)
    if left.is_empty() {
      return false
    }
    let negative = predicate.name.contains("not-")
    let any = predicate.name.has_prefix("#any-") && predicate.name != "#any-of?"
    let results : Array[Bool] = []
    if predicate.regex is Some(_) {
      for text in left {
        results.push(regex_matches(predicate, text, budget) != negative)
      }
    } else if predicate.name is ("#any-of?" | "#not-any-of?") {
      let options = []
      for i in 1..<predicate.args.length() {
        options.append(values(predicate.args[i], captures, source))
      }
      for text in left {
        results.push(options.contains(text) != negative)
      }
    } else {
      let right = values(predicate.args[1], captures, source)
      if right.is_empty() {
        return false
      }
      if predicate.args[1] is Capture(_) {
        if left.length() != right.length() {
          return false
        }
        for i in 0..<left.length() {
          results.push((left[i] == right[i]) != negative)
        }
      } else {
        for text in left {
          results.push((text == right[0]) != negative)
        }
      }
    }
    if !(if any { results.any(x => x) } else { results.all(x => x) }) {
      return false
    }
  }
  true
}

///|
pub fn Query::matches(
  self : Query,
  root : @ts.Node,
  source : Bytes,
  start_byte~ : Int32 = 0,
  end_byte~ : Int32 = 2147483647,
  max_steps~ : Int32 = 100000,
  max_matches~ : Int32 = 10000,
  cancelled~ : () -> Bool = () => false,
  property~ : (String, String?, @ts.Node?) -> Bool = (_, _, _) => false,
  predicate? : (String, Array[Argument], Array[Capture], Bytes) -> Bool,
) -> Array[Match] raise QueryError {
  let cursor = self.cursor(
    root,
    source,
    start_byte~,
    end_byte~,
    max_steps~,
    max_matches~,
    cancelled~,
    property~,
    predicate?,
  )
  let result = []
  while cursor.next_match() is Some(matched) {
    result.push(matched)
  }
  result
}

///|
pub fn Query::captures(
  self : Query,
  root : @ts.Node,
  source : Bytes,
) -> Array[Capture] raise QueryError {
  let captures : Array[(Int32, Capture)] = []
  for matched in self.matches(root, source) {
    for capture in matched.captures {
      captures.push((matched.pattern_index, capture))
    }
  }
  captures.sort_by((a, b) => {
    let start = a.1.node.start_byte().compare(b.1.node.start_byte())
    if start != 0 {
      start
    } else {
      let end = b.1.node.end_byte().compare(a.1.node.end_byte())
      if end != 0 {
        end
      } else {
        a.0.compare(b.0)
      }
    }
  })
  captures.map(c => c.1)
}

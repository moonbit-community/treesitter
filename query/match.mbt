///|
// A structural match records the traversal event that completes its final step.
// Captures may include earlier ancestors, so capture positions alone cannot
// determine when the match becomes observable to the cursor.
priv struct Completion {
  captures : Array[Capture]
  finish : @ts.Node
  delayed : Bool
}

///|
fn Completion::at(node : @ts.Node) -> Completion {
  { captures: [], finish: node, delayed: false, }
}

///|
fn Completion::then(self : Completion, next : Completion) -> Completion {
  { ..next, captures: self.captures + next.captures, }
}

///|
priv struct Budget {
  mut steps : Int32
  limit : Int32
  cancelled : () -> Bool
  containing_byte_range : (Int32, Int32)?
  containing_point_range : (@ts.Point, @ts.Point)?
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
fn Budget::contains(self : Budget, node : @ts.Node) -> Bool {
  if self.containing_byte_range is Some((start, end)) &&
    (node.start_byte() < start || node.end_byte() > end) {
    return false
  }
  if self.containing_point_range is Some((start, end)) &&
    (node.start_position() < start || node.end_position() > end) {
    return false
  }
  true
}

///|
// Completions of the same rooted pattern retain only maximal capture lists.
// Different uncaptured choices may complete at different siblings but must not
// produce duplicate matches, or an empty subset of an already captured match.
fn maximal_captures(
  candidates : Array[Completion],
  budget : Budget,
) -> Array[Completion] raise QueryError {
  let unique = []
  let seen : Map[String, Unit] = Map([])
  for candidate in candidates {
    budget.tick()
    let key = candidate.captures
      .map(c => "\{c.name.length()}:\{c.name}:\{c.node.id()};")
      .join("")
    if !seen.contains(key) {
      seen[key] = ()
      unique.push(candidate)
    }
  }
  let largest = unique.fold(init=0, (n, c) => Int32::max(n, c.captures.length()))
  let result = []
  for candidate in unique {
    if candidate.captures.length() == largest {
      result.push(candidate)
      continue
    }
    let mut contained = false
    for other in unique {
      if other.captures.length() > candidate.captures.length() {
        budget.tick()
        if captures_contain(other.captures, candidate.captures) {
          contained = true
          break
        }
      }
    }
    if !contained {
      result.push(candidate)
    }
  }
  result
}

///|
fn match_pattern(
  pattern : Pattern,
  node : @ts.Node,
  budget : Budget,
) -> Array[Completion] raise QueryError {
  budget.tick()
  match pattern {
    Capture(inner, name) =>
      match_pattern(inner, node, budget).map(completed => {
        let captures = completed.captures.copy()
        let index = captures
          .search_by(c => c.node.id() != node.id())
          .unwrap_or(captures.length())
        captures.insert(index, { name, node, })
        { ..completed, captures, }
      })
    Either(alternatives) => {
      let result = []
      for alternative in alternatives {
        result.append(match_pattern(alternative, node, budget))
      }
      result
    }
    Group(children, trailing) =>
      match_children(
        children,
        trailing,
        node,
        0,
        0,
        Completion::at(node),
        budget,
      ).map(m => m.0)
    Node(p) => {
      if !budget.contains(node) {
        return []
      }
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
      let matches = match_children(
        p.children,
        p.trailing_anchor,
        node,
        0,
        0,
        Completion::at(node),
        budget,
      )
      matches.sort_by_key(m => m.1)
      maximal_captures(matches.map(m => m.0), budget)
    }
  }
}

///|
fn match_at(
  pattern : Pattern,
  parent : @ts.Node,
  index : Int32,
  budget : Budget,
) -> Array[(Completion, Int32)] raise QueryError {
  match pattern {
    Group(children, trailing) => {
      let children = children.copy()
      if !children.is_empty() {
        children[0] = { ..children[0], anchor: true, }
      }
      match_children(
        children,
        trailing,
        parent,
        0,
        index,
        Completion::at(parent),
        budget,
        strict_start=true,
      )
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
        let node = parent.child(index).unwrap()
        let captures = m.0.captures.copy()
        let position = captures
          .search_by(c => c.node.id() != node.id())
          .unwrap_or(captures.length())
        captures.insert(position, { name, node, })
        ({ ..m.0, captures, }, m.1)
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
  completed : Completion,
  budget : Budget,
  strict_start~ : Bool = false,
) -> Array[(Completion, Int32)] raise QueryError {
  budget.tick()
  if pi == children.length() {
    if trailing_anchor {
      for i in from..<parent.child_count() {
        if parent.child(i).unwrap().is_named() {
          return []
        }
      }
    }
    return [(completed, from)]
  }
  let spec = children[pi]
  let result = []
  let mut skip_until = from
  for i in from..<parent.child_count() {
    if strict_start && i != from {
      break
    }
    if i < skip_until {
      continue
    }
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
            completed.then(matched),
            budget,
          ),
        )
      } else {
        let runs = [(after, 1, completed.then(matched))]
        let stops = []
        while runs.pop() is Some((next, count, accumulated)) {
          budget.tick()
          stops.push((next, count, accumulated))
          if next < parent.child_count() {
            if spec.field is None ||
              spec.field == parent.field_name_for_child(next) {
              // Repetition requires the next concrete sibling. An anchor can
              // skip anonymous nodes, but a quantifier's loop-back cannot.
              let found = match_at(spec.pattern, parent, next, budget)
              for (additional, after) in found {
                if after > next {
                  runs.push((after, count + 1, accumulated.then(additional)))
                }
              }
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
            {
              ..accumulated,
              finish: parent.child(next - 1).unwrap(),
              delayed: true,
            },
            budget,
          )
          if !found.is_empty() {
            result.append(found)
            skip_until = Int32::max(skip_until, next)
            break
          }
        }
      }
    }
    if spec.anchor && node.is_named() {
      break
    }
  }
  if spec.min == 0 {
    let children = children.copy()
    if pi + 1 < children.length() {
      children[pi + 1] = { ..children[pi + 1], anchor: spec.anchor, }
    }
    let skipped = match_children(
      children,
      trailing_anchor,
      parent,
      pi + 1,
      from,
      completed,
      budget,
      strict_start~,
    )
    if result.is_empty() {
      return skipped
    }
    // An optional prefix can be absent before one sibling and present before
    // another. Keep both matches, while preferring the populated alternative
    // when it contains all the captures of an otherwise identical match.
    for candidate in skipped {
      if !result.any(existing => {
          candidate.0.captures.all(capture => {
            existing.0.captures.any(other => {
              other.name == capture.name && other.node.id() == capture.node.id()
            })
          })
        }) {
        result.push(candidate)
      }
    }
    result.sort_by_key(item => item.1)
  }
  result
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
    if !results.is_empty() &&
      !(if any { results.any(x => x) } else { results.all(x => x) }) {
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
  containing_byte_range? : (Int32, Int32),
  containing_point_range? : (@ts.Point, @ts.Point),
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
    containing_byte_range?,
    containing_point_range?,
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

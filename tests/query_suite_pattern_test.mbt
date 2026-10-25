// Port of the random pattern model in tree-sitter
// crates/cli/src/tests/helpers/query_helpers.rs (`Pattern`, `Match`), used
// by `test_query_random`.

///|
priv struct Pattern {
  kind : String?
  named : Bool
  mut field : String?
  capture : String?
  children : Array[Pattern]
}

///|
priv struct Match {
  captures : Array[(String, @treesitter.Node)]
  mut last_node : @treesitter.Node?
} derive(Eq)

///|
impl Show for Match with fn output(self, logger) {
  logger.write_string("Match { captures: [")
  for i, c in self.captures {
    if i > 0 {
      logger.write_string(", ")
    }
    logger.write_string("(\{c.0}, \{c.1})")
  }
  logger.write_string("], last_node: ")
  match self.last_node {
    Some(node) => logger.write_string("Some(\{node})")
    None => logger.write_string("None")
  }
  logger.write_string(" }")
}

///|
let capture_names_for_patterns : Array[String] = [
  "one", "two", "three", "four", "five", "six", "seven", "eight",
]

///|
fn Pattern::random_pattern_in_tree(
  tree : @treesitter.Tree,
  rng : @cli_test.StdRng,
) -> (Pattern, (@treesitter.Point, @treesitter.Point)) {
  let cursor = tree.walk()

  // Descend to the node at a random byte offset and depth.
  let mut max_depth = 0
  let byte_offset = rng.random_range_usize(0, cursor.node().end_byte())
  while cursor.goto_first_child_for_byte(byte_offset) is Some(_) {
    max_depth += 1
  }
  let depth = rng.random_range_inclusive_i32(0, max_depth)
  for _ in 0..<depth {
    ignore(cursor.goto_parent())
  }

  // Build a pattern that matches that node.
  // Sometimes include subsequent siblings of the node.
  let pattern_start = cursor.node().start_position()
  let roots = [Pattern::random_pattern_for_node(cursor, rng)]
  while roots.length() < 5 && cursor.goto_next_sibling() {
    if rng.random_bool(0.2) {
      roots.push(Pattern::random_pattern_for_node(cursor, rng))
    }
  }
  let pattern_end = cursor.node().end_position()
  let mut pattern : Pattern = {
    kind: None,
    named: true,
    field: None,
    capture: None,
    children: roots,
  }
  if pattern.children.length() == 1 ||
    // In a parenthesized list of sibling patterns, the first
    // sibling can't be an anonymous `_` wildcard.
    (pattern.children[0].kind == Some("_") && !pattern.children[0].named) {
    pattern = pattern.children.unsafe_pop()
  } else {
    // In a parenthesized list of sibling patterns, the first
    // sibling can't have a field name.
    pattern.children[0].field = None
  }
  (pattern, (pattern_start, pattern_end))
}

///|
fn Pattern::random_pattern_for_node(
  cursor : @treesitter.TreeCursor,
  rng : @cli_test.StdRng,
) -> Pattern {
  let node = cursor.node()

  // Sometimes specify the node's type, sometimes use a wildcard.
  let (kind, named) = if rng.random_bool(0.9) {
    (Some(node.kind()), node.is_named())
  } else {
    (Some("_"), node.is_named() && rng.random_bool(0.8))
  }

  // Sometimes specify the node's field.
  let field = if rng.random_bool(0.75) { cursor.field_name() } else { None }

  // Sometimes capture the node.
  let capture = if rng.random_bool(0.7) {
    Some(
      capture_names_for_patterns[rng.random_range_usize(
        0,
        capture_names_for_patterns.length(),
      )],
    )
  } else {
    None
  }

  // Walk the children and include child patterns for some of them.
  let children = []
  if named && cursor.goto_first_child() {
    let max_children = rng.random_range_usize(0, 4)
    while cursor.goto_next_sibling() {
      if rng.random_bool(0.6) {
        let child_ast = Pattern::random_pattern_for_node(cursor, rng)
        children.push(child_ast)
        if children.length() >= max_children {
          break
        }
      }
    }
    ignore(cursor.goto_parent())
  }
  { kind, named, field, capture, children, }
}

///|
fn Pattern::write_to_string(
  self : Pattern,
  string : StringBuilder,
  indent : Int32,
) -> Unit {
  if self.field is Some(field) {
    string.write_string("\{field}: ")
  }
  if self.named {
    string.write_char('(')
    let mut has_contents = if self.kind is Some(kind) {
      string.write_string(kind)
      true
    } else {
      false
    }
    for child in self.children {
      let indent = indent + 2
      if has_contents {
        string.write_char('\n')
        string.write_string(" ".repeat(indent))
      }
      child.write_to_string(string, indent)
      has_contents = true
    }
    string.write_char(')')
  } else if self.kind == Some("_") {
    string.write_char('_')
  } else {
    string.write_string(
      "\"\{self.kind.unwrap().replace_all(old="\"", new="\\\"")}\"",
    )
  }
  if self.capture is Some(capture) {
    string.write_string(" @\{capture}")
  }
}

///|
impl Show for Pattern with fn output(self, logger) {
  let result = StringBuilder()
  self.write_to_string(result, 0)
  logger.write_string(result.to_string())
}

///|
fn Pattern::matches_in_tree(self : Pattern, tree : @treesitter.Tree) -> Array[Match] {
  let matches = []

  // Compute the matches naively: walk the tree and
  // retry the entire pattern for each node.
  let cursor = tree.walk()
  let mut ascending = false
  for ;; {
    if ascending {
      if cursor.goto_next_sibling() {
        ascending = false
      } else if !cursor.goto_parent() {
        break
      }
    } else {
      let matches_here = self.match_node(cursor)
      matches.append(matches_here)
      if !cursor.goto_first_child() {
        ascending = true
      }
    }
  }

  // Upstream uses `sort_unstable`; a stable sort is one of its valid
  // outcomes (matches that compare equal keep their discovery order).
  stable_sort_by(matches, Match::cmp)
  for m in matches {
    m.last_node = None
  }
  dedup_matches(matches)
}

///|
fn Pattern::match_node(
  self : Pattern,
  cursor : @treesitter.TreeCursor,
) -> Array[Match] {
  let node = cursor.node()

  // If a kind is specified, check that it matches the node.
  if self.kind is Some(kind) {
    if kind == "_" {
      if self.named && !node.is_named() {
        return []
      }
    } else if kind != node.kind() || self.named != node.is_named() {
      return []
    }
  }

  // If a field is specified, check that it matches the node.
  if self.field is Some(field) && cursor.field_name() != Some(field) {
    return []
  }

  // Create a match for the current node.
  let mat : Match = {
    captures: match self.capture {
      Some(name) => [(name, node)]
      None => []
    },
    last_node: Some(node),
  }

  // If there are no child patterns to match, then return this single match.
  if self.children.is_empty() {
    return [mat]
  }

  // Find every matching combination of child patterns and child nodes.
  let finished_matches : Array[Match] = []
  if cursor.goto_first_child() {
    let match_states = [(0, mat)]
    for ;; {
      let new_match_states = []
      for state in match_states {
        let (pattern_index, mat) = state
        let child_pattern = self.children[pattern_index]
        let child_matches = child_pattern.match_node(cursor)
        for child_match in child_matches {
          let combined_match = mat.clone()
          combined_match.last_node = child_match.last_node
          combined_match.captures.append(child_match.captures)
          if pattern_index + 1 < self.children.length() {
            new_match_states.push((pattern_index + 1, combined_match))
          } else {
            let mut existing = false
            for existing_match in finished_matches {
              if existing_match.captures == combined_match.captures {
                if child_pattern.capture is Some(_) {
                  existing_match.last_node = combined_match.last_node
                }
                existing = true
              }
            }
            if !existing {
              finished_matches.push(combined_match)
            }
          }
        }
      }
      match_states.append(new_match_states)
      if !cursor.goto_next_sibling() {
        break
      }
    }
    ignore(cursor.goto_parent())
  }
  finished_matches
}

///|
fn Match::clone(self : Match) -> Match {
  { captures: self.captures.copy(), last_node: self.last_node, }
}

///|
/// Tree-sitter returns matches in the order that they terminate
/// during a depth-first walk of the tree. If multiple matches
/// terminate on the same node, those matches are produced in the
/// order that their captures were discovered.
fn Match::cmp(self : Match, other : Match) -> Int32 {
  if self.last_node is Some(last_node_a) && other.last_node is Some(last_node_b) {
    let cmp = compare_depth_first(last_node_a, last_node_b)
    if cmp != 0 {
      return cmp
    }
  }
  let n = if self.captures.length() < other.captures.length() {
    self.captures.length()
  } else {
    other.captures.length()
  }
  for i in 0..<n {
    let cmp = compare_depth_first(self.captures[i].1, other.captures[i].1)
    if cmp != 0 {
      return cmp
    }
  }
  self.captures.length().compare(other.captures.length())
}

///|
fn compare_depth_first(a : @treesitter.Node, b : @treesitter.Node) -> Int32 {
  let (a_start, a_end) = a.byte_range()
  let (b_start, b_end) = b.byte_range()
  let c = a_start.compare(b_start)
  if c != 0 {
    c
  } else {
    b_end.compare(a_end)
  }
}

///|
/// A stable merge sort by `cmp` (Rust's `sort_by`).
fn[T] stable_sort_by(array : Array[T], cmp : (T, T) -> Int32) -> Unit {
  let n = array.length()
  if n < 2 {
    return
  }
  let mut src = array.copy()
  let mut dst = array.copy()
  let mut width = 1
  while width < n {
    let mut lo = 0
    while lo < n {
      let mid = if lo + width < n { lo + width } else { n }
      let hi = if lo + 2 * width < n { lo + 2 * width } else { n }
      let mut i = lo
      let mut j = mid
      for k in lo..<hi {
        if i < mid && (j >= hi || cmp(src[i], src[j]) <= 0) {
          dst[k] = src[i]
          i += 1
        } else {
          dst[k] = src[j]
          j += 1
        }
      }
      lo = hi
    }
    let t = src
    src = dst
    dst = t
    width *= 2
  }
  for k in 0..<n {
    array[k] = src[k]
  }
}

///|
/// `Vec::dedup` for matches.
fn dedup_matches(matches : Array[Match]) -> Array[Match] {
  let result : Array[Match] = []
  for m in matches {
    if result.last() is Some(last) && last == m {
      continue
    }
    result.push(m)
  }
  result
}

///|
fn format_matches(matches : Array[Match]) -> String {
  matches.map(m => Show::to_string(m)).join("\n")
}

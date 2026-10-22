///|
fn fuzz_points(source : Bytes) -> Array[@ts.Point] {
  let points : Array[@ts.Point] = [{ row: 0, column: 0, }]
  let mut row = 0
  let mut column = 0
  for byte in source {
    if byte == b'\n' {
      row += 1
      column = 0
    } else {
      column += 1
    }
    points.push({ row, column, })
  }
  points
}

///|
fn fuzz_check_tree(tree : @ts.Tree) -> String? {
  let points = fuzz_points(tree.source)
  let pending = [tree.root_node()]
  while pending.pop() is Some(node) {
    if node.start_byte() < 0 ||
      node.end_byte() < node.start_byte() ||
      node.end_byte() > tree.source.length() {
      return Some("invalid byte extent for \{node.kind()}")
    }
    if node.start_position() != points[node.start_byte()] ||
      node.end_position() != points[node.end_byte()] {
      return Some("invalid point extent for \{node.kind()}")
    }
    let mut previous = node.start_byte()
    let mut named = 0
    for child in node.children() {
      if child.start_byte() < previous || child.end_byte() > node.end_byte() {
        return Some("overlapping or out-of-parent child in \{node.kind()}")
      }
      previous = child.end_byte()
      if child.is_named() {
        named += 1
      }
      pending.push(child)
    }
    if named != node.named_child_count() {
      return Some("incorrect named-child count for \{node.kind()}")
    }
  }
  None
}

///|
fn fuzz_compare(left : @ts.Tree, right : @ts.Tree) -> String? {
  let pending = [(left.root_node(), right.root_node())]
  while pending.pop() is Some((a, b)) {
    if a.kind() != b.kind() ||
      a.range() != b.range() ||
      a.is_named() != b.is_named() ||
      a.is_missing() != b.is_missing() ||
      a.is_extra() != b.is_extra() ||
      a.has_error() != b.has_error() ||
      a.child_count() != b.child_count() {
      return Some(
        "incremental/fresh mismatch at \{a.kind()} [\{a.start_byte()},\{a.end_byte()})",
      )
    }
    for i in 0..<a.child_count() {
      if a.field_name_for_child(i) != b.field_name_for_child(i) {
        return Some(
          "incremental/fresh field mismatch at \{a.kind()} child \{i}",
        )
      }
      pending.push((a.child(i).unwrap(), b.child(i).unwrap()))
    }
  }
  None
}

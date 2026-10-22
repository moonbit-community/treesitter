///|
// Tree-sitter retains the first equivalent link between the same stack nodes.
// Full derivation ordering is only needed when these links are not equivalent.
fn equivalent_top_link(left : Array[Entry], right : Array[Entry]) -> Bool {
  if left.length() != right.length() || left.is_empty() {
    return false
  }
  for i in 0..<left.length() {
    let a = left[i].node
    let b = right[i].node
    if left[i].leading.length() != right[i].leading.length() {
      return false
    }
    for j in 0..<left[i].leading.length() {
      if !physical_equal(left[i].leading[j].data, right[i].leading[j].data) {
        return false
      }
    }
    if a.symbol() != b.symbol() ||
      a.start_byte() != b.start_byte() ||
      a.end_byte() != b.end_byte() ||
      a.is_extra() != b.is_extra() ||
      a.is_missing() != b.is_missing() ||
      a.data.scan_before != b.data.scan_before ||
      a.data.scan_after != b.data.scan_after ||
      a.data.derivation.children.length() != b.data.derivation.children.length() {
      return false
    }
    if i + 1 < left.length() &&
      !physical_equal(a.data.derivation, b.data.derivation) {
      return false
    }
  }
  true
}

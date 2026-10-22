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
      discarded.push({ data: { ..previous.data, error_repeat: true, }, })
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

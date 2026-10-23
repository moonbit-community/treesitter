///|
// Keep execution lowering separate from source-level capture quantifiers.
// Upstream reports the quantifier of a capture where it was written, even when
// a group capture is attached to several concrete entry steps at execution.
fn compile_pattern(pattern : Pattern) -> Pattern {
  match pattern {
    Capture(inner, name) => capture_entries(compile_pattern(inner), name)
    Node(node) => Node({ ..node, children: node.children.map(compile_child), })
    Group(children, trailing) => Group(children.map(compile_child), trailing)
    Either(items) => Either(items.map(compile_pattern))
  }
}

///|
fn compile_child(child : Child) -> Child {
  let pattern = compile_pattern(child.pattern)
  let mut nullable_alternative = false
  let pattern = if pattern is Either(items) {
    Either(
      items.mapi((index, item) => {
        // Alternation links replace a nonfinal branch's empty-path jump. The
        // final branch's jump survives and makes the enclosing child optional.
        if item is Group([branch], false) && branch.min == 0 {
          if index + 1 == items.length() {
            nullable_alternative = true
          }
          if branch.max == Some(1) {
            branch.pattern
          } else {
            Group([{ ..branch, min: 1, }], false)
          }
        } else {
          item
        }
      }),
    )
  } else {
    pattern
  }
  { ..child, pattern, min: if nullable_alternative { 0 } else { child.min }, }
}

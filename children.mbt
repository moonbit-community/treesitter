///|
priv enum ChildPart {
  Item(String?, Node)
  Nested(String?, ChildList)
}

///|
// Hidden reductions share child segments instead of copying the growing prefix
// of a repetition. Flatten only when the public node API needs indexed children.
// The cache does not alter any observable node or field and is safe to share.
priv struct ChildList {
  parts : Array[ChildPart]
  length : Int32
  named_length : Int32
  has_error : Bool
  error_cost : Int32
  mut flattened : Array[(String?, Node)]?
}

///|
fn child_list(parts : Array[ChildPart]) -> ChildList {
  let mut length = 0
  let mut named_length = 0
  let mut has_error = false
  let mut error_cost = 0
  for part in parts {
    match part {
      Item(_, node) => {
        error_cost += node.data.error_cost
        length += 1
        if node.is_named() {
          named_length += 1
        }
        has_error = has_error || node.has_error()
      }
      Nested(_, nested) => {
        error_cost += nested.error_cost
        length += nested.length
        named_length += nested.named_length
        has_error = has_error || nested.has_error
      }
    }
  }
  { parts, length, named_length, has_error, error_cost, flattened: None, }
}

///|
fn child_entries(entries : Array[(String?, Node)]) -> ChildList {
  let list = child_list(entries.map(c => Item(c.0, c.1)))
  list.flattened = Some(entries)
  list
}

///|
fn ChildList::entries(self : ChildList) -> Array[(String?, Node)] {
  if self.flattened is Some(entries) {
    return entries
  }
  let output = []
  let stack : Array[(ChildPart, String?)] = [(Nested(None, self), None)]
  while stack.pop() is Some((part, outer_field)) {
    match part {
      Item(field, node) => {
        let field = match field {
          Some(_) => field
          None => if node.is_extra() { None } else { outer_field }
        }
        output.push((field, node))
      }
      Nested(field, list) => {
        let inherited = match field {
          Some(_) => field
          None => outer_field
        }
        if list.flattened is Some(entries) {
          for (field, node) in entries {
            let field = match field {
              Some(_) => field
              None => if node.is_extra() { None } else { inherited }
            }
            output.push((field, node))
          }
        } else {
          for i = list.parts.length() - 1; i >= 0; i = i - 1 {
            stack.push((list.parts[i], inherited))
          }
        }
      }
    }
  }
  self.flattened = Some(output)
  output
}

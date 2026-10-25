// Port of tree-sitter crates/cli/src/fuzz/scope_sequence.rs.

///|
/// For each byte of the text, the kinds of the nodes containing it.
pub struct ScopeSequence(Array[Array[String]])

///|
pub fn ScopeSequence::new(tree : @treesitter.Tree) -> ScopeSequence {
  let result : Array[Array[String]] = []
  let scope_stack : Array[String] = []
  let cursor = tree.walk()
  let mut visited_children = false
  for ;; {
    let node = cursor.node()
    for _ in result.length()..<node.start_byte() {
      result.push(scope_stack.copy())
    }
    if visited_children {
      for _ in result.length()..<node.end_byte() {
        result.push(scope_stack.copy())
      }
      ignore(scope_stack.pop())
      if cursor.goto_next_sibling() {
        visited_children = false
      } else if !cursor.goto_parent() {
        break
      }
    } else {
      scope_stack.push(cursor.node().kind())
      if !cursor.goto_first_child() {
        visited_children = true
      }
    }
  }
  ScopeSequence(result)
}

///|
/// `{:?}` of an `Option<&Vec<&str>>`.
fn debug_scope_stack(stack : Array[String]?) -> String {
  match stack {
    None => "None"
    Some(stack) => {
      let items = stack.map(s => rust_debug_str(s))
      "Some([\{items.join(", ")}])"
    }
  }
}

///|
/// `{:?}` of a `&str`.
fn rust_debug_str(s : String) -> String {
  let buf = StringBuilder()
  buf.write_char('"')
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      '\u{0}' => buf.write_string("\\0")
      _ => buf.write_char(c)
    }
  }
  buf.write_char('"')
  buf.to_string()
}

///|
/// `{:?}` of a `Point`.
fn debug_point(point : @treesitter.Point) -> String {
  "Point { row: \{point.row}, column: \{point.column} }"
}

///|
/// `{:?}` of a `Range`.
pub fn debug_range(range : @treesitter.Range) -> String {
  "Range { start_byte: \{range.start_byte}, end_byte: \{range.end_byte}, start_point: \{debug_point(range.start_point)}, end_point: \{debug_point(range.end_point)} }"
}

///|
pub fn ScopeSequence::check_changes(
  self : ScopeSequence,
  other : ScopeSequence,
  text : BytesView,
  known_changed_ranges : Array[@treesitter.Range],
) -> Result[Unit, String] {
  let ScopeSequence(scopes) = self
  let ScopeSequence(other_scopes) = other
  let mut position : @treesitter.Point = { row: 0, column: 0, }
  let len = if scopes.length() > other_scopes.length() {
    scopes.length()
  } else {
    other_scopes.length()
  }
  for i in 0..<len {
    let stack = scopes.get(i)
    let other_stack = other_scopes.get(i)
    if stack != other_stack && text[i] != b'\r' && text[i] != b'\n' {
      let containing_range = known_changed_ranges.search_by(range => {
        range.start_point <= position && position < range.end_point
      })
      if containing_range is None {
        let line_start = i - position.column
        let mut line_end = line_start
        while line_end < text.length() && text[line_end] != b'\n' {
          line_end += 1
        }
        let line = @utf8.decode_lossy(text[line_start:line_end])
        let ranges = known_changed_ranges.map(debug_range).join(", ")
        return Err(
          (
            $|Position: \{position}
            $|Byte offset: \{i}
            $|Line: \{line}
            $|\{" ".repeat(position.column + "Line: ".length())}^
            $|Old scopes: \{debug_scope_stack(stack)}
            $|New scopes: \{debug_scope_stack(other_stack)}
            $|Invalidated ranges: [\{ranges}]
          ),
        )
      }
    }
    if text[i] == b'\n' {
      position = { row: position.row + 1, column: 0, }
    } else {
      position = { ..position, column: position.column + 1, }
    }
  }
  Ok(())
}

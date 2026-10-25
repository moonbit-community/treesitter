// Port of the parts of tree-sitter crates/cli/src/parse.rs that corpus tests
// and fuzzing use: `perform_edit`, `position_for_offset` and the CST renderer
// (`render_cst`, without colors: `ParseTheme::empty()`, ranges shown).

///|
pub(all) suberror ParseError {
  ParseError(String)
} derive(Debug)

///|
pub impl Show for ParseError with fn output(self, logger) {
  let ParseError(message) = self
  logger.write_string(message)
}

///|
/// Apply `edit` to `input` and to `tree`, returning the `InputEdit`.
pub fn perform_edit(
  tree : @treesitter.Tree,
  input : Array[Byte],
  edit : Edit,
) -> @treesitter.InputEdit raise ParseError {
  let start_byte = edit.position
  // The endpoints as `usize` arithmetic computes them: checked before the
  // input or the tree changes (an `Int32` sum could wrap).
  let wide_old_end = edit.position.to_int64() + edit.deleted_length.to_int64()
  if wide_old_end > input.length().to_int64() && start_byte <= input.length() {
    raise ParseError("Failed to address an offset: \{wide_old_end}")
  }
  let old_end_byte = edit.position + edit.deleted_length
  let new_end_byte = edit.position + edit.inserted_text.length()
  let start_position = position_for_offset(input, start_byte)
  let old_end_position = position_for_offset(input, old_end_byte)
  if old_end_byte < start_byte {
    raise ParseError(
      "slice index starts at \{start_byte} but ends at \{old_end_byte}",
    )
  }
  // `input.splice(start_byte..old_end_byte, inserted_text)`
  let tail = input[old_end_byte:].to_owned()
  input.truncate(start_byte)
  input.append(edit.inserted_text)
  input.append(tail)
  let new_end_position = position_for_offset(input, new_end_byte)
  let edit : @treesitter.InputEdit = {
    start_byte,
    old_end_byte,
    new_end_byte,
    start_position,
    old_end_position,
    new_end_position,
  }
  tree.edit(edit)
  edit
}

///|
pub fn position_for_offset(
  input : ArrayView[Byte],
  offset : Int32,
) -> @treesitter.Point raise ParseError {
  if offset > input.length() {
    raise ParseError("Failed to address an offset: \{offset}")
  }
  let mut row = 0
  let mut last = 0
  for pos in 0..<offset {
    if input[pos] == b'\n' {
      row += 1
      last = pos
    }
  }
  let column = if row > 0 { offset - last - 1 } else { offset }
  { row, column, }
}

///|
fn escape_invisible(c : Char) -> String? {
  match c {
    '\n' => Some("\\n")
    '\r' => Some("\\r")
    '\t' => Some("\\t")
    '\u{0}' => Some("\\0")
    '\\' => Some("\\\\")
    '\u{b}' => Some("\\v")
    '\u{c}' => Some("\\f")
    _ => None
  }
}

///|
fn escape_delimiter(c : Char) -> String? {
  match c {
    '`' => Some("\\`")
    '"' => Some("\\\"")
    _ => None
  }
}

///|
/// `checked_ilog10(n).unwrap_or(0)`.
fn ilog10_or_zero(n : Int32) -> Int32 {
  let mut n = n
  let mut result = 0
  while n >= 10 {
    n /= 10
    result += 1
  }
  result
}

///|
/// Render the concrete syntax tree of `tree` (the `--cst` output of `parse`).
pub fn render_cst(
  source_code : Bytes,
  tree : @treesitter.Tree,
  cursor : @treesitter.TreeCursor,
  out : StringBuilder,
) -> Unit {
  let lossy_source_code = @utf8.decode_lossy(source_code)
  let mut total_width = 0
  let mut any_line = false
  for row, line in rust_lines(lossy_source_code) {
    let width = ilog10_or_zero(row) + ilog10_or_zero(utf8_len(line)) + 1
    if !any_line || width > total_width {
      total_width = width
    }
    any_line = true
  }
  if !any_line {
    total_width = 1
  }
  let mut indent_level = 1 // usize::from(!opts.no_ranges)
  let mut did_visit_children = false
  let mut in_error = false
  for ;; {
    if did_visit_children {
      if cursor.goto_next_sibling() {
        did_visit_children = false
      } else if cursor.goto_parent() {
        did_visit_children = true
        indent_level -= 1
        if !cursor.node().has_error() {
          in_error = false
        }
      } else {
        break
      }
    } else {
      cst_render_node(
        cursor, source_code, out, total_width, indent_level, in_error,
      )
      if cursor.goto_first_child() {
        did_visit_children = false
        indent_level += 1
        if cursor.node().has_error() {
          in_error = true
        }
      } else {
        did_visit_children = true
      }
    }
  }
  cursor.reset(tree.root_node())
}

///|
/// `CstNodeText`'s `Display`.
fn write_cst_node_text(out : StringBuilder, text : StringView) -> Unit {
  for c in text {
    match escape_invisible(c) {
      Some(esc) => out.write_string(esc)
      None =>
        match escape_delimiter(c) {
          Some(esc) => out.write_string(esc)
          None => out.write_char(c)
        }
    }
  }
}

///|
fn write_node_text(
  out : StringBuilder,
  cursor : @treesitter.TreeCursor,
  is_named : Bool,
  source : String,
  text_info : (Int32, Int32),
) -> Unit {
  let (total_width, indent_level) = text_info
  let quote = if is_named { '`' } else { '"' }
  if !is_named {
    out.write_char(quote)
    write_cst_node_text(out, source)
    out.write_char(quote)
  } else {
    let multiline = source.contains("\n")
    for i, line in split_inclusive_newline(source) {
      if line.is_empty() {
        break
      }
      let range = cursor.node().range()
      // For each line of text, adjust the row by shifting it down `i` rows,
      // and adjust the column by setting it to the length of *this* line.
      let start_point = { ..range.start_point, row: range.start_point.row + i, }
      let end_point : @treesitter.Point = {
        row: start_point.row,
        column: utf8_len(line) + (if i == 0 { start_point.column } else { 0 }),
      }
      let node_range = { ..range, start_point, end_point, }
      if multiline {
        out.write_char('\n')
        write_cst_node_range(out, total_width, node_range)
        for _ in 0..<=indent_level {
          out.write_string("  ")
        }
      } else {
        out.write_char(' ')
      }
      out.write_char(quote)
      // `CstLineFeed`
      let parts = line.split("\n").to_array()
      write_cst_node_text(out, parts[0])
      for part in parts[1:] {
        write_cst_node_text(out, "\n")
        write_cst_node_text(out, part)
      }
      out.write_char(quote)
    }
  }
}

///|
/// `CstNodeRange`'s `Display` (without colors).
fn write_cst_node_range(
  out : StringBuilder,
  total_width : Int32,
  range : @treesitter.Range,
) -> Unit {
  let start = range.start_point
  let end = range.end_point
  let remaining_width = (row : Int32, col : Int32) => {
    let w = total_width - ilog10_or_zero(row)
    let w = if w < 0 { 0 } else { w }
    let w = w - ilog10_or_zero(col)
    let w = if w < 0 { 0 } else { w }
    if w < 1 {
      1
    } else {
      w
    }
  }
  let remaining_width_start = remaining_width(start.row, start.column)
  let remaining_width_end = remaining_width(end.row, end.column)
  out.write_string(
    "\{start.row}:\{start.column}\{" ".repeat(remaining_width_start)}- \{end.row}:\{end.column}\{" ".repeat(remaining_width_end)}",
  )
}

///|
fn cst_render_node(
  cursor : @treesitter.TreeCursor,
  source_code : Bytes,
  out : StringBuilder,
  total_width : Int32,
  indent_level : Int32,
  in_error : Bool,
) -> Unit {
  let node = cursor.node()
  let is_named = node.is_named()
  write_cst_node_range(out, total_width, node.range())
  out.write_string("  ".repeat(indent_level))
  out.write_string(if in_error && !node.has_error() { " " } else { "" })
  if is_named {
    if cursor.field_name() is Some(field_name) {
      out.write_string("\{field_name}: ")
    }
    if node.has_error() || node.is_error() {
      out.write_string("•")
    }
    out.write_string(node.kind())
    if node.child_count() == 0 {
      // Node text from a pattern or external scanner
      write_node_text(
        out,
        cursor,
        is_named,
        @utf8.decode_lossy(source_code[node.start_byte():node.end_byte()]),
        (total_width, indent_level),
      )
    }
  } else if node.is_missing() {
    out.write_string("MISSING: ")
    out.write_string("\"\{node.kind()}\"")
  } else {
    // Terminal literals, like "fn"
    write_node_text(
      out,
      cursor,
      is_named,
      node.kind(),
      (total_width, indent_level),
    )
  }
  out.write_char('\n')
}

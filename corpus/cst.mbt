///|
fn digits(n : Int32) -> Int32 {
  n.to_string().length()
}

///|
fn spaces(n : Int32) -> String {
  Array::make(n, " ").join("")
}

///|
fn escaped(text : String) -> String {
  let out = StringBuilder()
  for c in text {
    match c {
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      '\\' => out.write_string("\\\\")
      '"' => out.write_string("\\\"")
      '`' => out.write_string("\\`")
      '\u{0000}' => out.write_string("\\0")
      _ => out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn range_text(start : @ts.Point, end : @ts.Point, width : Int32) -> String {
  "\{start.row}:\{start.column}\{spaces(Int32::max(1, width - digits(start.row) - digits(start.column) + 2))}- \{end.row}:\{end.column}\{spaces(Int32::max(1, width - digits(end.row) - digits(end.column) + 2))}"
}

///|
/// Render all named and anonymous nodes in the upstream corpus CST format.
pub fn render_cst(root : @ts.Node, source : String) -> String {
  let bytes = @utf8.encode(source)
  let mut width = 1
  for row, line in source.split("\n").to_array() {
    width = Int32::max(
      width,
      digits(row) + digits(@utf8.encode(line.to_owned()).length()) - 1,
    )
  }
  let output = StringBuilder()
  let work : Array[(@ts.Node, String?, Int32, Bool)] = [(root, None, 1, false)]
  while work.pop() is Some((node, field, depth, in_error)) {
    output.write_string(
      range_text(node.start_position(), node.end_position(), width),
    )
    output.write_string(spaces(depth * 2))
    if in_error && !node.has_error() {
      output.write_char(' ')
    }
    if node.is_named() {
      if field is Some(name) {
        output.write_string(name + ": ")
      }
      if node.has_error() {
        output.write_char('•')
      }
      output.write_string(node.kind())
      if node.child_count() == 0 {
        let text = node.text(bytes)
        if text.contains("\n") {
          let lines = text.split("\n").to_array()
          for i, line in lines {
            if i == lines.length() - 1 && line.is_empty() {
              break
            }
            let start : @ts.Point = {
              row: node.start_position().row + i,
              column: if i == 0 {
                node.start_position().column
              } else {
                0
              },
            }
            let line = line.to_owned() +
              (if i < lines.length() - 1 { "\n" } else { "" })
            let end : @ts.Point = {
              row: start.row,
              column: start.column + @utf8.encode(line).length(),
            }
            output.write_string(
              "\n" +
              range_text(start, end, width) +
              spaces((depth + 1) * 2) +
              "`" +
              escaped(line) +
              "`",
            )
          }
        } else if !text.is_empty() {
          output.write_string(" `" + escaped(text) + "`")
        }
      }
    } else {
      if node.is_missing() {
        output.write_string("MISSING: ")
      }
      output.write_string("\"" + escaped(node.kind()) + "\"")
    }
    output.write_char('\n')
    for i = node.child_count() - 1; i >= 0; i = i - 1 {
      work.push(
        (
          node.child(i).unwrap(),
          node.field_name_for_child(i),
          depth + 1,
          in_error || node.has_error(),
        ),
      )
    }
  }
  output.to_string()
}

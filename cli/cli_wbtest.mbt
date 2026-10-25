///|
test "anyhow debug formatting" {
  inspect(CliError(["outer"]).debug(), content="outer")
  inspect(
    CliError(["Error when generating parser", "line one\nline two"]).debug(),
    content=(
      #|Error when generating parser
      #|
      #|Caused by:
      #|    line one
      #|    line two
    ),
  )
  inspect(
    CliError(["a", "b", "c\nd"]).debug(),
    content=(
      #|a
      #|
      #|Caused by:
      #|    0: b
      #|    1: c
      #|       d
    ),
  )
}

///|
test "number formatting" {
  inspect(format_fixed2(3.14159), content="3.14")
  inspect(format_fixed2(0.005), content="0.01")
  inspect(format_fixed3(12.3456), content="12.346")
  inspect(pad_left("1.50", 7), content="   1.50")
  inspect(pad_right("ab", 4) + "|", content="ab  |")
  inspect(format_duration_debug(1500000L), content="1.5ms")
  inspect(format_duration_debug(42L), content="42ns")
}

///|
test "ranges and edits" {
  debug_inspect(parse_range(Some("3:9")), content="Some((3, 9))")
  let err = try parse_range(Some("3")) catch {
    e => error_message(e)
  } noraise {
    _ => "ok"
  }
  inspect(err, content="Invalid range '3', expected 'start:end'")
  let source = @support.utf8("abc\ndef").to_array()
  inspect(offset_for_position(source, { row: 1, column: 2, }), content="6")
  let edit = parse_edit_flag(source, "1,1 2 x y")
  debug_inspect(
    (edit.position, edit.deleted_length, edit.inserted_text),
    content="(5, 2, [0x78, 0x20, 0x79])",
  )
  // `usize` values: rows and columns past `i32::MAX` are addressing errors,
  // not invalid edit strings.
  let err = try parse_edit_flag(source, "4294967296,0 0 x") catch {
    e => error_message(e)
  } noraise {
    _ => "ok"
  }
  inspect(err, content="Failed to address a row: 4294967296")
  let err = try parse_edit_flag(source, "0,99999999999 0 x") catch {
    e => error_message(e)
  } noraise {
    _ => "ok"
  }
  inspect(err, content="Failed to address a column: 99999999999")
  // Query ranges are `usize`, passed to the cursor `as u32`.
  debug_inspect(
    parse_range(Some("0:99999999999")),
    content="Some((0, 1215752191))",
  )
  debug_inspect(parse_range(Some("3:4294967296")), content="Some((3, 0))")
  debug_inspect(
    parse_range(Some("3:4294967295")),
    content="Some((3, 2147483647))",
  )
}

///|
test "edit offsets are checked before the input changes" {
  let source = @support.utf8("0").to_array()
  // `1 + 2147483647` overflows `i32`, but not `usize`.
  let edit = parse_edit_flag(source, "1 2147483647 ")
  let err = try check_flag_edit(source.length(), edit) catch {
    e => e.to_string()
  } noraise {
    _ => "ok"
  }
  inspect(err, content="Failed to address an offset: 2147483648")
  let edit = parse_edit_flag(source, "0 18446744073709551615 x")
  let err = try check_flag_edit(source.length(), edit) catch {
    e => e.to_string()
  } noraise {
    _ => "ok"
  }
  inspect(err, content="Failed to address an offset: 18446744073709551615")
  let edit = parse_edit_flag(source, "$ 0 x")
  debug_inspect(check_flag_edit(source.length(), edit), content="(1, 0)")
}

///|
test "theme" {
  let theme = Theme::default()
  inspect(theme.highlight_names[0], content="attribute")
  debug_inspect(
    theme.styles[0].css,
    content="Some(\"font-style: italic;color: #af0000\")",
  )
  inspect(ansi256_from_rgb(38, 166, 154), content="72")
}

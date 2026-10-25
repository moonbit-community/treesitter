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
    edit,
    content=(
      #|{ position: 5, deleted_length: 2, inserted_text: [0x78, 0x20, 0x79] }
    ),
  )
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

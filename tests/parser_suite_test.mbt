// Port of tree-sitter crates/cli/src/tests/parser_test.rs.
//
// Tests whose grammar needs an external scanner that is not ported yet return
// early with a notice (see `get_parsing_language` and
// `get_test_fixture_language`). Deviations:
// - `test_parsing_on_multiple_threads` reparses sequentially (MoonBit has no
//   threads); the assertions are unchanged.
// - `test_parsing_cancelled_by_another_thread` sets the cancellation flag
//   from the input callback once 100ms have elapsed instead of from another
//   thread.
// - `test_grammar_that_should_hang_and_not_segfault` is not ported: it
//   detects a hang by running the parse on a thread with a timeout.
// - Durations are measured with C's `clock()` (see `elapsed_micros`).

///|
/// `#[retry(n)]`: run `f` until it succeeds, retrying at most `n` times.
async fn retry(n : Int32, f : async () -> Unit) -> Unit {
  for attempt in 0..<=n {
    try f() catch {
      e => if attempt == n { raise e }
    } noraise {
      _ => return
    }
  }
}

///|
/// Swap the bytes of each code unit (`u16::to_be` on a little-endian host).
fn swap_units(units : ArrayView[UInt16]) -> Array[UInt16] {
  units
  .iter()
  .map(u => ((u.to_int() >> 8) | ((u.to_int() & 0xFF) << 8)).to_uint16())
  .to_array()
}

///|
async test "parsing_simple_string" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(
    parser, "\n        struct Stuff {}\n        fn main() {}\n    ",
  )
  let root_node = tree.root_node()
  assert_eq(root_node.kind(), "source_file")
  assert_eq(
    root_node.to_sexp(),
    "(source_file " +
    "(struct_item name: (type_identifier) body: (field_declaration_list)) " +
    "(function_item name: (identifier) parameters: (parameters) body: (block)))",
  )
  let struct_node = root_node.child(0).unwrap()
  assert_eq(struct_node.kind(), "struct_item")
}

///|
async test "parsing_with_logging" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let messages : Array[(@treesitter.LogType, String)] = []
  parser.set_logger(
    Some((log_type, message) => messages.push((log_type, message))),
  )
  ignore(parse(parser, "\n        struct Stuff {}\n        fn main() {}\n    "))
  assert_true(
    messages.contains((Parse, "reduce sym:struct_item, child_count:3")),
  )
  assert_true(messages.contains((Lex, "skip character:' '")))
  let mut row_starts_from_0 = false
  for message in messages {
    let (_, m) = message
    if m.contains("row:0") {
      row_starts_from_0 = true
      break
    }
  }
  assert_true(row_starts_from_0)
}

///|
async test "parsing_with_debug_graph_enabled" {
  let has_zero_indexed_row = (s : StringView) => s.contains("position: 0,")
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let debug_graph_file = StringBuilder()
  parser.print_dot_graphs(s => debug_graph_file.write_string(s))
  ignore(parse(parser, "const zero = 0"))
  for line in debug_graph_file.to_string().split("\n") {
    assert_false(
      has_zero_indexed_row(line),
      msg="Graph log output includes zero-indexed row: \{line}",
    )
  }
}

///|
async test "parsing_with_custom_utf8_input" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let lines = ["pub fn foo() {", "  1", "}"].map(utf8)
  let tree = parser
    .parse_with_options((_, position) => {
      let row = position.row
      let column = position.column
      if row < lines.length() {
        if column < lines[row].length() {
          lines[row][column:]
        } else {
          b"\n"[:]
        }
      } else {
        b""[:]
      }
    })
    .unwrap()
  let root = tree.root_node()
  assert_eq(
    root.to_sexp(),
    "(source_file " +
    "(function_item " +
    "(visibility_modifier) " +
    "name: (identifier) " +
    "parameters: (parameters) " +
    "body: (block (integer_literal))))",
  )
  assert_eq(root.kind(), "source_file")
  assert_false(root.has_error())
  assert_eq(root.child(0).unwrap().kind(), "function_item")
}

///|
async test "parsing_with_custom_utf16le_input" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  // `u16::to_le` is the identity on a little-endian host.
  let lines = ["pub fn foo() {", "  1", "}"].map(utf16)
  let newline : Array[UInt16] = ['\n']
  let tree = parser
    .parse_utf16_le_with_options((_, position) => {
      let row = position.row
      let column = position.column
      if row < lines.length() {
        if column < lines[row].length() {
          lines[row][column:]
        } else {
          newline[:]
        }
      } else {
        [][:]
      }
    })
    .unwrap()
  let root = tree.root_node()
  assert_eq(
    root.to_sexp(),
    "(source_file (function_item (visibility_modifier) name: (identifier) parameters: (parameters) body: (block (integer_literal))))",
  )
  assert_eq(root.kind(), "source_file")
  assert_false(root.has_error())
  assert_eq(root.child(0).unwrap().kind(), "function_item")
}

///|
async test "parsing_with_custom_utf16_be_input" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let lines = ["pub fn foo() {", "  1", "}"].map(s => swap_units(utf16(s)))
  let newline = swap_units(['\n'])
  let tree = parser
    .parse_utf16_be_with_options((_, position) => {
      let row = position.row
      let column = position.column
      if row < lines.length() {
        if column < lines[row].length() {
          lines[row][column:]
        } else {
          newline[:]
        }
      } else {
        [][:]
      }
    })
    .unwrap()
  let root = tree.root_node()
  assert_eq(
    root.to_sexp(),
    "(source_file (function_item (visibility_modifier) name: (identifier) parameters: (parameters) body: (block (integer_literal))))",
  )
  assert_eq(root.kind(), "source_file")
  assert_false(root.has_error())
  assert_eq(root.child(0).unwrap().kind(), "function_item")
}

///|
async test "utf16_decodes_surrogate_pairs" {
  let parser = @treesitter.Parser::new()
  guard get_test_fixture_language("utf16_surrogate_oob") is Some(language) else {
    return
  }
  parser.set_language(language)
  let le : Array[UInt16] = [0xD83D, 0xDE00]
  let tree = parser.parse_utf16_le(le).unwrap()
  assert_eq(tree.root_node().to_sexp(), "(program (supplementary))")
  let be = swap_units([0xD83D, 0xDE00])
  let tree = parser.parse_utf16_be(be).unwrap()
  assert_eq(tree.root_node().to_sexp(), "(program (supplementary))")
}

///|
async test "utf16_decode_does_not_read_oob" {
  // Test for a buffer over-read in ts_decode_utf16_le/be when a lead surrogate
  // is the last code unit in a chunk. The test grammar's external scanner
  // distinguishes surrogate code points from supplementary-plane characters,
  // making the over-read directly observable in the parse tree.
  //
  // Buffer layout:
  //   buf[0] = 0xD83E  (lead surrogate)
  //   buf[1] = 0xDD8B  (POISON: fake trail surrogate, adjacent in memory)
  //
  // The callback returns only buf[0..1] (one code unit = 2 bytes).
  //
  // When functioning correctly, this test passes a length of 2 bytes, which is
  // interpreted as 2/2 = 1 code unit, and thus doesn't over-read into the "poison"
  // fake trail surrogate. If an over-read does occur, the scanner sees a
  // supplementary token.
  let parser = @treesitter.Parser::new()
  guard get_test_fixture_language("utf16_surrogate_oob") is Some(language) else {
    return
  }
  parser.set_language(language)
  let buf : Array[UInt16] = [
    0xD83E, // lead surrogate (the only "visible" code unit)
     0xDD8B, // POISON: adjacent in Vec memory, past the chunk
  ]
  // `String::from_utf16(&buf) == "🦋"`
  assert_eq(utf16("🦋"), buf)
  let callback = (offset : Int32, _position : @treesitter.Point) => {
    // only expose buf[0], never buf[1]
    if offset >= 1 {
      return [][:]
    }
    buf[0:1]
  }

  // Use the parse function matching the host endianness, since the
  // buffer contains native u16 values.
  let tree = parser.parse_utf16_le_with_options(callback).unwrap()
  let root = tree.root_node()

  // Correct: scanner sees raw surrogate (0xD83E) -> `surrogate` node
  // Incorrect: scanner sees supplementary (U+1F98B, aka 🦋) -> `supplementary` node
  assert_eq(
    root.to_sexp(),
    "(program (surrogate))",
    msg="buffer over-read: decoder read past chunk boundary and formed a supplementary character from OOB adjacent memory",
  )
}

///|
async test "parsing_with_callback_returning_owned_strings" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let text = b"pub fn foo() { 1 }"
  let tree = parser
    .parse_with_options((i, _) => Bytes::from_array(text[i:].to_array())[:])
    .unwrap()
  let root = tree.root_node()
  assert_eq(
    root.to_sexp(),
    "(source_file (function_item (visibility_modifier) name: (identifier) parameters: (parameters) body: (block (integer_literal))))",
  )
}

///|
async test "parsing_text_with_byte_order_mark" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)

  // Parse UTF16 text with a BOM
  let tree = parser.parse_utf16_le(utf16("\u{FEFF}fn a() {}")).unwrap()
  assert_eq(
    tree.root_node().to_sexp(),
    "(source_file (function_item name: (identifier) parameters: (parameters) body: (block)))",
  )
  assert_eq(tree.root_node().start_byte(), 2)

  // Parse UTF8 text with a BOM
  let tree = parse(parser, "\u{FEFF}fn a() {}")
  assert_eq(
    tree.root_node().to_sexp(),
    "(source_file (function_item name: (identifier) parameters: (parameters) body: (block)))",
  )
  assert_eq(tree.root_node().start_byte(), 3)

  // Edit the text, inserting a character before the BOM. The BOM is now an error.
  tree.edit({
    start_byte: 0,
    old_end_byte: 0,
    new_end_byte: 1,
    start_position: @treesitter.Point::new(0, 0),
    old_end_position: @treesitter.Point::new(0, 0),
    new_end_position: @treesitter.Point::new(0, 1),
  })
  let tree = parser.parse(utf8(" \u{FEFF}fn a() {}"), old_tree=tree).unwrap()
  assert_eq(
    tree.root_node().to_sexp(),
    "(source_file (ERROR (UNEXPECTED 65279)) (function_item name: (identifier) parameters: (parameters) body: (block)))",
  )
  assert_eq(tree.root_node().start_byte(), 1)

  // Edit the text again, putting the BOM back at the beginning.
  tree.edit({
    start_byte: 0,
    old_end_byte: 1,
    new_end_byte: 0,
    start_position: @treesitter.Point::new(0, 0),
    old_end_position: @treesitter.Point::new(0, 1),
    new_end_position: @treesitter.Point::new(0, 0),
  })
  let tree = parser.parse(utf8("\u{FEFF}fn a() {}"), old_tree=tree).unwrap()
  assert_eq(
    tree.root_node().to_sexp(),
    "(source_file (function_item name: (identifier) parameters: (parameters) body: (block)))",
  )
  assert_eq(tree.root_node().start_byte(), 3)
}

///|
async test "parsing_invalid_chars_at_eof" {
  guard get_parsing_language("json") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parser.parse(b"\xdf").unwrap()
  assert_eq(
    tree.root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED INVALID)))",
  )
}

///|
async test "parsing_unexpected_null_characters_within_source" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parser.parse(b"var \x00 something;").unwrap()
  assert_eq(
    tree.root_node().to_sexp(),
    "(program (variable_declaration (ERROR (UNEXPECTED '\\0')) (variable_declarator name: (identifier))))",
  )
}

///|
async test "parsing_ends_when_input_callback_returns_empty" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let mut i = 0
  let source = b"abcdefghijklmnoqrs"
  let tree = parser
    .parse_with_options((offset, _) => {
      i += 1
      if offset >= 6 {
        b""[:]
      } else {
        let end = if source.length() < offset + 3 {
          source.length()
        } else {
          offset + 3
        }
        source[offset:end]
      }
    })
    .unwrap()
  assert_eq(tree.root_node().end_byte(), 6)
  ignore(i)
}

// Incremental parsing

///|
async test "parsing_after_editing_beginning_of_code" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let code = utf8("123 + 456 * (10 + x);").to_array()
  let tree = parser.parse(Bytes::from_array(code)).unwrap()
  assert_eq(
    tree.root_node().to_sexp(),
    "(program (expression_statement (binary_expression " +
    "left: (number) " +
    "right: (binary_expression left: (number) right: (parenthesized_expression " +
    "(binary_expression left: (number) right: (identifier)))))))",
  )
  ignore(@cli_test.perform_edit(tree, code, edit(3, 0, " || 5")))
  let recorder = ReadRecorder::new(code)
  let tree = parser
    .parse_with_options((i, _) => recorder.read(i), old_tree=tree)
    .unwrap()
  assert_eq(
    tree.root_node().to_sexp(),
    "(program (expression_statement (binary_expression " +
    "left: (number) " +
    "right: (binary_expression " +
    "left: (number) " +
    "right: (binary_expression " +
    "left: (number) " +
    "right: (parenthesized_expression (binary_expression left: (number) right: (identifier))))))))",
  )
  assert_eq(recorder.strings_read(), ["123 || 5 "])
}

///|
async test "parsing_after_editing_end_of_code" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let code = utf8("x * (100 + abc);").to_array()
  let tree = parser.parse(Bytes::from_array(code)).unwrap()
  assert_eq(
    tree.root_node().to_sexp(),
    "(program (expression_statement (binary_expression " +
    "left: (identifier) " +
    "right: (parenthesized_expression (binary_expression left: (number) right: (identifier))))))",
  )
  let position = code.length() - 2
  ignore(@cli_test.perform_edit(tree, code, edit(position, 0, ".d")))
  let recorder = ReadRecorder::new(code)
  let tree = parser
    .parse_with_options((i, _) => recorder.read(i), old_tree=tree)
    .unwrap()
  assert_eq(
    tree.root_node().to_sexp(),
    "(program (expression_statement (binary_expression " +
    "left: (identifier) " +
    "right: (parenthesized_expression (binary_expression " +
    "left: (number) " +
    "right: (member_expression " +
    "object: (identifier) " +
    "property: (property_identifier)))))))",
  )
  assert_eq(recorder.strings_read(), [" * ", "abc.d)"])
}

///|
async test "parsing_empty_file_with_reused_tree" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parser.parse(b"")
  ignore(parser.parse(b"", old_tree?=tree))
  let tree = parser.parse(b"\n  ")
  ignore(parser.parse(b"\n  ", old_tree?=tree))
}

///|
async test "parsing_after_editing_tree_that_depends_on_column_values" {
  let parser = @treesitter.Parser::new()
  guard get_test_fixture_language("uses_current_column") is Some(language) else {
    return
  }
  parser.set_language(language)
  let code = utf8(
    (
      #|
      #|a = b
      #|c = do d
      #|       e + f
      #|       g
      #|h + i
      #|
    ),
  ).to_array()
  let tree = parser.parse(Bytes::from_array(code)).unwrap()
  assert_eq(
    tree.root_node().to_sexp(),
    "(block " +
    "(binary_expression (identifier) (identifier)) " +
    "(binary_expression (identifier) (do_expression (block (identifier) (binary_expression (identifier) (identifier)) (identifier)))) " +
    "(binary_expression (identifier) (identifier)))",
  )
  ignore(@cli_test.perform_edit(tree, code, edit(8, 0, "1234")))
  assert_eq(
    Bytes::from_array(code),
    utf8(
      (
        #|
        #|a = b
        #|c1234 = do d
        #|       e + f
        #|       g
        #|h + i
        #|
      ),
    ),
  )
  let recorder = ReadRecorder::new(code)
  let tree = parser
    .parse_with_options((i, _) => recorder.read(i), old_tree=tree)
    .unwrap()
  assert_eq(
    tree.root_node().to_sexp(),
    "(block " +
    "(binary_expression (identifier) (identifier)) " +
    "(binary_expression (identifier) (do_expression (block (identifier)))) " +
    "(binary_expression (identifier) (identifier)) " +
    "(identifier) " +
    "(binary_expression (identifier) (identifier)))",
  )
  assert_eq(recorder.strings_read(), [
    "\nc1234 = do d\n       e + f\n       g\n",
  ])
}

///|
async test "parsing_after_editing_tree_that_depends_on_column_position" {
  let parser = @treesitter.Parser::new()
  guard get_test_fixture_language("depends_on_column") is Some(language) else {
    return
  }
  parser.set_language(language)
  let code = utf8("\n x").to_array()
  let tree = parser.parse(Bytes::from_array(code)).unwrap()
  assert_eq(tree.root_node().to_sexp(), "(x_is_at (odd_column))")
  ignore(@cli_test.perform_edit(tree, code, edit(1, 0, " ")))
  assert_eq(Bytes::from_array(code), b"\n  x")
  let recorder = ReadRecorder::new(code)
  let tree = parser
    .parse_with_options((i, _) => recorder.read(i), old_tree=tree)
    .unwrap()
  assert_eq(tree.root_node().to_sexp(), "(x_is_at (even_column))")
  assert_eq(recorder.strings_read(), ["\n  x"])
  ignore(@cli_test.perform_edit(tree, code, edit(1, 0, "\n")))
  assert_eq(Bytes::from_array(code), b"\n\n  x")
  let recorder = ReadRecorder::new(code)
  let tree = parser
    .parse_with_options((i, _) => recorder.read(i), old_tree=tree)
    .unwrap()
  assert_eq(tree.root_node().to_sexp(), "(x_is_at (even_column))")
  assert_eq(recorder.strings_read(), ["\n\n  x"])
}

///|
async test "parsing_after_failed_external_scan_that_depends_on_column" {
  let parser = @treesitter.Parser::new()
  guard get_test_fixture_language("depends_on_column_failed_scan")
    is Some(language) else {
    return
  }
  parser.set_language(language)
  let code = utf8("ax").to_array()
  let tree = parser.parse(Bytes::from_array(code)).unwrap()
  assert_eq(tree.root_node().to_sexp(), "(document (letter) (tail))")
  ignore(@cli_test.perform_edit(tree, code, edit(0, 1, "\n")))
  let incremental = parser
    .parse(Bytes::from_array(code), old_tree=tree)
    .unwrap()
  let fresh = parser.parse(Bytes::from_array(code)).unwrap()
  assert_eq(fresh.root_node().to_sexp(), "(document (newline) (head))")
  assert_eq(incremental.root_node().to_sexp(), fresh.root_node().to_sexp())
}

///|
async test "parsing_after_detecting_error_in_the_middle_of_a_string_token" {
  guard get_parsing_language("python") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let source = utf8("a = b, 'c, d'").to_array()
  let tree = parser.parse(Bytes::from_array(source)).unwrap()
  assert_eq(
    tree.root_node().to_sexp(),
    "(module (expression_statement (assignment left: (identifier) right: (expression_list (identifier) (string (string_start) (string_content) (string_end))))))",
  )

  // Delete a suffix of the source code, starting in the middle of the string
  // literal, after some whitespace. With this deletion, the remaining string
  // content: "c, " looks like two valid python tokens: an identifier and a comma.
  // When this edit is undone, in order correctly recover the original tree, the
  // parser needs to remember that before matching the `c` as an identifier, it
  // lookahead ahead several bytes, trying to find the closing quotation mark in
  // order to match the "string content" node.
  let edit_ix = byte_find("a = b, 'c, d'", "d'")
  let edit = edit(edit_ix, source.length() - edit_ix, "")
  let undo = @cli_test.invert_edit(source, edit)
  let tree2 = tree.clone()
  ignore(@cli_test.perform_edit(tree2, source, edit))
  let tree2 = parser.parse(Bytes::from_array(source), old_tree=tree2).unwrap()
  assert_true(tree2.root_node().has_error())
  let tree3 = tree2.clone()
  ignore(@cli_test.perform_edit(tree3, source, undo))
  let tree3 = parser.parse(Bytes::from_array(source), old_tree=tree3).unwrap()
  assert_eq(tree3.root_node().to_sexp(), tree.root_node().to_sexp())
}

// Thread safety

///|
async test "parsing_on_multiple_threads" {
  // Parse this source file so that each thread has a non-trivial amount of
  // work to do.
  guard upstream_dir() is Some(upstream) else { return }
  let this_file_source = @fs.read_file(
    "\{upstream}/crates/cli/src/tests/parser_test.rs",
  ).text()
  guard get_parsing_language("rust") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, this_file_source)
  let parse_threads = []
  for thread_id in 1..<5 {
    let tree_clone = tree.clone()
    // (Run sequentially: MoonBit has no threads.)
    parse_threads.push(fn() raise {
      // For each thread, prepend a different number of declarations to the
      // source code.
      let mut prepend_line_count = 0
      let prepended_source = StringBuilder()
      for _ in 0..<thread_id {
        prepend_line_count += 2
        prepended_source.write_string("struct X {}\n\n")
      }
      tree_clone.edit({
        start_byte: 0,
        old_end_byte: 0,
        new_end_byte: utf8(prepended_source.to_string()).length(),
        start_position: @treesitter.Point::new(0, 0),
        old_end_position: @treesitter.Point::new(0, 0),
        new_end_position: @treesitter.Point::new(prepend_line_count, 0),
      })
      prepended_source.write_string(this_file_source)

      // Reparse using the old tree as a starting point.
      let parser = @treesitter.Parser::new()
      parser.set_language(language)
      parser
      .parse(utf8(prepended_source.to_string()), old_tree=tree_clone)
      .unwrap()
    })
  }

  // Check that the trees have the expected relationship to one another.
  let trees = parse_threads.map(thread => thread())
  let child_count_differences = trees.map(t => {
    t.root_node().child_count() - tree.root_node().child_count()
  })
  assert_eq(child_count_differences, [1, 2, 3, 4])
}

///|
async test "parsing_cancelled_by_another_thread" {
  let mut cancellation_flag = 0
  let callback = (_ : @treesitter.ParseState) => {
    if cancellation_flag != 0 {
      @treesitter.ControlFlow::Break
    } else {
      Continue
    }
  }
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)

  // Long input - parsing succeeds
  let tree = parser.parse_with_options(
    (offset, _) => {
      if offset == 0 {
        b" ["[:]
      } else if offset >= 20000 {
        b""[:]
      } else {
        b"0,"[:]
      }
    },
    options=@treesitter.ParseOptions::new(progress_callback=callback),
  )
  assert_true(tree is Some(_))

  // (Upstream sets the flag from a thread that sleeps for 100ms; here the
  // input callback sets it once 100ms have elapsed.)
  let start_time = c_clock()

  // Infinite input
  let tree = parser.parse_with_options(
    (offset, _) => {
      if elapsed_micros(start_time) > 100000L {
        cancellation_flag = 1
      }
      if offset == 0 {
        b" ["[:]
      } else {
        b"0,"[:]
      }
    },
    options=@treesitter.ParseOptions::new(progress_callback=callback),
  )

  // Parsing returns None because it was cancelled.
  assert_true(tree is None)
}

// Timeouts

///|
async test "parsing_with_a_timeout" {
  guard get_parsing_language("json") is Some(language) else { return }
  retry(10, () => {
    let parser = @treesitter.Parser::new()
    parser.set_language(language)

    // Parse an infinitely-long array, but pause after 1ms of processing.
    let start_time = c_clock()
    let tree = parser.parse_with_options(
      (offset, _) => if offset == 0 { b" ["[:] } else { b",0"[:] },
      options=@treesitter.ParseOptions::new(progress_callback=_ => {
        if elapsed_micros(start_time) > 1000L {
          Break
        } else {
          Continue
        }
      }),
    )
    assert_true(tree is None)
    assert_true(elapsed_micros(start_time) < 2000L)

    // Continue parsing, but pause after 1 ms of processing.
    let start_time = c_clock()
    let tree = parser.parse_with_options(
      (offset, _) => if offset == 0 { b" ["[:] } else { b",0"[:] },
      options=@treesitter.ParseOptions::new(progress_callback=_ => {
        if elapsed_micros(start_time) > 5000L {
          Break
        } else {
          Continue
        }
      }),
    )
    assert_true(tree is None)
    assert_true(elapsed_micros(start_time) > 100L)
    assert_true(elapsed_micros(start_time) < 10000L)

    // Finish parsing
    let tree = parser
      .parse_with_options((offset, _) => {
        if offset >= 5001 {
          b""[:]
        } else if offset == 5000 {
          b"]"[:]
        } else {
          b",0"[:]
        }
      })
      .unwrap()
    assert_eq(tree.root_node().child(0).unwrap().kind(), "array")
  })
}

///|
async test "parsing_with_a_timeout_and_a_reset" {
  guard get_parsing_language("json") is Some(language) else { return }
  retry(10, () => {
    let parser = @treesitter.Parser::new()
    parser.set_language(language)
    let start_time = c_clock()
    let code = utf8(
      "[\"ok\", 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]",
    )
    let tree = parser.parse_with_options(
      (offset, _) => {
        if offset >= code.length() {
          b""[:]
        } else {
          code[offset:]
        }
      },
      options=@treesitter.ParseOptions::new(progress_callback=_ => {
        if elapsed_micros(start_time) > 5L {
          Break
        } else {
          Continue
        }
      }),
    )
    assert_true(tree is None)

    // Without calling reset, the parser continues from where it left off, so
    // it does not see the changes to the beginning of the source code.
    let tree = parse(
      parser, "[null, 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]",
    )
    assert_eq(
      tree.root_node().named_child(0).unwrap().named_child(0).unwrap().kind(),
      "string",
    )
    let start_time = c_clock()
    let tree = parser.parse_with_options(
      (offset, _) => {
        if offset >= code.length() {
          b""[:]
        } else {
          code[offset:]
        }
      },
      options=@treesitter.ParseOptions::new(progress_callback=_ => {
        if elapsed_micros(start_time) > 5L {
          Break
        } else {
          Continue
        }
      }),
    )
    assert_true(tree is None)

    // By calling reset, we force the parser to start over from scratch so
    // that it sees the changes to the beginning of the source code.
    parser.reset()
    let tree = parse(
      parser, "[null, 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]",
    )
    assert_eq(
      tree.root_node().named_child(0).unwrap().named_child(0).unwrap().kind(),
      "null",
    )
  })
}

///|
async test "parsing_with_a_timeout_and_implicit_reset" {
  guard get_parsing_language("javascript") is Some(javascript) else { return }
  guard get_parsing_language("json") is Some(json) else { return }
  retry(10, () => {
    let parser = @treesitter.Parser::new()
    parser.set_language(javascript)
    let code = utf8(
      "[\"ok\", 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]",
    )
    let start_time = c_clock()
    let tree = parser.parse_with_options(
      (offset, _) => {
        if offset >= code.length() {
          b""[:]
        } else {
          code[offset:]
        }
      },
      options=@treesitter.ParseOptions::new(progress_callback=_ => {
        if elapsed_micros(start_time) > 5L {
          Break
        } else {
          Continue
        }
      }),
    )
    assert_true(tree is None)

    // Changing the parser's language implicitly resets, discarding
    // the previous partial parse.
    parser.set_language(json)
    let tree = parse(
      parser, "[null, 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]",
    )
    assert_eq(
      tree.root_node().named_child(0).unwrap().named_child(0).unwrap().kind(),
      "null",
    )
  })
}

///|
async test "parsing_with_timeout_and_no_completion" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  retry(10, () => {
    let parser = @treesitter.Parser::new()
    parser.set_language(language)
    let code = utf8(
      "[\"ok\", 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]",
    )
    let start_time = c_clock()
    let tree = parser.parse_with_options(
      (offset, _) => {
        if offset >= code.length() {
          b""[:]
        } else {
          code[offset:]
        }
      },
      options=@treesitter.ParseOptions::new(progress_callback=_ => {
        if elapsed_micros(start_time) > 5L {
          Break
        } else {
          Continue
        }
      }),
    )
    assert_true(tree is None)

    // drop the parser when it has an unfinished parse
  })
}

///|
async test "parsing_with_timeout_during_balancing" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let function_count = 100
  let code = utf8("function() {}\n".repeat(function_count))
  let mut current_byte_offset = 0
  let mut in_balancing = false
  let read = (offset : Int32, _ : @treesitter.Point) => {
    if offset >= code.length() {
      b""[:]
    } else {
      code[offset:]
    }
  }
  let tree = parser.parse_with_options(
    read,
    options=@treesitter.ParseOptions::new(progress_callback=state => {
      // The parser will call the progress_callback during parsing, and at the very end
      // during tree-balancing. For very large trees, this balancing act can take quite
      // some time, so we want to verify that timing out during this operation is
      // possible.
      //
      // We verify this by checking the current byte offset, as this number will *not* be
      // updated during tree balancing. If we see the same offset twice, we know that we
      // are in the balancing phase.
      if state.current_byte_offset() != current_byte_offset {
        current_byte_offset = state.current_byte_offset()
        Continue
      } else {
        in_balancing = true
        Break
      }
    }),
  )
  assert_true(tree is None)
  assert_true(in_balancing)

  // This should not cause an assertion failure.
  parser.reset()
  let tree = parser.parse_with_options(
    read,
    options=@treesitter.ParseOptions::new(progress_callback=state => {
      if state.current_byte_offset() != current_byte_offset {
        current_byte_offset = state.current_byte_offset()
        Continue
      } else {
        in_balancing = true
        Break
      }
    }),
  )
  assert_true(tree is None)
  assert_true(in_balancing)

  // If we resume parsing (implying we didn't call `parser.reset()`), we should be able to
  // finish parsing the tree, continuing from where we left off.
  let offsets_seen = []
  let tree = parser
    .parse_with_options(
      read,
      options=@treesitter.ParseOptions::new(progress_callback=state => {
        // Because we've already finished parsing, we should only be resuming the
        // balancing phase.
        offsets_seen.push(state.current_byte_offset())
        Continue
      }),
    )
    .unwrap()
  for offset in offsets_seen {
    assert_eq(offset, current_byte_offset)
  }
  assert_false(tree.root_node().has_error())
  assert_eq(tree.root_node().child_count(), function_count)
}

///|
async test "parsing_with_timeout_when_error_detected" {
  guard get_parsing_language("json") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)

  // Parse an infinitely-long array, but insert an error after 1000 characters.
  let mut offset = 0
  let erroneous_code = "!,"
  let tree = parser.parse_with_options(
    (i, _) => {
      if i == 0 {
        b"["[:]
      } else if i <= 1000 {
        b"0,"[:]
      } else {
        utf8(erroneous_code)[:]
      }
    },
    options=@treesitter.ParseOptions::new(progress_callback=state => {
      offset = state.current_byte_offset()
      if state.has_error() {
        Break
      } else {
        Continue
      }
    }),
  )

  // The callback is called at the end of parsing, however, what we're asserting here is that
  // parsing ends immediately as the error is detected. This is verified by checking the offset
  // of the last byte processed is the length of the erroneous code we inserted, aka, 1002, or
  // 1000 + the length of the erroneous code.
  assert_eq(offset, 1000 + erroneous_code.length())
  assert_true(tree is None)
}

// Included Ranges

///|
async test "parsing_with_one_included_range" {
  let source_code = "<span>hi</span><script>console.log('sup');</script>"
  guard get_parsing_language("html") is Some(html) else { return }
  guard get_parsing_language("javascript") is Some(javascript) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(html)
  let html_tree = parse(parser, source_code)
  let script_content_node = html_tree
    .root_node()
    .child(1)
    .unwrap()
    .child(1)
    .unwrap()
  assert_eq(script_content_node.kind(), "raw_text")
  assert_eq(parser.included_ranges(), [
    {
      start_byte: 0,
      end_byte: 0x7FFFFFFF, // u32::MAX
      start_point: @treesitter.Point::new(0, 0),
      end_point: @treesitter.Point::new(0x7FFFFFFF, 0x7FFFFFFF),
    },
  ])
  parser.set_included_ranges([script_content_node.range()])
  assert_eq(parser.included_ranges(), [script_content_node.range()])
  parser.set_language(javascript)
  let js_tree = parse(parser, source_code)
  assert_eq(
    js_tree.root_node().to_sexp(),
    "(program (expression_statement (call_expression " +
    "function: (member_expression object: (identifier) property: (property_identifier)) " +
    "arguments: (arguments (string (string_fragment))))))",
  )
  assert_eq(
    js_tree.root_node().start_position(),
    @treesitter.Point::new(0, byte_find(source_code, "console")),
  )
  assert_eq(js_tree.included_ranges(), [script_content_node.range()])
}

///|
async test "parsing_with_multiple_included_ranges" {
  let source_code = "html `<div>Hello, ${name.toUpperCase()}, it's <b>${now()}</b>.</div>`"
  guard get_parsing_language("javascript") is Some(javascript) else { return }
  guard get_parsing_language("html") is Some(html) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(javascript)
  let js_tree = parse(parser, source_code)
  let template_string_node = js_tree
    .root_node()
    .descendant_for_byte_range(
      byte_find(source_code, "`<"),
      byte_find(source_code, ">`"),
    )
    .unwrap()
  assert_eq(template_string_node.kind(), "template_string")
  let open_quote_node = template_string_node.child(0).unwrap()
  let interpolation_node1 = template_string_node.child(2).unwrap()
  let interpolation_node2 = template_string_node.child(4).unwrap()
  let close_quote_node = template_string_node.child(6).unwrap()
  parser.set_language(html)
  let html_ranges : Array[@treesitter.Range] = [
    {
      start_byte: open_quote_node.end_byte(),
      start_point: open_quote_node.end_position(),
      end_byte: interpolation_node1.start_byte(),
      end_point: interpolation_node1.start_position(),
    },
    {
      start_byte: interpolation_node1.end_byte(),
      start_point: interpolation_node1.end_position(),
      end_byte: interpolation_node2.start_byte(),
      end_point: interpolation_node2.start_position(),
    },
    {
      start_byte: interpolation_node2.end_byte(),
      start_point: interpolation_node2.end_position(),
      end_byte: close_quote_node.start_byte(),
      end_point: close_quote_node.start_position(),
    },
  ]
  parser.set_included_ranges(html_ranges)
  let html_tree = parse(parser, source_code)
  assert_eq(
    html_tree.root_node().to_sexp(),
    "(document (element" +
    " (start_tag (tag_name))" +
    " (text)" +
    " (element (start_tag (tag_name)) (end_tag (tag_name)))" +
    " (text)" +
    " (end_tag (tag_name))))",
  )
  assert_eq(html_tree.included_ranges(), html_ranges)
  let div_element_node = html_tree.root_node().child(0).unwrap()
  let hello_text_node = div_element_node.child(1).unwrap()
  let b_element_node = div_element_node.child(2).unwrap()
  let b_start_tag_node = b_element_node.child(0).unwrap()
  let b_end_tag_node = b_element_node.child(1).unwrap()
  assert_eq(hello_text_node.kind(), "text")
  assert_eq(hello_text_node.start_byte(), byte_find(source_code, "Hello"))
  assert_eq(hello_text_node.end_byte(), byte_find(source_code, " <b>"))
  assert_eq(b_start_tag_node.kind(), "start_tag")
  assert_eq(b_start_tag_node.start_byte(), byte_find(source_code, "<b>"))
  assert_eq(b_start_tag_node.end_byte(), byte_find(source_code, "${now()}"))
  assert_eq(b_end_tag_node.kind(), "end_tag")
  assert_eq(b_end_tag_node.start_byte(), byte_find(source_code, "</b>"))
  assert_eq(b_end_tag_node.end_byte(), byte_find(source_code, ".</div>"))
}

///|
async test "parsing_with_included_range_containing_mismatched_positions" {
  let source_code = "<div>test</div>{_ignore_this_part_}"
  guard get_parsing_language("html") is Some(html) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(html)
  let end_byte = byte_find(source_code, "{_ignore_this_part_")
  let range_to_parse : @treesitter.Range = {
    start_byte: 0,
    start_point: { row: 10, column: 12, },
    end_byte,
    end_point: { row: 10, column: 12 + end_byte, },
  }
  parser.set_included_ranges([range_to_parse])
  let html_tree = parser
    .parse_with_options(chunked_input(source_code, 3))
    .unwrap()
  assert_eq(html_tree.root_node().range(), range_to_parse)
  assert_eq(
    html_tree.root_node().to_sexp(),
    "(document (element (start_tag (tag_name)) (text) (end_tag (tag_name))))",
  )
}

///|
test "parsing_error_in_invalid_included_ranges" {
  let parser = @treesitter.Parser::new()

  // Ranges are not ordered
  try
    parser.set_included_ranges([
      {
        start_byte: 23,
        end_byte: 29,
        start_point: @treesitter.Point::new(0, 23),
        end_point: @treesitter.Point::new(0, 29),
      },
      {
        start_byte: 0,
        end_byte: 5,
        start_point: @treesitter.Point::new(0, 0),
        end_point: @treesitter.Point::new(0, 5),
      },
      {
        start_byte: 50,
        end_byte: 60,
        start_point: @treesitter.Point::new(0, 50),
        end_point: @treesitter.Point::new(0, 60),
      },
    ])
  catch {
    error => assert_eq(error, IncludedRangesError(1))
  } noraise {
    _ => fail("expected an error")
  }

  // Range ends before it starts
  try
    parser.set_included_ranges([
      {
        start_byte: 10,
        end_byte: 5,
        start_point: @treesitter.Point::new(0, 10),
        end_point: @treesitter.Point::new(0, 5),
      },
    ])
  catch {
    error => assert_eq(error, IncludedRangesError(0))
  } noraise {
    _ => fail("expected an error")
  }
}

///|
async test "parsing_utf16_code_with_errors_at_the_end_of_an_included_range" {
  let source_code = "<script>a.</script>"
  let utf16_source_code = utf16(source_code)
  let start_byte = 2 * byte_find(source_code, "a.")
  let end_byte = 2 * byte_find(source_code, "</script>")
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  parser.set_included_ranges([
    {
      start_byte,
      end_byte,
      start_point: @treesitter.Point::new(0, start_byte),
      end_point: @treesitter.Point::new(0, end_byte),
    },
  ])
  let tree = parser.parse_utf16_le(utf16_source_code).unwrap()
  assert_eq(tree.root_node().to_sexp(), "(program (ERROR (identifier)))")
}

///|
async test "parsing_with_external_scanner_that_uses_included_range_boundaries" {
  let source_code = "a <%= b() %> c <% d() %>"
  let range1_start_byte = byte_find(source_code, " b() ")
  let range1_end_byte = range1_start_byte + " b() ".length()
  let range2_start_byte = byte_find(source_code, " d() ")
  let range2_end_byte = range2_start_byte + " d() ".length()
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  parser.set_included_ranges([
    {
      start_byte: range1_start_byte,
      end_byte: range1_end_byte,
      start_point: @treesitter.Point::new(0, range1_start_byte),
      end_point: @treesitter.Point::new(0, range1_end_byte),
    },
    {
      start_byte: range2_start_byte,
      end_byte: range2_end_byte,
      start_point: @treesitter.Point::new(0, range2_start_byte),
      end_point: @treesitter.Point::new(0, range2_end_byte),
    },
  ])
  let tree = parse(parser, source_code)
  let root = tree.root_node()
  let statement1 = root.child(0).unwrap()
  let statement2 = root.child(1).unwrap()
  assert_eq(
    root.to_sexp(),
    "(program" +
    " (expression_statement (call_expression function: (identifier) arguments: (arguments)))" +
    " (expression_statement (call_expression function: (identifier) arguments: (arguments))))",
  )
  assert_eq(statement1.start_byte(), byte_find(source_code, "b()"))
  assert_eq(statement1.end_byte(), byte_find(source_code, " %> c"))
  assert_eq(statement2.start_byte(), byte_find(source_code, "d()"))
  assert_eq(statement2.end_byte(), source_code.length() - " %>".length())
}

///|
async test "parsing_with_a_newly_excluded_range" {
  let mut source_code = "<div><span><%= something %></span></div>"

  // Parse HTML including the template directive, which will cause an error
  guard get_parsing_language("html") is Some(html) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(html)
  let first_tree = parser
    .parse_with_options(chunked_input(source_code, 3))
    .unwrap()

  // Insert code at the beginning of the document.
  let prefix = "a very very long line of plain text. "
  first_tree.edit({
    start_byte: 0,
    old_end_byte: 0,
    new_end_byte: prefix.length(),
    start_position: @treesitter.Point::new(0, 0),
    old_end_position: @treesitter.Point::new(0, 0),
    new_end_position: @treesitter.Point::new(0, prefix.length()),
  })
  source_code = prefix + source_code

  // Parse the HTML again, this time *excluding* the template directive
  // (which has moved since the previous parse).
  let directive_start = byte_find(source_code, "<%=")
  let directive_end = byte_find(source_code, "</span>")
  let source_code_end = source_code.length()
  parser.set_included_ranges([
    {
      start_byte: 0,
      end_byte: directive_start,
      start_point: @treesitter.Point::new(0, 0),
      end_point: @treesitter.Point::new(0, directive_start),
    },
    {
      start_byte: directive_end,
      end_byte: source_code_end,
      start_point: @treesitter.Point::new(0, directive_end),
      end_point: @treesitter.Point::new(0, source_code_end),
    },
  ])
  let tree = parser
    .parse_with_options(chunked_input(source_code, 3), old_tree=first_tree)
    .unwrap()
  assert_eq(
    tree.root_node().to_sexp(),
    "(document (text) (element" +
    " (start_tag (tag_name))" +
    " (element (start_tag (tag_name)) (end_tag (tag_name)))" +
    " (end_tag (tag_name))))",
  )
  assert_eq(tree.changed_ranges(first_tree), [
    // The first range that has changed syntax is the range of the newly-inserted text.
    {
      start_byte: 0,
      end_byte: prefix.length(),
      start_point: @treesitter.Point::new(0, 0),
      end_point: @treesitter.Point::new(0, prefix.length()),
    },
    // Even though no edits were applied to the outer `div` element,
    // its contents have changed syntax because a range of text that
    // was previously included is now excluded.
    {
      start_byte: directive_start,
      end_byte: directive_end,
      start_point: @treesitter.Point::new(0, directive_start),
      end_point: @treesitter.Point::new(0, directive_end),
    },
  ])
}

///|
async test "parsing_with_a_newly_included_range" {
  let source_code = "<div><%= foo() %></div><span><%= bar() %></span><%= baz() %>"
  let range1_start = byte_find(source_code, " foo")
  let range2_start = byte_find(source_code, " bar")
  let range3_start = byte_find(source_code, " baz")
  let range1_end = range1_start + 7
  let range2_end = range2_start + 7
  let range3_end = range3_start + 7

  // Parse only the first code directive as JavaScript
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  parser.set_included_ranges([simple_range(range1_start, range1_end)])
  let tree = parser.parse_with_options(chunked_input(source_code, 3)).unwrap()
  assert_eq(
    tree.root_node().to_sexp(),
    "(program" +
    " (expression_statement (call_expression function: (identifier) arguments: (arguments))))",
  )

  // Parse both the first and third code directives as JavaScript, using the old tree as a
  // reference.
  parser.set_included_ranges([
    simple_range(range1_start, range1_end),
    simple_range(range3_start, range3_end),
  ])
  let tree2 = parser
    .parse_with_options(chunked_input(source_code, 3), old_tree=tree)
    .unwrap()
  assert_eq(
    tree2.root_node().to_sexp(),
    "(program" +
    " (expression_statement (call_expression function: (identifier) arguments: (arguments)))" +
    " (expression_statement (call_expression function: (identifier) arguments: (arguments))))",
  )
  assert_eq(tree2.changed_ranges(tree), [simple_range(range1_end, range3_end)])

  // Parse all three code directives as JavaScript, using the old tree as a
  // reference.
  parser.set_included_ranges([
    simple_range(range1_start, range1_end),
    simple_range(range2_start, range2_end),
    simple_range(range3_start, range3_end),
  ])
  let tree3 = parser.parse(utf8(source_code), old_tree=tree).unwrap()
  assert_eq(
    tree3.root_node().to_sexp(),
    "(program" +
    " (expression_statement (call_expression function: (identifier) arguments: (arguments)))" +
    " (expression_statement (call_expression function: (identifier) arguments: (arguments)))" +
    " (expression_statement (call_expression function: (identifier) arguments: (arguments))))",
  )
  assert_eq(tree3.changed_ranges(tree2), [
    simple_range(range2_start + 1, range2_end - 1),
  ])
}

///|
test "parsing_with_included_ranges_and_missing_tokens" {
  let (parser_name, parser_code) = generate_parser(
    (
      #|{
      #|            "name": "test_leading_missing_token",
      #|            "rules": {
      #|                "program": {
      #|                    "type": "SEQ",
      #|                    "members": [
      #|                        {"type": "SYMBOL", "name": "A"},
      #|                        {"type": "SYMBOL", "name": "b"},
      #|                        {"type": "SYMBOL", "name": "c"},
      #|                        {"type": "SYMBOL", "name": "A"},
      #|                        {"type": "SYMBOL", "name": "b"},
      #|                        {"type": "SYMBOL", "name": "c"}
      #|                    ]
      #|                },
      #|                "A": {"type": "SYMBOL", "name": "a"},
      #|                "a": {"type": "STRING", "value": "a"},
      #|                "b": {"type": "STRING", "value": "b"},
      #|                "c": {"type": "STRING", "value": "c"}
      #|            }
      #|        }
    ),
  )
  let parser = @treesitter.Parser::new()
  parser.set_language(get_test_language(parser_name, parser_code, None))

  // There's a missing `a` token at the beginning of the code. It must be inserted
  // at the beginning of the first included range, not at {0, 0}.
  let source_code = "__bc__bc__"
  parser.set_included_ranges([
    {
      start_byte: 2,
      end_byte: 4,
      start_point: @treesitter.Point::new(0, 2),
      end_point: @treesitter.Point::new(0, 4),
    },
    {
      start_byte: 6,
      end_byte: 8,
      start_point: @treesitter.Point::new(0, 6),
      end_point: @treesitter.Point::new(0, 8),
    },
  ])
  let tree = parse(parser, source_code)
  let root = tree.root_node()
  assert_eq(
    root.to_sexp(),
    "(program (A (MISSING a)) (b) (c) (A (MISSING a)) (b) (c))",
  )
  assert_eq(root.start_byte(), 2)
  assert_eq(root.child(3).unwrap().start_byte(), 4)
}

///|
test "grammars_that_can_hang_on_eof" {
  let (parser_name, parser_code) = generate_parser(
    (
      #|
      #|        {
      #|            "name": "test_single_null_char_regex",
      #|            "rules": {
      #|                "source_file": {
      #|                    "type": "SEQ",
      #|                    "members": [
      #|                        { "type": "STRING", "value": "\"" },
      #|                        { "type": "PATTERN", "value": "[\\x00]*" },
      #|                        { "type": "STRING", "value": "\"" }
      #|                    ]
      #|                }
      #|            },
      #|            "extras": [ { "type": "PATTERN", "value": "\\s" } ]
      #|        }
      #|
    ),
  )
  let parser = @treesitter.Parser::new()
  parser.set_language(get_test_language(parser_name, parser_code, None))
  ignore(parse(parser, "\""))
  let (parser_name, parser_code) = generate_parser(
    (
      #|
      #|        {
      #|            "name": "test_null_char_with_next_char_regex",
      #|            "rules": {
      #|                "source_file": {
      #|                    "type": "SEQ",
      #|                    "members": [
      #|                        { "type": "STRING", "value": "\"" },
      #|                        { "type": "PATTERN", "value": "[\\x00-\\x01]*" },
      #|                        { "type": "STRING", "value": "\"" }
      #|                    ]
      #|                }
      #|            },
      #|            "extras": [ { "type": "PATTERN", "value": "\\s" } ]
      #|        }
      #|
    ),
  )
  parser.set_language(get_test_language(parser_name, parser_code, None))
  ignore(parse(parser, "\""))
  let (parser_name, parser_code) = generate_parser(
    (
      #|
      #|        {
      #|            "name": "test_null_char_with_range_regex",
      #|            "rules": {
      #|                "source_file": {
      #|                    "type": "SEQ",
      #|                    "members": [
      #|                        { "type": "STRING", "value": "\"" },
      #|                        { "type": "PATTERN", "value": "[\\x00-\\x7F]*" },
      #|                        { "type": "STRING", "value": "\"" }
      #|                    ]
      #|                }
      #|            },
      #|            "extras": [ { "type": "PATTERN", "value": "\\s" } ]
      #|        }
      #|
    ),
  )
  parser.set_language(get_test_language(parser_name, parser_code, None))
  ignore(parse(parser, "\""))
}

///|
async test "parse_stack_recursive_merge_error_cost_calculation_bug" {
  let source_code =
    #|
    #|fn main() {
    #|  if n == 1 {
    #|  } else if n == 2 {
    #|  } else {
    #|  }
    #|}
    #|
    #|let y = if x == 5 { 10 } else { 15 };
    #|
    #|if foo && bar {}
    #|
    #|if foo && bar || baz {}
    #|
  guard get_parsing_language("rust") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source_code)
  let edit = edit(60, 63, "")
  let input = utf8(source_code).to_array()
  ignore(@cli_test.perform_edit(tree, input, edit))
  ignore(parser.parse(Bytes::from_array(input), old_tree=tree).unwrap())
}

///|
async test "parsing_with_scanner_logging" {
  let parser = @treesitter.Parser::new()
  guard get_test_fixture_language("external_tokens") is Some(language) else {
    return
  }
  parser.set_language(language)
  let mut found = false
  parser.set_logger(
    Some((log_type, message) => {
      if log_type == Lex && message == "Found a percent string" {
        found = true
      }
    }),
  )
  let source_code = "x + %(sup (external) scanner?)"
  ignore(parse(parser, source_code))
  assert_true(found)
}

///|
async test "parsing_get_column_at_eof" {
  let parser = @treesitter.Parser::new()
  guard get_test_fixture_language("get_col_eof") is Some(language) else {
    return
  }
  parser.set_language(language)
  ignore(parse(parser, "a"))
}

///|
async test "parsing_by_halting_at_offset" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let source_code = utf8("function foo() { return 1; }".repeat(1000))
  let seen_byte_offsets = []
  ignore(
    parser
    .parse_with_options(
      (offset, _) => {
        if offset < source_code.length() {
          source_code[offset:]
        } else {
          b""[:]
        }
      },
      options=@treesitter.ParseOptions::new(progress_callback=p => {
        seen_byte_offsets.push(p.current_byte_offset())
        Continue
      }),
    )
    .unwrap(),
  )
  assert_true(seen_byte_offsets.length() > 100)
}

///|
/// The expected tree of the `test_decode_*` tests.
let decode_expected_sexp : String = "(source_file (function_item (visibility_modifier) name: (identifier) parameters: (parameters) body: (block (expression_statement (macro_invocation macro: (identifier) (token_tree (string_literal (string_content))))))))"

///|
async test "decode_utf32" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  // `u32cstr!` text in native (little-endian) byte order.
  let utf32_text : Array[Byte] = []
  for c in "pub fn foo() { println!(\"€50\"); }" {
    let code_point = c.to_int()
    utf32_text.push((code_point & 0xFF).to_byte())
    utf32_text.push(((code_point >> 8) & 0xFF).to_byte())
    utf32_text.push(((code_point >> 16) & 0xFF).to_byte())
    utf32_text.push(((code_point >> 24) & 0xFF).to_byte())
  }
  let utf32_text = Bytes::from_array(utf32_text)
  // `U32Decoder` (little-endian host)
  let decode = (bytes : BytesView) => {
    if bytes.length() >= 4 {
      (
        bytes[0].to_int() |
        (bytes[1].to_int() << 8) |
        (bytes[2].to_int() << 16) |
        (bytes[3].to_int() << 24),
        4,
      )
    } else {
      (0, 0)
    }
  }
  let tree = parser
    .parse_custom_encoding(decode, (offset, _) => {
      if offset < utf32_text.length() {
        utf32_text[offset:]
      } else {
        b""[:]
      }
    })
    .unwrap()
  assert_eq(tree.root_node().to_sexp(), decode_expected_sexp)
}

///|
/// A single-byte decoder (`Cp1252Decoder` and `MacintoshDecoder`).
fn single_byte_decode(bytes : BytesView) -> (Int32, Int32) {
  if !bytes.is_empty() {
    let byte = bytes[0]
    (byte.to_int(), 1)
  } else {
    (0, 0)
  }
}

///|
/// The ASCII text of the `test_decode_*` tests with `€` encoded as `euro`.
fn encode_single_byte(euro : Byte) -> Bytes {
  let result : Array[Byte] = []
  for c in "pub fn foo() { println!(\"€50\"); }" {
    if c == '€' {
      result.push(euro)
    } else {
      result.push(c.to_int().to_byte())
    }
  }
  Bytes::from_array(result)
}

///|
async test "decode_cp1252" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  // `WINDOWS_1252.encode(...)`: `€` is 0x80.
  let windows_1252_text = encode_single_byte(0x80)
  let tree = parser
    .parse_custom_encoding(single_byte_decode, (offset, _) => {
      windows_1252_text[offset:]
    })
    .unwrap()
  assert_eq(tree.root_node().to_sexp(), decode_expected_sexp)
}

///|
async test "decode_macintosh" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  // `MACINTOSH.encode(...)`: `€` is 0xDB.
  let macintosh_text = encode_single_byte(0xDB)
  let tree = parser
    .parse_custom_encoding(single_byte_decode, (offset, _) => {
      macintosh_text[offset:]
    })
    .unwrap()
  assert_eq(tree.root_node().to_sexp(), decode_expected_sexp)
}

///|
async test "decode_utf24le" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let utf24le_text : Array[Byte] = []
  for c in "pub fn foo() { println!(\"€50\"); }" {
    let code_point = c.to_int()
    utf24le_text.push((code_point & 0xFF).to_byte())
    utf24le_text.push(((code_point >> 8) & 0xFF).to_byte())
    utf24le_text.push(((code_point >> 16) & 0xFF).to_byte())
  }
  let utf24le_text = Bytes::from_array(utf24le_text)
  // `Utf24LeDecoder`
  let decode = (bytes : BytesView) => {
    if bytes.length() >= 3 {
      (
        bytes[0].to_int() | (bytes[1].to_int() << 8) | (bytes[2].to_int() << 16),
        3,
      )
    } else {
      (0, 0)
    }
  }
  let tree = parser
    .parse_custom_encoding(decode, (offset, _) => utf24le_text[offset:])
    .unwrap()
  assert_eq(tree.root_node().to_sexp(), decode_expected_sexp)
}

///|
/// Whether generating a parser for `grammar_json` fails.
fn generate_parser_fails(grammar_json : String) -> Bool {
  try generate_parser(grammar_json) catch {
    _ => true
  } noraise {
    _ => false
  }
}

///|
test "grammars_that_should_not_compile" {
  assert_true(
    generate_parser_fails(
      (
        #|
        #|        {
        #|            "name": "issue_1111",
        #|            "rules": {
        #|                "source_file": { "type": "STRING", "value": "" }
        #|            },
        #|        }
        #|
      ),
    ),
  )
  assert_true(
    generate_parser_fails(
      (
        #|
        #|        {
        #|            "name": "issue_1271",
        #|            "rules": {
        #|                "source_file": { "type": "SYMBOL", "name": "identifier" },
        #|                "identifier": {
        #|                    "type": "TOKEN",
        #|                    "content": {
        #|                        "type": "REPEAT",
        #|                        "content": { "type": "PATTERN", "value": "a" }
        #|                    }
        #|                }
        #|            },
        #|        }
        #|
      ),
    ),
  )
  assert_true(
    generate_parser_fails(
      (
        #|
        #|        {
        #|            "name": "issue_1156_expl_1",
        #|            "rules": {
        #|                "source_file": {
        #|                    "type": "TOKEN",
        #|                    "content": {
        #|                        "type": "REPEAT",
        #|                        "content": { "type": "STRING", "value": "c" }
        #|                    }
        #|                }
        #|            },
        #|        }
        #|
      ),
    ),
  )
  assert_true(
    generate_parser_fails(
      (
        #|
        #|        {
        #|            "name": "issue_1156_expl_2",
        #|            "rules": {
        #|                "source_file": {
        #|                    "type": "TOKEN",
        #|                    "content": {
        #|                        "type": "CHOICE",
        #|                        "members": [
        #|                            { "type": "STRING", "value": "e" },
        #|                            { "type": "BLANK" }
        #|                        ]
        #|                    }
        #|                }
        #|            },
        #|        }
        #|
      ),
    ),
  )
  assert_true(
    generate_parser_fails(
      (
        #|
        #|        {
        #|            "name": "issue_1156_expl_3",
        #|            "rules": {
        #|                "source_file": {
        #|                    "type": "IMMEDIATE_TOKEN",
        #|                    "content": {
        #|                        "type": "REPEAT",
        #|                        "content": { "type": "STRING", "value": "p" }
        #|                    }
        #|                }
        #|            },
        #|        }
        #|
      ),
    ),
  )
  assert_true(
    generate_parser_fails(
      (
        #|
        #|        {
        #|            "name": "issue_1156_expl_4",
        #|            "rules": {
        #|                "source_file": {
        #|                    "type": "IMMEDIATE_TOKEN",
        #|                    "content": {
        #|                        "type": "CHOICE",
        #|                        "members": [
        #|                            { "type": "STRING", "value": "r" },
        #|                            { "type": "BLANK" }
        #|                        ]
        #|                    }
        #|                }
        #|            },
        #|        }
        #|
      ),
    ),
  )
}

///|
async test "parse_options_reborrow" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let mut parse_count = 0
  let callback = (_ : @treesitter.ParseState) => {
    parse_count += 1
    @treesitter.ControlFlow::Continue
  }
  let options = @treesitter.ParseOptions::new(progress_callback=callback)
  let text1 = utf8("fn first() {}".repeat(20))
  let text2 = utf8("fn second() {}".repeat(20))
  let tree1 = parser
    .parse_with_options(
      (offset, _) => {
        if offset >= text1.length() {
          b""[:]
        } else {
          text1[offset:]
        }
      },
      options~,
    )
    .unwrap()
  assert_eq(tree1.root_node().child(0).unwrap().kind(), "function_item")
  let tree2 = parser
    .parse_with_options(
      (offset, _) => {
        if offset >= text2.length() {
          b""[:]
        } else {
          text2[offset:]
        }
      },
      options~,
    )
    .unwrap()
  assert_eq(tree2.root_node().child(0).unwrap().kind(), "function_item")
  assert_true(parse_count > 0)
}

///|
async test "error_recovery_checks_versions_after_failed_missing_token_reduction" {
  let parser = @treesitter.Parser::new()
  guard get_test_fixture_language("error_recovery_loop") is Some(language) else {
    return
  }
  parser.set_language(language)
  let input = b"<<a/a>{[:aaaaa"
  let mut progress_checks = 0
  let tree = parser
    .parse_with_options(
      (offset, _) => input[offset:],
      options=@treesitter.ParseOptions::new(progress_callback=_ => {
        progress_checks += 1
        if progress_checks > 100 {
          // error recovery should finish without repeating the same stack versions
          Break
        } else {
          Continue
        }
      }),
    )
    .unwrap()
  assert_eq(tree.root_node().end_byte(), input.length())
}

///|
async test "parsing_after_balancing_tree_that_depends_on_column" {
  let parser = @treesitter.Parser::new()
  guard get_test_fixture_language("depends_on_column_repetition")
    is Some(language) else {
    return
  }
  parser.set_language(language)
  let code = utf8("\nax\na").to_array()
  let tree = parser.parse(Bytes::from_array(code)).unwrap()
  assert_eq(
    tree.root_node().to_sexp(),
    "(document (newline) (word) (tail) (newline) (word))",
  )
  ignore(@cli_test.perform_edit(tree, code, edit(2, 0, "\n")))
  let incremental = parser
    .parse(Bytes::from_array(code), old_tree=tree)
    .unwrap()
  let fresh = parser.parse(Bytes::from_array(code)).unwrap()
  assert_eq(
    fresh.root_node().to_sexp(),
    "(document (newline) (word) (newline) (head) (newline) (word))",
  )
  assert_eq(incremental.root_node().to_sexp(), fresh.root_node().to_sexp())
}

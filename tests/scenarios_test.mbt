// Ports of tree_test.rs and parser_test.rs tests, adapted to the C and JSON
// grammars (whose parsers need no external scanner). Each scenario prints a
// transcript; the expected transcripts were produced by the same scenarios
// written against the Rust binding (lib.rs) of the pinned upstream checkout,
// with the C library and the upstream-generated parsers.

///|
/// Rust's `{:?}` of a `&str`.
fn rust_debug_str(s : String) -> String {
  let sb = StringBuilder()
  sb.write_char('"')
  for c in s {
    match c {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      c => sb.write_char(c)
    }
  }
  sb.write_char('"')
  sb.to_string()
}

///|
/// A `usize` as upstream prints it (`Int::max_value()` stands for
/// `u32::MAX`).
fn usize(x : Int32) -> String {
  if x == 0x7FFFFFFF {
    "4294967295"
  } else {
    x.to_string()
  }
}

///|
fn debug_point(p : @treesitter.Point) -> String {
  "Point { row: \{usize(p.row)}, column: \{usize(p.column)} }"
}

///|
fn debug_option_int(x : Int32?) -> String {
  match x {
    Some(x) => "Some(\{x})"
    None => "None"
  }
}

///|
fn node_line(out : StringBuilder, label : String, n : @treesitter.Node) -> Unit {
  out.write_string(
    "\{label} \{n.kind()} \{n.start_byte()}..\{n.end_byte()} \{n.start_position()}-\{n.end_position()} changes=\{n.has_changes()}\n",
  )
}

///|
async test "tree_edit (c)" {
  guard get_parsing_language("c") is Some(c) else { return }
  let out = StringBuilder()
  let parser = parser_for(c)
  let tree = parse(parser, "  abc  <<=  def;")
  out.write_string("\{tree.root_node().to_sexp()}\n")
  for
    e in [
      (1, 1, 2),
      (1, 4, 5),
      (2, 2, 4),
      (1, 11, 4),
      (15, 15, 16),
      (3, 90, 4),
      (6, 90, 8),
    ] {
    let (s, o, n) = e
    let tree = tree.clone()
    tree.edit({
      start_byte: s,
      old_end_byte: o,
      new_end_byte: n,
      start_position: @treesitter.Point::new(0, s),
      old_end_position: @treesitter.Point::new(0, o),
      new_end_position: @treesitter.Point::new(0, n),
    })
    out.write_string("edit \{s} \{o} \{n}\n")
    let expr = tree.root_node().child(0).unwrap().child(0).unwrap()
    node_line(out, " expr", expr)
    for i in 0..<expr.child_count() {
      node_line(out, " child", expr.child(i).unwrap())
    }
  }
  inspect(
    out,
    content=(
      #|(translation_unit (expression_statement (assignment_expression left: (identifier) right: (identifier))))
      #|edit 1 1 2
      #| expr assignment_expression 3..16 (0, 3)-(0, 16) changes=true
      #| child identifier 3..6 (0, 3)-(0, 6) changes=true
      #| child <<= 8..11 (0, 8)-(0, 11) changes=false
      #| child identifier 13..16 (0, 13)-(0, 16) changes=false
      #|edit 1 4 5
      #| expr assignment_expression 5..16 (0, 5)-(0, 16) changes=true
      #| child identifier 5..6 (0, 5)-(0, 6) changes=true
      #| child <<= 8..11 (0, 8)-(0, 11) changes=false
      #| child identifier 13..16 (0, 13)-(0, 16) changes=false
      #|edit 2 2 4
      #| expr assignment_expression 4..17 (0, 4)-(0, 17) changes=true
      #| child identifier 4..7 (0, 4)-(0, 7) changes=true
      #| child <<= 9..12 (0, 9)-(0, 12) changes=false
      #| child identifier 14..17 (0, 14)-(0, 17) changes=false
      #|edit 1 11 4
      #| expr assignment_expression 4..8 (0, 4)-(0, 8) changes=true
      #| child identifier 4..4 (0, 4)-(0, 4) changes=true
      #| child <<= 4..4 (0, 4)-(0, 4) changes=true
      #| child identifier 5..8 (0, 5)-(0, 8) changes=true
      #|edit 15 15 16
      #| expr assignment_expression 2..16 (0, 2)-(0, 16) changes=true
      #| child identifier 2..5 (0, 2)-(0, 5) changes=false
      #| child <<= 7..10 (0, 7)-(0, 10) changes=false
      #| child identifier 12..16 (0, 12)-(0, 16) changes=true
      #|edit 3 90 4
      #| expr assignment_expression 2..4 (0, 2)-(0, 4) changes=true
      #| child identifier 2..4 (0, 2)-(0, 4) changes=true
      #| child <<= 4..4 (0, 4)-(0, 4) changes=true
      #| child identifier 4..4 (0, 4)-(0, 4) changes=true
      #|edit 6 90 8
      #| expr assignment_expression 2..8 (0, 2)-(0, 8) changes=true
      #| child identifier 2..5 (0, 2)-(0, 5) changes=false
      #| child <<= 8..8 (0, 8)-(0, 8) changes=true
      #| child identifier 8..8 (0, 8)-(0, 8) changes=true
      #|
    ),
  )
}

///|
async test "tree_cursor (c)" {
  guard get_parsing_language("c") is Some(c) else { return }
  let out = StringBuilder()
  let source = "\nstruct Stuff {\n    int a;\n    B /* x */ b;\n};\n// done\n"
  let tree = parse(parser_for(c), source)
  let cursor = tree.walk()
  // A pre-order walk.
  let mut visited_children = false
  for ;; {
    if !visited_children {
      let n = cursor.node()
      let field = match cursor.field_name() {
        Some(name) => "Some(\{rust_debug_str(name)})"
        None => "None"
      }
      out.write_string(
        "\{n.kind()} field=\{field} depth=\{cursor.depth()} index=\{cursor.descendant_index()} named=\{n.is_named()} at=\{n.start_position()}\n",
      )
      if !cursor.goto_first_child() {
        visited_children = true
      }
    } else if cursor.goto_next_sibling() {
      visited_children = false
    } else if !cursor.goto_parent() {
      break
    }
  }
  // Walking backwards from the last child of the field list.
  let cursor = tree.walk()
  ignore(cursor.goto_first_child())
  ignore(cursor.goto_first_child())
  ignore(cursor.goto_next_sibling())
  ignore(cursor.goto_next_sibling())
  out.write_string("at \{cursor.node().kind()}\n")
  out.write_string("last \{cursor.goto_last_child()}\n")
  for ;; {
    out.write_string(
      "  \{cursor.node().kind()} \{cursor.node().start_position()}\n",
    )
    if !cursor.goto_previous_sibling() {
      break
    }
  }
  let copy = tree.walk()
  copy.reset_to(cursor)
  out.write_string("copy \{copy.node().kind()}\n")
  out.write_string("parent \{copy.goto_parent()} \{copy.node().kind()}\n")
  out.write_string("parent \{copy.goto_parent()} \{copy.node().kind()}\n")
  let c2 = tree.walk()
  out.write_string("last \{c2.goto_last_child()} \{c2.node().kind()}\n")
  out.write_string("prev \{c2.goto_previous_sibling()} \{c2.node().kind()}\n")
  out.write_string("prev \{c2.goto_previous_sibling()} \{c2.node().kind()}\n")
  let clone = c2.clone()
  out.write_string("clone \{clone.goto_first_child()} \{clone.node().kind()}\n")
  out.write_string("orig \{c2.node().kind()}\n")
  inspect(
    out,
    content=(
      #|translation_unit field=None depth=0 index=0 named=true at=(1, 0)
      #|struct_specifier field=None depth=1 index=1 named=true at=(1, 0)
      #|struct field=None depth=2 index=2 named=false at=(1, 0)
      #|type_identifier field=Some("name") depth=2 index=3 named=true at=(1, 7)
      #|field_declaration_list field=Some("body") depth=2 index=4 named=true at=(1, 13)
      #|{ field=None depth=3 index=5 named=false at=(1, 13)
      #|field_declaration field=None depth=3 index=6 named=true at=(2, 4)
      #|primitive_type field=Some("type") depth=4 index=7 named=true at=(2, 4)
      #|field_identifier field=Some("declarator") depth=4 index=8 named=true at=(2, 8)
      #|; field=None depth=4 index=9 named=false at=(2, 9)
      #|field_declaration field=None depth=3 index=10 named=true at=(3, 4)
      #|type_identifier field=Some("type") depth=4 index=11 named=true at=(3, 4)
      #|comment field=None depth=4 index=12 named=true at=(3, 6)
      #|field_identifier field=Some("declarator") depth=4 index=13 named=true at=(3, 14)
      #|; field=None depth=4 index=14 named=false at=(3, 15)
      #|} field=None depth=3 index=15 named=false at=(4, 0)
      #|; field=None depth=1 index=16 named=false at=(4, 1)
      #|comment field=None depth=1 index=17 named=true at=(5, 0)
      #|at field_declaration_list
      #|last true
      #|  } (4, 0)
      #|  field_declaration (3, 4)
      #|  field_declaration (2, 4)
      #|  { (1, 13)
      #|copy {
      #|parent true field_declaration_list
      #|parent true struct_specifier
      #|last true comment
      #|prev true ;
      #|prev true struct_specifier
      #|clone true struct
      #|orig struct_specifier
      #|
    ),
  )
}

///|
async test "tree_cursor_child_for_point (json)" {
  guard get_parsing_language("json") is Some(json) else { return }
  let out = StringBuilder()
  let source = "    [\n        1,\n        {\n            \"two\": 3\n        },\n        4, 5, 6\n    ]"
  let tree = parse(parser_for(json), source)
  let c = tree.walk()
  for
    step in [
      "p 7 0", "p 6 7", "p 6 5", "p 7 0", "p 6 6", "p 6 4", "p 0 4", "up", "p 1 0",
      "up", "p 1 10", "up", "p 1 9", "up", "p 5 0", "up", "p 6 0", "up", "p 2 0",
      "b 50", "up", "b 9", "up", "b 999",
    ] {
    let parts = step.split(" ").map(s => s.to_owned()).to_array()
    let num = (i : Int32) => @string.parse_int(parts[i]) catch { _ => -1 }
    let r = match parts[0] {
      "p" =>
        debug_option_int(
          c.goto_first_child_for_point(@treesitter.Point::new(num(1), num(2))),
        )
      "b" => debug_option_int(c.goto_first_child_for_byte(num(1)))
      _ => c.goto_parent().to_string()
    }
    out.write_string(
      "\{step} -> \{r} \{c.node().kind()} \{c.node().start_position()}\n",
    )
  }
  inspect(
    out,
    content=(
      #|p 7 0 -> None document (0, 4)
      #|p 6 7 -> None document (0, 4)
      #|p 6 5 -> None document (0, 4)
      #|p 7 0 -> None document (0, 4)
      #|p 6 6 -> None document (0, 4)
      #|p 6 4 -> Some(0) array (0, 4)
      #|p 0 4 -> Some(0) [ (0, 4)
      #|up -> true array (0, 4)
      #|p 1 0 -> Some(1) number (1, 8)
      #|up -> true array (0, 4)
      #|p 1 10 -> Some(3) object (2, 8)
      #|up -> true array (0, 4)
      #|p 1 9 -> Some(2) , (1, 9)
      #|up -> true array (0, 4)
      #|p 5 0 -> Some(5) number (5, 8)
      #|up -> true array (0, 4)
      #|p 6 0 -> Some(10) ] (6, 4)
      #|up -> true array (0, 4)
      #|p 2 0 -> Some(3) object (2, 8)
      #|b 50 -> Some(2) } (4, 8)
      #|up -> true object (2, 8)
      #|b 9 -> Some(0) { (2, 8)
      #|up -> true object (2, 8)
      #|b 999 -> None object (2, 8)
      #|
    ),
  )
}

///|
async test "get_changed_ranges (json)" {
  guard get_parsing_language("json") is Some(json) else { return }
  let out = StringBuilder()
  let parser = parser_for(json)
  let source = utf8("{\"a\": null}\n").to_array()
  let tree = parser.parse(Bytes::from_array(source)).unwrap()
  out.write_string("\{tree.root_node().to_sexp()}\n")
  let groups : Array[Array[(String, Int32, String)]] = [
    [("ull", 3, "ever"), ("ever", 4, "ull")],
    [("", 0, "\n"), ("\n", 1, "")],
    [
      ("}", 0, ", \"b\": false"),
      (", \"b\"", 0, ", \"c\": 1"),
      (", \"c\": 1", 8, ""),
      (", \"b\": false", 12, ""),
    ],
    [("null", 4, "[1, null]"), ("[1, null]", 9, "null")],
  ]
  for group in groups {
    let mut tree = tree.clone()
    let source = source.copy()
    for edit in group {
      let (needle, deleted, inserted) = edit
      let text = @utf8.decode_lossy(Bytes::from_array(source))
      let position = if needle.is_empty() { 0 } else { find(text, needle) }
      ignore(perform_edit(tree, source, position, deleted, inserted))
      let bytes = Bytes::from_array(source)
      let new_tree = parser.parse(bytes, old_tree=tree).unwrap()
      let ranges = tree.changed_ranges(new_tree)
      out.write_string(
        "\{rust_debug_str(@utf8.decode_lossy(bytes))} -> \{new_tree.root_node().to_sexp()}\n",
      )
      for r in ranges {
        out.write_string(
          "  \{r.start_byte}..\{r.end_byte} \{r.start_point}-\{r.end_point}\n",
        )
      }
      tree = new_tree
    }
  }
  inspect(
    out,
    content=(
      #|(document (object (pair key: (string (string_content)) value: (null))))
      #|"{\"a\": never}\n" -> (document (object (ERROR (string (string_content)) (UNEXPECTED 'e'))))
      #|  1..11 (0, 1)-(0, 11)
      #|"{\"a\": null}\n" -> (document (object (pair key: (string (string_content)) value: (null))))
      #|  1..10 (0, 1)-(0, 10)
      #|"\n{\"a\": null}\n" -> (document (object (pair key: (string (string_content)) value: (null))))
      #|"{\"a\": null}\n" -> (document (object (pair key: (string (string_content)) value: (null))))
      #|"{\"a\": null, \"b\": false}\n" -> (document (object (pair key: (string (string_content)) value: (null)) (pair key: (string (string_content)) value: (false))))
      #|  10..22 (0, 10)-(0, 22)
      #|"{\"a\": null, \"c\": 1, \"b\": false}\n" -> (document (object (pair key: (string (string_content)) value: (null)) (pair key: (string (string_content)) value: (number)) (pair key: (string (string_content)) value: (false))))
      #|  10..18 (0, 10)-(0, 18)
      #|"{\"a\": null, \"b\": false}\n" -> (document (object (pair key: (string (string_content)) value: (null)) (pair key: (string (string_content)) value: (false))))
      #|"{\"a\": null}\n" -> (document (object (pair key: (string (string_content)) value: (null))))
      #|"{\"a\": [1, null]}\n" -> (document (object (pair key: (string (string_content)) value: (array (number) (null)))))
      #|  6..15 (0, 6)-(0, 15)
      #|"{\"a\": null}\n" -> (document (object (pair key: (string (string_content)) value: (null))))
      #|  6..10 (0, 6)-(0, 10)
      #|
    ),
  )
}

///|
async test "included_ranges (json)" {
  guard get_parsing_language("json") is Some(json) else { return }
  let out = StringBuilder()
  let parser = parser_for(json)
  let default_ranges = parser
    .included_ranges()
    .map(r => {
      "(\{usize(r.start_byte)}, \{usize(r.end_byte)}, \{debug_point(r.start_point)}, \{debug_point(r.end_point)})"
    })
  out.write_string("default [\{default_ranges.join(", ")}]\n")
  let source = "abc [1,\n2] def\n[3] ghi"
  let first = find(source, "[")
  let second = source.rev_find("[").unwrap()
  let ranges : Array[@treesitter.Range] = [
    {
      start_byte: first,
      end_byte: first + 6,
      start_point: @treesitter.Point::new(0, first),
      end_point: @treesitter.Point::new(1, 2),
    },
    {
      start_byte: second,
      end_byte: second + 3,
      start_point: @treesitter.Point::new(2, 0),
      end_point: @treesitter.Point::new(2, 3),
    },
  ]
  parser.set_included_ranges(ranges)
  let tree = parse(parser, source)
  out.write_string("\{tree.root_node().to_sexp()}\n")
  node_line(out, "root", tree.root_node())
  let cursor = tree.walk()
  for n in tree.root_node().children(cursor) {
    node_line(out, " child", n)
  }
  let pairs = (rs : Array[@treesitter.Range]) => {
    rs.map(r => "(\{r.start_byte}, \{r.end_byte})").join(", ")
  }
  out.write_string("tree ranges [\{pairs(tree.included_ranges())}]\n")
  out.write_string("parser ranges [\{pairs(parser.included_ranges())}]\n")
  // Editing a tree also edits its included ranges.
  tree.edit({
    start_byte: 2,
    old_end_byte: 5,
    new_end_byte: 3,
    start_position: @treesitter.Point::new(0, 2),
    old_end_position: @treesitter.Point::new(0, 5),
    new_end_position: @treesitter.Point::new(0, 3),
  })
  let edited = tree
    .included_ranges()
    .map(r => {
      "(\{r.start_byte}, \{r.end_byte}, \{debug_point(r.start_point)}, \{debug_point(r.end_point)})"
    })
  out.write_string("edited ranges [\{edited.join(", ")}]\n")
  try parser.set_included_ranges([ranges[1], ranges[0]]) catch {
    IncludedRangesError(i) =>
      out.write_string("error IncludedRangesError(\{i})\n")
  } noraise {
    _ => out.write_string("no error\n")
  }
  parser.set_included_ranges([])
  out.write_string("reset \{parser.included_ranges().length()}\n")
  inspect(
    out,
    content=(
      #|default [(0, 4294967295, Point { row: 0, column: 0 }, Point { row: 4294967295, column: 4294967295 })]
      #|(document (array (number) (number)) (array (number)))
      #|root document 4..18 (0, 4)-(2, 3) changes=false
      #| child array 4..10 (0, 4)-(1, 2) changes=false
      #| child array 15..18 (2, 0)-(2, 3) changes=false
      #|tree ranges [(4, 10), (15, 18)]
      #|parser ranges [(4, 10), (15, 18)]
      #|edited ranges [(2, 8, Point { row: 0, column: 2 }, Point { row: 1, column: 2 }), (13, 16, Point { row: 2, column: 0 }, Point { row: 2, column: 3 })]
      #|error IncludedRangesError(1)
      #|reset 1
      #|
    ),
  )
  // test_parsing_error_in_invalid_included_ranges
  let parser = @treesitter.Parser::new()
  let range = fn(s : Int32, e : Int32) -> @treesitter.Range {
    {
      start_byte: s,
      end_byte: e,
      start_point: @treesitter.Point::new(0, s),
      end_point: @treesitter.Point::new(0, e),
    }
  }
  try
    parser.set_included_ranges([range(23, 29), range(0, 5), range(50, 60)])
  catch {
    e => assert_eq(e, IncludedRangesError(1))
  } noraise {
    _ => fail("expected an error")
  }
  try parser.set_included_ranges([range(10, 5)]) catch {
    e => assert_eq(e, IncludedRangesError(0))
  } noraise {
    _ => fail("expected an error")
  }
}

///|
/// Code units in memory order for big-endian parsing (Rust's `u16::to_be` on
/// a little-endian host).
fn to_be(units : Array[UInt16]) -> Array[UInt16] {
  units.map(u => ((u.to_int() >> 8) | ((u.to_int() & 0xFF) << 8)).to_uint16())
}

///|
fn utf16(s : String) -> Array[UInt16] {
  Array::makei(s.length(), i => s[i])
}

///|
async test "parsing with encodings (json, c)" {
  guard get_parsing_language("json") is Some(json) else { return }
  guard get_parsing_language("c") is Some(c) else { return }
  let out = StringBuilder()
  let parser = parser_for(json)
  // test_parsing_with_custom_utf16le_input / utf16_be_input
  let lines = ["[1, \"€\",", "  {\"😀\": 2}", "]"].map(utf16)
  let newline : Array[UInt16] = ['\n']
  let read_lines = (lines : Array[Array[UInt16]], newline : Array[UInt16]) => {
    (_ : Int32, position : @treesitter.Point) => {
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
    }
  }
  let tree = parser
    .parse_utf16_le_with_options(read_lines(lines, newline))
    .unwrap()
  out.write_string("le \{tree.root_node().to_sexp()}\n")
  let cursor = tree.walk()
  for n in tree.root_node().child(0).unwrap().named_children(cursor) {
    node_line(out, " le", n)
  }
  let tree = parser
    .parse_utf16_be_with_options(read_lines(lines.map(to_be), to_be(newline)))
    .unwrap()
  out.write_string("be \{tree.root_node().to_sexp()}\n")
  // test_parsing_text_with_byte_order_mark
  let tree = parser.parse_utf16_le(utf16("\u{FEFF}[1]")).unwrap()
  out.write_string(
    "bom \{tree.root_node().to_sexp()} \{tree.root_node().start_byte()}\n",
  )
  // test_text_provider_for_vec_utf16_text
  let text = utf16("[\"你好\"]")
  let tree = parser.parse_utf16_le(text).unwrap()
  let s = tree.root_node().child(0).unwrap().named_child(0).unwrap()
  let units = s.utf16_text(text)
  let decoded = String::from_array(
    units.iter().map(u => u.to_int().unsafe_to_char()).to_array(),
  )
  out.write_string("utf16_text \{rust_debug_str(decoded)}\n")
  // test_parsing_invalid_chars_at_eof
  let tree = parser.parse(b"\xdf").unwrap()
  out.write_string("invalid \{tree.root_node().to_sexp()}\n")
  // test_parsing_ends_when_input_callback_returns_empty
  let source = b"[1, 2, 3, 4, 5]"
  let tree = parser
    .parse_with_options((offset, _) => {
      if offset >= 6 {
        b""[:]
      } else {
        source[offset:(offset + 3).min(source.length())]
      }
    })
    .unwrap()
  out.write_string(
    "short \{tree.root_node().to_sexp()} \{tree.root_node().end_byte()}\n",
  )
  // test_decode_utf32 and a single-byte encoding, on C.
  parser.set_language(c)
  let utf32 = Buffer()
  for ch in "int x = \"€50\";" {
    utf32.write_int_le(ch.to_int())
  }
  let utf32 = utf32.to_bytes()
  let tree = parser
    .parse_custom_encoding(
      bytes => {
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
      },
      (offset, _) => {
        if offset < utf32.length() {
          utf32[offset:]
        } else {
          b""[:]
        }
      },
    )
    .unwrap()
  out.write_string(
    "utf32 \{tree.root_node().to_sexp()} \{tree.root_node().end_byte()}\n",
  )
  let latin1 = b"int \xe9 = 1;"
  let tree = parser
    .parse_custom_encoding(
      bytes => if bytes.length() > 0 { (bytes[0].to_int(), 1) } else { (0, 0) },
      (offset, _) => {
        if offset < latin1.length() {
          latin1[offset:]
        } else {
          b""[:]
        }
      },
    )
    .unwrap()
  out.write_string("latin1 \{tree.root_node().to_sexp()}\n")
  inspect(
    out,
    content=(
      #|le (document (array (number) (string (string_content)) (object (pair key: (string (string_content)) value: (number)))))
      #| le number 2..4 (0, 2)-(0, 4) changes=false
      #| le string 8..14 (0, 8)-(0, 14) changes=false
      #| le object 22..40 (1, 4)-(1, 22) changes=false
      #|be (document (array (number) (string (string_content)) (object (pair key: (string (string_content)) value: (number)))))
      #|bom (document (array (number))) 2
      #|utf16_text "\"你好\""
      #|invalid (document (ERROR (UNEXPECTED INVALID)))
      #|short (document (ERROR (number) (number))) 6
      #|utf32 (translation_unit (declaration type: (primitive_type) declarator: (init_declarator declarator: (identifier) value: (string_literal (string_content))))) 56
      #|latin1 (translation_unit (declaration type: (primitive_type) declarator: (init_declarator declarator: (identifier) value: (number_literal))))
      #|
    ),
  )
}

///|
/// `test_parsing_after_editing_beginning_of_code` / `..._end_of_code`, on
/// C: the bytes read by the incremental reparse.
async test "parsing_after_editing (c)" {
  guard get_parsing_language("c") is Some(c) else { return }
  let out = StringBuilder()
  let parser = parser_for(c)
  for
    case in [
      ("123 + 456 * (10 + x);", 3, 0, " || 5"),
      ("x * (100 + abc);", 14, 0, ".d"),
    ] {
    let (code, position, deleted, inserted) = case
    let code = utf8(code).to_array()
    let tree = parser.parse(Bytes::from_array(code)).unwrap()
    out.write_string("\{tree.root_node().to_sexp()}\n")
    ignore(perform_edit(tree, code, position, deleted, inserted))
    let indices : Array[Int32] = []
    let tree2 = parser
      .parse_with_options(
        (i, _) => {
          if i < code.length() {
            match indices.binary_search(i) {
              Ok(_) => ()
              Err(k) => indices.insert(k, i)
            }
            Bytes::from_array(code[i:i + 1])[:]
          } else {
            b""[:]
          }
        },
        old_tree=tree,
      )
      .unwrap()
    out.write_string("\{tree2.root_node().to_sexp()}\n")
    let strings = []
    let mut last : (Int32, Int32)? = None
    for index in indices {
      match last {
        Some((s, e)) =>
          if e == index {
            last = Some((s, e + 1))
          } else {
            strings.push(@utf8.decode_lossy(Bytes::from_array(code[s:e])))
            last = None
          }
        None => last = Some((index, index + 1))
      }
    }
    if last is Some((s, e)) {
      strings.push(@utf8.decode_lossy(Bytes::from_array(code[s:e])))
    }
    out.write_string("read [\{strings.map(rust_debug_str).join(", ")}]\n")
  }
  inspect(
    out,
    content=(
      #|(translation_unit (expression_statement (update_expression argument: (binary_expression left: (number_literal) right: (binary_expression left: (number_literal) right: (parenthesized_expression (binary_expression left: (number_literal) right: (identifier))))) operator: (MISSING "--"))))
      #|(translation_unit (expression_statement (update_expression argument: (binary_expression left: (number_literal) right: (binary_expression left: (number_literal) right: (binary_expression left: (number_literal) right: (parenthesized_expression (binary_expression left: (number_literal) right: (identifier)))))) operator: (MISSING "--"))))
      #|read ["123 || 5 + "]
      #|(translation_unit (expression_statement (update_expression argument: (binary_expression left: (identifier) right: (parenthesized_expression (binary_expression left: (number_literal) right: (identifier)))) operator: (MISSING "--"))))
      #|(translation_unit (expression_statement (update_expression argument: (binary_expression left: (identifier) right: (parenthesized_expression (binary_expression left: (number_literal) right: (field_expression argument: (identifier) field: (field_identifier))))) operator: (MISSING "--"))))
      #|read [" * (100 ", "abc.d);"]
      #|
    ),
  )
}

///|
async test "parsing_with_logging and debug graphs (json)" {
  guard get_parsing_language("json") is Some(json) else { return }
  let out = StringBuilder()
  let parser = parser_for(json)
  let messages : Array[(@treesitter.LogType, String)] = []
  parser.set_logger(
    Some((log_type, message) => messages.push((log_type, message))),
  )
  assert_true(parser.logger() is Some(_))
  ignore(parser.parse(utf8("[1, 2]")))
  parser.set_logger(None)
  assert_true(parser.logger() is None)
  for i, entry in messages {
    if i >= 12 {
      break
    }
    let (log_type, message) = entry
    let t = if log_type == Parse { "P" } else { "L" }
    out.write_string("\{t} \{message}\n")
  }
  out.write_string("count \{messages.length()}\n")
  inspect(
    out,
    content=(
      #|P new_parse
      #|P process version:0, version_count:1, state:1, row:0, col:0
      #|P lex_internal state:0, row:0, column:0
      #|L consume character:'['
      #|P lexed_lookahead sym:[, size:1
      #|P shift state:4
      #|P process version:0, version_count:1, state:4, row:0, col:1
      #|P lex_internal state:0, row:0, column:1
      #|L consume character:'1'
      #|P lexed_lookahead sym:number, size:1
      #|P shift state:8
      #|P process version:0, version_count:1, state:8, row:0, col:2
      #|count 38
      #|
    ),
  )
  // test_parsing_with_debug_graph_enabled: rows are printed one-based.
  let graph = StringBuilder()
  parser.print_dot_graphs(s => graph.write_string(s))
  ignore(parser.parse(utf8("[1, 2]")))
  parser.stop_printing_dot_graphs()
  let graph = graph.to_string()
  assert_true(graph.contains("digraph stack {"))
  assert_false(graph.contains("position: 0,"))
  let tree_graph = StringBuilder()
  parse(parser, "[1]").print_dot_graph(tree_graph)
  assert_true(tree_graph.to_string().has_prefix("digraph tree {"))
}

///|
/// `test_parsing_with_a_timeout` and `..._and_a_reset`, with progress
/// callbacks that stop after a number of calls instead of a duration.
async test "parsing_with_progress_callback (json)" {
  guard get_parsing_language("json") is Some(json) else { return }
  let out = StringBuilder()
  let parser = parser_for(json)
  // Cancel an endless array after a number of progress calls.
  let mut calls = 0
  let tree = parser.parse_with_options(
    (offset, _) => if offset == 0 { b" ["[:] } else { b",0"[:] },
    options=@treesitter.ParseOptions::new(progress_callback=_ => {
      calls += 1
      if calls > 100 {
        Break
      } else {
        Continue
      }
    }),
  )
  out.write_string("cancelled \{tree is None}\n")
  // Resume and finish.
  let tree = parser
    .parse_with_options((offset, _) => {
      if offset > 5000 {
        b""[:]
      } else if offset == 5000 {
        b"]"[:]
      } else {
        b",0"[:]
      }
    })
    .unwrap()
  let array = tree.root_node().child(0).unwrap()
  out.write_string("resumed \{array.kind()} \{array.named_child_count()}\n")
  // A cancelled parse resumes unless the parser is reset.
  let numbers = Array::makei(299, i => (i + 1).to_string()).join(", ")
  let code = utf8("[\"ok\", \{numbers}]")
  let null_code = "[null, \{numbers}]"
  for reset in [false, true] {
    let mut calls = 0
    let tree = parser.parse_with_options(
      (offset, _) => {
        if offset >= code.length() {
          b""[:]
        } else {
          code[offset:]
        }
      },
      options=@treesitter.ParseOptions::new(progress_callback=_ => {
        calls += 1
        if calls > 1 {
          Break
        } else {
          Continue
        }
      }),
    )
    out.write_string("cancel \{tree is None}\n")
    if reset {
      parser.reset()
    }
    let tree = parse(parser, null_code)
    let first = tree.root_node().named_child(0).unwrap().named_child(0).unwrap()
    out.write_string("reset=\{reset} \{first.kind()}\n")
  }
  let offsets : Array[(Int32, Bool)] = []
  let source = utf8("[\{numbers}]")
  ignore(
    parser.parse_with_options(
      (offset, _) => {
        if offset < source.length() {
          source[offset:]
        } else {
          b""[:]
        }
      },
      options=@treesitter.ParseOptions::new(progress_callback=p => {
        offsets.push((p.current_byte_offset(), p.has_error()))
        Continue
      }),
    ),
  )
  let first = offsets[0]
  let last = offsets[offsets.length() - 1]
  out.write_string(
    "offsets \{offsets.length()} Some((\{first.0}, \{first.1})) Some((\{last.0}, \{last.1}))\n",
  )
  inspect(
    out,
    content=(
      #|cancelled true
      #|resumed array 2501
      #|cancel true
      #|reset=false string
      #|cancel true
      #|reset=true null
      #|offsets 24 Some((74, false)) Some((1387, false))
      #|
    ),
  )
}

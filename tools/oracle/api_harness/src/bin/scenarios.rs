// Scenarios adapted from tree_test.rs / parser_test.rs to grammars without
// external scanners (C, JSON); the MoonBit tests print the same text.
use std::fmt::Write;
use std::ops::ControlFlow;
use tree_sitter::{InputEdit, Language, LogType, Node, ParseOptions, Parser, Point, Range, Tree};

unsafe extern "C" {
    fn tree_sitter_json() -> *const ();
    fn tree_sitter_c() -> *const ();
}

fn lang(f: unsafe extern "C" fn() -> *const ()) -> Language {
    let f = unsafe { tree_sitter_language::LanguageFn::from_raw(std::mem::transmute(f)) };
    Language::new(f)
}

fn node_line(out: &mut String, label: &str, n: Node) {
    writeln!(
        out,
        "{label} {} {}..{} {}-{} changes={}",
        n.kind(),
        n.start_byte(),
        n.end_byte(),
        n.start_position(),
        n.end_position(),
        n.has_changes()
    )
    .unwrap();
}

fn pos(text: &[u8], offset: usize) -> Point {
    let mut row = 0;
    let mut column = 0;
    for &b in &text[..offset] {
        if b == b'\n' {
            row += 1;
            column = 0;
        } else {
            column += 1;
        }
    }
    Point::new(row, column)
}

fn perform_edit(tree: &mut Tree, input: &mut Vec<u8>, position: usize, deleted: usize, inserted: &str) -> InputEdit {
    let start_position = pos(input, position);
    let old_end_position = pos(input, position + deleted);
    input.splice(position..position + deleted, inserted.bytes());
    let edit = InputEdit {
        start_byte: position,
        old_end_byte: position + deleted,
        new_end_byte: position + inserted.len(),
        start_position,
        old_end_position,
        new_end_position: pos(input, position + inserted.len()),
    };
    tree.edit(&edit);
    edit
}

fn tree_edit(c: &Language) -> String {
    let mut out = String::new();
    let mut parser = Parser::new();
    parser.set_language(c).unwrap();
    let tree = parser.parse("  abc  <<=  def;", None).unwrap();
    writeln!(out, "{}", tree.root_node().to_sexp()).unwrap();
    for (s, o, n) in [(1, 1, 2), (1, 4, 5), (2, 2, 4), (1, 11, 4), (15, 15, 16), (3, 90, 4), (6, 90, 8)] {
        let mut tree = tree.clone();
        tree.edit(&InputEdit {
            start_byte: s,
            old_end_byte: o,
            new_end_byte: n,
            start_position: Point::new(0, s),
            old_end_position: Point::new(0, o),
            new_end_position: Point::new(0, n),
        });
        writeln!(out, "edit {s} {o} {n}").unwrap();
        let expr = tree.root_node().child(0).unwrap().child(0).unwrap();
        node_line(&mut out, " expr", expr);
        for i in 0..expr.child_count() {
            node_line(&mut out, " child", expr.child(i).unwrap());
        }
    }
    out
}

fn tree_cursor(c: &Language) -> String {
    let mut out = String::new();
    let mut parser = Parser::new();
    parser.set_language(c).unwrap();
    let source = "\nstruct Stuff {\n    int a;\n    B /* x */ b;\n};\n// done\n";
    let tree = parser.parse(source, None).unwrap();
    let mut cursor = tree.walk();
    // A pre-order walk.
    let mut visited_children = false;
    loop {
        if !visited_children {
            let n = cursor.node();
            writeln!(
                out,
                "{} field={:?} depth={} index={} named={} at={}",
                n.kind(),
                cursor.field_name(),
                cursor.depth(),
                cursor.descendant_index(),
                n.is_named(),
                n.start_position()
            )
            .unwrap();
            if !cursor.goto_first_child() {
                visited_children = true;
            }
        } else if cursor.goto_next_sibling() {
            visited_children = false;
        } else if !cursor.goto_parent() {
            break;
        }
    }
    // Walking backwards from the last child of the field list.
    let mut cursor = tree.walk();
    cursor.goto_first_child();
    cursor.goto_first_child();
    cursor.goto_next_sibling();
    cursor.goto_next_sibling();
    writeln!(out, "at {}", cursor.node().kind()).unwrap();
    writeln!(out, "last {}", cursor.goto_last_child()).unwrap();
    loop {
        writeln!(out, "  {} {}", cursor.node().kind(), cursor.node().start_position()).unwrap();
        if !cursor.goto_previous_sibling() {
            break;
        }
    }
    let mut copy = tree.walk();
    copy.reset_to(&cursor);
    writeln!(out, "copy {}", copy.node().kind()).unwrap();
    writeln!(out, "parent {} {}", copy.goto_parent(), copy.node().kind()).unwrap();
    writeln!(out, "parent {} {}", copy.goto_parent(), copy.node().kind()).unwrap();
    let mut c2 = tree.walk();
    writeln!(out, "last {} {}", c2.goto_last_child(), c2.node().kind()).unwrap();
    writeln!(out, "prev {} {}", c2.goto_previous_sibling(), c2.node().kind()).unwrap();
    writeln!(out, "prev {} {}", c2.goto_previous_sibling(), c2.node().kind()).unwrap();
    let mut clone = c2.clone();
    writeln!(out, "clone {} {}", clone.goto_first_child(), clone.node().kind()).unwrap();
    writeln!(out, "orig {}", c2.node().kind()).unwrap();
    out
}

fn child_for_point(json: &Language) -> String {
    let mut out = String::new();
    let mut parser = Parser::new();
    parser.set_language(json).unwrap();
    let source = "\n    [\n        1,\n        {\n            \"two\": 3\n        },\n        4, 5, 6\n    ]";
    let source = &source[1..];
    let tree = parser.parse(source, None).unwrap();
    let mut c = tree.walk();
    for step in [
        "p 7 0", "p 6 7", "p 6 5", "p 7 0", "p 6 6", "p 6 4", "p 0 4", "up", "p 1 0", "up", "p 1 10",
        "up", "p 1 9", "up", "p 5 0", "up", "p 6 0", "up", "p 2 0", "b 50", "up", "b 9", "up", "b 999",
    ] {
        let parts: Vec<&str> = step.split(' ').collect();
        let r = match parts[0] {
            "p" => format!(
                "{:?}",
                c.goto_first_child_for_point(Point::new(parts[1].parse().unwrap(), parts[2].parse().unwrap()))
            ),
            "b" => format!("{:?}", c.goto_first_child_for_byte(parts[1].parse().unwrap())),
            _ => format!("{}", c.goto_parent()),
        };
        writeln!(out, "{step} -> {r} {} {}", c.node().kind(), c.node().start_position()).unwrap();
    }
    out
}

fn changed_ranges(json: &Language) -> String {
    let mut out = String::new();
    let mut parser = Parser::new();
    parser.set_language(json).unwrap();
    let source: Vec<u8> = b"{\"a\": null}\n".to_vec();
    let tree = parser.parse(&source, None).unwrap();
    writeln!(out, "{}", tree.root_node().to_sexp()).unwrap();
    let edits: &[&[(&str, usize, &str)]] = &[
        &[("ull", 3, "ever"), ("ever", 4, "ull")],
        &[("", 0, "\n"), ("\n", 1, "")],
        &[("}", 0, ", \"b\": false"), (", \"b\"", 0, ", \"c\": 1"), (", \"c\": 1", 8, ""), (", \"b\": false", 12, "")],
        &[("null", 4, "[1, null]"), ("[1, null]", 9, "null")],
    ];
    for group in edits {
        let mut tree = tree.clone();
        let mut source = source.clone();
        for (needle, deleted, inserted) in group.iter() {
            let position = if needle.is_empty() { 0 } else { std::str::from_utf8(&source).unwrap().find(needle).unwrap() };
            perform_edit(&mut tree, &mut source, position, *deleted, inserted);
            let new_tree = parser.parse(&source, Some(&tree)).unwrap();
            let ranges: Vec<Range> = tree.changed_ranges(&new_tree).collect();
            writeln!(out, "{:?} -> {}", std::str::from_utf8(&source).unwrap(), new_tree.root_node().to_sexp()).unwrap();
            for r in ranges {
                writeln!(out, "  {}..{} {}-{}", r.start_byte, r.end_byte, r.start_point, r.end_point).unwrap();
            }
            tree = new_tree;
        }
    }
    out
}

fn included_ranges(json: &Language) -> String {
    let mut out = String::new();
    let mut parser = Parser::new();
    parser.set_language(json).unwrap();
    let r = parser.included_ranges();
    writeln!(out, "default {:?}", r.iter().map(|r| (r.start_byte, r.end_byte, r.start_point, r.end_point)).collect::<Vec<_>>()).unwrap();
    let source = "abc [1,\n2] def\n[3] ghi";
    let first = source.find('[').unwrap();
    let second = source.rfind('[').unwrap();
    let ranges = [
        Range { start_byte: first, end_byte: first + 6, start_point: Point::new(0, first), end_point: Point::new(1, 2) },
        Range { start_byte: second, end_byte: second + 3, start_point: Point::new(2, 0), end_point: Point::new(2, 3) },
    ];
    parser.set_included_ranges(&ranges).unwrap();
    let tree = parser.parse(source, None).unwrap();
    writeln!(out, "{}", tree.root_node().to_sexp()).unwrap();
    node_line(&mut out, "root", tree.root_node());
    {
        let mut cursor = tree.walk();
        for n in tree.root_node().children(&mut cursor) {
            node_line(&mut out, " child", n);
        }
    }
    writeln!(out, "tree ranges {:?}", tree.included_ranges().iter().map(|r| (r.start_byte, r.end_byte)).collect::<Vec<_>>()).unwrap();
    writeln!(out, "parser ranges {:?}", parser.included_ranges().iter().map(|r| (r.start_byte, r.end_byte)).collect::<Vec<_>>()).unwrap();
    // Editing a tree also edits its included ranges.
    let mut tree = tree;
    tree.edit(&InputEdit {
        start_byte: 2,
        old_end_byte: 5,
        new_end_byte: 3,
        start_position: Point::new(0, 2),
        old_end_position: Point::new(0, 5),
        new_end_position: Point::new(0, 3),
    });
    writeln!(out, "edited ranges {:?}", tree.included_ranges().iter().map(|r| (r.start_byte, r.end_byte, r.start_point, r.end_point)).collect::<Vec<_>>()).unwrap();
    let bad = [ranges[1], ranges[0]];
    writeln!(out, "error {:?}", parser.set_included_ranges(&bad).unwrap_err()).unwrap();
    parser.set_included_ranges(&[]).unwrap();
    writeln!(out, "reset {:?}", parser.included_ranges().len()).unwrap();
    out
}

fn encodings(json: &Language, c: &Language) -> String {
    let mut out = String::new();
    let mut parser = Parser::new();
    parser.set_language(json).unwrap();
    let lines: Vec<Vec<u16>> = ["[1, \"€\",", "  {\"😀\": 2}", "]"].iter().map(|s| s.encode_utf16().collect()).collect();
    let newline = ['\n' as u16];
    let tree = parser
        .parse_utf16_le_with_options(
            &mut |_, position| {
                let row = position.row;
                let column = position.column;
                if row < lines.len() {
                    if column < lines[row].len() { &lines[row][column..] } else { &newline }
                } else {
                    &[]
                }
            },
            None,
            None,
        )
        .unwrap();
    writeln!(out, "le {}", tree.root_node().to_sexp()).unwrap();
    let mut cursor = tree.walk();
    for n in tree.root_node().child(0).unwrap().named_children(&mut cursor) {
        node_line(&mut out, " le", n);
    }
    let be_lines: Vec<Vec<u16>> = lines.iter().map(|l| l.iter().map(|u| u.to_be()).collect()).collect();
    let be_newline = [('\n' as u16).to_be()];
    let tree = parser
        .parse_utf16_be_with_options(
            &mut |_, position| {
                let row = position.row;
                let column = position.column;
                if row < be_lines.len() {
                    if column < be_lines[row].len() { &be_lines[row][column..] } else { &be_newline }
                } else {
                    &[]
                }
            },
            None,
            None,
        )
        .unwrap();
    writeln!(out, "be {}", tree.root_node().to_sexp()).unwrap();
    let bom: Vec<u16> = "\u{FEFF}[1]".encode_utf16().collect();
    let tree = parser.parse_utf16_le(&bom, None).unwrap();
    writeln!(out, "bom {} {}", tree.root_node().to_sexp(), tree.root_node().start_byte()).unwrap();
    let text: Vec<u16> = "[\"你好\"]".encode_utf16().collect();
    let tree = parser.parse_utf16_le(&text, None).unwrap();
    let s = tree.root_node().child(0).unwrap().named_child(0).unwrap();
    writeln!(out, "utf16_text {:?}", String::from_utf16(s.utf16_text(&text)).unwrap()).unwrap();
    let tree = parser.parse(b"\xdf", None).unwrap();
    writeln!(out, "invalid {}", tree.root_node().to_sexp()).unwrap();
    let mut i = 0;
    let source = b"[1, 2, 3, 4, 5]";
    let tree = parser
        .parse_with_options(
            &mut |offset, _| {
                i += 1;
                if offset >= 6 { b"" } else { &source[offset..usize::min(source.len(), offset + 3)] }
            },
            None,
            None,
        )
        .unwrap();
    writeln!(out, "short {} {}", tree.root_node().to_sexp(), tree.root_node().end_byte()).unwrap();
    // UTF-32 and a single-byte encoding through the custom decoder, on C.
    parser.set_language(c).unwrap();
    let text = "int x = \"€50\";";
    let mut utf32 = Vec::new();
    for ch in text.chars() {
        utf32.extend_from_slice(&(ch as u32).to_le_bytes());
    }
    struct U32;
    impl tree_sitter::Decode for U32 {
        fn decode(bytes: &[u8]) -> (i32, u32) {
            if bytes.len() >= 4 { (i32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]), 4) } else { (0, 0) }
        }
    }
    let tree = parser
        .parse_custom_encoding::<U32, _, _>(&mut |offset, _| if offset < utf32.len() { &utf32[offset..] } else { &[] }, None, None)
        .unwrap();
    writeln!(out, "utf32 {} {}", tree.root_node().to_sexp(), tree.root_node().end_byte()).unwrap();
    struct Latin1;
    impl tree_sitter::Decode for Latin1 {
        fn decode(bytes: &[u8]) -> (i32, u32) {
            if !bytes.is_empty() { (i32::from(bytes[0]), 1) } else { (0, 0) }
        }
    }
    let latin1: Vec<u8> = b"int \xe9 = 1;".to_vec();
    let tree = parser
        .parse_custom_encoding::<Latin1, _, _>(&mut |offset, _| if offset < latin1.len() { &latin1[offset..] } else { &[] }, None, None)
        .unwrap();
    writeln!(out, "latin1 {}", tree.root_node().to_sexp()).unwrap();
    out
}

fn incremental(c: &Language) -> String {
    let mut out = String::new();
    let mut parser = Parser::new();
    parser.set_language(c).unwrap();
    for (code, position, deleted, inserted) in [
        ("123 + 456 * (10 + x);", 3usize, 0usize, " || 5"),
        ("x * (100 + abc);", 14, 0, ".d"),
    ] {
        let mut code = code.as_bytes().to_vec();
        let mut tree = parser.parse(&code, None).unwrap();
        writeln!(out, "{}", tree.root_node().to_sexp()).unwrap();
        perform_edit(&mut tree, &mut code, position, deleted, inserted);
        let mut indices: Vec<usize> = Vec::new();
        let tree2 = parser
            .parse_with_options(
                &mut |i, _| {
                    if i < code.len() {
                        if let Err(k) = indices.binary_search(&i) {
                            indices.insert(k, i);
                        }
                        &code[i..=i]
                    } else {
                        &[]
                    }
                },
                Some(&tree),
                None,
            )
            .unwrap();
        writeln!(out, "{}", tree2.root_node().to_sexp()).unwrap();
        let mut strings = Vec::new();
        let mut last: Option<std::ops::Range<usize>> = None;
        for &index in &indices {
            if let Some(range) = &mut last {
                if range.end == index {
                    range.end += 1;
                } else {
                    strings.push(String::from_utf8(code[range.clone()].to_vec()).unwrap());
                    last = None;
                }
            } else {
                last = Some(index..index + 1);
            }
        }
        if let Some(range) = last {
            strings.push(String::from_utf8(code[range].to_vec()).unwrap());
        }
        writeln!(out, "read {strings:?}").unwrap();
    }
    out
}

fn logging(json: &Language) -> String {
    let mut out = String::new();
    let mut parser = Parser::new();
    parser.set_language(json).unwrap();
    let mut messages = Vec::new();
    unsafe {
        parser.set_logger_unchecked(Some(Box::new(|log_type, message| {
            messages.push((log_type, message.to_string()));
        })));
    }
    parser.parse("[1, 2]", None).unwrap();
    parser.set_logger(None);
    for (t, m) in messages.iter().take(12) {
        writeln!(out, "{} {m}", if *t == LogType::Parse { "P" } else { "L" }).unwrap();
    }
    writeln!(out, "count {}", messages.len()).unwrap();
    out
}

fn progress(json: &Language) -> String {
    let mut out = String::new();
    let mut parser = Parser::new();
    parser.set_language(json).unwrap();
    // Cancel an endless array after a number of progress calls.
    let mut calls = 0;
    let tree = parser.parse_with_options(
        &mut |offset, _| if offset == 0 { b" [" } else { b",0" },
        None,
        Some(ParseOptions::new().progress_callback(&mut |_| {
            calls += 1;
            if calls > 100 { ControlFlow::Break(()) } else { ControlFlow::Continue(()) }
        })),
    );
    writeln!(out, "cancelled {}", tree.is_none()).unwrap();
    // Resume and finish.
    let tree = parser
        .parse_with_options(
            &mut |offset, _| match offset {
                5001.. => "".as_bytes(),
                5000 => "]".as_bytes(),
                _ => ",0".as_bytes(),
            },
            None,
            None,
        )
        .unwrap();
    writeln!(out, "resumed {} {}", tree.root_node().child(0).unwrap().kind(), tree.root_node().child(0).unwrap().named_child_count()).unwrap();
    // A cancelled parse resumes unless the parser is reset.
    let numbers = (1..300).map(|i| i.to_string()).collect::<Vec<_>>().join(", ");
    let code = format!("[\"ok\", {numbers}]");
    let null_code = format!("[null, {numbers}]");
    for reset in [false, true] {
        let mut calls = 0;
        let tree = parser.parse_with_options(
            &mut |offset, _| if offset >= code.len() { &[] } else { &code.as_bytes()[offset..] },
            None,
            Some(ParseOptions::new().progress_callback(&mut |_| {
                calls += 1;
                if calls > 1 { ControlFlow::Break(()) } else { ControlFlow::Continue(()) }
            })),
        );
        writeln!(out, "cancel {}", tree.is_none()).unwrap();
        if reset {
            parser.reset();
        }
        let tree = parser.parse(&null_code, None).unwrap();
        writeln!(out, "reset={reset} {}", tree.root_node().named_child(0).unwrap().named_child(0).unwrap().kind()).unwrap();
    }
    let mut offsets = Vec::new();
    let source = format!("[{numbers}]");
    parser
        .parse_with_options(
            &mut |offset, _| if offset < source.len() { &source.as_bytes()[offset..] } else { &[] },
            None,
            Some(ParseOptions::new().progress_callback(&mut |p| {
                offsets.push((p.current_byte_offset(), p.has_error()));
                ControlFlow::Continue(())
            })),
        )
        .unwrap();
    writeln!(out, "offsets {} {:?} {:?}", offsets.len(), offsets.first(), offsets.last()).unwrap();
    out
}

fn main() {
    let json = lang(tree_sitter_json);
    let c = lang(tree_sitter_c);
    println!("=== tree_edit\n{}", tree_edit(&c));
    println!("=== tree_cursor\n{}", tree_cursor(&c));
    println!("=== child_for_point\n{}", child_for_point(&json));
    println!("=== changed_ranges\n{}", changed_ranges(&json));
    println!("=== included_ranges\n{}", included_ranges(&json));
    println!("=== encodings\n{}", encodings(&json, &c));
    println!("=== incremental\n{}", incremental(&c));
    println!("=== logging\n{}", logging(&json));
    println!("=== progress\n{}", progress(&json));
}

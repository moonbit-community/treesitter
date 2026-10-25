// Regression tests for divergences from the upstream runtime and Rust
// binding found in review. Expected values were checked against the pinned
// upstream C library (a parser.c generated from the grammar below by the
// pinned CLI, with the equivalent C scanner) or follow from lib.rs.

///|
/// `source_file: repeat(choice($.ext, $.word))`, with the external token
/// `ext` (an `x`).
let review_grammar_json : String =
  #|{
  #|  "name": "review_ext",
  #|  "rules": {
  #|    "source_file": {
  #|      "type": "REPEAT",
  #|      "content": {
  #|        "type": "CHOICE",
  #|        "members": [
  #|          { "type": "SYMBOL", "name": "ext" },
  #|          { "type": "SYMBOL", "name": "word" }
  #|        ]
  #|      }
  #|    },
  #|    "word": { "type": "PATTERN", "value": "[a-w]+" }
  #|  },
  #|  "extras": [{ "type": "PATTERN", "value": "\\s" }],
  #|  "externals": [{ "type": "SYMBOL", "name": "ext" }]
  #|}

///|
/// The observable state of the review grammar's scanner.
struct ReviewScanner {
  /// The length of the serialized state; byte 16 is 1, the others 0.
  mut state_length : Int32
  /// Messages the scanner logs on each call.
  messages : Array[String]
  mut destroyed : Int32
}

///|
fn ReviewScanner::new() -> ReviewScanner {
  { state_length: 0, messages: [], destroyed: 0, }
}

///|
fn ReviewScanner::language(self : ReviewScanner) -> @treesitter.Language raise {
  let (_, parser) = generate_parser(review_grammar_json)
  @treesitter.Language::new(parser.language, external_scanner=() => {
    scan: (lexer, _) => {
      for message in self.messages {
        lexer.log(message)
      }
      while lexer.lookahead == ' ' {
        lexer.advance(true)
      }
      if lexer.lookahead != 'x' {
        return false
      }
      lexer.advance(false)
      lexer.result_symbol = 0
      true
    },
    serialize: buffer => {
      for i in 0..<self.state_length {
        buffer[i] = if i == 16 { 1 } else { 0 }
      }
      self.state_length
    },
    deserialize: _ => (),
    destroy: () => self.destroyed += 1,
  })
}

///|
/// The `label` and `repeat-depth` of each node in a DOT graph.
fn dot_repeat_depths(graph : String) -> Array[String] {
  let result = []
  for line in graph.split("\n") {
    if line.find("[label=\"") is Some(start) {
      let rest = line.view(start_offset=start + 8)
      let end = rest.find("\"").unwrap()
      result.push(rest.view(end_offset=end).to_owned())
    } else if line.has_prefix("repeat-depth: ") {
      result.push(line.to_owned())
    }
  }
  result
}

///|
test "external scanner state overlaps repeat_depth" {
  let scanner = ReviewScanner::new()
  let parser = parser_for(scanner.language())
  // Bytes 16 and 17 of a short state are the leaf's repeat depth.
  scanner.state_length = 18
  let graph = StringBuilder()
  parser.parse(b"x x x").unwrap().print_dot_graph(graph)
  debug_inspect(
    dot_repeat_depths(graph.to_string()),
    content=(
      #|[
      #|  "source_file",
      #|  "repeat-depth: 0",
      #|  "source_file_repeat1",
      #|  "repeat-depth: 2",
      #|  "source_file_repeat1",
      #|  "repeat-depth: 0",
      #|  "ext",
      #|  "repeat-depth: 1",
      #|  "ext",
      #|  "repeat-depth: 1",
      #|  "ext",
      #|  "repeat-depth: 1",
      #|  "end",
      #|  "repeat-depth: 0",
      #|]
    ),
  )
  // States longer than 24 bytes are stored on the heap.
  scanner.state_length = 30
  parser.reset()
  let graph = StringBuilder()
  parser.parse(b"x x x").unwrap().print_dot_graph(graph)
  inspect(
    dot_repeat_depths(graph.to_string())
    .filter(s => s.has_prefix("repeat"))
    .join(" "),
    content="repeat-depth: 0 repeat-depth: 1 repeat-depth: 0 repeat-depth: 0 repeat-depth: 0 repeat-depth: 0 repeat-depth: 0",
  )
}

///|
test "DOT graphs write the raw byte of an unexpected character" {
  let scanner = ReviewScanner::new()
  let parser = parser_for(scanner.language())
  let tree = parser.parse(utf8("é")).unwrap()
  let bytes = Buffer()
  tree.print_dot_graph(bytes)
  let graph = bytes.to_bytes()
  // C's `%c` writes the low byte of U+00E9.
  let marker = @utf8.encode("character: '")
  let start = for i in 0..<(graph.length() - marker.length()) {
    if graph[i:i + marker.length()] == marker[:] {
      break i + marker.length()
    }
  } nobreak {
    -1
  }
  assert_true(start > 0)
  assert_eq(graph[start], 0xE9)
  assert_eq(graph[start + 1], b'\'')
  // A `StringBuilder` receives the graph decoded lossily.
  let text = StringBuilder()
  tree.print_dot_graph(text)
  assert_true(text.to_string().contains("character: '\u{FFFD}'"))
  // The parser's graphs carry the same bytes.
  let graphs = Buffer()
  parser.print_dot_graphs_to(graphs)
  ignore(parser.parse(utf8("é")))
  parser.stop_printing_dot_graphs()
  let graphs = graphs.to_bytes()
  let found = for i in 0..<(graphs.length() - marker.length() - 1) {
    if graphs[i:i + marker.length()] == marker[:] &&
      graphs[i + marker.length()] == 0xE9 {
      break true
    }
  } nobreak {
    false
  }
  assert_true(found)
}

///|
test "scanner log messages are C strings delivered only when valid UTF-8" {
  let scanner = ReviewScanner::new()
  let parser = parser_for(scanner.language())
  // 1,022 ASCII characters and a two-byte character: the 1,023-byte buffer
  // ends inside the character, so the Rust binding drops the message.
  let long = "\{"a".repeat(1022)}é"
  scanner.messages.push(long)
  scanner.messages.push("ab\u{0}cd")
  scanner.messages.push("b".repeat(1100))
  let lex_messages : Array[String] = []
  parser.set_logger(
    Some((log_type, message) => {
      if log_type is Lex {
        lex_messages.push(message)
      }
    }),
  )
  ignore(parser.parse(b"x"))
  assert_false(lex_messages.iter().any(m => m.has_prefix("aaaa")))
  assert_true(lex_messages.contains("ab"))
  assert_false(lex_messages.iter().any(m => m.has_prefix("ab\u{0}")))
  // A message that is cut between characters is still delivered.
  assert_true(lex_messages.contains("b".repeat(1023)))
}

///|
test "deleting a parser destroys the scanner of a cancelled parse" {
  let scanner = ReviewScanner::new()
  let language = scanner.language()
  let parser = parser_for(language)
  let text = utf8("x ".repeat(500))
  let options = @treesitter.ParseOptions::new(progress_callback=_ => Break)
  assert_true(parser.parse_with_options((i, _) => text[i:], options~) is None)
  assert_eq(scanner.destroyed, 0)
  parser.delete()
  assert_eq(scanner.destroyed, 1)
  assert_true(parser.language() is None)
  assert_true(parser.parse(text) is None)
  // The parser can be used again.
  parser.set_language(language)
  assert_true(parser.parse(text) is Some(_))
}

///|
test "capture equality creates both text iterators before reading them" {
  let scanner = ReviewScanner::new()
  let language = scanner.language()
  let parser = parser_for(language)
  let tree = parser.parse(b"ab ab").unwrap()
  let query = @treesitter.Query::new(
    language, "((word) @a (word) @b (#eq? @a @b))",
  )
  let calls = Ref(0)
  let texts : Array[String] = []
  let provider = @treesitter.TextCallback::new(_ => {
    calls.val += 1
    let mut done = false
    Iter::new(() => {
      if done {
        None
      } else {
        done = true
        texts.push(calls.val.to_string())
        Some(@utf8.encode(calls.val.to_string())[:])
      }
    })
  })
  let cursor = @treesitter.QueryCursor::new()
  let matches = cursor.matches(query, tree.root_node(), provider)
  assert_true(matches.next() is Some(_))
  debug_inspect(texts, content="[\"2\", \"2\"]")
}

///|
test "utf8_text raises Rust's Utf8Error" {
  let scanner = ReviewScanner::new()
  let parser = parser_for(scanner.language())
  let root = parser.parse(b"ab").unwrap().root_node()
  try root.utf8_text(b"a\xff") catch {
    error => {
      inspect(error, content="invalid utf-8 sequence of 1 bytes from index 1")
      guard error is Utf8Error(valid_up_to~, error_len~)
      assert_eq(valid_up_to, 1)
      assert_eq(error_len, Some(1))
    }
  } noraise {
    _ => fail("expected an error")
  }
  try root.utf8_text(b"a\xe2\x82") catch {
    error =>
      inspect(error, content="incomplete utf-8 byte sequence from index 1")
  } noraise {
    _ => fail("expected an error")
  }
  assert_eq(root.utf8_text(b"ab"), "ab")
}

///|
test "panic utf8_text outside the source" {
  let scanner = ReviewScanner::new()
  let parser = parser_for(scanner.language()) catch { _ => panic() }
  let root = parser.parse(b"ab ab").unwrap().root_node()
  // Rust's `&source[start..end]` panics.
  ignore(root.utf8_text(b"ab") catch { _ => "" })
}

///|
test "panic utf16_text outside the source" {
  let scanner = ReviewScanner::new()
  let parser = parser_for(scanner.language()) catch { _ => panic() }
  let root = parser.parse(b"ab ab").unwrap().root_node()
  let source : Array[UInt16] = ['a']
  ignore(root.utf16_text(source[:]))
}

///|
test "panic Bytes text provider outside the source" {
  let scanner = ReviewScanner::new()
  let language = scanner.language() catch { _ => panic() }
  let parser = parser_for(language) catch { _ => panic() }
  let tree = parser.parse(b"ab ab").unwrap()
  let query = @treesitter.Query::new(language, "((word) @a (#eq? @a \"ab\"))") catch {
    _ => panic()
  }
  let cursor = @treesitter.QueryCursor::new()
  let source : Bytes = b"ab"
  let matches = cursor.matches(query, tree.root_node(), source)
  while matches.next() is Some(_) {

  }
}

///|
test "Language is a hash key consistent with equality" {
  let scanner = ReviewScanner::new()
  let language = scanner.language()
  let other = scanner.language()
  let map : Map[@treesitter.Language, Int32] = Map([])
  map[language] = 1
  map[other] = 2
  assert_eq(map.get(language), Some(1))
  assert_eq(map.get(other), Some(2))
  assert_eq(map.length(), 2)
  let copy = @treesitter.Language::new(language.raw())
  assert_eq(copy.hash(), language.hash())
  assert_eq(map.get(copy), Some(1))
}

// Development probe for differential testing of the runtime port against
// the C runtime. Usage:
//   probe parse <language.json> <file>...   print the S-expression per file

///|
async fn load_language(path : String) -> @language.Language {
  let text = @fs.read_file(path).text()
  @json.from_json(@json.parse(text))
}

///|
fn new_parser(language : @language.Language) -> @runtime.Parser {
  let parser = @runtime.Parser::new()
  let scanner = if language.external_token_count > 0 {
    @scanners.scanner_for(language.name)
  } else {
    None
  }
  let ok = match scanner {
    Some(scanner) => parser.set_language(Some(language), scanner~)
    None => parser.set_language(Some(language))
  }
  if !ok {
    println("error: incompatible language")
  }
  parser
}

///|
async fn main {
  let args = @env.args()
  match args[1] {
    "parse" => {
      let language = load_language(args[2])
      let parser = new_parser(language)
      for i in 3..<args.length() {
        let source = @fs.read_file(args[i]).binary()
        println("== \{args[i]}")
        match parser.parse_string(None, source) {
          Some(tree) => {
            println(tree.root_node().to_sexp())
          }
          None => println("(no tree)")
        }
      }
    }
    "log" => {
      let language = load_language(args[2])
      let parser = new_parser(language)
      parser.set_logger(
        Some((kind, message) => {
          let prefix = match kind {
            Parse => "P"
            Lex => "L"
          }
          println("\{prefix} \{message}")
        }),
      )
      for i in 3..<args.length() {
        let source = @fs.read_file(args[i]).binary()
        println("== \{args[i]}")
        ignore(parser.parse_string(None, source))
      }
    }
    "query" => {
      let language = load_language(args[2])
      let source = @fs.read_file(args[3]).binary()
      let query = @query.Query::new(language, source) catch {
        QueryError(kind~, offset~) => {
          let code = match kind {
            Syntax => 1
            NodeType => 2
            Field => 3
            Capture => 4
            Structure => 5
            Language => 6
          }
          println("error \{code} \{offset}")
          return
        }
      }
      println(
        "patterns \{query.pattern_count()} captures \{query.capture_count()} strings \{query.string_count()}",
      )
      let b = (x : Bool) => if x { 1 } else { 0 }
      for i in 0..<query.pattern_count() {
        println(
          "pattern \{i} rooted \{b(query.is_pattern_rooted(i))} nonlocal \{b(query.is_pattern_non_local(i))} start \{query.start_byte_for_pattern(i)} end \{query.end_byte_for_pattern(i)}",
        )
      }
      for byte in 0..<source.length() {
        if query.is_pattern_guaranteed_at_step(byte.reinterpret_as_uint()) {
          println("guaranteed \{byte}")
        }
      }
      let parser = new_parser(language)
      let cursor = @query.QueryCursor::new()
      for i in 4..<args.length() {
        let text = @fs.read_file(args[i]).binary()
        println("== \{args[i]}")
        let tree = parser.parse_string(None, text).unwrap()
        cursor.exec(query, tree.root_node())
        while cursor.next_match() is Some(m) {
          let line = StringBuilder()
          line.write_string("M \{m.pattern_index} \{m.id}")
          for capture in m.captures {
            line.write_string(
              " \{capture.index}:\{capture.node.start_byte()}-\{capture.node.end_byte()}",
            )
          }
          println(line.to_string())
        }
        cursor.exec(query, tree.root_node())
        while cursor.next_capture() is Some((m, ci)) {
          let capture = m.captures[ci]
          println(
            "C \{m.pattern_index} \{ci} \{capture.index} \{capture.node.start_byte()}-\{capture.node.end_byte()}",
          )
        }
        println("exceeded \{b(cursor.did_exceed_match_limit())}")
      }
    }
    "bench" => {
      let language = load_language(args[2])
      let parser = new_parser(language)
      let text = @fs.read_file(args[3]).binary()
      let n = parse_uint(args[4]).reinterpret_as_int()
      let start = @env.now()
      for _ in 0..<n {
        ignore(parser.parse_string(None, text))
      }
      let elapsed = @env.now() - start
      println("\{n} parses in \{elapsed} ms (\{elapsed.to_double() / n.to_double()} ms/parse)")
    }
    "modes" => {
      let language = load_language(args[2])
      let parser = new_parser(language)
      let (encoding, unit) = match args[3] {
        "utf16le" => (@runtime.InputEncoding::UTF16LE, 2)
        "utf16be" => (@runtime.InputEncoding::UTF16BE, 2)
        _ => (@runtime.InputEncoding::UTF8, 1)
      }
      for i in 5..<args.length() {
        let text = @fs.read_file(args[i]).binary()
        println("== \{args[i]}")
        let ranges : Array[@runtime.Range] = []
        if args[4] != "-" {
          for tok in args[4].split(",") {
            let parts = tok.split("-").collect()
            let size = text.length().reinterpret_as_uint()
            let mut a = parse_uint(parts[0].to_string())
            let mut b = parse_uint(parts[1].to_string())
            if a > size {
              a = size
            }
            if b > size {
              b = size
            }
            ranges.push({
              start_byte: a,
              end_byte: b,
              start_point: point_at_unit(text, a, unit),
              end_point: point_at_unit(text, b, unit),
            })
          }
        }
        let b = (x : Bool) => if x { 1 } else { 0 }
        println("set \{b(parser.set_included_ranges(ranges))}")
        match parser.parse_string_encoding(None, text, encoding) {
          None => println("(no tree)")
          Some(tree) => {
            let root = tree.root_node()
            println(root.to_sexp())
            println(
              "root \{root.start_byte()}-\{root.end_byte()} (\{root.end_point().row},\{root.end_point().column})",
            )
            for r in tree.included_ranges() {
              println("incl \{r.start_byte}-\{r.end_byte}")
            }
          }
        }
      }
    }
    "walk" => {
      let language = load_language(args[2])
      let parser = new_parser(language)
      let text = @fs.read_file(args[3]).binary()
      let tree = parser.parse_string(None, text).unwrap()
      let cursor = @runtime.TreeCursor::new(tree.root_node())
      let mut ascending = false
      let mut steps = 0
      while steps < 200 {
        steps += 1
        if ascending {
          match cursor.goto_next_sibling_internal() {
            StepNone => if !cursor.goto_parent() { break } else { println("up") }
            step => { println("sibling \{to_repr(step)}"); ascending = false }
          }
        } else {
          let node = cursor.current_node()
          println("enter \{node.kind()} \{node.start_byte()}-\{node.end_byte()} depth=\{cursor.current_depth()}")
          match cursor.goto_first_child_internal() {
            StepNone => ascending = true
            step => println("child \{to_repr(step)}")
          }
        }
      }
    }
    "edit" => {
      let language = load_language(args[2])
      let parser = new_parser(language)
      let mut a = 3
      while a + 4 < args.length() {
        let old_text = @fs.read_file(args[a]).binary()
        let new_text = @fs.read_file(args[a + 1]).binary()
        let start = parse_uint(args[a + 2])
        let old_end = parse_uint(args[a + 3])
        let new_end = parse_uint(args[a + 4])
        let old_tree = parser.parse_string(None, old_text).unwrap()
        let edit : @runtime.InputEdit = {
          start_byte: start,
          old_end_byte: old_end,
          new_end_byte: new_end,
          start_point: point_at(old_text, start),
          old_end_point: point_at(old_text, old_end),
          new_end_point: point_at(new_text, new_end),
        }
        old_tree.edit(edit)
        let new_tree = parser.parse_string(Some(old_tree), new_text).unwrap()
        println("== \{args[a + 1]}")
        println(new_tree.root_node().to_sexp())
        for range in @runtime.Tree::changed_ranges(old_tree, new_tree) {
          println(
            "range \{range.start_byte} \{range.end_byte} (\{range.start_point.row},\{range.start_point.column})-(\{range.end_point.row},\{range.end_point.column})",
          )
        }
        let fresh = parser.parse_string(None, new_text).unwrap()
        println("fresh \{fresh.root_node().to_sexp()}")
        a += 5
      }
    }
    _ => println("unknown command")
  }
}

///|
fn point_at(text : Bytes, byte : UInt) -> @runtime.Point {
  let mut row : UInt = 0
  let mut column : UInt = 0
  for i in 0..<byte.reinterpret_as_int() {
    if text[i] == '\n' {
      row += 1
      column = 0
    } else {
      column += 1
    }
  }
  { row, column }
}

///|
fn parse_uint(s : String) -> UInt {
  let mut n : UInt = 0
  for c in s {
    n = n * 10 + (c.to_int() - '0'.to_int()).reinterpret_as_uint()
  }
  n
}

///|
fn point_at_unit(text : Bytes, byte : UInt, unit : Int) -> @runtime.Point {
  let mut row : UInt = 0
  let mut column : UInt = 0
  let mut i = 0
  while i < byte.reinterpret_as_int() {
    let nl = if unit == 1 {
      text[i] == b'\n'
    } else {
      let a = text[i]
      let c = if i + 1 < text.length() { text[i + 1] } else { b'\x00' }
      (a == b'\n' && c == b'\x00') || (a == b'\x00' && c == b'\n')
    }
    if nl {
      row += 1
      column = 0
    } else {
      column += unit.reinterpret_as_uint()
    }
    i += unit
  }
  { row, column }
}

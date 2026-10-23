// Development probe for differential testing of the runtime port against
// the C runtime. Usage:
//   probe parse <language.json> <file>...   print the S-expression per file

///|
async fn load_language(path : String) -> @language.Language {
  let text = @fs.read_file(path).text()
  @json.from_json(@json.parse(text))
}

///|
async fn main {
  let args = @env.args()
  match args[1] {
    "parse" => {
      let language = load_language(args[2])
      let parser = @runtime.Parser::new()
      if !parser.set_language(Some(language)) {
        println("error: incompatible language")
        return
      }
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
    "edit" => {
      let language = load_language(args[2])
      let parser = @runtime.Parser::new()
      ignore(parser.set_language(Some(language)))
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

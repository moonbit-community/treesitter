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
            let root = tree.root()
            println(
              root.to_sexp(
                0,
                language.symbol_metadata_of(0).named,
                language,
                false,
              ),
            )
          }
          None => println("(no tree)")
        }
      }
    }
    _ => println("unknown command")
  }
}

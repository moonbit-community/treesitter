///|
suberror CliError {
  Usage(String)
}

///|
async fn main {
  let args = @env.args()
  if args.length() < 2 {
    raise Usage(
      "usage: treesitter generate <grammar.mbtx|json> <language.json> | grammar-json <grammar.mbtx> | parse <language.json> <source> | emit <language.json> <language.mbt>",
    )
  }
  let root = @env.get_env_var("TREESITTER_MBT_ROOT").unwrap_or(
    @env.current_dir().unwrap_or("."),
  )
  match args[1] {
    "generate" if args.length() == 4 => {
      let grammar = @loader.load_grammar(args[2], root)
      let language = @generate.generate(grammar)
      write_file(args[3], Json(language).stringify())
      println(
        "Generated \{language.name}: \{language.states.length()} states, \{language.productions.length()} productions",
      )
    }
    "grammar-json" if args.length() == 3 => {
      let grammar = @loader.run_grammar(args[2], root)
      println(Json(grammar).stringify(indent=2))
    }
    "parse" if args.length() == 4 => {
      let language = @loader.load_language(args[2])
      let tree = @ts.Parser::new(language).parse(
        @fs.read_file(args[3]).binary(),
      )
      println(tree.root_node().to_sexp())
      if tree.root_node().has_error() {
        raise Usage("source contains syntax errors")
      }
    }
    "emit" if args.length() == 4 =>
      write_file(args[3], @generate.emit(@loader.load_language(args[2])))
    _ => raise Usage("invalid command or arguments")
  }
}

///|
async fn write_file(path : String, content : String) -> Unit {
  @fs.write_file(path, content, create_mode=CreateOrTruncate)
}

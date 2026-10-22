///|
suberror CliError {
  Usage(String)
}

///|
async fn main {
  let args = @env.args()
  if args.length() < 2 {
    raise Usage(
      "usage: treesitter generate <grammar.mbtx|json> <language.json> | grammar-json <grammar.mbtx> | parse <language.json> <source> | test <language.json> <corpus.txt> | query|highlight|tags <language.json> <query.scm> <source> | emit <language.json> <language.mbt>",
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
    "query" | "highlight" | "tags" if args.length() == 5 => {
      let language = @loader.load_language(args[2])
      let query_source = @fs.read_file(args[3]).text()
      let tree = @ts.Parser::new(language).parse(
        @fs.read_file(args[4]).binary(),
      )
      if args[1] == "highlight" {
        println(
          @highlight.Configuration::new(language, query_source).html(tree),
        )
      } else if args[1] == "tags" {
        let config = @tags.Configuration::new(language, query_source)
        for tag in config.generate(tree) {
          println(
            Json::object({
              "name": Json(tag.name),
              "kind": Json(tag.syntax_type),
              "definition": Json(tag.is_definition),
              "range": Json(tag.range),
              "name_range": Json(tag.name_range),
              "docs": Json(tag.docs),
            }).stringify(),
          )
        }
      } else {
        let query = @query.Query::new(language, query_source)
        for matched in query.matches(tree.root_node(), tree.source) {
          for capture in matched.captures {
            println(
              Json::object({
                "pattern": Json(matched.pattern_index),
                "capture": Json(capture.name),
                "text": Json(capture.node.text(tree.source)),
                "range": Json(capture.node.range()),
              }).stringify(),
            )
          }
        }
      }
    }
    "test" if args.length() == 4 => {
      let language = @loader.load_language(args[2])
      let cases = @corpus.parse(@fs.read_file(args[3]).text())
      let results = @corpus.run(language, cases)
      for result in results {
        let status = if result.skipped {
          "SKIP"
        } else if result.passed {
          "PASS"
        } else {
          "FAIL"
        }
        println("\{status} \{result.name}")
        if !result.passed {
          println("expected: \{result.expected}\nactual: \{result.actual}")
        }
      }
      if results.any(r => !r.passed) {
        raise Usage("corpus tests failed")
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

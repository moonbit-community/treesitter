///|
priv suberror CliError {
  Usage(String)
}

///|
/// Run the native CLI with an optional language-name-to-scanner registry.
/// `args` includes the executable name at index zero.
pub async fn run(
  args : Array[String],
  scanners~ : (String) -> @ts.ExternalScanner? = _ => None,
  current_dir~ : String = @env.current_dir().unwrap_or("."),
  module_root? : String,
) -> Unit {
  let root = module_root.unwrap_or_else(() => {
    @env.get_env_var("TREESITTER_MBT_ROOT").unwrap_or(current_dir)
  })
  dispatch(args, scanners, current_dir, root) catch {
    error => raise Failure("treesitter: " + describe(error))
  }
}

///|
fn describe(error : Error) -> String {
  match error {
    Usage(message)
    | @loader.LoadFailure(message)
    | @config.InvalidConfig(message)
    | @corpus.InvalidCorpus(message)
    | @generate.InvalidGrammar(message)
    | @generate.ResourceLimit(message)
    | @grammar.InvalidGrammar(message)
    | @language.InvalidLanguage(message)
    | @ts.InvalidRanges(message)
    | @ts.ScannerError(message)
    | @ts.ParseLimit(message) => message
    @generate.Conflict(state, token, rules) =>
      "unresolved conflict in state \{state} at '\{token}' between \{rules.join(", ")}"
    @query.InvalidQuery(offset, message) => "query byte \{offset}: \{message}"
    @lex.InvalidRegex(offset, message) =>
      "regex character \{offset}: \{message}"
    @ts.NoParse(offset) => "unable to recover a parse at byte \{offset}"
    @ts.Cancelled | @query.Cancelled => "cancelled"
    @query.MatchLimit => "query match/work limit exceeded"
    _ => "\{error}"
  }
}

///|
async fn dispatch(
  args : Array[String],
  scanners : (String) -> @ts.ExternalScanner?,
  current_dir : String,
  root : String,
) -> Unit {
  if args.length() < 2 {
    raise Usage(
      "usage: treesitter generate <grammar.mbtx|json> <language.json> | grammar-json <grammar.mbtx> | parse <language.json> <source> | test <language.json> <corpus.txt> | query|highlight|tags <language.json> <query.scm> <source> | emit <language.json> <language.mbt> | node-types <language.json> <node-types.json>",
    )
  }
  if args[1] == "--scanner" && args.length() >= 4 {
    let forwarded = [args[0]] + args[3:].to_owned()
    let code = @loader.run_scanner(args[2], root, forwarded, current_dir~)
    if code != 0 {
      raise Usage("scanner command failed (exit \{code})")
    }
    return
  }
  fn parser(language : @language.Language) -> @ts.Parser raise {
    @ts.Parser::new(language, scanner?=scanners(language.name))
  }
  match args[1] {
    "--version" | "version" => println("treesitter.mbt 0.1.0")
    "--help" | "help" =>
      println(
        "treesitter [--scanner scanner.mbtx] generate <grammar.mbtx|json> <language.json> | parse [language.json] <source> | highlight|tags <source> | parse --cst <language.json> <source> | test <language.json> <corpus-file-or-directory> [--update] | fuzz <language.json> <corpus> [--seed N] [--iterations N] [--edits N] [--include REGEX] [--exclude REGEX] | query|highlight|tags <language.json> <query.scm> <source> | query --check <language.json> <query.scm> | languages [config.json] | init <name> <directory> | init-config <path> | emit <language.json> <language.mbt> | node-types <language.json> <node-types.json> | grammar-json <grammar.mbtx>",
      )
    "languages" if args.length() <= 3 => {
      let directories = @loader.parser_directories(path?=args.get(2))
      for location in @loader.discover([current_dir] + directories) {
        println(
          Json::object({
            "name": Json(location.grammar.name),
            "scope": Json(location.grammar.scope),
            "path": Json(location.root),
            "file-types": Json(location.grammar.file_types),
          }).stringify(),
        )
      }
    }
    "init" if args.length() == 4 => init_grammar(args[2], args[3])
    "init-config" if args.length() == 3 => {
      if @fs.exists(args[2]) {
        raise Usage("configuration already exists: \{args[2]}")
      }
      write_file(args[2], "{\"parser-directories\": []}\n")
    }
    "parse" | "highlight" | "tags" if args.length() == 3 => {
      let source = @fs.read_file(args[2]).binary()
      let locations = @loader.discover(
        [current_dir] + @loader.parser_directories(),
      )
      guard @config.select(
          locations.map(l => l.grammar),
          args[2],
          @utf8.decode_lossy(source),
        )
        is Some(grammar) else {
        raise Usage("no language configuration matches \{args[2]}")
      }
      let location = locations[locations
        .search_by(l => physical_equal(l.grammar, grammar))
        .unwrap()]
      let tree = parser(location.language(root)).parse(source)
      match args[1] {
        "highlight" =>
          println(configured_html(location, locations, tree, root, scanners))
        "tags" => {
          let config = @tags.Configuration::new(
            tree.language,
            location.queries("tags"),
            locals=location.queries("locals"),
          )
          print_tags(config.generate(tree))
        }
        _ => {
          println(tree.root_node().to_sexp())
          if tree.root_node().has_error() {
            raise Usage("source contains syntax errors")
          }
        }
      }
    }
    "parse" if args.length() == 5 && args[2] == "--cst" => {
      let source = @fs.read_file(args[4]).text()
      let tree = parser(@loader.load_language(args[3])).parse_string(source)
      println(@corpus.render_cst(tree.root_node(), source).trim().to_owned())
      if tree.root_node().has_error() {
        raise Usage("source contains syntax errors")
      }
    }
    "generate" if args.length() == 4 => {
      let grammar = @loader.load_grammar(args[2], root)
      let language = @generate.generate(grammar)
      write_file(args[3], Json(language).stringify())
      println(
        "Generated \{language.name}: \{language.states.length()} states, \{language.productions.length()} productions",
      )
    }
    "node-types" if args.length() == 4 =>
      write_file(
        args[3],
        @loader.load_language(args[2]).node_types().stringify(indent=2),
      )
    "grammar-json" if args.length() == 3 => {
      let grammar = @loader.run_grammar(args[2], root)
      println(Json(grammar).stringify(indent=2))
    }
    "parse" if args.length() == 4 => {
      let language = @loader.load_language(args[2])
      let tree = parser(language).parse(@fs.read_file(args[3]).binary())
      println(tree.root_node().to_sexp())
      if tree.root_node().has_error() {
        raise Usage("source contains syntax errors")
      }
    }
    "query" if args.length() == 5 && args[2] == "--check" => {
      let language = @loader.load_language(args[3])
      let query = @query.Query::new(language, @fs.read_file(args[4]).text())
      println("Compiled query: \{query.pattern_count()} patterns")
    }
    "query" | "highlight" | "tags" if args.length() == 5 => {
      let language = @loader.load_language(args[2])
      let query_source = @fs.read_file(args[3]).text()
      let tree = parser(language).parse(@fs.read_file(args[4]).binary())
      if args[1] == "highlight" {
        println(
          @highlight.Configuration::new(
            language,
            query_source,
            scanner?=scanners(language.name),
          ).html(tree),
        )
      } else if args[1] == "tags" {
        let config = @tags.Configuration::new(language, query_source)
        print_tags(config.generate(tree))
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
    "fuzz" if args.length() >= 4 => {
      let options = fuzz_options(args[4:])
      let language = @loader.load_language(args[2])
      run_fuzz(language, read_corpus(args[3]), options, scanners(language.name))
    }
    "test" if args.length() == 5 &&
      (
        args[2] == "--update" ||
        args[2] == "-u" ||
        args[4] == "--update" ||
        args[4] == "-u"
      ) => {
      let first = if args[2] == "--update" || args[2] == "-u" { 3 } else { 2 }
      let language = @loader.load_language(args[first])
      update_corpus(args[first + 1], language, scanners(language.name))
    }
    "test" if args.length() == 4 => {
      let language = @loader.load_language(args[2])
      let cases = read_corpus(args[3])
      let results = @corpus.run(
        language,
        cases,
        scanner?=scanners(language.name),
      )
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

///|
async fn read_corpus(path : String) -> Array[@corpus.Case] {
  if @fs.kind(path) != Directory {
    return @corpus.parse(@fs.read_file(path).text())
  }
  let cases = []
  for name in @fs.readdir(path, sort=true) {
    let child = "\{path}/\{name}"
    if @fs.kind(child) == Directory || name.has_suffix(".txt") {
      cases.append(read_corpus(child))
    }
  }
  cases
}

// Differential probe (development only) for highlight, tags and
// query_testing. It prints, for the fixture languages, the same output
// as a Rust harness built on the pinned `tree-sitter-highlight` and
// `tree-sitter-tags` crates (see the port's report): highlight event streams
// and HTML, tags, query-testing assertions and positions, grapheme
// boundaries and regex `find_iter` results.
//
//   moon run --target native query_testing/probe -- highlight <lang> <files...>
//   ... tags|querytest <lang> <files...> | graphemes <file> | regex <file>
//
// Languages are read from `_build/reflang/fixture_<name>.json`; only
// grammars whose external scanner is ported are available (the environment
// variable TS_LANGS, a comma-separated list, restricts them further).

///|
let names : Array[String] = [
  "attribute", "boolean", "carriage-return", "comment", "constant", "constant.builtin",
  "constructor", "embedded", "function", "function.builtin", "keyword", "module",
  "number", "operator", "property", "property.builtin", "punctuation", "punctuation.bracket",
  "punctuation.delimiter", "punctuation.special", "string", "string.special", "tag",
  "type", "type.builtin", "variable", "variable.builtin", "variable.parameter", "comment.documentation",
  "constructor.builtin", "error", "escape", "markup", "markup.bold", "markup.heading",
  "markup.italic", "markup.link", "markup.link.url", "markup.list", "markup.list.checked",
  "markup.list.numbered", "markup.list.unchecked", "markup.list.unnumbered", "markup.quote",
  "markup.raw", "markup.raw.block", "markup.raw.inline", "markup.strikethrough",
  "string.escape", "string.regexp", "string.special.symbol", "variable.member",
]

///|
let all_languages : Array[String] = [
  "bash", "c", "cpp", "embedded-template", "go", "html", "java", "javascript", "jsdoc",
  "json", "python", "ruby", "rust", "typescript", "tsx", "php", "php_only",
]

///|
let ported_scanners : Array[String] = ["bash", "ruby", "python", "cpp", "jsdoc"]

///|
let grammars : String = "/Users/dii/git/treesitter/.repos/ts-pinned/test/fixtures/grammars"

///|
fn fixture_file(name : String) -> String {
  match name {
    "typescript" => "fixture_typescript_typescript"
    "tsx" => "fixture_typescript_tsx"
    "php" => "fixture_php_php"
    "php_only" => "fixture_php_php_only"
    _ => "fixture_\{name}"
  }
}

///|
fn queries_dir(name : String) -> String {
  match name {
    "typescript" | "tsx" => "\{grammars}/typescript/queries"
    "php" | "php_only" => "\{grammars}/php/queries"
    _ => "\{grammars}/\{name}/queries"
  }
}

///|
fn injection_file(name : String) -> String? {
  match name {
    "javascript" | "html" | "rust" | "cpp" | "php" => Some("injections.scm")
    "embedded-template" => Some("injections-ejs.scm")
    _ => None
  }
}

///|
async fn read_text(path : String) -> String? {
  if @fs.exists(path) {
    Some(@fs.read_file(path).text())
  } else {
    None
  }
}

///|
async fn read_query(name : String, file : String) -> String? {
  read_text("\{queries_dir(name)}/\{file}")
}

///|
let languages : Map[String, @treesitter.Language] = Map([])

///|
async fn load_language(name : String) -> @treesitter.Language? {
  if languages.get(name) is Some(language) {
    return Some(language)
  }
  let allowed = match @env.get_env_var("TS_LANGS") {
    Some(list) => list.split(",").any(l => l == name)
    None => true
  }
  guard allowed else { return None }
  guard read_text("_build/reflang/\{fixture_file(name)}.json") is Some(text) else {
    return None
  }
  let raw : @language.Language = @json.from_json(@json.parse(text))
  if raw.external_token_count > 0 && !ported_scanners.contains(name) {
    return None
  }
  let scanner = if raw.external_token_count > 0 {
    @scanners.scanner_for(raw.name)
  } else {
    None
  }
  let language = match scanner {
    Some(scanner) => @treesitter.Language::new(raw, external_scanner=scanner)
    None => @treesitter.Language::new(raw)
  }
  languages[name] = language
  Some(language)
}

///|
let configs : Map[String, @highlight.HighlightConfiguration] = Map([])

///|
async fn load_configs() -> Unit {
  for name in all_languages {
    guard load_language(name) is Some(language) else { continue }
    guard read_query(name, "highlights.scm") is Some(highlights) else {
      continue
    }
    let injections = match injection_file(name) {
      Some(file) => read_query(name, file).unwrap_or("")
      None => ""
    }
    let locals = read_query(name, "locals.scm").unwrap_or("")
    let config = @highlight.HighlightConfiguration::new(
      language, name, highlights, injections, locals,
    )
    config.configure(names)
    configs[name] = config
  }
}

///|
fn injection(name : String) -> @highlight.HighlightConfiguration? {
  configs.get(name)
}

///|
fn escape(s : String) -> String {
  let out = StringBuilder()
  for c in s {
    match c {
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      '"' => out.write_string("\\\"")
      c if c.to_int() < 0x20 => {
        let hex = "0123456789abcdef"
        out.write_string("\\x")
        out.write_char(hex.get_char(c.to_int() >> 4).unwrap())
        out.write_char(hex.get_char(c.to_int() & 15).unwrap())
      }
      c => out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// Print offsets like upstream's `usize`, where `Int::max_value()` stands
/// for `usize::MAX`.
fn usize(x : Int32) -> String {
  if x == 0x7FFFFFFF {
    "18446744073709551615"
  } else {
    x.to_string()
  }
}

///|
fn highlight(name : String, source : Bytes) -> Unit {
  guard configs.get(name) is Some(config) else {
    println("SKIP")
    return
  }
  let highlighter = @highlight.Highlighter::new()
  let events = highlighter.highlight(config, source, injection) catch {
    e => {
      println("ERROR \{e}")
      return
    }
  }
  let collected = []
  while events.next() is Some(event) {
    match event {
      Ok(Source(start~, end~)) => println("S \{start} \{end}")
      Ok(HighlightStart(h)) => println("H \{h.0}")
      Ok(HighlightEnd) => println("E")
      Err(e) => println("ERROR \{e}")
    }
    collected.push(event)
  }
  let renderer = @highlight.HtmlRenderer::new()
  renderer.set_carriage_return_highlight(
    names.search("carriage-return").map(i => @highlight.Highlight(i)),
  )
  renderer.render(collected.iter(), source, (h, out) => {
    for b in @utf8.encode("class=\{names[h.0]}") {
      out.push(b)
    }
  }) catch {
    e => abort(e.to_string())
  }
  for line in renderer.lines() {
    println("HTML \{line.strip_suffix("\n").unwrap_or(line[:])}")
  }
}

///|
async fn tags(name : String, source : Bytes) -> Unit {
  guard load_language(name) is Some(language) else {
    println("SKIP")
    return
  }
  guard read_query(name, "tags.scm") is Some(tags_query) else {
    println("NO TAGS")
    return
  }
  let locals = read_query(name, "locals.scm").unwrap_or("")
  let config = @tags.TagsConfiguration::new(language, tags_query, locals) catch {
    e => {
      println("ERROR \{e}")
      return
    }
  }
  let context = @tags.TagsContext::new()
  let (iter, has_error) = context.generate_tags(config, source) catch {
    e => {
      println("ERROR \{e}")
      return
    }
  }
  println("HAS_ERROR \{has_error}")
  while iter.next() is Some(tag) {
    match tag {
      Err(e) => println("ERROR \{e}")
      Ok(t) => {
        let docs = match t.docs {
          Some(d) => "\"\{escape(d)}\""
          None => "None"
        }
        println(
          "TAG \{if t.is_definition { "def" } else { "ref" }} \{config.syntax_type_name(t.syntax_type_id)} range=\{usize(t.range.0)}..\{usize(t.range.1)} name=\{t.name_range.0}..\{t.name_range.1} line=\{t.line_range.0}..\{t.line_range.1} span=(\{t.span.0.row}, \{t.span.0.column})..(\{t.span.1.row}, \{t.span.1.column}) utf16=\{t.utf16_column_range.0}..\{t.utf16_column_range.1} docs=\{docs}",
        )
      }
    }
  }
}

///|
async fn query_test(name : String, source : Bytes) -> Unit {
  guard load_language(name) is Some(language) else {
    println("SKIP")
    return
  }
  try
    @query_testing.parse_position_comments(@treesitter.Parser::new(), language, source)
  catch {
    e => println("ASSERTIONS ERROR \{e}")
  } noraise {
    assertions =>
      for a in assertions {
        println(
          "ASSERT \{a.position.row} \{a.position.column} len=\{a.length} neg=\{a.negative} \{a.expected_capture_name}",
        )
      }
  }
  if configs.get(name) is Some(config) {
    try
      @query_testing.get_highlight_positions(
        @highlight.Highlighter::new(),
        config,
        injection,
        source,
      )
    catch {
      e => println("HIGHLIGHTS ERROR \{e}")
    } noraise {
      hs =>
        for h in hs {
          println("HPOS \{h.0} \{h.1} \{names[h.2.0]}")
        }
    }
  }
  if read_query(name, "tags.scm") is Some(tags_query) {
    let locals = read_query(name, "locals.scm").unwrap_or("")
    let config = @tags.TagsConfiguration::new(language, tags_query, locals)
    try
      @query_testing.get_tag_positions(@tags.TagsContext::new(), config, source)
    catch {
      e => println("TAGS ERROR \{e}")
    } noraise {
      ts =>
        for t in ts {
          println("TPOS \{t.0} \{t.1} \{t.2}")
        }
    }
  }
}

///|
fn graphemes(source : Bytes) -> Unit {
  for line in @query_testing.lines_with_terminator(source) {
    println(
      @query_testing.grapheme_ends(line).map(e => e.to_string()).join(" "),
    )
  }
}

///|
fn regex_find(source : String) -> Unit {
  let lines = source.split("\n").map(l => l.to_owned()).to_array()
  let mut i = 0
  while i + 1 < lines.length() {
    let pattern = lines[i]
    let hay = lines[i + 1].replace_all(old="\\n", new="\n")
    i += 2
    let regex = @regex.Regex::new(pattern, utf8=true) catch {
      e => {
        println("ERR \{escape(e.to_string())}")
        continue
      }
    }
    println(
      regex.find_iter(@utf8.encode(hay)).map(m => "\{m.0}-\{m.1}").join(" "),
    )
  }
}

///|
async fn main {
  let args = @env.args()
  match args[1] {
    "graphemes" => graphemes(@fs.read_file(args[2]).binary())
    "regex" => regex_find(@fs.read_file(args[2]).text())
    mode => {
      let name = args[2]
      if mode != "tags" {
        load_configs()
      }
      for path in args[3:] {
        let source = @fs.read_file(path).binary()
        println("FILE \{path}")
        match mode {
          "highlight" => highlight(name, source)
          "tags" => tags(name, source)
          "querytest" => query_test(name, source)
          _ => abort("unknown mode")
        }
      }
    }
  }
}

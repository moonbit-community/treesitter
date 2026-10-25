// Port of tree-sitter crates/cli/src/tests/highlight_test.rs.
//
// Tests that need a fixture language whose external scanner is not ported yet
// (javascript, html, rust) are skipped with a notice until it is (see
// fixtures). `test_highlighting_via_c_api` is not ported (the C API is
// not ported).

///|
let highlight_names : Array[String] = [
  "attribute", "boolean", "carriage-return", "comment", "constant", "constant.builtin",
  "constructor", "embedded", "function", "function.builtin", "keyword", "module",
  "number", "operator", "property", "property.builtin", "punctuation", "punctuation.bracket",
  "punctuation.delimiter", "punctuation.special", "string", "string.special", "tag",
  "type", "type.builtin", "variable", "variable.builtin", "variable.parameter",
]

///|
let html_attrs : Array[String] = highlight_names.map(s => "class=\{s}")

///|
/// The configurations of upstream's `JS_HIGHLIGHT`, `JSDOC_HIGHLIGHT`,
/// `HTML_HIGHLIGHT`, `EJS_HIGHLIGHT` and `RUST_HIGHLIGHT`, by language name.
let configs : Map[String, @highlight.HighlightConfiguration?] = Map([])

///|
async fn config(name : String) -> @highlight.HighlightConfiguration? {
  if configs.get(name) is Some(config) {
    return config
  }
  let config = match name {
    "javascript" =>
      @fixtures.get_highlight_config(
        "javascript",
        Some("injections.scm"),
        highlight_names,
      )
    "jsdoc" => @fixtures.get_highlight_config("jsdoc", None, highlight_names)
    "html" =>
      @fixtures.get_highlight_config(
        "html",
        Some("injections.scm"),
        highlight_names,
      )
    "embedded-template" =>
      @fixtures.get_highlight_config(
        "embedded-template",
        Some("injections-ejs.scm"),
        highlight_names,
      )
    "rust" =>
      @fixtures.get_highlight_config(
        "rust",
        Some("injections.scm"),
        highlight_names,
      )
    _ => None
  }
  configs[name] = config
  config
}

///|
/// The configuration for `name`, provided that every language of
/// `test_language_for_injection_string` is available (otherwise the
/// injections, and hence the results, would differ from upstream's).
async fn test_config(name : String) -> @highlight.HighlightConfiguration? {
  for injected in ["javascript", "html", "rust", "jsdoc"] {
    guard config(injected) is Some(_) else { return None }
  }
  config(name)
}

///|
fn test_language_for_injection_string(
  string : String,
) -> @highlight.HighlightConfiguration? {
  match string {
    "javascript" | "html" | "rust" | "jsdoc" =>
      match configs.get(string) {
        Some(config) => config
        None => None
      }
    _ => None
  }
}

///|
fn utf8(s : String) -> Bytes {
  @utf8.encode(s)
}

///|
fn to_html(
  src : String,
  language_config : @highlight.HighlightConfiguration,
) -> Array[String] raise @highlight.HighlightError {
  let src = utf8(src)
  let renderer = @highlight.HtmlRenderer::new()
  let highlighter = @highlight.Highlighter::new()
  let events = highlighter.highlight(
    language_config, src, test_language_for_injection_string,
  )
  renderer.set_carriage_return_highlight(
    highlight_names.search("carriage-return").map(i => @highlight.Highlight(i)),
  )
  renderer.render(events.iter(), src, (highlight, output) => {
    for b in utf8(html_attrs[highlight.0]) {
      output.push(b)
    }
  })
  renderer.lines().to_array()
}

///|
fn to_token_vector(
  src : String,
  language_config : @highlight.HighlightConfiguration,
) -> Array[Array[(String, Array[String])]] raise @highlight.HighlightError {
  let src = utf8(src)
  let highlighter = @highlight.Highlighter::new()
  let lines = []
  let highlights = []
  let mut line = []
  let events = highlighter.highlight(
    language_config, src, test_language_for_injection_string,
  )
  while events.next() is Some(event) {
    match event {
      Err(e) => raise e
      Ok(HighlightStart(s)) => highlights.push(highlight_names[s.0])
      Ok(HighlightEnd) => ignore(highlights.pop())
      Ok(Source(start~, end~)) => {
        let s = @utf8.decode(src[start:end]) catch { _ => abort("not UTF-8") }
        for i, l in s.split("\n").to_array() {
          let mut l = l
          while l.has_suffix("\r") {
            l = l[:l.length() - 1]
          }
          if i > 0 {
            lines.push(line)
            line = []
          }
          if !l.is_empty() {
            line.push((l.to_owned(), highlights.copy()))
          }
        }
      }
    }
  }
  if !line.is_empty() {
    lines.push(line)
  }
  lines
}

///|
async test "highlighting_javascript" {
  guard test_config("javascript") is Some(js) else { return }
  let source = "const a = function(b) { return b + c; }"
  assert_eq(to_token_vector(source, js), [
    [
      ("const", ["keyword"]),
      (" ", []),
      ("a", ["function"]),
      (" ", []),
      ("=", ["operator"]),
      (" ", []),
      ("function", ["keyword"]),
      ("(", ["punctuation.bracket"]),
      ("b", ["variable"]),
      (")", ["punctuation.bracket"]),
      (" ", []),
      ("{", ["punctuation.bracket"]),
      (" ", []),
      ("return", ["keyword"]),
      (" ", []),
      ("b", ["variable"]),
      (" ", []),
      ("+", ["operator"]),
      (" ", []),
      ("c", ["variable"]),
      (";", ["punctuation.delimiter"]),
      (" ", []),
      ("}", ["punctuation.bracket"]),
    ],
  ])
}

///|
async test "highlighting_injected_html_in_javascript" {
  guard test_config("javascript") is Some(js) else { return }
  let source = "const s = html `<div>${a < b}</div>`;"
  assert_eq(to_token_vector(source, js), [
    [
      ("const", ["keyword"]),
      (" ", []),
      ("s", ["variable"]),
      (" ", []),
      ("=", ["operator"]),
      (" ", []),
      ("html", ["function"]),
      (" ", []),
      ("`", ["string"]),
      ("<", ["string", "punctuation.bracket"]),
      ("div", ["string", "tag"]),
      (">", ["string", "punctuation.bracket"]),
      ("${", ["string", "embedded", "punctuation.special"]),
      ("a", ["string", "embedded", "variable"]),
      (" ", ["string", "embedded"]),
      ("<", ["string", "embedded", "operator"]),
      (" ", ["string", "embedded"]),
      ("b", ["string", "embedded", "variable"]),
      ("}", ["string", "embedded", "punctuation.special"]),
      ("</", ["string", "punctuation.bracket"]),
      ("div", ["string", "tag"]),
      (">", ["string", "punctuation.bracket"]),
      ("`", ["string"]),
      (";", ["punctuation.delimiter"]),
    ],
  ])
}

///|
async test "highlighting_injected_javascript_in_html_mini" {
  guard test_config("html") is Some(html) else { return }
  let source = "<script>const x = new Thing();</script>"
  assert_eq(to_token_vector(source, html), [
    [
      ("<", ["punctuation.bracket"]),
      ("script", ["tag"]),
      (">", ["punctuation.bracket"]),
      ("const", ["keyword"]),
      (" ", []),
      ("x", ["variable"]),
      (" ", []),
      ("=", ["operator"]),
      (" ", []),
      ("new", ["keyword"]),
      (" ", []),
      ("Thing", ["constructor"]),
      ("(", ["punctuation.bracket"]),
      (")", ["punctuation.bracket"]),
      (";", ["punctuation.delimiter"]),
      ("</", ["punctuation.bracket"]),
      ("script", ["tag"]),
      (">", ["punctuation.bracket"]),
    ],
  ])
}

///|
async test "highlighting_injected_javascript_in_html" {
  guard test_config("html") is Some(html) else { return }
  let source = [
    "<body>", "  <script>", "    const x = new Thing();", "  </script>", "</body>",
  ].join("\n")
  assert_eq(to_token_vector(source, html), [
    [
      ("<", ["punctuation.bracket"]),
      ("body", ["tag"]),
      (">", ["punctuation.bracket"]),
    ],
    [
      ("  ", []),
      ("<", ["punctuation.bracket"]),
      ("script", ["tag"]),
      (">", ["punctuation.bracket"]),
    ],
    [
      ("    ", []),
      ("const", ["keyword"]),
      (" ", []),
      ("x", ["variable"]),
      (" ", []),
      ("=", ["operator"]),
      (" ", []),
      ("new", ["keyword"]),
      (" ", []),
      ("Thing", ["constructor"]),
      ("(", ["punctuation.bracket"]),
      (")", ["punctuation.bracket"]),
      (";", ["punctuation.delimiter"]),
    ],
    [
      ("  ", []),
      ("</", ["punctuation.bracket"]),
      ("script", ["tag"]),
      (">", ["punctuation.bracket"]),
    ],
    [
      ("</", ["punctuation.bracket"]),
      ("body", ["tag"]),
      (">", ["punctuation.bracket"]),
    ],
  ])
}

///|
async test "highlighting_multiline_nodes_to_html" {
  guard test_config("javascript") is Some(js) else { return }
  let source = [
    "const SOMETHING = `", "  one ${", "    two()", "  } three", "`", "",
  ].join("\n")
  assert_eq(to_html(source, js), [
    "<span class=keyword>const</span> <span class=constant>SOMETHING</span> <span class=operator>=</span> <span class=string>`</span>\n",
    "<span class=string>  one <span class=embedded><span class=punctuation.special>${</span></span></span>\n",
    "<span class=string><span class=embedded>    <span class=function>two</span><span class=punctuation.bracket>(</span><span class=punctuation.bracket>)</span></span></span>\n",
    "<span class=string><span class=embedded>  <span class=punctuation.special>}</span></span> three</span>\n",
    "<span class=string>`</span>\n",
  ])
}

///|
async test "highlighting_with_local_variable_tracking" {
  guard test_config("javascript") is Some(js) else { return }
  let source = [
    "module.exports = function a(b) {", "  const module = c;", "  console.log(module, b);",
    "}",
  ].join("\n")
  assert_eq(to_token_vector(source, js), [
    [
      ("module", ["variable.builtin"]),
      (".", ["punctuation.delimiter"]),
      ("exports", ["function"]),
      (" ", []),
      ("=", ["operator"]),
      (" ", []),
      ("function", ["keyword"]),
      (" ", []),
      ("a", ["function"]),
      ("(", ["punctuation.bracket"]),
      ("b", ["variable"]),
      (")", ["punctuation.bracket"]),
      (" ", []),
      ("{", ["punctuation.bracket"]),
    ],
    [
      ("  ", []),
      ("const", ["keyword"]),
      (" ", []),
      ("module", ["variable"]),
      (" ", []),
      ("=", ["operator"]),
      (" ", []),
      ("c", ["variable"]),
      (";", ["punctuation.delimiter"]),
    ],
    [
      ("  ", []),
      ("console", ["variable.builtin"]),
      (".", ["punctuation.delimiter"]),
      ("log", ["function"]),
      ("(", ["punctuation.bracket"]),
      // Not a builtin, because `module` was defined as a variable above.
      ("module", ["variable"]),
      (",", ["punctuation.delimiter"]),
      (" ", []),
      // A parameter, because `b` was defined as a parameter above.
      ("b", ["variable"]),
      (")", ["punctuation.bracket"]),
      (";", ["punctuation.delimiter"]),
    ],
    [("}", ["punctuation.bracket"])],
  ])
}

///|
async test "highlighting_empty_lines" {
  guard test_config("javascript") is Some(js) else { return }
  let source = ["class A {", "", "  b(c) {", "", "    d(e)", "", "  }", "", "}"].join(
    "\n",
  )
  assert_eq(to_html(source, js), [
    "<span class=keyword>class</span> <span class=constructor>A</span> <span class=punctuation.bracket>{</span>\n",
    "\n", "  <span class=function>b</span><span class=punctuation.bracket>(</span><span class=variable>c</span><span class=punctuation.bracket>)</span> <span class=punctuation.bracket>{</span>\n",
    "\n", "    <span class=function>d</span><span class=punctuation.bracket>(</span><span class=variable>e</span><span class=punctuation.bracket>)</span>\n",
    "\n", "  <span class=punctuation.bracket>}</span>\n", "\n", "<span class=punctuation.bracket>}</span>\n",
  ])
}

///|
async test "highlighting_carriage_returns" {
  guard test_config("javascript") is Some(js) else { return }
  let source = "a = \"a\rb\"\r\nb\r"
  assert_eq(to_html(source, js), [
    "<span class=variable>a</span> <span class=operator>=</span> <span class=string>&quot;a<span class=carriage-return></span><span class=variable>b</span>&quot;</span>\n",
    "<span class=variable>b</span><span class=carriage-return></span>\n",
  ])
}

///|
async test "highlighting_ejs_with_html_and_javascript" {
  guard test_config("embedded-template") is Some(ejs) else { return }
  let source = "<div><% foo() %></div><script> bar() </script>"
  assert_eq(to_token_vector(source, ejs), [
    [
      ("<", ["punctuation.bracket"]),
      ("div", ["tag"]),
      (">", ["punctuation.bracket"]),
      ("<%", ["keyword"]),
      (" ", []),
      ("foo", ["function"]),
      ("(", ["punctuation.bracket"]),
      (")", ["punctuation.bracket"]),
      (" ", []),
      ("%>", ["keyword"]),
      ("</", ["punctuation.bracket"]),
      ("div", ["tag"]),
      (">", ["punctuation.bracket"]),
      ("<", ["punctuation.bracket"]),
      ("script", ["tag"]),
      (">", ["punctuation.bracket"]),
      (" ", []),
      ("bar", ["function"]),
      ("(", ["punctuation.bracket"]),
      (")", ["punctuation.bracket"]),
      (" ", []),
      ("</", ["punctuation.bracket"]),
      ("script", ["tag"]),
      (">", ["punctuation.bracket"]),
    ],
  ])
}

///|
async test "highlighting_javascript_with_jsdoc" {
  guard test_config("javascript") is Some(js) else { return }
  // Regression test: the middle comment has no highlights. This should not prevent
  // later injections from highlighting properly.
  let source = "a /* @see a */ b; /* nothing */ c; /* @see b */"
  assert_eq(to_token_vector(source, js), [
    [
      ("a", ["variable"]),
      (" ", []),
      ("/* ", ["comment"]),
      ("@see", ["comment", "keyword"]),
      (" a */", ["comment"]),
      (" ", []),
      ("b", ["variable"]),
      (";", ["punctuation.delimiter"]),
      (" ", []),
      ("/* nothing */", ["comment"]),
      (" ", []),
      ("c", ["variable"]),
      (";", ["punctuation.delimiter"]),
      (" ", []),
      ("/* ", ["comment"]),
      ("@see", ["comment", "keyword"]),
      (" b */", ["comment"]),
    ],
  ])
}

///|
async test "highlighting_with_content_children_included" {
  guard test_config("rust") is Some(rust) else { return }
  let source = ["assert!(", "    a.b.c() < D::e::<F>()", ");"].join("\n")
  assert_eq(to_token_vector(source, rust), [
    [
      ("assert", ["function"]),
      ("!", ["function"]),
      ("(", ["punctuation.bracket"]),
    ],
    [
      ("    a", []),
      (".", ["punctuation.delimiter"]),
      ("b", ["property"]),
      (".", ["punctuation.delimiter"]),
      ("c", ["function"]),
      ("(", ["punctuation.bracket"]),
      (")", ["punctuation.bracket"]),
      (" < ", []),
      ("D", ["type"]),
      ("::", ["punctuation.delimiter"]),
      ("e", ["function"]),
      ("::", ["punctuation.delimiter"]),
      ("<", ["punctuation.bracket"]),
      ("F", ["type"]),
      (">", ["punctuation.bracket"]),
      ("(", ["punctuation.bracket"]),
      (")", ["punctuation.bracket"]),
    ],
    [(")", ["punctuation.bracket"]), (";", ["punctuation.delimiter"])],
  ])
}

///|
async test "highlighting_cancellation" {
  guard test_config("html") is Some(html) else { return }
  // An HTML document with a large injected JavaScript document:
  let source = StringBuilder()
  source.write_string("<script>\n")
  for _ in 0..<500 {
    source.write_string("function a() { console.log('hi'); }\n")
  }
  source.write_string("</script>\n")
  let source = utf8(source.to_string())

  // Cancel the highlighting before parsing the injected document.
  let cancellation_flag = Ref::{ val: 0, }
  let injection_callback = name => {
    cancellation_flag.val = 1
    test_language_for_injection_string(name)
  }

  // The initial `highlight` call, which eagerly parses the outer document, should not fail.
  let highlighter = @highlight.Highlighter::new()
  let events = highlighter.highlight(
    html,
    source,
    cancellation_flag~,
    injection_callback,
  )

  // Iterating the scopes should not panic. It should return an error once the
  // cancellation is detected.
  let found_cancellation_error = events
    .iter()
    .any(event => {
      match event {
        Ok(_) => false
        Err(Cancelled) => true
        Err(InvalidLanguage(_) | Unknown) =>
          abort("Unexpected error type while iterating events")
      }
    })
  assert_true(
    found_cancellation_error,
    msg="Expected a cancellation error while iterating events",
  )
}

///|
async test "highlighting_with_all_captures_applied" {
  guard @fixtures.get_language("rust") is Some(language) else { return }
  let source = "fn main(a: u32, b: u32) -> { let c = a + b; }"
  let highlights_query =
    #|[
    #|  "fn"
    #|  "let"
    #|] @keyword
    #|(identifier) @variable
    #|(function_item name: (identifier) @function)
    #|(parameter pattern: (identifier) @variable.parameter)
    #|(primitive_type) @type.builtin
    #|"=" @operator
    #|[ "->" ":" ";" ] @punctuation.delimiter
    #|[ "{" "}" "(" ")" ] @punctuation.bracket
    #|
  let rust_highlight_reverse = @highlight.HighlightConfiguration::new(
    language, "rust", highlights_query, "", "",
  )
  rust_highlight_reverse.configure(highlight_names)
  assert_eq(to_token_vector(source, rust_highlight_reverse), [
    [
      ("fn", ["keyword"]),
      (" ", []),
      ("main", ["function"]),
      ("(", ["punctuation.bracket"]),
      ("a", ["variable.parameter"]),
      (":", ["punctuation.delimiter"]),
      (" ", []),
      ("u32", ["type.builtin"]),
      (", ", []),
      ("b", ["variable.parameter"]),
      (":", ["punctuation.delimiter"]),
      (" ", []),
      ("u32", ["type.builtin"]),
      (")", ["punctuation.bracket"]),
      (" ", []),
      ("->", ["punctuation.delimiter"]),
      (" ", []),
      ("{", ["punctuation.bracket"]),
      (" ", []),
      ("let", ["keyword"]),
      (" ", []),
      ("c", ["variable"]),
      (" ", []),
      ("=", ["operator"]),
      (" ", []),
      ("a", ["variable"]),
      (" + ", []),
      ("b", ["variable"]),
      (";", ["punctuation.delimiter"]),
      (" ", []),
      ("}", ["punctuation.bracket"]),
    ],
  ])
}

///|
test "decode_utf8_lossy" {
  let parts = @treesitter.LossyUtf8::new(b"hi").iter().to_array()
  assert_eq(parts, ["hi"])
  let parts = @treesitter.LossyUtf8::new(b"hi\xc0\xc1bye").iter().to_array()
  assert_eq(parts, ["hi", "\u{fffd}", "\u{fffd}", "bye"])
  let parts = @treesitter.LossyUtf8::new(b"\xc0\xc1bye").iter().to_array()
  assert_eq(parts, ["\u{fffd}", "\u{fffd}", "bye"])
  let parts = @treesitter.LossyUtf8::new(b"hello\xc0\xc1").iter().to_array()
  assert_eq(parts, ["hello", "\u{fffd}", "\u{fffd}"])
}

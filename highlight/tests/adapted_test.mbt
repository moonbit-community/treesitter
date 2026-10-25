// Highlighting tests on fixture languages whose external scanners are
// ported, complementing the upstream tests (which mostly need javascript,
// html and rust). Expected outputs come from upstream's
// `tree-sitter-highlight` (the pinned crate) run on the same fixture parsers
// and queries, with the `highlight_names` of highlight_test.mbt.

///|
async fn adapted_config(
  name : String,
  injections~ : String = "",
) -> @highlight.HighlightConfiguration? {
  guard @fixtures.get_language(name) is Some(language) else { return None }
  guard @fixtures.read_query(name, "highlights.scm") is Some(highlights) else {
    return None
  }
  let locals = @fixtures.read_query(name, "locals.scm").unwrap_or("")
  let config = @highlight.HighlightConfiguration::new(
    language, name, highlights, injections, locals,
  )
  config.configure(highlight_names)
  Some(config)
}

///|
fn adapted_html(
  src : Bytes,
  config : @highlight.HighlightConfiguration,
  callback : (String) -> @highlight.HighlightConfiguration?,
) -> Array[String] raise @highlight.HighlightError {
  let renderer = @highlight.HtmlRenderer::new()
  let highlighter = @highlight.Highlighter::new()
  let events = highlighter.highlight(config, src, callback)
  renderer.set_carriage_return_highlight(
    highlight_names.search("carriage-return").map(i => @highlight.Highlight(i)),
  )
  renderer.render(events.iter(), src, (h, out) => {
    for b in utf8(html_attrs[h.0]) {
      out.push(b)
    }
  })
  renderer.lines().to_array()
}

///|
async test "adapted: ruby local variable tracking" {
  guard adapted_config("ruby") is Some(ruby) else { return }
  let src = utf8(
    "def foo(a)\n  b = a\n  [1].each do |c|\n    puts a, b, c, d\n  end\nend\nputs a\n",
  )
  assert_eq(adapted_html(src, ruby, _ => None), [
    "<span class=keyword>def</span> <span class=function>foo</span><span class=punctuation.bracket>(</span><span class=variable.parameter>a</span><span class=punctuation.bracket>)</span>\n",
    "  <span class=variable>b</span> <span class=operator>=</span> <span class=variable.parameter>a</span>\n",
    "  <span class=punctuation.bracket>[</span><span class=number>1</span><span class=punctuation.bracket>]</span><span class=punctuation.delimiter>.</span><span class=function>each</span> <span class=keyword>do</span> |<span class=variable.parameter>c</span>|\n",
    "    <span class=function>puts</span> <span class=variable.parameter>a</span><span class=punctuation.delimiter>,</span> <span class=variable>b</span><span class=punctuation.delimiter>,</span> <span class=variable.parameter>c</span><span class=punctuation.delimiter>,</span> <span class=function>d</span>\n",
    "  <span class=keyword>end</span>\n", "<span class=keyword>end</span>\n", "<span class=function>puts</span> <span class=function>a</span>\n",
  ])
}

///|
async test "adapted: cpp raw string injection" {
  guard adapted_config("python") is Some(python) else { return }
  guard @fixtures.read_query("cpp", "injections.scm") is Some(injections) else {
    return
  }
  guard adapted_config("cpp", injections~) is Some(cpp) else { return }
  let src = utf8(
    "auto s = R\"python(def f(x):\n  return x)python\";\nauto t = R\"ruby(puts 1)ruby\";\n",
  )
  assert_eq(
    adapted_html(src, cpp, n => if n == "python" { Some(python) } else { None }),
    [
      "<span class=type>auto</span> s = <span class=string>R&quot;python(def f(x):</span>\n",
      "<span class=string>  return x)python&quot;</span>;\n", "<span class=type>auto</span> t = <span class=string>R&quot;ruby(puts 1)ruby&quot;</span>;\n",
    ],
  )
}

///|
async test "adapted: combined injections" {
  guard adapted_config("ruby") is Some(ruby) else { return }
  let injections =
    #|((code) @injection.content (#set! injection.language "ruby") (#set! injection.combined))
    #|
  guard adapted_config("embedded-template", injections~) is Some(erb) else {
    return
  }
  let src = utf8("<% if x %>hello <%= y %><% y = 1 %>\n<% end %><%# note %>")
  assert_eq(
    adapted_html(src, erb, n => if n == "ruby" { Some(ruby) } else { None }),
    [
      "<span class=keyword>&lt;%</span> <span class=keyword>if</span> <span class=function>x</span> <span class=keyword>%&gt;</span>hello <span class=keyword>&lt;%=</span> <span class=function>y</span> <span class=keyword>%&gt;</span><span class=keyword>&lt;%</span> <span class=variable>y</span> <span class=operator>=</span> <span class=number>1</span> <span class=keyword>%&gt;</span>\n",
      "<span class=keyword>&lt;%</span> <span class=keyword>end</span> <span class=keyword>%&gt;</span><span class=comment><span class=keyword>&lt;%#</span> note <span class=keyword>%&gt;</span></span>\n",
    ],
  )
}

///|
async test "adapted: escaping, carriage returns and invalid UTF-8" {
  guard adapted_config("python") is Some(python) else { return }
  let src = b"x = \"<a&b>'\"\r\ny = '\xff\xfe'\rz = 1\r"
  assert_eq(adapted_html(src, python, _ => None), [
    "<span class=variable>x</span> <span class=operator>=</span> <span class=string>&quot;&lt;a&amp;b&gt;&#39;&quot;</span>\n",
    "<span class=variable>y</span> <span class=operator>=</span> <span class=string>&#39;\u{fffd}\u{fffd}&#39;</span><span class=carriage-return></span><span class=variable>z</span> <span class=operator>=</span> <span class=number>1</span><span class=carriage-return></span>\n",
  ])
}

///|
async test "adapted: c and bash" {
  guard adapted_config("c") is Some(c) else { return }
  let src = utf8("int main(void) {\n  return 0; // done\n}\n")
  assert_eq(adapted_html(src, c, _ => None), [
    "<span class=type>int</span> <span class=function>main</span>(<span class=type>void</span>) {\n",
    "  <span class=keyword>return</span> <span class=number>0</span>; <span class=comment>// done</span>\n",
    "}\n",
  ])
  guard adapted_config("bash") is Some(bash) else { return }
  let src = utf8(
    "cat <<EOF\nhello $USER\nEOF\nfor i in 1 2; do echo \"$i\"; done\n",
  )
  assert_eq(adapted_html(src, bash, _ => None), [
    "<span class=function>cat</span> &lt;&lt;<span class=string>EOF</span>\n", "<span class=string>hello <span class=operator>$</span><span class=property>USER</span></span>\n",
    "<span class=string></span>EOF\n", "<span class=keyword>for</span> <span class=property>i</span> <span class=keyword>in</span> 1 2; <span class=keyword>do</span> <span class=function>echo</span> <span class=string>&quot;<span class=operator>$</span><span class=property>i</span>&quot;</span>; <span class=keyword>done</span>\n",
  ])
}

///|
async test "adapted: cancellation" {
  guard adapted_config("python") is Some(python) else { return }
  let source = StringBuilder()
  for _ in 0..<200 {
    source.write_string("def f(a):\n  return a + 1\n")
  }
  let source = utf8(source.to_string())

  // A flag that is already set makes the initial parse fail.
  let highlighter = @highlight.Highlighter::new()
  let flag = Ref::{ val: 1, }
  try
    highlighter.highlight(python, source, cancellation_flag=flag, _ => None)
    |> ignore
  catch {
    e => inspect(e, content="Cancelled")
  } noraise {
    _ => fail("expected the initial parse to be cancelled")
  }

  // A flag set while iterating is noticed within 100 events.
  let flag = Ref::{ val: 0, }
  let events = highlighter.highlight(python, source, cancellation_flag=flag, _ => {
    None
  })
  let mut count = 0
  let mut cancelled_after = None
  while events.next() is Some(event) {
    count += 1
    if count == 10 {
      flag.val = 1
    }
    if event is Err(Cancelled) {
      cancelled_after = Some(count)
      break
    }
  }
  assert_true(cancelled_after is Some(_))
}

///|
async test "adapted: nonconformant capture names" {
  let set = @hashset.HashSet::from_array(["keyword", "string"])
  guard adapted_config("python") is Some(python) else { return }
  debug_inspect(
    python.nonconformant_capture_names(@hashset.HashSet([])),
    content=(
      #|["function.method"]
    ),
  )
  debug_inspect(
    python.nonconformant_capture_names(set),
    content=(
      #|[
      #|  "variable",
      #|  "constructor",
      #|  "constant",
      #|  "function",
      #|  "function.method",
      #|  "function.builtin",
      #|  "property",
      #|  "type",
      #|  "constant.builtin",
      #|  "number",
      #|  "comment",
      #|  "escape",
      #|  "punctuation.special",
      #|  "embedded",
      #|  "operator",
      #|]
    ),
  )
  guard adapted_config("ruby") is Some(ruby) else { return }
  debug_inspect(
    ruby.nonconformant_capture_names(@hashset.HashSet([])),
    content=(
      #|[
      #|  "local.scope",
      #|  "local.definition",
      #|  "local.reference",
      #|  "function.method",
      #|  "function.method.builtin",
      #|  "string.special.regex",
      #|]
    ),
  )
  guard adapted_config("c") is Some(c) else { return }
  debug_inspect(
    c.nonconformant_capture_names(@hashset.HashSet([])),
    content=(
      #|["delimiter", "label", "function.special"]
    ),
  )
}

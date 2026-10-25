// Tests of `HtmlRenderer` (crates/highlight/src/highlight.rs).

///|
/// The events of `source` highlighted as a whole with highlight 0.
fn whole_source_events(
  source : Bytes,
) -> Iter[Result[@highlight.HighlightEvent, @highlight.HighlightError]] {
  let events : Array[
    Result[@highlight.HighlightEvent, @highlight.HighlightError],
  ] = [
    Ok(HighlightStart(@highlight.Highlight(0))),
    Ok(Source(start=0, end=source.length())),
    Ok(HighlightEnd),
  ]
  events.iter()
}

///|
test "panic html lines with invalid utf-8" {
  // `str::from_utf8(..).unwrap()` panics on the byte the callback writes.
  let renderer = @highlight.HtmlRenderer::new()
  renderer.render(whole_source_events(b"a"), b"a", (_, attrs) => {
    attrs.push(0xFF)
  })
  ignore(renderer.lines().collect())
}

///|
test "html lines" {
  let renderer = @highlight.HtmlRenderer::new()
  renderer.render(whole_source_events(b"a\nb"), b"a\nb", (_, attrs) => {
    for b in b"class=x" {
      attrs.push(b)
    }
  })
  debug_inspect(
    renderer.lines().collect(),
    content=(
      #|["<span class=x>a</span>\n", "<span class=x>b</span>\n"]
    ),
  )
}

///|
#cfg(not(target="js"))
test "reset shrinks the buffers to their reserve capacity" {
  let renderer = @highlight.HtmlRenderer::new()
  let source = "x\n".repeat(5000)
  let source = @utf8.encode(source)
  renderer.render(whole_source_events(source), source, (_, _) => ())
  assert_true(renderer.html.capacity() > 10 * 1024)
  assert_true(renderer.line_offsets.capacity() > 1000)
  renderer.reset()
  inspect(renderer.html.length(), content="0")
  inspect(renderer.html.capacity(), content="10240")
  debug_inspect(renderer.line_offsets, content="[0]")
  inspect(renderer.line_offsets.capacity(), content="1000")
  // Smaller buffers keep their capacity.
  let source = b"x\n"
  renderer.render(whole_source_events(source), source, (_, _) => ())
  renderer.reset()
  inspect(renderer.html.capacity(), content="10240")
}

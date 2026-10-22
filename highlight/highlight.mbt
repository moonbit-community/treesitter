///|
pub(all) enum Event {
  Start(String)
  End
  Source(Int32, Int32)
} derive(Debug, Eq)

///|
pub extend Event with Eq::{equal, not_equal}

///|
pub extend Event with @debug.Debug::{to_repr}

///|
pub struct Configuration {
  language : @language.Language
  priv query : @query.Query
  priv names : Array[String]
}

///|
pub fn Configuration::new(
  language : @language.Language,
  highlights : String,
  names~ : Array[String] = [],
) -> Configuration raise @query.QueryError {
  { language, query: @query.Query::new(language, highlights), names, }
}

///|
fn Configuration::name(self : Configuration, capture : String) -> String? {
  if self.names.is_empty() {
    return Some(capture)
  }
  let mut best : String? = None
  for name in self.names {
    if capture == name || capture.has_prefix(name + ".") {
      if best is None || name.length() > best.unwrap().length() {
        best = Some(name)
      }
    }
  }
  best
}

///|
priv struct Span {
  start : Int32
  end : Int32
  name : String
  priority : Int32
} derive(Eq)

///|
/// Produce a balanced event stream covering every source byte, including
/// unhighlighted text. Nested and crossing captures are closed and reopened at
/// boundaries; earlier query patterns win ties for identical ranges.
pub fn Configuration::highlight(
  self : Configuration,
  tree : @ts.Tree,
  cancelled~ : () -> Bool = () => false,
) -> Array[Event] raise @query.QueryError {
  let spans : Array[Span] = []
  for matched in self.query.matches(tree.root_node(), tree.source, cancelled~) {
    for capture in matched.captures {
      if capture.node.end_byte() > capture.node.start_byte() &&
        self.name(capture.name) is Some(name) {
        spans.push({
          start: capture.node.start_byte(),
          end: capture.node.end_byte(),
          name,
          priority: matched.pattern_index,
        })
      }
    }
  }
  spans.sort_by_key(s => s.start)
  let boundaries = [0, tree.source.length()]
  for span in spans {
    boundaries.push(span.start)
    boundaries.push(span.end)
  }
  boundaries.sort()
  let events : Array[Event] = []
  let mut stack : Array[Span] = []
  let mut active : Array[Span] = []
  let mut incoming = 0
  for i in 0..<(boundaries.length() - 1) {
    if cancelled() {
      raise Cancelled
    }
    let start = boundaries[i]
    let end = boundaries[i + 1]
    if start == end {
      continue
    }
    active = active.filter(s => s.end > start)
    while incoming < spans.length() && spans[incoming].start <= start {
      active.push(spans[incoming])
      incoming += 1
    }
    active.sort_by((a, b) => {
      let by_start = a.start.compare(b.start)
      if by_start != 0 {
        by_start
      } else {
        let by_end = b.end.compare(a.end)
        if by_end != 0 {
          by_end
        } else {
          a.priority.compare(b.priority)
        }
      }
    })
    let selected : Array[Span] = []
    for span in active {
      if selected.last() is Some(previous) &&
        previous.start == span.start &&
        previous.end == span.end {
        continue
      }
      selected.push(span)
    }
    let mut common = 0
    while common < stack.length() &&
          common < selected.length() &&
          stack[common] == selected[common] {
      common += 1
    }
    for _ in common..<stack.length() {
      events.push(End)
    }
    for j in common..<selected.length() {
      events.push(Start(selected[j].name))
    }
    events.push(Source(start, end))
    stack = selected
  }
  for _ in stack {
    events.push(End)
  }
  events
}

///|
fn escape(text : String) -> String {
  let output = StringBuilder()
  for c in text {
    match c {
      '&' => output.write_string("&amp;")
      '<' => output.write_string("&lt;")
      '>' => output.write_string("&gt;")
      '"' => output.write_string("&quot;")
      '\'' => output.write_string("&#39;")
      _ => output.write_char(c)
    }
  }
  output.to_string()
}

///|
pub fn Configuration::html(
  self : Configuration,
  tree : @ts.Tree,
) -> String raise @query.QueryError {
  let output = StringBuilder()
  for event in self.highlight(tree) {
    match event {
      Start(name) => output.write_string("<span class=\"\{escape(name)}\">")
      End => output.write_string("</span>")
      Source(start, end) =>
        output.write_string(escape(@utf8.decode_lossy(tree.source[start:end])))
    }
  }
  output.to_string()
}

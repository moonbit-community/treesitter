///|
pub suberror HighlightError {
  InjectionLimit
}

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
  priv locals : @query.Query
  priv injections : @query.Query
  priv scanner : @ts.ExternalScanner?
}

///|
pub fn Configuration::new(
  language : @language.Language,
  highlights : String,
  names~ : Array[String] = [],
  locals~ : String = "",
  injections~ : String = "",
  scanner? : @ts.ExternalScanner,
) -> Configuration raise @query.QueryError {
  {
    language,
    query: @query.Query::new(language, highlights),
    names,
    locals: @query.Query::new(language, locals),
    injections: @query.Query::new(language, injections),
    scanner,
  }
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
  injection~ : (String) -> Configuration? = _ => None,
  max_injection_depth~ : Int32 = 32,
) -> Array[Event] raise {
  let spans = self.collect(
    tree,
    injection,
    cancelled,
    0,
    max_injection_depth,
    None,
  )
  render_events(spans, tree.source.length(), cancelled)
}

///|
fn Configuration::collect(
  self : Configuration,
  tree : @ts.Tree,
  injection : (String) -> Configuration?,
  cancelled : () -> Bool,
  depth : Int32,
  max_depth : Int32,
  parent : Configuration?,
) -> Array[Span] raise {
  let spans : Array[Span] = []
  let locals = @query.Locals::new(self.locals, tree)
  let definitions : Map[(Int32, Int32), String] = Map([])
  for
    matched in self.query.matches(tree.root_node(), tree.source, cancelled~, property=(
      key,
      _,
      node,
    ) => key == "local" && node is Some(node) && locals.is_local(node)) {
    for capture in matched.captures {
      if capture.node.end_byte() > capture.node.start_byte() &&
        self.name(capture.name) is Some(name) {
        let definition = locals.definition(capture.node)
        if definition is Some(node) &&
          node.start_byte() == capture.node.start_byte() {
          let key = (node.start_byte(), node.end_byte())
          if !definitions.contains(key) {
            definitions[key] = name
          }
        }
        let name = match definition {
          Some(node) =>
            definitions
            .get((node.start_byte(), node.end_byte()))
            .unwrap_or(name)
          None => name
        }
        add_span(
          spans,
          tree,
          capture.node.start_byte(),
          capture.node.end_byte(),
          name,
          matched.pattern_index - depth * 100000,
        )
      }
    }
  }
  let groups : Array[(Configuration, Array[@ts.Range], Int32)] = []
  for
    matched in self.injections.matches(
      tree.root_node(),
      tree.source,
      cancelled~,
    ) {
    let language_name = matched.captures
      .filter(c => c.name == "injection.language")
      .get(0)
      .map(c => c.node.text(tree.source))
    let config = if matched.properties.contains("injection.self") {
      Some(self)
    } else if matched.properties.contains("injection.parent") {
      parent
    } else {
      match
        (if language_name is Some(_) {
          language_name
        } else {
          matched.properties.get("injection.language")
        }) {
        Some(name) => injection(name)
        None => None
      }
    }
    guard config is Some(config) else { continue }
    let ranges = []
    for capture in matched.captures {
      if capture.name != "injection.content" {
        continue
      }
      let node = capture.node
      let mut start = node.start_byte()
      if !matched.properties.contains("injection.include-children") {
        for child in node.children() {
          if start < child.start_byte() {
            append_range(ranges, tree, start, child.start_byte())
          }
          start = child.end_byte()
        }
      }
      if start < node.end_byte() {
        append_range(ranges, tree, start, node.end_byte())
      }
    }
    if ranges.is_empty() {
      continue
    }
    let existing = if matched.properties.contains("injection.combined") {
      groups.search_by(g => {
        g.2 == matched.pattern_index && physical_equal(g.0, config)
      })
    } else {
      None
    }
    match existing {
      Some(index) => groups[index].1.append(ranges)
      None => groups.push((config, ranges, matched.pattern_index))
    }
  }
  for (config, ranges, _) in groups {
    if depth >= max_depth {
      raise InjectionLimit
    }
    ranges.sort_by_key(r => r.start_byte)
    let merged : Array[@ts.Range] = []
    for range in ranges {
      if merged.last() is Some(last) && range.start_byte <= last.end_byte {
        if range.end_byte > last.end_byte {
          merged[merged.length() - 1] = {
            ..last,
            end_byte: range.end_byte,
            end_point: range.end_point,
          }
        }
      } else {
        merged.push(range)
      }
    }
    let injected = @ts.Parser::new(config.language, scanner?=config.scanner).parse(
      tree.source,
      included_ranges=merged,
      cancelled~,
    )
    spans.append(
      config.collect(
        injected,
        injection,
        cancelled,
        depth + 1,
        max_depth,
        Some(self),
      ),
    )
  }
  spans
}

///|
fn render_events(
  spans : Array[Span],
  length : Int32,
  cancelled : () -> Bool,
) -> Array[Event] raise @query.QueryError {
  spans.sort_by_key(s => s.start)
  let boundaries = [0, length]
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
  injection~ : (String) -> Configuration? = _ => None,
) -> String raise {
  let output = StringBuilder()
  for event in self.highlight(tree, injection~) {
    match event {
      Start(name) => output.write_string("<span class=\"\{escape(name)}\">")
      End => output.write_string("</span>")
      Source(start, end) =>
        output.write_string(escape(@utf8.decode_lossy(tree.source[start:end])))
    }
  }
  output.to_string()
}

///|
fn point(source : Bytes, end : Int32) -> @ts.Point {
  let mut row = 0
  let mut column = 0
  for i in 0..<end {
    if source[i] == 10 {
      row += 1
      column = 0
    } else {
      column += 1
    }
  }
  { row, column, }
}

///|
fn append_range(
  ranges : Array[@ts.Range],
  tree : @ts.Tree,
  start : Int32,
  end : Int32,
) -> Unit {
  let included = tree.included_ranges()
  if included.is_empty() {
    ranges.push({
      start_byte: start,
      end_byte: end,
      start_point: point(tree.source, start),
      end_point: point(tree.source, end),
    })
  } else {
    for range in included {
      let start = Int32::max(start, range.start_byte)
      let end = Int32::min(end, range.end_byte)
      if start < end {
        ranges.push({
          start_byte: start,
          end_byte: end,
          start_point: point(tree.source, start),
          end_point: point(tree.source, end),
        })
      }
    }
  }
}

///|
fn add_span(
  spans : Array[Span],
  tree : @ts.Tree,
  start : Int32,
  end : Int32,
  name : String,
  priority : Int32,
) -> Unit {
  let ranges = []
  append_range(ranges, tree, start, end)
  for range in ranges {
    spans.push({ start: range.start_byte, end: range.end_byte, name, priority, })
  }
}

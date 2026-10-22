///|
/// Capture text after applying the standard documentation directives.
/// select-adjacent! retains the contiguous suffix immediately preceding its
/// target; strip! removes all matches of its regular expression.
pub fn Match::texts(
  self : Match,
  name : String,
  source : Bytes,
) -> Array[String] raise QueryError {
  let mut nodes = self.captures.filter(c => c.name == name).map(c => c.node)
  nodes.sort_by_key(n => n.start_byte())
  for directive in self.directives {
    if directive.name == "#select-adjacent!" &&
      directive.args[0] is Capture(capture) &&
      capture == name &&
      directive.args[1] is Capture(target) {
      let targets = self.captures.filter(c => c.name == target)
      if targets.is_empty() {
        nodes = []
        continue
      }
      let mut row = targets[0].node.start_position().row
      let mut start = nodes.length()
      for i = nodes.length() - 1; i >= 0; i = i - 1 {
        if nodes[i].end_position().row + 1 < row ||
          nodes[i].end_byte() > targets[0].node.start_byte() {
          break
        }
        start = i
        row = nodes[i].start_position().row
      }
      nodes = nodes[start:].to_owned()
    }
  }
  let mut texts = nodes.map(n => n.text(source))
  for directive in self.directives {
    if directive.name == "#strip!" &&
      directive.args[0] is Capture(capture) &&
      capture == name &&
      directive.args[1] is Text(pattern) {
      texts = texts.map(text => strip_matches(text, pattern))
    }
  }
  texts
}

///|
fn strip_matches(text : String, pattern : String) -> String raise QueryError {
  let start_anchor = pattern.has_prefix("^")
  let end_anchor = pattern.has_suffix("$") && !pattern.has_suffix("\\$")
  let first = if start_anchor { 1 } else { 0 }
  let last = pattern.length() - (if end_anchor { 1 } else { 0 })
  let pattern = pattern[first:last].to_owned()
  let regex = @lex.compile(@lex.parse(pattern)) catch {
    _ => raise InvalidQuery(0, "invalid strip regex")
  }
  let source = @utf8.encode(text)
  let out = StringBuilder()
  let mut offset = 0
  while offset < source.length() {
    if (!start_anchor || offset == 0) &&
      regex.match_prefix(source, start=offset) is Some(end) &&
      end > offset &&
      (!end_anchor || end == source.length()) {
      offset = end
    } else {
      let end = offset + @lex.decode(source, offset).1
      out.write_string(@utf8.decode_lossy(source[offset:end]))
      offset = end
    }
  }
  out.to_string()
}

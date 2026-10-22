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
  let regex = @lex.Regex::new(pattern) catch {
    _ => raise InvalidQuery(0, "invalid strip regex")
  }
  let source = @utf8.encode(text)
  let out = StringBuilder()
  let mut offset = 0
  for ;; {
    let found = regex.find(source, start=offset) catch { _ => raise MatchLimit }
    guard found is Some((start, end)) else {
      out.write_string(@utf8.decode_lossy(source[offset:]))
      break
    }
    out.write_string(@utf8.decode_lossy(source[offset:start]))
    offset = end
    if end == start {
      if offset == source.length() {
        break
      }
      let next = offset + @lex.decode(source, offset).1
      out.write_string(@utf8.decode_lossy(source[offset:next]))
      offset = next
    }
  }
  out.to_string()
}

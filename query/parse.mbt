///|
priv enum TokenKind {
  Word(String)
  Quoted(String)
  Punct(Char)
}

///|
priv struct Token {
  end_offset : Int32
  kind : TokenKind
  offset : Int32
}

///|
priv struct Reader {
  tokens : Array[Token]
  mut pos : Int32
  language : @language.Language
  captures : Array[String]
  mut predicates : Array[Predicate]
}

///|
fn tokenize(source : String) -> Array[Token] raise QueryError {
  let chars = source.iter().to_array()
  let result = []
  let mut i = 0
  let mut offset = 0
  while i < chars.length() {
    let c = chars[i]
    let start = i
    let start_offset = offset
    if c is (' ' | '\t' | '\n' | '\r') {
      i += 1
      offset += 1
      continue
    }
    if c == ';' {
      while i < chars.length() && chars[i] != '\n' {
        offset += @utf8.encode(chars[i].to_string()).length()
        i += 1
      }
      continue
    }
    let kind = if c == '"' {
      i += 1
      let mut escaped = false
      while i < chars.length() {
        if !escaped && chars[i] == '"' {
          break
        }
        if !escaped && chars[i] == '\\' {
          escaped = true
        } else {
          escaped = false
        }
        i += 1
      }
      if i == chars.length() {
        raise InvalidQuery(start_offset, "unterminated string")
      }
      i += 1
      let raw = String::from_array(chars[start:i])
      let text = @json.parse(raw) catch {
        _ => raise InvalidQuery(start_offset, "invalid string escape")
      }
      match text {
        String(s) => TokenKind::Quoted(s)
        _ => raise InvalidQuery(start_offset, "expected string")
      }
    } else if c is ('(' | ')' | '[' | ']' | ':' | '!' | '.' | '?' | '+' | '*') {
      i += 1
      Punct(c)
    } else {
      i += 1
      while i < chars.length() &&
            !(chars[i]
            is (' '
            | '\t'
            | '\r'
            | '\n'
            | '('
            | ')'
            | '['
            | ']'
            | ':'
            | '"'
            | ';'
            | '+'
            | '*')) {
        // Capture names and predicates may contain dots and ?/! suffixes.
        if chars[i] == '?' && c != '#' {
          break
        }
        i += 1
      }
      Word(String::from_array(chars[start:i]))
    }
    offset += @utf8.encode(String::from_array(chars[start:i])).length()
    result.push({ kind, offset: start_offset, end_offset: offset, })
  }
  result
}

///|
fn Reader::error(self : Reader, message : String) -> QueryError {
  InvalidQuery(
    match self.tokens.get(self.pos) {
      Some(t) => t.offset
      None => self.tokens.last().map(t => t.offset + 1).unwrap_or(0)
    },
    message,
  )
}

///|
fn Reader::punct(self : Reader, c : Char) -> Bool {
  if self.tokens.get(self.pos) is Some({ kind: Punct(actual), .. }) &&
    actual == c {
    self.pos += 1
    true
  } else {
    false
  }
}

///|
fn Reader::expect(self : Reader, c : Char) -> Unit raise QueryError {
  if !self.punct(c) {
    raise self.error("expected '\{c}'")
  }
}

///|
fn Reader::take(self : Reader) -> TokenKind raise QueryError {
  match self.tokens.get(self.pos) {
    None => raise self.error("unexpected end of query")
    Some(token) => {
      self.pos += 1
      token.kind
    }
  }
}

///|
fn Reader::word(self : Reader) -> String raise QueryError {
  match self.take() {
    Word(s) => s
    _ => raise self.error("expected identifier")
  }
}

///|
fn Reader::predicate(self : Reader) -> Unit raise QueryError {
  self.expect('(')
  let name = self.word()
  let args = []
  while !self.punct(')') {
    match self.take() {
      Word(s) if s.has_prefix("@") =>
        args.push(Argument::Capture(s[1:].to_owned()))
      Quoted(s) | Word(s) => args.push(Text(s))
      _ => raise self.error("invalid predicate argument")
    }
  }
  let equality = name is ("#eq?" | "#not-eq?" | "#any-eq?" | "#any-not-eq?")
  let matching = name
    is ("#match?" | "#not-match?" | "#any-match?" | "#any-not-match?")
  let anyof = name is ("#any-of?" | "#not-any-of?")
  if equality || matching {
    if args.length() != 2 || !(args[0] is Capture(_)) {
      raise self.error("predicate requires a capture and one value")
    }
  } else if anyof {
    if args.length() < 2 || !(args[0] is Capture(_)) {
      raise self.error("any-of requires a capture and values")
    }
  } else if name == "#set!" {
    if args.length() < 1 || args.length() > 2 || !args.all(a => a is Text(_)) {
      raise self.error("set! requires a property name and optional value")
    }
  } else if name is ("#is?" | "#is-not?") {
    let values = args.filter(a => a is Text(_))
    if values.length() < 1 ||
      values.length() > 2 ||
      args.filter(a => a is Capture(_)).length() > 1 {
      raise self.error(
        "property predicate requires a key, optional value and optional capture",
      )
    }
  } else if name == "#strip!" {
    if args.length() != 2 || !(args[0] is Capture(_)) || !(args[1] is Text(_)) {
      raise self.error("strip! requires a capture and a regex")
    }
  } else if name == "#select-adjacent!" {
    if args.length() != 2 || !args.all(a => a is Capture(_)) {
      raise self.error("select-adjacent! requires two captures")
    }
  } else if !name.has_prefix("#") {
    raise self.error("invalid predicate name")
  }
  let regex = if matching || name == "#strip!" {
    guard args[1] is Text(text) else {
      raise self.error("regex predicate requires a string")
    }
    Some(
      @lex.Regex::new(text) catch {
        _ => raise self.error("invalid predicate regex")
      },
    )
  } else {
    None
  }
  self.predicates.push({ name, args, regex, })
}

///|
fn Reader::is_predicate(self : Reader) -> Bool {
  self.tokens.get(self.pos) is Some({ kind: Punct('('), .. }) &&
  self.tokens.get(self.pos + 1) is Some({ kind: Word(name), .. }) &&
  name.has_prefix("#")
}

///|
fn Reader::pattern(self : Reader, depth : Int32) -> Pattern raise QueryError {
  if depth > 128 {
    raise self.error("query nesting limit exceeded")
  }
  let start_byte = self.tokens.get(self.pos).map(t => t.offset).unwrap_or(0)
  let mut pattern = match self.take() {
    Punct('[') => {
      let alternatives = []
      while !self.punct(']') {
        alternatives.push(self.pattern(depth + 1))
      }
      if alternatives.is_empty() {
        raise self.error("empty alternative")
      }
      Either(alternatives)
    }
    Quoted(kind) => {
      self.check_kind(kind, false, start_byte + 1)
      Node({
        start_byte,
        kind: Some(kind),
        supertype: None,
        named: Some(false),
        missing: false,
        children: [],
        absent_fields: [],
        trailing_anchor: false,
      })
    }
    Word("_") =>
      Node({
        start_byte,
        kind: None,
        supertype: None,
        named: None,
        missing: false,
        children: [],
        absent_fields: [],
        trailing_anchor: false,
      })
    Punct('(') =>
      if self.tokens.get(self.pos)
        is Some({ kind: Punct('(' | '[') | Quoted(_), .. }) {
        let children = []
        let mut anchor = false
        let mut anchor_byte = 0
        while !self.punct(')') {
          if self.is_predicate() {
            self.predicate()
            continue
          }
          if self.punct('.') {
            anchor_byte = self.tokens[self.pos - 1].offset
            anchor = true
            continue
          }
          children.push(self.child(depth + 1, None, anchor))
          anchor = false
        }
        if anchor {
          raise InvalidQuery(anchor_byte, "anchor at group edge")
        }
        if children.length() == 1 &&
          children[0].min == 1 &&
          children[0].max == Some(1) &&
          !children[0].anchor &&
          !anchor {
          children[0].pattern
        } else {
          Group(children, anchor)
        }
      } else {
        let kind = self.word()
        let missing = kind == "MISSING"
        let anonymous_missing = missing &&
          self.tokens.get(self.pos) is Some({ kind: Quoted(_), .. })
        let kind = if missing {
          match self.tokens.get(self.pos) {
            Some({ kind: Word(_) | Quoted(_), .. }) =>
              match self.take() {
                Word(k) | Quoted(k) => k
                _ => "_"
              }
            _ => "_"
          }
        } else {
          kind
        }
        let parts = kind.split("/").to_array()
        let supertype = if parts.length() == 2 {
          Some(parts[0].to_owned())
        } else if self.language.supertypes.any(id => {
            self.language.symbols[id].name == kind
          }) {
          Some(kind)
        } else {
          None
        }
        if parts.length() > 2 {
          raise self.error("invalid supertype pattern")
        }
        if supertype is Some(name) &&
          !self.language.supertypes.any(id => {
            self.language.symbols[id].name == name
          }) {
          raise InvalidQuery(start_byte, "unknown supertype '\{name}'")
        }
        let kind = if parts.length() == 2 {
          parts[1].to_owned()
        } else if supertype is Some(_) {
          "_"
        } else {
          kind
        }
        if kind != "_" && kind != "ERROR" {
          self.check_kind(
            kind,
            !anonymous_missing,
            self.tokens[self.pos - 1].offset +
            (if anonymous_missing { 1 } else { 0 }),
          )
        }
        let children = []
        let absent_fields = []
        let mut anchor = false
        while !self.punct(')') {
          if self.punct('.') {
            anchor = true
            continue
          }
          if self.punct('!') {
            let name = self.word()
            self.check_field(name, self.tokens[self.pos - 1].offset)
            absent_fields.push(name)
            continue
          }
          if self.is_predicate() {
            self.predicate()
            continue
          }
          let child_start = self.tokens
            .get(self.pos)
            .map(t => t.offset)
            .unwrap_or(start_byte)
          let field = if self.tokens.get(self.pos)
            is Some({ kind: Word(name), .. }) &&
            self.tokens.get(self.pos + 1) is Some({ kind: Punct(':'), .. }) {
            self.pos += 2
            Some(name)
          } else {
            None
          }
          children.push(
            self.child(depth + 1, field, anchor, start_byte=child_start),
          )
          anchor = false
        }
        Node({
          start_byte,
          supertype,
          kind: if kind == "_" {
            None
          } else {
            Some(kind)
          },
          named: if missing {
            None
          } else {
            Some(true)
          },
          missing,
          children,
          absent_fields,
          trailing_anchor: anchor,
        })
      }
    _ => raise self.error("expected node pattern")
  }
  while self.tokens.get(self.pos) is Some({ kind: Word(name), .. }) &&
        name.has_prefix("@") {
    self.pos += 1
    let name = name[1:].to_owned()
    if name.is_empty() {
      raise self.error("empty capture name")
    }
    if !self.captures.contains(name) {
      self.captures.push(name)
    }
    pattern = Capture(pattern, name)
  }
  pattern
}

///|
fn Reader::check_kind(
  self : Reader,
  name : String,
  named : Bool,
  offset : Int32,
) -> Unit raise QueryError {
  let exists = self.language.symbols.any(s => s.name == name && s.named == named) ||
    self.language.productions.any(p => {
      p.steps.any(s => s.rename == Some((name, named)))
    })
  if !exists {
    raise InvalidQuery(offset, "unknown node type '\{name}'")
  }
}

///|
pub fn Query::new(
  language : @language.Language,
  source : String,
) -> Query raise QueryError {
  let reader : Reader = {
    tokens: tokenize(source),
    pos: 0,
    language,
    captures: [],
    predicates: [],
  }
  let patterns = []
  let schema = match language.node_types() {
    Array(items) => items
    _ => []
  }
  while reader.pos < reader.tokens.length() {
    reader.predicates = []
    let start_byte = reader.tokens[reader.pos].offset
    let root = reader.child(0, None, false)
    let pattern = root.pattern
    validate_structure(schema, pattern, start_byte)
    for predicate in reader.predicates {
      for arg in predicate.args {
        if arg is Capture(name) && !pattern_captures(pattern).contains(name) {
          raise reader.error("unknown capture '@\{name}'")
        }
      }
    }
    patterns.push({
      pattern,
      min: root.min,
      max: root.max,
      predicates: reader.predicates,
      start_byte,
      end_byte: reader.tokens[reader.pos - 1].end_offset,
    })
  }
  {
    patterns,
    capture_names: reader.captures,
    disabled_patterns: Map([]),
    disabled_captures: Map([]),
  }
}

///|
fn Reader::check_field(
  self : Reader,
  name : String,
  offset : Int32,
) -> Unit raise QueryError {
  if !self.language.productions.any(p => p.steps.any(s => s.field == Some(name))) {
    raise InvalidQuery(offset, "unknown field '\{name}'")
  }
}

///|
fn pattern_captures(pattern : Pattern) -> Array[String] {
  match pattern {
    Capture(inner, name) => pattern_captures(inner) + [name]
    Group(children, _) => {
      let out = []
      for child in children {
        out.append(pattern_captures(child.pattern))
      }
      out
    }
    Either(items) => {
      let out = []
      for item in items {
        out.append(pattern_captures(item))
      }
      out
    }
    Node(node) => {
      let out = []
      for child in node.children {
        out.append(pattern_captures(child.pattern))
      }
      out
    }
  }
}

///|
fn Reader::child(
  self : Reader,
  depth : Int32,
  field : String?,
  anchor : Bool,
  start_byte? : Int32,
) -> Child raise QueryError {
  let start_byte = start_byte.unwrap_or_else(() => {
    self.tokens.get(self.pos).map(t => t.offset).unwrap_or(0)
  })
  if field is Some(name) {
    self.check_field(name, start_byte)
  }
  let mut pattern = self.pattern(depth)
  let (min, max) = if self.punct('?') {
    (0, Some(1))
  } else if self.punct('*') {
    (0, None)
  } else if self.punct('+') {
    (1, None)
  } else {
    (1, Some(1))
  }
  while self.tokens.get(self.pos) is Some({ kind: Word(name), .. }) &&
        name.has_prefix("@") {
    self.pos += 1
    let name = name[1:].to_owned()
    if name.is_empty() {
      raise self.error("empty capture name")
    }
    if !self.captures.contains(name) {
      self.captures.push(name)
    }
    pattern = Capture(pattern, name)
  }
  { start_byte, pattern, field, anchor, min, max, }
}

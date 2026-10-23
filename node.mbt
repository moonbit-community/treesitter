///|
// Keep the hidden production hierarchy for deterministic GLR tie-breaking.
// This immutable shape is independent of byte positions and survives edits.
priv struct Derivation {
  symbol : Int32
  children : Array[Derivation]
}

///|
priv struct NodeData {
  language : @language.Language
  continuation : (Lexeme, Array[Node], Int32)?
  fragile : Bool
  derivation : Derivation
  dependency_end : Int32
  encoding : InputEncoding
  id : Int32
  error_repeat : Bool
  error_extent : Int32
  error_cost : Int32
  unexpected : Int32?
  changed : Bool
  origin_start : Int32
  origin_end : Int32
  dynamic_score : Int32
  supertypes : Array[String]
  scan_before : Bytes
  scan_after : Bytes
  symbol : Int32
  kind : String
  named : Bool
  extra : Bool
  missing : Bool
  error : Bool
  visible : Bool
  start_byte : Int32
  end_byte : Int32
  start_point : Point
  end_point : Point
  children : ChildList
  parse_state : Int32
  next_state : Int32
}

///|
/// A persistent syntax node. Children and their field names cannot be mutated.
pub struct Node {
  priv data : NodeData
  priv context : NodeContext?
}

///|
pub fn Node::kind(self : Node) -> String {
  self.data.kind
}

///|
pub fn Node::id(self : Node) -> Int32 {
  self.data.id
}

///|
/// Public symbol identity, including aliases and canonicalized duplicate names.
pub fn Node::symbol(self : Node) -> Int32 {
  self
  .language()
  .symbol_id(self.kind(), named=self.is_named())
  .unwrap_or(self.data.symbol)
}

///|
/// Symbol used by the parser before a production-specific alias is applied.
pub fn Node::grammar_symbol(self : Node) -> Int32 {
  self.data.symbol
}

///|
/// Grammar symbol name. Default aliases are part of the generated grammar's
/// symbol table; production-specific aliases only affect `kind` and `symbol`.
pub fn Node::grammar_kind(self : Node) -> String {
  self.language().symbol_name(self.grammar_symbol()).unwrap_or(self.kind())
}

///|
pub fn Node::is_named(self : Node) -> Bool {
  self.data.named
}

///|
pub fn Node::is_extra(self : Node) -> Bool {
  self.data.extra
}

///|
pub fn Node::is_missing(self : Node) -> Bool {
  self.data.missing
}

///|
pub fn Node::is_error(self : Node) -> Bool {
  self.data.error
}

///|
pub fn Node::has_error(self : Node) -> Bool {
  self.is_error() || self.is_missing() || self.data.children.has_error
}

///|
pub fn Node::start_byte(self : Node) -> Int32 {
  self.data.start_byte + self.context.map(c => c.byte_delta).unwrap_or(0)
}

///|
pub fn Node::end_byte(self : Node) -> Int32 {
  self.data.end_byte + self.context.map(c => c.byte_delta).unwrap_or(0)
}

///|
pub fn Node::start_position(self : Node) -> Point {
  self.context
  .map(c => c.point(self.data.start_point))
  .unwrap_or(self.data.start_point)
}

///|
pub fn Node::end_position(self : Node) -> Point {
  self.context
  .map(c => c.point(self.data.end_point))
  .unwrap_or(self.data.end_point)
}

///|
pub fn Node::range(self : Node) -> Range {
  {
    start_byte: self.start_byte(),
    end_byte: self.end_byte(),
    start_point: self.start_position(),
    end_point: self.end_position(),
  }
}

///|
pub fn Node::parse_state(self : Node) -> Int32 {
  self.data.parse_state
}

///|
pub fn Node::next_parse_state(self : Node) -> Int32 {
  self.data.next_state
}

///|
pub fn Node::child_count(self : Node) -> Int32 {
  self.data.children.length
}

///|
pub fn Node::named_child_count(self : Node) -> Int32 {
  self.data.children.named_length
}

///|
pub fn Node::child(self : Node, index : Int32) -> Node? {
  self.data.children.entries().get(index).map(c => self.contextual_child(c.1))
}

///|
pub fn Node::named_child(self : Node, index : Int32) -> Node? {
  if index < 0 {
    return None
  }
  let mut current = 0
  for (_, child) in self.data.children.entries() {
    if child.is_named() {
      if current == index {
        return Some(self.contextual_child(child))
      }
      current += 1
    }
  }
  None
}

///|
pub fn Node::children(self : Node) -> Array[Node] {
  self.data.children.entries().map(c => self.contextual_child(c.1))
}

///|
pub fn Node::named_children(self : Node) -> Array[Node] {
  self.children().filter(c => c.is_named())
}

///|
pub fn Node::field_name_for_child(self : Node, index : Int32) -> String? {
  match self.data.children.entries().get(index) {
    Some((field, _)) => field
    None => None
  }
}

///|
pub fn Node::child_by_field_name(self : Node, name : String) -> Node? {
  for (field, child) in self.data.children.entries() {
    if field == Some(name) {
      return Some(self.contextual_child(child))
    }
  }
  None
}

///|
pub fn Node::children_by_field_name(self : Node, name : String) -> Array[Node] {
  self.data.children
  .entries()
  .filter(c => c.0 == Some(name))
  .map(c => self.contextual_child(c.1))
}

///|
pub fn Node::descendant_for_byte_range(
  self : Node,
  start : Int32,
  end : Int32,
  named~ : Bool = false,
) -> Node? {
  if start < self.start_byte() || end > self.end_byte() || end < start {
    return None
  }
  for child in self.children() {
    if child.start_byte() <= start &&
      child.end_byte() >= end &&
      (child.end_byte() > start || child.start_byte() == child.end_byte()) {
      if child.descendant_for_byte_range(start, end, named~) is Some(found) {
        return Some(found)
      }
    }
  }
  if !named || self.is_named() {
    Some(self)
  } else {
    None
  }
}

///|
pub fn Node::text(self : Node, source : Bytes) -> String {
  input_text(source[self.start_byte():self.end_byte()], self.data.encoding)
}

///|
fn Node::write_sexp(self : Node, output : StringBuilder, fields : Bool) -> Unit {
  if self.data.unexpected is Some(code) {
    output.write_string("(UNEXPECTED '")
    match code {
      0 => output.write_string("\\0")
      10 => output.write_string("\\n")
      13 => output.write_string("\\r")
      9 => output.write_string("\\t")
      39 => output.write_string("\\'")
      92 => output.write_string("\\\\")
      _ => output.write_char(code.unsafe_to_char())
    }
    output.write_string("')")
    return
  }
  if self.is_missing() {
    output.write_string("(MISSING ")
    output.write_string(
      if self.is_named() {
        self.kind()
      } else {
        Json(self.kind()).stringify()
      },
    )
    output.write_char(')')
    return
  }
  output.write_char('(')
  output.write_string(self.kind())
  for (field, child) in self.data.children.entries() {
    if child.is_named() || child.is_missing() || child.is_error() {
      output.write_char(' ')
      if fields && field is Some(name) {
        output.write_string(name)
        output.write_string(": ")
      }
      child.write_sexp(output, fields)
    }
  }
  output.write_char(')')
}

///|
pub fn Node::to_sexp(self : Node, fields~ : Bool = true) -> String {
  let output = StringBuilder()
  self.write_sexp(output, fields)
  output.to_string()
}

///|
fn Node::renamed(self : Node, name : String, named : Bool) -> Node {
  { context: None, data: { ..self.data, kind: name, named, visible: true, }, }
}

///|
/// Hidden supertype categories on this node's actual parse path.
pub fn Node::supertypes(self : Node) -> Array[String] {
  self.data.supertypes.copy()
}

///|
fn Node::as_extra(self : Node) -> Node {
  let children = if self.data.visible {
    self.data.children
  } else {
    child_entries(
      self.data.children
      .entries()
      .map(c => (c.0, { context: None, data: { ..c.1.data, extra: true, }, })),
    )
  }
  { context: None, data: { ..self.data, extra: true, children, }, }
}

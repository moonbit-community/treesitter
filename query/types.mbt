///|
pub(all) suberror QueryError {
  InvalidQuery(Int32, String)
  MatchLimit
  Cancelled
} derive(Debug)

///|
pub extend QueryError with @debug.Debug::{to_repr}

///|
priv enum Pattern {
  Node(NodePattern)
  Either(Array[Pattern])
  Group(Array[Child], Bool)
  Capture(Pattern, String)
}

///|
priv struct NodePattern {
  kind : String?
  supertype : String?
  named : Bool?
  missing : Bool
  children : Array[Child]
  absent_fields : Array[String]
  trailing_anchor : Bool
}

///|
priv struct Child {
  pattern : Pattern
  field : String?
  anchor : Bool
  min : Int32
  max : Int32?
}

///|
pub(all) enum Argument {
  Capture(String)
  Text(String)
}

///|
priv struct Predicate {
  name : String
  args : Array[Argument]
  regex : @lex.Regex?
}

///|
priv struct QueryPattern {
  start_byte : Int32
  end_byte : Int32
  pattern : Pattern
  predicates : Array[Predicate]
}

///|
pub struct Query {
  priv disabled_patterns : Map[Int32, Bool]
  priv disabled_captures : Map[String, Bool]
  priv patterns : Array[QueryPattern]
  capture_names : Array[String]
}

///|
pub(all) struct Capture {
  name : String
  node : @ts.Node
}

///|
pub(all) struct Directive {
  name : String
  args : Array[Argument]
}

///|
pub(all) struct Match {
  pattern_index : Int32
  captures : Array[Capture]
  properties : Map[String, String]
  directives : Array[Directive]
}

///|
pub fn Query::pattern_count(self : Query) -> Int32 {
  self.patterns.length()
}

///|
pub fn Query::disable_pattern(self : Query, index : Int32) -> Bool {
  if index < 0 || index >= self.patterns.length() {
    return false
  }
  self.disabled_patterns[index] = true
  true
}

///|
pub fn Query::disable_capture(self : Query, name : String) -> Bool {
  if !self.capture_names.contains(name) {
    return false
  }
  self.disabled_captures[name] = true
  true
}

///|
/// UTF-8 byte range of a pattern, excluding surrounding comments/whitespace.
pub fn Query::pattern_range(self : Query, index : Int32) -> (Int32, Int32)? {
  self.patterns.get(index).map(p => (p.start_byte, p.end_byte))
}

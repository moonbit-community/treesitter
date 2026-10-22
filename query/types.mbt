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
  regex : @lex.Dfa?
  start_anchor : Bool
  end_anchor : Bool
}

///|
priv struct QueryPattern {
  pattern : Pattern
  predicates : Array[Predicate]
}

///|
pub struct Query {
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

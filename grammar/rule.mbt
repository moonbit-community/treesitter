///|
/// Precedence values retain the distinction between numeric and named precedence.
pub(all) enum Precedence {
  Integer(Int32)
  Name(String)
} derive(Debug, Eq)

///|
/// The Tree-sitter grammar rule language. Use these constructors from mbtx.
pub(all) enum Rule {
  Blank
  Literal(String)
  Pattern(String, flags~ : String)
  Symbol(String)
  Choice(Array[Rule])
  Seq(Array[Rule])
  Repeat(Rule)
  Repeat1(Rule)
  Token(Rule)
  ImmediateToken(Rule)
  Prec(Precedence, Rule)
  PrecLeft(Precedence, Rule)
  PrecRight(Precedence, Rule)
  PrecDynamic(Int32, Rule)
  Field(String, Rule)
  Alias(Rule, String, named~ : Bool)
  Reserved(String, Rule)
  Eof
} derive(Debug, Eq)

///|
pub fn pattern(value : String, flags~ : String = "") -> Rule {
  Pattern(value, flags~)
}

///|
pub fn optional(rule : Rule) -> Rule {
  Choice([rule, Blank])
}

///|
pub fn sep1(rule : Rule, separator : Rule) -> Rule {
  Seq([rule, Repeat(Seq([separator, rule]))])
}

///|
pub fn sep(rule : Rule, separator : Rule) -> Rule {
  optional(sep1(rule, separator))
}

///|
pub fn prec(value : Int32, rule : Rule) -> Rule {
  Prec(Integer(value), rule)
}

///|
pub fn prec_left(rule : Rule, value~ : Int32 = 0) -> Rule {
  PrecLeft(Integer(value), rule)
}

///|
pub fn prec_right(rule : Rule, value~ : Int32 = 0) -> Rule {
  PrecRight(Integer(value), rule)
}

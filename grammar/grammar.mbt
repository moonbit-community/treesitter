///|
/// Rule order is significant: the first rule is the start rule.
pub(all) struct Grammar {
  name : String
  rules : Array[(String, Rule)]
  extras : Array[Rule]
  externals : Array[Rule]
  conflicts : Array[Array[String]]
  precedences : Array[Array[Rule]]
  inline_rules : Array[String]
  supertypes : Array[String]
  word : String?
  reserved : Map[String, Array[Rule]]
} derive(Debug, Eq)

///|
pub fn Grammar::new(
  name : String,
  rules : Array[(String, Rule)],
  extras~ : Array[Rule] = [Pattern("\\s", flags="")],
  externals~ : Array[Rule] = [],
  conflicts~ : Array[Array[String]] = [],
  precedences~ : Array[Array[Rule]] = [],
  inline_rules~ : Array[String] = [],
  supertypes~ : Array[String] = [],
  word? : String,
  reserved~ : Map[String, Array[Rule]] = Map([]),
) -> Grammar {
  {
    name,
    rules,
    extras,
    externals,
    conflicts,
    precedences,
    inline_rules,
    supertypes,
    word,
    reserved,
  }
}

///|
pub suberror GrammarError {
  InvalidGrammar(String)
} derive(Debug, Eq)

///|
fn invalid(message : String) -> Unit raise GrammarError {
  raise InvalidGrammar(message)
}

///|
fn check_rule(
  rule : Rule,
  names : Map[String, Bool],
  contexts : Map[String, Array[Rule]],
  path : String,
) -> Unit raise GrammarError {
  match rule {
    Symbol(name) =>
      if !names.contains(name) {
        invalid("\{path}: unknown rule '\{name}'")
      }
    Literal("") => invalid("\{path}: empty string; use Blank instead")
    Pattern("", flags=_) => invalid("\{path}: empty pattern")
    Choice(items) | Seq(items) => {
      if items.is_empty() {
        invalid("\{path}: empty choice/sequence; use Blank instead")
      }
      for i, child in items {
        check_rule(child, names, contexts, "\{path}[\{i}]")
      }
    }
    Repeat(child)
    | Repeat1(child)
    | Token(child)
    | ImmediateToken(child)
    | Prec(_, child)
    | PrecLeft(_, child)
    | PrecRight(_, child)
    | PrecDynamic(_, child) => check_rule(child, names, contexts, path)
    Field(name, child) | Alias(child, name, named=_) => {
      if name.is_empty() {
        invalid("\{path}: empty field or alias name")
      }
      check_rule(child, names, contexts, path)
    }
    Reserved(context, child) => {
      if !contexts.contains(context) {
        invalid("\{path}: unknown reserved word context '\{context}'")
      }
      check_rule(child, names, contexts, path)
    }
    _ => ()
  }
}

///|
/// Validate references before generation, including references in configuration.
pub fn Grammar::validate(self : Grammar) -> Unit raise GrammarError {
  if self.name.is_empty() {
    invalid("grammar name must not be empty")
  }
  for c in self.name {
    if !(c is ('a'..<='z' | 'A'..<='Z' | '0'..<='9' | '_')) {
      invalid(
        "grammar name must contain only ASCII letters, digits and underscores",
      )
    }
  }
  if self.rules.is_empty() {
    invalid("grammar must have a start rule")
  }
  let names : Map[String, Bool] = Map([])
  for (name, _) in self.rules {
    if name.is_empty() {
      invalid("rule name must not be empty")
    }
    if names.contains(name) {
      invalid("duplicate rule '\{name}'")
    }
    names[name] = true
  }
  for rule in self.externals {
    if rule is Symbol(name) {
      names[name] = true
    }
  }
  for (name, rule) in self.rules {
    check_rule(rule, names, self.reserved, "rules.\{name}")
  }
  for rule in self.extras {
    check_rule(rule, names, self.reserved, "extras")
  }
  for rule in self.externals {
    check_rule(rule, names, self.reserved, "externals")
  }
  for context, rules in self.reserved {
    for rule in rules {
      check_rule(rule, names, self.reserved, "reserved.\{context}")
    }
  }
  for name in self.inline_rules + self.supertypes {
    if !self.rules.any(r => r.0 == name) {
      invalid("unknown inline/supertype rule '\{name}'")
    }
  }
  if self.word is Some(name) && !names.contains(name) {
    invalid("unknown word rule '\{name}'")
  }
  for conflict in self.conflicts {
    if conflict.is_empty() {
      invalid("empty conflict set")
    }
    for name in conflict {
      if !names.contains(name) {
        invalid("unknown conflict rule '\{name}'")
      }
    }
  }
  for group in self.precedences {
    for rule in group {
      match rule {
        Literal(_) => ()
        Symbol(name) =>
          if !names.contains(name) {
            invalid("unknown precedence rule '\{name}'")
          }
        _ => invalid("precedence entries must be strings or symbols")
      }
    }
  }
}

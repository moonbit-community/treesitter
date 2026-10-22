///|
pub suberror GenerateError {
  InvalidGrammar(String)
  Conflict(Int32, String, Array[String])
  ResourceLimit(String)
} derive(Debug)

///|
pub extend GenerateError with @debug.Debug::{to_repr}

///|
priv struct Context {
  reserved_set : Int32
  precedence : Int32
  precedence_name : String?
  associativity : Int32
  dynamic_precedence : Int32
  field : String?
  rename : (String, Bool)?
}

///|
priv struct Alternative {
  steps : Array[@language.Step]
  precedence : Int32
  precedence_name : String?
  associativity : Int32
  dynamic_precedence : Int32
}

///|
priv struct Builder {
  grammar : @grammar.Grammar
  symbols : Array[@language.Symbol]
  tokens : Array[@language.Token]
  productions : Array[@language.Production]
  names : Map[String, Int32]
  token_ids : Map[String, Int32]
  repeats : Map[String, Int32]
  max_productions : Int32
  externals : Array[Int32]
  reserved_sets : Array[Array[Int32]]
  reserved_names : Map[String, Int32]
}

///|
fn Builder::symbol(
  self : Builder,
  name : String,
  named : Bool,
  visible : Bool,
  terminal : Bool,
) -> Int32 {
  let id = self.symbols.length()
  self.symbols.push({ name, named, visible, terminal, })
  id
}

///|
fn lexical(rule : @grammar.Rule) -> Bool {
  match rule {
    Literal(_) | Pattern(_, ..) | Token(_) | ImmediateToken(_) => true
    _ => false
  }
}

///|
fn expression(rule : @grammar.Rule) -> @lex.Expr raise {
  match rule {
    Blank => Empty
    Literal(s) => @lex.literal(s)
    Pattern(s, flags~) => @lex.parse(s, flags~)
    Choice(items) => Alt(items.map(expression))
    Seq(items) => Concat(items.map(expression))
    Repeat(child) => Many(expression(child))
    Repeat1(child) => {
      let expr = expression(child)
      Concat([expr, Many(expr)])
    }
    Token(child) | ImmediateToken(child) | Prec(_, child) => expression(child)
    _ =>
      raise InvalidGrammar(
        "token rules may only contain strings, patterns, choices, sequences, repetitions and numeric precedence",
      )
  }
}

///|
fn token_precedence(rule : @grammar.Rule) -> Int32 raise GenerateError {
  match rule {
    Prec(Integer(n), _) => n
    Token(child) | ImmediateToken(child) => token_precedence(child)
    Prec(Name(_), _) =>
      raise InvalidGrammar("lexical precedence must be numeric")
    _ => 0
  }
}

///|
fn token_key(rule : @grammar.Rule) -> String {
  match rule {
    Token(child) => token_key(child)
    _ => Json(rule).stringify()
  }
}

///|
fn count_tokens(grammar : @grammar.Grammar) -> Map[String, Int32] {
  let counts : Map[String, Int32] = Map([])
  fn visit(rule : @grammar.Rule) {
    if lexical(rule) {
      let key = token_key(rule)
      counts[key] = counts.get(key).unwrap_or(0) + 1
      return
    }
    match rule {
      Seq(children) | Choice(children) => children.each(visit)
      Repeat(child)
      | Repeat1(child)
      | Field(_, child)
      | Alias(child, _, ..)
      | Prec(_, child)
      | PrecLeft(_, child)
      | PrecRight(_, child)
      | PrecDynamic(_, child)
      | Reserved(_, child) => visit(child)
      _ => ()
    }
  }
  for (_, rule) in grammar.rules {
    visit(rule)
  }
  for rule in grammar.externals {
    visit(rule)
  }
  counts
}

///|
fn Builder::token(
  self : Builder,
  rule : @grammar.Rule,
  name? : String,
) -> Int32 raise {
  let key = match name {
    Some(name) => "named:\{name}"
    None => token_key(rule)
  }
  if self.token_ids.get(key) is Some(id) {
    return id
  }
  let lexer = @lex.compile(expression(rule))
  let token_name = match name {
    Some(name) => name
    None => literal_name(rule).unwrap_or(key)
  }
  let symbol = self.symbol(
    token_name,
    name != None,
    (name is Some(_) && !token_name.has_prefix("_")) ||
    (name is None && literal_token(rule)),
    true,
  )
  self.tokens.push({
    symbol,
    lexer,
    precedence: token_precedence(rule),
    immediate: rule is ImmediateToken(_),
    literal: literal_token(rule),
  })
  self.token_ids[key] = symbol
  symbol
}

///|
fn Builder::emit(
  self : Builder,
  lhs : Int32,
  alternatives : Array[Alternative],
) -> Unit raise GenerateError {
  for alternative in alternatives {
    let eof = alternative.steps.search_by(s => s.symbol == 0)
    if eof is Some(index) && index != alternative.steps.length() - 1 {
      continue
    }
    if self.productions.length() >= self.max_productions {
      raise ResourceLimit("production limit exceeded")
    }
    let production : @language.Production = {
      lhs,
      requires_eof: if eof is Some(_) {
        Some(true)
      } else {
        None
      },
      steps: if eof is Some(index) {
        alternative.steps[:index].to_owned()
      } else {
        alternative.steps
      },
      precedence: alternative.precedence,
      precedence_name: alternative.precedence_name,
      associativity: alternative.associativity,
      dynamic_precedence: alternative.dynamic_precedence,
    }
    let equivalent = self.productions.search_by(p => {
      { ..p, requires_eof: None, } == { ..production, requires_eof: None, }
    })
    match equivalent {
      Some(index) =>
        if production.requires_eof != Some(true) {
          self.productions[index] = production
        }
      None => self.productions.push(production)
    }
  }
}

///|
fn single(symbol : Int32, context : Context) -> Array[Alternative] {
  [
    {
      steps: [
        {
          symbol,
          reserved_set: Some(context.reserved_set),
          field: context.field,
          rename: context.rename,
          precedence: context.precedence,
          precedence_name: context.precedence_name,
          associativity: context.associativity,
        },
      ],
      precedence: context.precedence,
      precedence_name: context.precedence_name,
      associativity: context.associativity,
      dynamic_precedence: context.dynamic_precedence,
    },
  ]
}

///|
fn Builder::expand(
  self : Builder,
  rule : @grammar.Rule,
  context : Context,
  inlines : Array[String],
) -> Array[Alternative] raise {
  match rule {
    Blank =>
      [
        {
          steps: [],
          precedence: context.precedence,
          precedence_name: context.precedence_name,
          associativity: context.associativity,
          dynamic_precedence: context.dynamic_precedence,
        },
      ]
    Eof => single(0, context)
    Symbol(name) =>
      if self.grammar.inline_rules.contains(name) {
        if inlines.contains(name) {
          raise InvalidGrammar("recursive inline rule '\{name}'")
        }
        let rule = self.grammar.rules[self.grammar.rules
          .search_by(r => r.0 == name)
          .unwrap()].1
        let alternatives = self.expand(rule, context, inlines + [name])
        // Inlining replaces a production step. Its alias and field apply to
        // every inserted step, overriding metadata inside the inline rule.
        for alternative in alternatives {
          for i, step in alternative.steps {
            alternative.steps[i] = {
              ..step,
              rename: if context.rename is Some(_) {
                context.rename
              } else {
                step.rename
              },
              field: if context.field is Some(_) {
                context.field
              } else {
                step.field
              },
            }
          }
        }
        alternatives
      } else {
        single(self.names[name], context)
      }
    Literal(_) | Pattern(_, ..) | Token(_) | ImmediateToken(_) =>
      single(self.token(rule), context)
    Choice(items) => {
      let result = []
      for item in items {
        result.append(self.expand(item, context, inlines))
        if result.length() > self.max_productions {
          raise ResourceLimit("choice expansion limit exceeded")
        }
      }
      result
    }
    Seq(items) => {
      let mut result : Array[Alternative] = [
        {
          steps: [],
          precedence: context.precedence,
          precedence_name: context.precedence_name,
          associativity: context.associativity,
          dynamic_precedence: 0,
        },
      ]
      for index, item in items {
        let suffixes = self.expand(
          item,
          { ..context, dynamic_precedence: 0, },
          inlines,
        )
        if index + 1 < items.length() {
          for suffix in suffixes {
            if !suffix.steps.is_empty() {
              let last = suffix.steps.length() - 1
              suffix.steps[last] = {
                ..suffix.steps[last],
                precedence: context.precedence,
                precedence_name: context.precedence_name,
                associativity: context.associativity,
              }
            }
          }
        }
        let next = []
        for prefix in result {
          for suffix in suffixes {
            if next.length() >= self.max_productions {
              raise ResourceLimit("sequence expansion limit exceeded")
            }
            next.push({
              steps: prefix.steps + suffix.steps,
              precedence: suffix.precedence,
              precedence_name: suffix.precedence_name,
              associativity: suffix.associativity,
              dynamic_precedence: dynamic_precedence(
                prefix.dynamic_precedence,
                suffix.dynamic_precedence,
              ),
            })
          }
        }
        result = next
      }
      result.map(a => {
        ..a,
        dynamic_precedence: dynamic_precedence(
          context.dynamic_precedence,
          a.dynamic_precedence,
        ),
      })
    }
    Repeat(child) | Repeat1(child) => {
      let key = Json(child).stringify()
      let symbol = match self.repeats.get(key) {
        Some(id) => id
        None => {
          let id = self.symbol(
            "_repeat\{self.repeats.length()}",
            false,
            false,
            false,
          )
          self.repeats[key] = id
          let neutral : Context = {
            reserved_set: 0,
            precedence: 0,
            precedence_name: None,
            associativity: 0,
            dynamic_precedence: 0,
            field: None,
            rename: None,
          }
          let alternatives = self.expand(child, neutral, inlines)
          for alternative in alternatives {
            if alternative.steps.is_empty() {
              raise InvalidGrammar(
                "repeated rule may not match the empty string",
              )
            }
            self.emit(id, [alternative])
            let prefix = single(id, neutral)[0]
            self.emit(id, [
              { ..alternative, steps: prefix.steps + alternative.steps, },
            ])
          }
          id
        }
      }
      let alternatives = single(symbol, context)
      if rule is Repeat(_) {
        alternatives.append(self.expand(Blank, context, inlines))
      }
      alternatives
    }
    Field(name, child) =>
      self.expand(child, { ..context, field: Some(name), }, inlines)
    Alias(child, name, named~) =>
      self.expand(child, { ..context, rename: Some((name, named)), }, inlines)
    Prec(Integer(n), child) =>
      self.expand(
        child,
        { ..context, precedence: n, precedence_name: None, },
        inlines,
      )
    PrecLeft(Integer(n), child) =>
      self.expand(
        child,
        { ..context, precedence: n, precedence_name: None, associativity: -1, },
        inlines,
      )
    PrecRight(Integer(n), child) =>
      self.expand(
        child,
        { ..context, precedence: n, precedence_name: None, associativity: 1, },
        inlines,
      )
    PrecDynamic(n, child) =>
      self.expand(
        child,
        {
          ..context,
          dynamic_precedence: dynamic_precedence(context.dynamic_precedence, n),
        },
        inlines,
      )
    Prec(Name(name), child) =>
      self.expand(
        child,
        { ..context, precedence: 0, precedence_name: Some(name), },
        inlines,
      )
    PrecLeft(Name(name), child) =>
      self.expand(
        child,
        {
          ..context,
          precedence: 0,
          precedence_name: Some(name),
          associativity: -1,
        },
        inlines,
      )
    PrecRight(Name(name), child) =>
      self.expand(
        child,
        {
          ..context,
          precedence: 0,
          precedence_name: Some(name),
          associativity: 1,
        },
        inlines,
      )
    Reserved(name, child) =>
      self.expand(
        child,
        { ..context, reserved_set: self.reserved_names[name], },
        inlines,
      )
  }
}

///|
fn normalize(
  grammar : @grammar.Grammar,
  max_productions : Int32,
) -> (Builder, Int32, Array[Int32]) raise {
  grammar.validate()
  // Inline rules do not produce nodes. Upstream drops these supertype entries
  // while retaining the inline rule (used by the public Go grammar).
  let grammar = {
    ..grammar,
    supertypes: grammar.supertypes.filter(name => {
      !grammar.inline_rules.contains(name)
    }),
  }
  let builder : Builder = {
    grammar,
    symbols: [],
    tokens: [],
    productions: [],
    names: Map([]),
    token_ids: Map([]),
    repeats: Map([]),
    externals: [],
    reserved_sets: [],
    reserved_names: Map([]),
    max_productions,
  }
  ignore(builder.symbol("end", false, false, true))
  let token_counts = count_tokens(grammar)
  for i, (name, rule) in grammar.rules {
    if grammar.supertypes.contains(name) && lexical(rule) {
      raise InvalidGrammar("terminal rule '\{name}' cannot be a supertype")
    }
    let id = if i != 0 &&
      lexical(rule) &&
      token_counts.get(token_key(rule)) == Some(1) {
      builder.token(rule, name~)
    } else {
      builder.symbol(
        name,
        true,
        !name.has_prefix("_") && !grammar.supertypes.contains(name),
        false,
      )
    }
    builder.names[name] = id
  }
  for external in grammar.externals {
    let id = match external {
      Symbol(name) =>
        match builder.names.get(name) {
          Some(id) => id
          None => {
            let id = builder.symbol(name, true, !name.has_prefix("_"), true)
            builder.names[name] = id
            id
          }
        }
      Literal(_) | Pattern(_, ..) | Token(_) | ImmediateToken(_) =>
        builder.token(external)
      _ =>
        raise InvalidGrammar("external tokens must be symbols or lexical rules")
    }
    if !builder.symbols[id].terminal {
      raise InvalidGrammar("external token cannot be a nonterminal")
    }
    builder.externals.push(id)
  }
  let contexts = grammar.reserved
    .keys()
    .filter(name => name != "global")
    .to_array()
  contexts.sort()
  contexts.insert(0, "global")
  for name in contexts {
    let tokens = []
    for rule in grammar.reserved.get(name).unwrap_or([]) {
      let id = match rule {
        Symbol(name) => builder.names[name]
        _ => builder.token(rule)
      }
      if !builder.tokens.any(t => t.symbol == id) {
        raise InvalidGrammar("reserved words must be lexical tokens")
      }
      if !tokens.contains(id) {
        tokens.push(id)
      }
    }
    builder.reserved_names[name] = builder.reserved_sets.length()
    builder.reserved_sets.push(tokens)
  }
  let start = builder.names[grammar.rules[0].0]
  if !builder.symbols[start].visible {
    raise InvalidGrammar("a grammar's start rule must be visible")
  }
  let neutral : Context = {
    reserved_set: 0,
    precedence: 0,
    precedence_name: None,
    associativity: 0,
    dynamic_precedence: 0,
    field: None,
    rename: None,
  }
  for (name, rule) in grammar.rules {
    let lhs = builder.names[name]
    if !builder.symbols[lhs].terminal && !grammar.inline_rules.contains(name) {
      builder.emit(lhs, builder.expand(rule, neutral, []))
      if !builder.productions.any(p => p.lhs == lhs) {
        raise InvalidGrammar(
          "rule '\{name}' has no reachable production: eof() must be last",
        )
      }
    }
  }
  builder.validate_supertypes()
  let extras = []
  for extra in grammar.extras {
    let id = match extra {
      Symbol(name) => builder.names[name]
      _ => {
        let before = builder.symbols.length()
        let id = builder.token(extra)
        // Lexical extras absent from syntax are separators, not CST nodes.
        if id >= before {
          builder.symbols[id] = { ..builder.symbols[id], visible: false, }
        }
        id
      }
    }
    extras.push(id)
  }
  builder.order_tokens()
  (builder, start, extras)
}

///|
fn literal_token(rule : @grammar.Rule) -> Bool {
  match rule {
    Literal(_) => true
    Token(child) | ImmediateToken(child) | Prec(_, child) =>
      literal_token(child)
    _ => false
  }
}

///|
// A flattened production uses the metadata with greatest absolute dynamic
// precedence; separate reductions still add their scores at runtime.
fn dynamic_precedence(first : Int32, next : Int32) -> Int32 {
  if next.to_int64().abs() > first.to_int64().abs() {
    next
  } else {
    first
  }
}

///|
fn literal_name(rule : @grammar.Rule) -> String? {
  match rule {
    Literal(value) => Some(value)
    Token(child) | ImmediateToken(child) | Prec(_, child) => literal_name(child)
    _ => None
  }
}

///|
// Extraction follows grammar rule order, including anonymous tokens inside
// earlier rules. Symbol allocation alone puts all named tokens first.
fn Builder::order_tokens(self : Builder) -> Unit {
  let order : Map[Int32, Int32] = Map([])
  fn visit(rule : @grammar.Rule) {
    if self.token_ids.get(token_key(rule)) is Some(id) {
      if !order.contains(id) {
        order[id] = order.length()
      }
      return
    }
    match rule {
      Choice(rules) | Seq(rules) =>
        for child in rules {
          visit(child)
        }
      Repeat(child)
      | Repeat1(child)
      | Token(child)
      | ImmediateToken(child)
      | Field(_, child)
      | Alias(child, _, ..)
      | Prec(_, child)
      | PrecLeft(_, child)
      | PrecRight(_, child)
      | PrecDynamic(_, child)
      | Reserved(_, child) => visit(child)
      _ => ()
    }
  }
  for (name, rule) in self.grammar.rules {
    if self.token_ids.get("named:\{name}") is Some(id) {
      if !order.contains(id) {
        order[id] = order.length()
      }
    } else {
      visit(rule)
    }
  }
  for rule in self.grammar.extras {
    visit(rule)
  }
  for token in self.tokens {
    if !order.contains(token.symbol) {
      order[token.symbol] = order.length()
    }
  }
  self.tokens.sort_by((a, b) => order[a.symbol].compare(order[b.symbol]))
}

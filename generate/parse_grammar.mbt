// Port of tree-sitter crates/generate/src/parse_grammar.rs.
//
// Upstream deserializes `grammar.json` with serde (serde_json 1.0.154, serde
// 1.0.229). The `RuleJSON`, `PrecedenceValueJSON` and `GrammarJSON` decoders
// below are what serde_derive generates for them, written against the
// serde_json port in `serde_json`: the same documents are accepted, errors are
// found in the same order and have the same text, including serde_json's
// ` at line L column C` suffix. The rule bodies in `rules` and `reserved` are
// read as `serde_json::Value`s first and converted with
// `serde_json::from_value`, whose errors have no position.

///|
/// `RuleJSON`: one rule of `grammar.json`, tagged by its `type` field.
priv enum RuleJSON {
  ALIAS(content~ : RuleJSON, named~ : Bool, value~ : String)
  BLANK
  STRING(value~ : String)
  PATTERN(value~ : String, flags~ : String?)
  SYMBOL(name~ : String)
  CHOICE(members~ : Array[RuleJSON])
  FIELD(name~ : String, content~ : RuleJSON)
  SEQ(members~ : Array[RuleJSON])
  REPEAT(content~ : RuleJSON)
  REPEAT1(content~ : RuleJSON)
  PREC_DYNAMIC(value~ : Int32, content~ : RuleJSON)
  PREC_LEFT(value~ : PrecedenceValueJSON, content~ : RuleJSON)
  PREC_RIGHT(value~ : PrecedenceValueJSON, content~ : RuleJSON)
  PREC(value~ : PrecedenceValueJSON, content~ : RuleJSON)
  TOKEN(content~ : RuleJSON)
  IMMEDIATE_TOKEN(content~ : RuleJSON)
  RESERVED(context_name~ : String, content~ : RuleJSON)
  EOF
}

///|
priv enum PrecedenceValueJSON {
  Integer(Int32)
  Name(String)
}

///|
priv struct GrammarJSON {
  name : String
  rules : Map[String, @serde_json.Value]
  precedences : Array[Array[RuleJSON]]
  conflicts : Array[Array[String]]
  externals : Array[RuleJSON]
  extras : Array[RuleJSON]
  inline : Array[String]
  supertypes : Array[String]
  word : String?
  reserved : Map[String, @serde_json.Value]
}

///|
pub(all) suberror ParseGrammarError {
  Serialization(String)
  InvalidExtra
  Unexpected
  InvalidReservedWordSet
  UnexpectedRule(String)
} derive(Eq, Debug)

///|
pub impl Show for ParseGrammarError with fn output(self, logger) {
  match self {
    Serialization(message) => logger.write_string(message)
    InvalidExtra =>
      logger.write_string(
        "Rules in the `extras` array must not contain empty strings",
      )
    Unexpected =>
      logger.write_string(
        "Invalid rule in precedences array. Only strings and symbols are allowed",
      )
    InvalidReservedWordSet =>
      logger.write_string("Reserved word sets must be arrays")
    UnexpectedRule(name) =>
      logger.write_string(
        "Grammar Error: Unexpected rule `\{name}` in `token()` call",
      )
  }
}

///|
/// `impl From<serde_json::Error> for ParseGrammarError`.
fn serialization_error(e : @serde_json.JsonError) -> ParseGrammarError {
  Serialization(e.to_string())
}

// serde_derive's `Deserialize` impls --------------------------------------------

///|
let rule_json_variants : Array[String] = [
  "ALIAS", "BLANK", "STRING", "PATTERN", "SYMBOL", "CHOICE", "FIELD", "SEQ", "REPEAT",
  "REPEAT1", "PREC_DYNAMIC", "PREC_LEFT", "PREC_RIGHT", "PREC", "TOKEN", "IMMEDIATE_TOKEN",
  "RESERVED", "EOF",
]

///|
/// The fields of each struct variant, in declaration order.
fn rule_json_fields(variant : String) -> Array[String] {
  match variant {
    "ALIAS" => ["content", "named", "value"]
    "STRING" => ["value"]
    "PATTERN" => ["value", "flags"]
    "SYMBOL" => ["name"]
    "CHOICE" | "SEQ" => ["members"]
    "FIELD" => ["name", "content"]
    "REPEAT" | "REPEAT1" | "TOKEN" | "IMMEDIATE_TOKEN" => ["content"]
    "PREC_DYNAMIC" | "PREC_LEFT" | "PREC_RIGHT" | "PREC" => ["value", "content"]
    "RESERVED" => ["context_name", "content"]
    _ => []
  }
}

///|
let rule_json_expecting = "internally tagged enum RuleJSON"

///|
/// `RuleJSON::deserialize` from the `serde_json` stream.
fn RuleJSON::deserialize(
  de : @serde_json.Deserializer,
) -> RuleJSON raise @serde_json.JsonError {
  let (variant, content) = de.deserialize_internally_tagged(
    "type", rule_json_expecting, rule_json_variants,
  )
  RuleJSON::from_variant(variant, content)
}

///|
/// `RuleJSON::deserialize` from a `ContentDeserializer` (a nested rule).
fn RuleJSON::from_content(
  content : @serde_json.Content,
) -> RuleJSON raise @serde_json.JsonError {
  let (variant, content) = content.deserialize_internally_tagged(
    "type", rule_json_expecting, rule_json_variants,
  )
  RuleJSON::from_variant(variant, content)
}

///|
/// `serde_json::from_value::<RuleJSON>`.
fn RuleJSON::from_value(
  value : @serde_json.Value,
) -> RuleJSON raise @serde_json.JsonError {
  let (variant, content) = value.deserialize_internally_tagged(
    "type", rule_json_expecting, rule_json_variants,
  )
  RuleJSON::from_variant(variant, content)
}

///|
/// The variant of an internally tagged `RuleJSON`, from the content left
/// once the tag was found.
fn RuleJSON::from_variant(
  variant : Int32,
  content : @serde_json.Content,
) -> RuleJSON raise @serde_json.JsonError {
  let name = rule_json_variants[variant]
  if name == "BLANK" || name == "EOF" {
    content.deserialize_internally_tagged_unit("RuleJSON", name)
    return if name == "BLANK" { BLANK } else { EOF }
  }
  let fields = rule_json_fields(name)
  let rule : Ref[RuleJSON?] = { val: None, }
  let members : Ref[Array[RuleJSON]?] = { val: None, }
  let named : Ref[Bool?] = { val: None, }
  let int_value : Ref[Int32?] = { val: None, }
  let prec : Ref[PrecedenceValueJSON?] = { val: None, }
  let flags : Ref[String?] = { val: None, }
  let strings : Map[String, String] = Map([])
  content.deserialize_struct(
    "struct variant RuleJSON::\{name}",
    fields,
    (i, value) => {
      let field = fields[i]
      match field {
        "content" => rule.val = Some(RuleJSON::from_content(value))
        "members" =>
          members.val = Some(value.deserialize_vec(RuleJSON::from_content))
        "named" => named.val = Some(value.deserialize_bool())
        "value" if name == "PREC_DYNAMIC" =>
          int_value.val = Some(value.deserialize_i32())
        "value" if name is ("PREC_LEFT" | "PREC_RIGHT" | "PREC") =>
          prec.val = Some(PrecedenceValueJSON::from_content(value))
        "flags" =>
          flags.val = value.deserialize_option(c => c.deserialize_string())
        _ => strings[field] = value.deserialize_string()
      }
    },
    present => {
      // The values of absent fields, in field order: `None` for an
      // `Option`, a `missing field` error otherwise.
      for i, field in fields {
        if !present[i] && field != "flags" {
          raise @serde_json.missing_field(field)
        }
      }
      let string_field = (field : String) => strings.get(field).unwrap()
      let content_field = () => rule.val.unwrap()
      match name {
        "ALIAS" =>
          ALIAS(
            content=content_field(),
            named=named.val.unwrap(),
            value=string_field("value"),
          )
        "STRING" => STRING(value=string_field("value"))
        "PATTERN" => PATTERN(value=string_field("value"), flags=flags.val)
        "SYMBOL" => SYMBOL(name=string_field("name"))
        "CHOICE" => CHOICE(members=members.val.unwrap())
        "FIELD" => FIELD(name=string_field("name"), content=content_field())
        "SEQ" => SEQ(members=members.val.unwrap())
        "REPEAT" => REPEAT(content=content_field())
        "REPEAT1" => REPEAT1(content=content_field())
        "PREC_DYNAMIC" =>
          PREC_DYNAMIC(value=int_value.val.unwrap(), content=content_field())
        "PREC_LEFT" =>
          PREC_LEFT(value=prec.val.unwrap(), content=content_field())
        "PREC_RIGHT" =>
          PREC_RIGHT(value=prec.val.unwrap(), content=content_field())
        "PREC" => PREC(value=prec.val.unwrap(), content=content_field())
        "TOKEN" => TOKEN(content=content_field())
        "IMMEDIATE_TOKEN" => IMMEDIATE_TOKEN(content=content_field())
        _ =>
          RESERVED(
            context_name=string_field("context_name"),
            content=content_field(),
          )
      }
    },
  )
}

///|
/// `PrecedenceValueJSON::deserialize` (`#[serde(untagged)]`): the first
/// variant the content deserializes as.
fn PrecedenceValueJSON::from_content(
  content : @serde_json.Content,
) -> PrecedenceValueJSON raise @serde_json.JsonError {
  if (Some(content.deserialize_i32()) catch { _ => None }) is Some(i) {
    return Integer(i)
  }
  if (Some(content.deserialize_string()) catch { _ => None }) is Some(s) {
    return Name(s)
  }
  raise @serde_json.untagged_mismatch("PrecedenceValueJSON")
}

///|
let grammar_json_fields : Array[String] = [
  "name", "rules", "precedences", "conflicts", "externals", "extras", "inline", "supertypes",
  "word", "reserved",
]

///|
fn deserialize_strings(
  de : @serde_json.Deserializer,
) -> Array[String] raise @serde_json.JsonError {
  de.deserialize_vec(de => de.deserialize_string())
}

///|
fn deserialize_rules(
  de : @serde_json.Deserializer,
) -> Array[RuleJSON] raise @serde_json.JsonError {
  de.deserialize_vec(RuleJSON::deserialize)
}

///|
fn deserialize_word(
  de : @serde_json.Deserializer,
) -> String? raise @serde_json.JsonError {
  de.deserialize_option_with(de => de.deserialize_string())
}

///|
/// `GrammarJSON::deserialize`: a struct, read from a map (unknown fields are
/// skipped, `#[serde(default)]` fields may be absent) or from a sequence of
/// its fields in declaration order.
fn GrammarJSON::deserialize(
  de : @serde_json.Deserializer,
) -> GrammarJSON raise @serde_json.JsonError {
  de.deserialize_struct(
    @serde_json.Visitor::new(
      "struct GrammarJSON",
      visit_seq=GrammarJSON::visit_seq,
      visit_map=GrammarJSON::visit_map,
    ),
  )
}

///|
fn GrammarJSON::visit_seq(
  seq : @serde_json.SeqAccess,
) -> GrammarJSON raise @serde_json.JsonError {
  let expecting = "struct GrammarJSON with 10 elements"
  let name = match seq.next_element(de => de.deserialize_string()) {
    Some(name) => name
    None => raise @serde_json.invalid_length(0, expecting)
  }
  let rules = match seq.next_element(de => de.deserialize_value_map()) {
    Some(rules) => rules
    None => raise @serde_json.invalid_length(1, expecting)
  }
  let precedences = seq
    .next_element(de => de.deserialize_vec(deserialize_rules))
    .unwrap_or([])
  let conflicts = seq
    .next_element(de => de.deserialize_vec(deserialize_strings))
    .unwrap_or([])
  let externals = seq.next_element(deserialize_rules).unwrap_or([])
  let extras = seq.next_element(deserialize_rules).unwrap_or([])
  let inline = seq.next_element(deserialize_strings).unwrap_or([])
  let supertypes = seq.next_element(deserialize_strings).unwrap_or([])
  let word = seq.next_element(deserialize_word).unwrap_or(None)
  let reserved = seq
    .next_element(de => de.deserialize_value_map())
    .unwrap_or(Map([]))
  {
    name,
    rules,
    precedences,
    conflicts,
    externals,
    extras,
    inline,
    supertypes,
    word,
    reserved,
  }
}

///|
fn GrammarJSON::visit_map(
  map : @serde_json.MapAccess,
) -> GrammarJSON raise @serde_json.JsonError {
  let mut name = None
  let mut rules = None
  let mut precedences = None
  let mut conflicts = None
  let mut externals = None
  let mut extras = None
  let mut inline = None
  let mut supertypes = None
  let mut word = None
  let mut reserved = None
  while map.next_key(key => grammar_json_fields.search(key).unwrap_or(-1))
        is Some(field) {
    // serde_derive's `duplicate field` check.
    if field >= 0 {
      let present = match field {
        0 => name is Some(_)
        1 => rules is Some(_)
        2 => precedences is Some(_)
        3 => conflicts is Some(_)
        4 => externals is Some(_)
        5 => extras is Some(_)
        6 => inline is Some(_)
        7 => supertypes is Some(_)
        8 => word is Some(_)
        _ => reserved is Some(_)
      }
      if present {
        raise @serde_json.duplicate_field(grammar_json_fields[field])
      }
    }
    match field {
      0 => name = Some(map.next_value(de => de.deserialize_string()))
      1 => rules = Some(map.next_value(de => de.deserialize_value_map()))
      2 =>
        precedences = Some(
          map.next_value(de => de.deserialize_vec(deserialize_rules)),
        )
      3 =>
        conflicts = Some(
          map.next_value(de => de.deserialize_vec(deserialize_strings)),
        )
      4 => externals = Some(map.next_value(deserialize_rules))
      5 => extras = Some(map.next_value(deserialize_rules))
      6 => inline = Some(map.next_value(deserialize_strings))
      7 => supertypes = Some(map.next_value(deserialize_strings))
      8 => word = Some(map.next_value(deserialize_word))
      9 => reserved = Some(map.next_value(de => de.deserialize_value_map()))
      _ => map.next_value(de => de.deserialize_ignored_any())
    }
  }
  let name = match name {
    Some(name) => name
    None => raise @serde_json.missing_field("name")
  }
  let rules = match rules {
    Some(rules) => rules
    None => raise @serde_json.missing_field("rules")
  }
  {
    name,
    rules,
    precedences: precedences.unwrap_or([]),
    conflicts: conflicts.unwrap_or([]),
    externals: externals.unwrap_or([]),
    extras: extras.unwrap_or([]),
    inline: inline.unwrap_or([]),
    supertypes: supertypes.unwrap_or([]),
    word: word.unwrap_or(None),
    reserved: reserved.unwrap_or(Map([])),
  }
}

// InputGrammar::normalize ------------------------------------------------------

///|
/// Strip unused rules from the grammar and clean up references to them
/// in the surrounding config. (conflicts, supertypes, inline, extras,
/// externals, precedences).
///
/// A variable is "used" if it is the start rule, the word token, named in
/// `extras`/`externals`, or transitively reachable via rule references from
/// any of the above.
fn InputGrammar::normalize(self : InputGrammar) -> InputGrammar {
  // Compute the used set via forward DFS from the implicit roots
  // (start rule, word_token, refs in extras and externals).
  //
  // Extras count their top-level `NamedSymbol` as a use (so naming
  // a rule directly in `extras` keeps it), but externals do not (the
  // external entry is the rule itself, not a reference to one).
  let used : @hashset.HashSet[StrId] = {
    let by_name : Map[StrId, RuleId] = Map([])
    for v in self.variables {
      by_name[v.name] = v.root
    }
    let visited = @hashset.HashSet([])
    let stack : Array[StrId] = []
    if self.variables.get(0) is Some(first) {
      stack.push(first.name)
    }
    if self.word_name is Some(word) {
      stack.push(word)
    }
    for root in self.extra_roots {
      self.pool.collect_referenced_ids(root, false, stack)
    }
    for root in self.external_roots {
      self.pool.collect_referenced_ids(root, true, stack)
    }
    for set in self.reserved_sets {
      for root in set.roots {
        self.pool.collect_referenced_ids(root, false, stack)
      }
    }
    while stack.pop() is Some(name) {
      if visited.contains(name) {
        continue
      }
      visited.add(name)
      if by_name.get(name) is Some(root) {
        self.pool.collect_referenced_ids(root, false, stack)
      }
    }
    visited
  }

  // Drop unused variables and clean up references to them in the config
  let dropped = self.variables
    .filter(v => !used.contains(v.name))
    .map(v => v.name)
  self.variables.retain(v => used.contains(v.name))
  for name in dropped {
    self.conflict_names.retain(c => !c.contains(name))
    self.supertype_names.retain(s => s != name)
    self.inline_names.retain(s => s != name)
    let pool = self.pool
    self.extra_roots.retain(r => !pool.rule_is_referenced(r, name, true))
    self.external_roots.retain(r => !pool.rule_is_referenced(r, name, true))
    self.precedence_orderings.retain(o => {
      !o.iter().any(e => e is Symbol(s) && s == name)
    })
    // Prune entries but keep the context: an intentionally-empty
    // reserved-word context is a meaningful marker that rule bodies
    // may reference by name.
    for set in self.reserved_sets {
      set.roots.retain(r => !pool.rule_is_referenced(r, name, false))
    }
  }
  self
}

///|
/// `parse_grammar::parse_grammar`: parse upstream `grammar.json` text.
pub fn parse_grammar(
  input : String,
  diagnostics : Array[Diagnostic],
) -> InputGrammar raise {
  let grammar_json = @serde_json.from_str(input, GrammarJSON::deserialize) catch {
    e => raise serialization_error(e)
  }
  let pool = RulePool::new()
  let extra_roots = []
  for item in grammar_json.extras {
    let root = pool.parse_rule(item, false, diagnostics)
    if pool.node(root) is String(s) && pool.resolve(s).is_empty() {
      raise InvalidExtra
    }
    extra_roots.push(root)
  }
  let external_roots = grammar_json.externals.map(e => {
    pool.parse_rule(e, false, diagnostics)
  })
  let precedence_orderings = []
  for list in grammar_json.precedences {
    let ordering = []
    for entry in list {
      ordering.push(
        match entry {
          STRING(value~) => PrecedenceEntry::Name(pool.intern(value))
          SYMBOL(name~) => PrecedenceEntry::Symbol(pool.intern(name))
          _ => raise Unexpected
        },
      )
    }
    precedence_orderings.push(ordering)
  }
  let variables = []
  for name, r in grammar_json.rules {
    let name = pool.intern(name)
    let rule = RuleJSON::from_value(r) catch {
      e => raise serialization_error(e)
    }
    variables.push({ name, root: pool.parse_rule(rule, false, diagnostics), })
  }
  let reserved_sets = []
  for name, rule_values in grammar_json.reserved {
    guard rule_values is Array(rule_values) else {
      raise InvalidReservedWordSet
    }
    let name = pool.intern(name)
    let roots = []
    for value in rule_values {
      roots.push(
        pool.parse_rule(
          RuleJSON::from_value(value) catch {
            e => raise serialization_error(e)
          },
          false,
          diagnostics,
        ),
      )
    }
    reserved_sets.push({ name, roots, })
  }
  let supertype_names = grammar_json.supertypes.map(s => pool.intern(s))
  let conflict_names = grammar_json.conflicts.map(c => {
    c.map(n => pool.intern(n))
  })
  let inline_names = grammar_json.inline.map(n => pool.intern(n))
  let word_name = match grammar_json.word {
    Some(w) => Some(pool.intern(w))
    None => None
  }
  let name = pool.intern(grammar_json.name)
  let grammar : InputGrammar = {
    pool,
    name,
    variables,
    external_roots,
    extra_roots,
    reserved_sets,
    supertype_names,
    conflict_names,
    inline_names,
    word_name,
    precedence_orderings,
  }
  grammar.normalize()
}

///|
fn RulePool::parse_rule(
  self : RulePool,
  json : RuleJSON,
  is_token : Bool,
  diagnostics : Array[Diagnostic],
) -> RuleId raise ParseGrammarError {
  match json {
    ALIAS(content~, named~, value~) => {
      let content = self.parse_rule(content, is_token, diagnostics)
      let value = self.intern(value)
      self.alias(content, value, named)
    }
    BLANK => self.blank()
    PATTERN(value~, flags~) => {
      let processed_flags = match flags {
        None => ""
        Some(f) => {
          let sb = StringBuilder()
          for c in f {
            if c == 'i' {
              sb.write_char(c)
            } else if c != 'u' && c != 'v' {
              // silently ignore unicode flags
              diagnostics.push(UnsupportedRegexFlag(flag=c, pattern=value))
            }
          }
          sb.to_string()
        }
      }
      let value = self.intern(value)
      let flags = self.intern(processed_flags)
      self.pattern(value, flags)
    }
    SYMBOL(name~) =>
      if is_token {
        raise UnexpectedRule(name)
      } else {
        let sid = self.intern(name)
        self.named_symbol(sid)
      }
    CHOICE(members~) => {
      let members = members.map(m => self.parse_rule(m, is_token, diagnostics))
      self.choice(members)
    }
    SEQ(members~) =>
      self.try_seq(members, (pool, m) => {
        pool.parse_rule(m, is_token, diagnostics)
      })
    FIELD(name~, content~) => {
      let content = self.parse_rule(content, is_token, diagnostics)
      let name = self.intern(name)
      self.field(name, content)
    }
    REPEAT(content~) => {
      let content = self.parse_rule(content, is_token, diagnostics)
      let repeat = self.repeat(content)
      let blank = self.blank()
      // Neither element is a `Choice` or equal to one another, so we
      // can skip `self.choice`'s flattening loop.
      let range = self.push_children([repeat, blank])
      self.push_node(Choice(range))
    }
    REPEAT1(content~) => {
      let content = self.parse_rule(content, is_token, diagnostics)
      self.repeat(content)
    }
    PREC(value~, content~) => {
      let content = self.parse_rule(content, is_token, diagnostics)
      let value = value.intern(self)
      self.prec(value, content)
    }
    PREC_LEFT(value~, content~) => {
      let content = self.parse_rule(content, is_token, diagnostics)
      let value = value.intern(self)
      self.prec_left(value, content)
    }
    PREC_RIGHT(value~, content~) => {
      let content = self.parse_rule(content, is_token, diagnostics)
      let value = value.intern(self)
      self.prec_right(value, content)
    }
    PREC_DYNAMIC(value~, content~) => {
      let content = self.parse_rule(content, is_token, diagnostics)
      self.prec_dynamic(value, content)
    }
    RESERVED(context_name~, content~) => {
      let content = self.parse_rule(content, is_token, diagnostics)
      let ctx = self.intern(context_name)
      self.reserved(content, ctx)
    }
    TOKEN(content~) => {
      let content = self.parse_rule(content, true, diagnostics)
      self.token(content)
    }
    IMMEDIATE_TOKEN(content~) => {
      let content = self.parse_rule(content, true, diagnostics)
      self.immediate_token(content)
    }
    STRING(value~) => {
      let sid = self.intern(value)
      self.string(sid)
    }
    EOF => self.eof()
  }
}

///|
fn PrecedenceValueJSON::intern(
  self : PrecedenceValueJSON,
  pool : RulePool,
) -> Precedence {
  match self {
    Integer(i) => Integer(i)
    Name(n) => Name(pool.intern(n))
  }
}

// Port of tree-sitter crates/generate/src/parse_grammar.rs.
//
// Upstream deserializes `grammar.json` with serde. The `RuleJSON`,
// `PrecedenceValueJSON` and `GrammarJSON` decoders below reproduce serde's
// observable behavior: which document is accepted, the order in which errors
// are found and the text of serde's messages. serde's ` at line L column C`
// suffix on errors raised while reading the top-level document is not
// reproduced (errors raised by `serde_json::from_value` for rule bodies carry
// no position upstream either). Nor is serde's `duplicate field` error for a
// key repeated inside the top-level object or an `extras`/`externals`/
// `precedences` rule: `@json.parse` keeps the last value, as upstream does for
// the `rules` and `reserved` maps. JSON syntax errors use `@json`'s text.

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
  rules : Map[String, Json]
  precedences : Array[Array[RuleJSON]]
  conflicts : Array[Array[String]]
  externals : Array[RuleJSON]
  extras : Array[RuleJSON]
  inline : Array[String]
  supertypes : Array[String]
  word : String?
  reserved : Map[String, Json]
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

// serde's error vocabulary ----------------------------------------------------

///|
/// serde_json's `JsonUnexpected` rendering of the value that had the wrong type.
fn serde_unexpected(json : Json) -> String {
  match json {
    Null => "null"
    True => "boolean `true`"
    False => "boolean `false`"
    Number(n, repr~) =>
      match json_integer(n, repr) {
        Some(i) => "integer `\{i}`"
        None => "floating point `\{serde_float(n)}`"
      }
    String(s) => "string \{rust_debug_str(s)}"
    Array(_) => "sequence"
    Object(_) => "map"
  }
}

///|
/// Rust's `{:?}` for a `&str`.
fn rust_debug_str(s : String) -> String {
  let sb = StringBuilder()
  sb.write_char('"')
  for c in s {
    match c {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      '\u{0}' => sb.write_string("\\0")
      c if c.to_int() < 0x20 || c.to_int() == 0x7f => {
        sb.write_string("\\u{")
        sb.write_string(c.to_int().to_string(radix=16))
        sb.write_char('}')
      }
      c => sb.write_char(c)
    }
  }
  sb.write_char('"')
  sb.to_string()
}

///|
/// serde_json prints floats in `invalid type` errors with a decimal point.
fn serde_float(n : Double) -> String {
  let s = n.to_string()
  if s.contains(".") || s.contains("e") || s.contains("N") || s.contains("I") {
    s
  } else {
    s + ".0"
  }
}

///|
/// The decimal text of the integer a JSON number denotes, if serde_json reads
/// it as an integer (no fraction or exponent, and within `i64` or `u64`;
/// larger literals are read as floats). Requires the number's source text.
fn json_integer(n : Double, repr : String?) -> String? {
  let text = match repr {
    Some(text) => text
    None => n.to_string()
  }
  if text.contains(".") || text.contains("e") || text.contains("E") {
    return None
  }
  try @string.parse_int64(text) catch {
    _ =>
      try @string.parse_uint64(text) catch {
        _ => None
      } noraise {
        u => Some(u.to_string())
      }
  } noraise {
    i => Some(i.to_string())
  }
}

///|
fn invalid_type(json : Json, expected : String) -> ParseGrammarError {
  Serialization("invalid type: \{serde_unexpected(json)}, expected \{expected}")
}

///|
fn missing_field(name : String) -> ParseGrammarError {
  Serialization("missing field `\{name}`")
}

///|
fn de_string(json : Json) -> String raise ParseGrammarError {
  match json {
    String(s) => s
    _ => raise invalid_type(json, "a string")
  }
}

///|
fn de_bool(json : Json) -> Bool raise ParseGrammarError {
  match json {
    True => true
    False => false
    _ => raise invalid_type(json, "a boolean")
  }
}

///|
fn de_i32(json : Json) -> Int32 raise ParseGrammarError {
  guard json is Number(n, repr~) else { raise invalid_type(json, "i32") }
  guard json_integer(n, repr) is Some(text) else {
    raise invalid_type(json, "i32")
  }
  @string.parse_int(text) catch {
    _ => raise Serialization("invalid value: integer `\{text}`, expected i32")
  }
}

///|
fn[T] de_seq(
  json : Json,
  f : (Json) -> T raise ParseGrammarError,
) -> Array[T] raise ParseGrammarError {
  guard json is Array(items) else { raise invalid_type(json, "a sequence") }
  items.map(f)
}

///|
fn de_map(json : Json) -> Map[String, Json] raise ParseGrammarError {
  guard json is Object(map) else { raise invalid_type(json, "a map") }
  map
}

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
fn PrecedenceValueJSON::from_json(
  json : Json,
) -> PrecedenceValueJSON raise ParseGrammarError {
  match json {
    String(s) => Name(s)
    Number(n, repr~) =>
      match json_integer(n, repr) {
        Some(text) =>
          Integer(
            @string.parse_int(text) catch {
              _ =>
                raise Serialization(
                  "data did not match any variant of untagged enum PrecedenceValueJSON",
                )
            },
          )
        None =>
          raise Serialization(
            "data did not match any variant of untagged enum PrecedenceValueJSON",
          )
      }
    _ =>
      raise Serialization(
        "data did not match any variant of untagged enum PrecedenceValueJSON",
      )
  }
}

///|
/// serde's internally tagged enum: find the tag, then read the variant's
/// fields in document order, then report the first missing field.
fn RuleJSON::from_json(json : Json) -> RuleJSON raise ParseGrammarError {
  guard json is Object(map) else {
    raise invalid_type(json, "internally tagged enum RuleJSON")
  }
  guard map.get("type") is Some(tag) else { raise missing_field("type") }
  let variant = match tag {
    String(s) => s
    _ => raise invalid_type(tag, "variant identifier")
  }
  if !rule_json_variants.contains(variant) {
    let expected = rule_json_variants.map(v => "`\{v}`").join(", ")
    raise Serialization(
      "unknown variant `\{variant}`, expected one of \{expected}",
    )
  }
  let fields = rule_json_fields(variant)
  let values : Map[String, String] = Map([])
  let content : Ref[RuleJSON?] = { val: None, }
  let members : Ref[Array[RuleJSON]?] = { val: None, }
  let prec : Ref[PrecedenceValueJSON?] = { val: None, }
  let int_value : Ref[Int32?] = { val: None, }
  let named : Ref[Bool?] = { val: None, }
  for key, value in map {
    if key == "type" || !fields.contains(key) {
      continue
    }
    match (variant, key) {
      (_, "content") => content.val = Some(RuleJSON::from_json(value))
      (_, "members") => members.val = Some(de_seq(value, RuleJSON::from_json))
      ("ALIAS", "named") => named.val = Some(de_bool(value))
      ("PREC_DYNAMIC", "value") => int_value.val = Some(de_i32(value))
      ("PREC_LEFT" | "PREC_RIGHT" | "PREC", "value") =>
        prec.val = Some(PrecedenceValueJSON::from_json(value))
      ("PATTERN", "flags") =>
        if !(value is Null) {
          values[key] = de_string(value)
        }
      _ => values[key] = de_string(value)
    }
  }
  fn string_field(name : String) -> String raise ParseGrammarError {
    match values.get(name) {
      Some(s) => s
      _ => raise missing_field(name)
    }
  }

  fn content_field() -> RuleJSON raise ParseGrammarError {
    match content.val {
      Some(c) => c
      None => raise missing_field("content")
    }
  }

  fn prec_field() -> PrecedenceValueJSON raise ParseGrammarError {
    match prec.val {
      Some(p) => p
      None => raise missing_field("value")
    }
  }

  fn members_field() -> Array[RuleJSON] raise ParseGrammarError {
    match members.val {
      Some(m) => m
      None => raise missing_field("members")
    }
  }

  match variant {
    "ALIAS" => {
      let content = content_field()
      guard named.val is Some(named) else { raise missing_field("named") }
      ALIAS(content~, named~, value=string_field("value"))
    }
    "BLANK" => BLANK
    "STRING" => STRING(value=string_field("value"))
    "PATTERN" => {
      let value = string_field("value")
      let flags = match values.get("flags") {
        Some(f) => Some(f)
        _ => None
      }
      PATTERN(value~, flags~)
    }
    "SYMBOL" => SYMBOL(name=string_field("name"))
    "CHOICE" => CHOICE(members=members_field())
    "FIELD" => {
      let name = string_field("name")
      FIELD(name~, content=content_field())
    }
    "SEQ" => SEQ(members=members_field())
    "REPEAT" => REPEAT(content=content_field())
    "REPEAT1" => REPEAT1(content=content_field())
    "PREC_DYNAMIC" => {
      guard int_value.val is Some(value) else { raise missing_field("value") }
      PREC_DYNAMIC(value~, content=content_field())
    }
    "PREC_LEFT" => {
      let value = prec_field()
      PREC_LEFT(value~, content=content_field())
    }
    "PREC_RIGHT" => {
      let value = prec_field()
      PREC_RIGHT(value~, content=content_field())
    }
    "PREC" => {
      let value = prec_field()
      PREC(value~, content=content_field())
    }
    "TOKEN" => TOKEN(content=content_field())
    "IMMEDIATE_TOKEN" => IMMEDIATE_TOKEN(content=content_field())
    "RESERVED" => {
      let context_name = string_field("context_name")
      RESERVED(context_name~, content=content_field())
    }
    _ => EOF
  }
}

///|
/// `serde_json::from_str::<GrammarJSON>`: fields are read in document order,
/// unknown fields are ignored, `#[serde(default)]` fields may be absent.
fn GrammarJSON::from_str(input : String) -> GrammarJSON raise ParseGrammarError {
  let json = @json.parse(input, preserve_number_repr=true) catch {
    e => raise Serialization(e.to_string())
  }
  let map = match json {
    Object(map) => map
    // serde also reads a struct from a sequence of its fields, in declaration
    // order; trailing `#[serde(default)]` fields may be left out.
    Array(items) => {
      let fields = [
        "name", "rules", "precedences", "conflicts", "externals", "extras", "inline",
        "supertypes", "word", "reserved",
      ]
      if items.length() < 2 {
        raise Serialization(
          "invalid length \{items.length()}, expected struct GrammarJSON with 10 elements",
        )
      }
      if items.length() > fields.length() {
        raise Serialization("trailing characters")
      }
      let map : Map[String, Json] = Map([])
      for i, item in items {
        map[fields[i]] = item
      }
      map
    }
    _ => raise invalid_type(json, "struct GrammarJSON")
  }
  let mut name : String? = None
  let mut rules : Map[String, Json]? = None
  let mut precedences = []
  let mut conflicts = []
  let mut externals = []
  let mut extras = []
  let mut inline = []
  let mut supertypes = []
  let mut word = None
  let mut reserved = Map([])
  for key, value in map {
    match key {
      "name" => name = Some(de_string(value))
      "rules" => rules = Some(de_map(value))
      "precedences" =>
        precedences = de_seq(value, list => de_seq(list, RuleJSON::from_json))
      "conflicts" => conflicts = de_seq(value, list => de_seq(list, de_string))
      "externals" => externals = de_seq(value, RuleJSON::from_json)
      "extras" => extras = de_seq(value, RuleJSON::from_json)
      "inline" => inline = de_seq(value, de_string)
      "supertypes" => supertypes = de_seq(value, de_string)
      "word" =>
        word = match value {
          Null => None
          _ => Some(de_string(value))
        }
      "reserved" => reserved = de_map(value)
      _ => ()
    }
  }
  guard name is Some(name) else { raise missing_field("name") }
  guard rules is Some(rules) else { raise missing_field("rules") }
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
  let grammar_json = GrammarJSON::from_str(input)
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
    let rule = RuleJSON::from_json(r)
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
        pool.parse_rule(RuleJSON::from_json(value), false, diagnostics),
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

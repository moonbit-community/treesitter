///|
fn Precedence::json(self : Precedence) -> Json {
  match self {
    Integer(n) => Json(n)
    Name(s) => Json(s)
  }
}

///|
pub impl ToJson for Rule with fn to_json(self) {
  let obj : Map[String, Json] = Map([])
  let kind = match self {
    Blank => "BLANK"
    Eof => "EOF"
    Literal(value) => {
      obj["value"] = Json(value)
      "STRING"
    }
    Pattern(value, flags~) => {
      obj["value"] = Json(value)
      if flags != "" {
        obj["flags"] = Json(flags)
      }
      "PATTERN"
    }
    Symbol(name) => {
      obj["name"] = Json(name)
      "SYMBOL"
    }
    Choice(members) => {
      obj["members"] = Json(members)
      "CHOICE"
    }
    Seq(members) => {
      obj["members"] = Json(members)
      "SEQ"
    }
    Repeat(content) => {
      obj["content"] = Json(content)
      "REPEAT"
    }
    Repeat1(content) => {
      obj["content"] = Json(content)
      "REPEAT1"
    }
    Token(content) => {
      obj["content"] = Json(content)
      "TOKEN"
    }
    ImmediateToken(content) => {
      obj["content"] = Json(content)
      "IMMEDIATE_TOKEN"
    }
    Prec(value, content)
    | PrecLeft(value, content)
    | PrecRight(value, content) => {
      obj["value"] = value.json()
      obj["content"] = Json(content)
      match self {
        Prec(_, _) => "PREC"
        PrecLeft(_, _) => "PREC_LEFT"
        _ => "PREC_RIGHT"
      }
    }
    PrecDynamic(value, content) => {
      obj["value"] = Json(value)
      obj["content"] = Json(content)
      "PREC_DYNAMIC"
    }
    Field(name, content) => {
      obj["name"] = Json(name)
      obj["content"] = Json(content)
      "FIELD"
    }
    Alias(content, value, named~) => {
      obj["content"] = Json(content)
      obj["value"] = Json(value)
      obj["named"] = Json(named)
      "ALIAS"
    }
    Reserved(context, content) => {
      obj["context_name"] = Json(context)
      obj["content"] = Json(content)
      "RESERVED"
    }
  }
  let result : Map[String, Json] = { "type": Json(kind) }
  for k, v in obj {
    result[k] = v
  }
  Json::object(result)
}

///|
pub impl ToJson for Grammar with fn to_json(self) {
  let rules : Map[String, Json] = Map([])
  for (name, rule) in self.rules {
    rules[name] = Json(rule)
  }
  let obj : Map[String, Json] = {
    "name": Json(self.name),
    "rules": Json::object(rules),
    "extras": Json(self.extras),
    "externals": Json(self.externals),
    "conflicts": Json(self.conflicts),
    "precedences": Json(self.precedences),
    "inline": Json(self.inline_rules),
    "supertypes": Json(self.supertypes),
    "reserved": Json(self.reserved),
  }
  if self.word is Some(word) {
    obj["word"] = Json(word)
  }
  Json::object(obj)
}

///|
fn object(value : Json, path : String) -> Map[String, Json] raise GrammarError {
  match value {
    Object(obj) => obj
    _ => raise InvalidGrammar("\{path}: expected object")
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
  path : String,
) -> Json raise GrammarError {
  match obj.get(key) {
    Some(value) => value
    None => raise InvalidGrammar("\{path}: missing '\{key}'")
  }
}

///|
fn string(value : Json, path : String) -> String raise GrammarError {
  match value {
    String(s) => s
    _ => raise InvalidGrammar("\{path}: expected string")
  }
}

///|
fn array(value : Json, path : String) -> Array[Json] raise GrammarError {
  match value {
    Array(a) => a
    _ => raise InvalidGrammar("\{path}: expected array")
  }
}

///|
fn integer(value : Json, path : String) -> Int32 raise GrammarError {
  match value {
    Number(n, ..) => {
      if n < -2147483648.0 || n > 2147483647.0 || n.to_int().to_double() != n {
        raise InvalidGrammar("\{path}: expected 32-bit integer")
      }
      n.to_int()
    }
    _ => raise InvalidGrammar("\{path}: expected integer")
  }
}

///|
fn precedence(value : Json, path : String) -> Precedence raise GrammarError {
  match value {
    String(s) => Name(s)
    _ => Integer(integer(value, path))
  }
}

///|
pub fn Rule::from_json(
  value : Json,
  path~ : String = "rule",
) -> Rule raise GrammarError {
  let obj = object(value, path)
  let kind = string(required(obj, "type", path), path)
  fn property(key) raise GrammarError {
    required(obj, key, path)
  }
  fn child() raise GrammarError {
    Rule::from_json(property("content"), path="\{path}.content")
  }
  match kind {
    "BLANK" => Blank
    "EOF" => Eof
    "STRING" => Literal(string(property("value"), path))
    "SYMBOL" => Symbol(string(property("name"), path))
    "PATTERN" =>
      Pattern(
        string(property("value"), path),
        flags=match obj.get("flags") {
          None | Some(Null) => ""
          Some(v) => string(v, path)
        },
      )
    "CHOICE" | "SEQ" => {
      let items = array(property("members"), path).mapi((i, v) => {
        Rule::from_json(v, path="\{path}.members[\{i}]")
      })
      if kind == "CHOICE" {
        Choice(items)
      } else {
        Seq(items)
      }
    }
    "REPEAT" => Repeat(child())
    "REPEAT1" => Repeat1(child())
    "TOKEN" => Token(child())
    "IMMEDIATE_TOKEN" => ImmediateToken(child())
    "PREC" => Prec(precedence(property("value"), path), child())
    "PREC_LEFT" => PrecLeft(precedence(property("value"), path), child())
    "PREC_RIGHT" => PrecRight(precedence(property("value"), path), child())
    "PREC_DYNAMIC" => PrecDynamic(integer(property("value"), path), child())
    "FIELD" => Field(string(property("name"), path), child())
    "ALIAS" => {
      let named = match property("named") {
        True => true
        False => false
        _ => raise InvalidGrammar("\{path}: named must be boolean")
      }
      Alias(child(), string(property("value"), path), named~)
    }
    "RESERVED" => Reserved(string(property("context_name"), path), child())
    _ => raise InvalidGrammar("\{path}: unknown rule type '\{kind}'")
  }
}

///|
pub fn Grammar::from_json(value : Json) -> Grammar raise GrammarError {
  let obj = object(value, "grammar")
  fn items(key) raise GrammarError {
    array(obj.get(key).unwrap_or(Json::array([])), key)
  }
  let rules_obj = object(required(obj, "rules", "grammar"), "rules")
  let rules = []
  for name, v in rules_obj {
    rules.push((name, Rule::from_json(v, path="rules.\{name}")))
  }
  let reserved : Map[String, Array[Rule]] = Map([])
  if obj.get("reserved") is Some(value) {
    for context, rules in object(value, "reserved") {
      reserved[context] = array(rules, "reserved.\{context}").map(r => {
        Rule::from_json(r)
      })
    }
  }
  let grammar : Grammar = {
    name: string(required(obj, "name", "grammar"), "name"),
    rules,
    extras: items("extras").map(r => Rule::from_json(r)),
    externals: items("externals").map(r => Rule::from_json(r)),
    conflicts: items("conflicts").map(v => {
      array(v, "conflicts").map(s => string(s, "conflicts"))
    }),
    precedences: items("precedences").map(v => {
      array(v, "precedences").map(r => Rule::from_json(r))
    }),
    inline_rules: items("inline").map(s => string(s, "inline")),
    supertypes: items("supertypes").map(s => string(s, "supertypes")),
    word: match obj.get("word") {
      None | Some(Null) => None
      Some(v) => Some(string(v, "word"))
    },
    reserved,
  }
  grammar.validate()
  grammar
}

///|
pub fn Grammar::parse(source : StringView) -> Grammar raise {
  Grammar::from_json(@json.parse(source, reject_duplicate_keys=true))
}

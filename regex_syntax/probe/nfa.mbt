// NFA probe (development only): converts the lexical rules of a
// `grammar.json` into pool rules, runs `expand_tokens` and dumps the NFA in
// the format of the Rust counterpart (a scratch copy of the upstream crate).

///|
fn convert(p : @generate.RulePool, v : Json) -> @generate.RuleId? {
  guard v is Object(obj) && obj.get("type") is Some(String(ty)) else {
    return None
  }
  let str_field = (name : String) => {
    match obj.get(name) {
      Some(String(s)) => Some(s)
      _ => None
    }
  }
  match ty {
    "STRING" => {
      guard str_field("value") is Some(value) else { return None }
      Some(p.string(p.intern(value)))
    }
    "PATTERN" => {
      guard str_field("value") is Some(value) else { return None }
      let flags = str_field("flags").unwrap_or("")
      let s = p.intern(value)
      let f = p.intern(flags)
      Some(p.pattern(s, f))
    }
    "BLANK" => Some(p.blank())
    "SEQ" | "CHOICE" => {
      guard obj.get("members") is Some(Array(members)) else { return None }
      let ids = []
      for m in members {
        guard convert(p, m) is Some(id) else { return None }
        ids.push(id)
      }
      Some(if ty == "SEQ" { p.seq(ids) } else { p.choice(ids) })
    }
    "REPEAT" => {
      guard convert(p, obj["content"]) is Some(c) else { return None }
      let r = p.repeat(c)
      let b = p.blank()
      Some(p.choice([r, b]))
    }
    "REPEAT1" => {
      guard convert(p, obj["content"]) is Some(c) else { return None }
      Some(p.repeat(c))
    }
    "PREC" | "PREC_LEFT" | "PREC_RIGHT" => {
      guard convert(p, obj["content"]) is Some(c) else { return None }
      match obj.get("value") {
        Some(Number(n, ..)) => Some(p.prec(Integer(n.to_int()), c))
        _ => Some(c)
      }
    }
    "PREC_DYNAMIC" | "ALIAS" | "FIELD" => convert(p, obj["content"])
    "TOKEN" => {
      guard convert(p, obj["content"]) is Some(c) else { return None }
      Some(p.token(c))
    }
    "IMMEDIATE_TOKEN" => {
      guard convert(p, obj["content"]) is Some(c) else { return None }
      Some(p.immediate_token(c))
    }
    _ => None
  }
}

///|
fn collect(v : Json, out : Array[Json]) -> Unit {
  guard v is Object(obj) else { return }
  match obj.get("type") {
    Some(String("TOKEN" | "IMMEDIATE_TOKEN" | "STRING" | "PATTERN")) =>
      out.push(v)
    Some(String("SEQ" | "CHOICE")) =>
      if obj.get("members") is Some(Array(members)) {
        for m in members {
          collect(m, out)
        }
      }
    _ => if obj.get("content") is Some(c) { collect(c, out) }
  }
}

///|
fn kind_name(kind : @generate.VariableType) -> String {
  match kind {
    Hidden => "Hidden"
    Auxiliary => "Auxiliary"
    Anonymous => "Anonymous"
    Named => "Named"
  }
}

///|
fn nfa_run(text : String) -> String raise {
  let g = @json.parse(text)
  guard g is Object(grammar) else { abort("grammar is not an object") }
  let candidates = []
  if grammar.get("rules") is Some(Object(rules)) {
    for _, rule in rules {
      collect(rule, candidates)
    }
  }
  let pool = @generate.RulePool::new()
  let vars : Array[@generate.LexicalToken] = []
  for c in candidates {
    if convert(pool, c) is Some(root) {
      if pool.subtree_matches_empty_str(root) {
        continue
      }
      let name = pool.intern("t\{vars.length()}")
      vars.push({ name, kind: Anonymous, root, })
    }
  }
  let seps = []
  if grammar.get("extras") is Some(Array(extras)) {
    for e in extras {
      if convert(pool, e) is Some(root) {
        seps.push(root)
      }
    }
  }
  let out = StringBuilder()
  let lg = @generate.expand_tokens(pool, vars, seps) catch {
    e => {
      out.write_string("ERR \{esc(e.to_string())}\n")
      return out.to_string()
    }
  }
  for v in lg.variables {
    out.write_string(
      "VAR \{pool.resolve(v.name)} \{kind_name(v.kind)} \{v.implicit_precedence} \{v.start_state}\n",
    )
  }
  for i, s in lg.nfa.states {
    match s {
      Advance(chars~, state_id~, is_sep~, precedence~) => {
        let r = chars
          .raw_ranges()
          .map(r => "\{hex(r.start)}-\{hex(r.end)}")
          .join(",")
        out.write_string("\{i} V [\{r}] \{state_id} \{is_sep} \{precedence}\n")
      }
      Split(a, b) => out.write_string("\{i} S \{a} \{b}\n")
      Accept(variable_index~, precedence~) =>
        out.write_string("\{i} A \{variable_index} \{precedence}\n")
    }
  }
  out.to_string()
}

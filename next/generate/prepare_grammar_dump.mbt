// Development-only canonical dump of a `PreparedGrammar` for the differential
// harness (`tools/next/diff_prepare_grammar.sh`). The format matches the dump
// added to a scratch copy of the upstream crate; lexical `start_state` and the
// NFA are excluded.

///|
fn dump_esc(s : String) -> String {
  let sb = StringBuilder()
  sb.write_char('"')
  for c in s {
    match c {
      '\\' => sb.write_string("\\\\")
      '"' => sb.write_string("\\\"")
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
fn dump_sym(s : Symbol) -> String {
  match s.kind {
    Terminal => "T\{s.index}"
    NonTerminal => "N\{s.index}"
    External => "E\{s.index}"
    End => "End"
    EndOfNonTerminalExtra => "EndNTE"
  }
}

///|
fn dump_syms(symbols : Array[Symbol]) -> String {
  symbols.map(dump_sym).join(" ")
}

///|
fn dump_kind(k : VariableType) -> String {
  match k {
    Hidden => "Hidden"
    Auxiliary => "Auxiliary"
    Anonymous => "Anonymous"
    Named => "Named"
  }
}

///|
fn dump_prec(p : Precedence, pool : StrPool) -> String {
  match p {
    NoPrecedence => "-"
    Integer(n) => "I\{n}"
    Name(s) => "N\{dump_esc(pool.resolve(s))}"
  }
}

///|
fn dump_assoc(a : Associativity?) -> String {
  match a {
    None => "-"
    Some(Left) => "L"
    Some(Right) => "R"
  }
}

///|
fn dump_alias(a : Alias?, pool : StrPool) -> String {
  match a {
    None => "-"
    Some(a) =>
      "\{dump_esc(pool.resolve(a.value))}/\{if a.is_named { "n" } else { "a" }}"
  }
}

///|
fn dump_opt_str(s : StrId?, pool : StrPool) -> String {
  match s {
    None => "-"
    Some(s) => dump_esc(pool.resolve(s))
  }
}

///|
/// The canonical dump of everything `prepare_grammar` produces except the NFA.
pub fn dump_prepared_grammar(g : PreparedGrammar) -> String {
  let pool = g.str_pool
  let sg = g.syntax_grammar
  let o = StringBuilder()
  o.write_string("variables:\n")
  for i, v in sg.variables {
    o.write_string(
      "  \{i} \{dump_esc(pool.resolve(v.name))} \{dump_kind(v.kind)}\n",
    )
  }
  o.write_string("productions:\n")
  for i, range in sg.var_prods {
    o.write_string("  var \{i} \{range.0} \{range.1}\n")
  }
  for id, p in sg.productions {
    let steps = sg.steps[p.steps_start:p.steps_start + p.steps_len]
      .iter()
      .map(s => {
        let r = s.reserved
        "\{dump_sym(s.symbol)} p=\{dump_prec(s.precedence, pool)} a=\{dump_assoc(s.associativity)} al=\{dump_alias(s.alias, pool)} f=\{dump_opt_str(s.field, pool)} r=\{r}"
      })
      .to_array()
      .join("; ")
    o.write_string(
      "  prod \{id} dyn=\{p.dynamic_precedence} eof=\{p.requires_eof_lookahead} [\{steps}]\n",
    )
  }
  o.write_string("extras: \{dump_syms(sg.extra_symbols)}\n")
  o.write_string("conflicts:\n")
  for c in sg.expected_conflicts {
    o.write_string("  \{dump_syms(c)}\n")
  }
  o.write_string("externals:\n")
  for i, e in sg.external_tokens {
    let internal = match e.corresponding_internal_token {
      Some(s) => dump_sym(s)
      None => "-"
    }
    o.write_string(
      "  \{i} \{dump_esc(pool.resolve(e.name))} \{dump_kind(e.kind)} \{internal}\n",
    )
  }
  o.write_string("supertypes: \{dump_syms(sg.supertype_symbols)}\n")
  o.write_string("inline: \{dump_syms(sg.variables_to_inline)}\n")
  let word = match sg.word_token {
    Some(s) => dump_sym(s)
    None => "-"
  }
  o.write_string("word: \{word}\n")
  o.write_string("precedences:\n")
  for list in sg.precedence_orderings {
    let entries = list
      .map(e => {
        match e {
          Name(s) => "N\{dump_esc(pool.resolve(s))}"
          Symbol(s) => "S\{dump_esc(pool.resolve(s))}"
        }
      })
      .join(" ")
    o.write_string("  \{entries}\n")
  }
  o.write_string("reserved_sets:\n")
  for i, set in sg.reserved_word_sets {
    o.write_string("  \{i}: \{dump_syms(set.iter())}\n")
  }
  o.write_string("lexical:\n")
  for i, v in g.lexical_grammar.variables {
    o.write_string(
      "  \{i} \{dump_esc(pool.resolve(v.name))} \{dump_kind(v.kind)} \{v.implicit_precedence}\n",
    )
  }
  o.write_string("default_aliases:\n")
  for s, a in g.default_aliases {
    o.write_string("  \{dump_sym(s)} \{dump_alias(Some(a), pool)}\n")
  }
  o.write_string("inlines:\n")
  let keys = g.inlines.map.keys().to_array()
  keys.sort()
  for k in keys {
    let ids = g.inlines.map[k].map(id => id.to_string()).join(" ")
    o.write_string("  \{k.0} \{k.1}: \{ids}\n")
  }
  o.write_string("fully_inlined:\n")
  let keys = g.inlines.fully_inlined.keys().to_array()
  keys.sort()
  for k in keys {
    let ids = g.inlines
      .fully_inlined_prod_ids(k)
      .unwrap()
      .iter()
      .map(id => id.to_string())
      .to_array()
      .join(" ")
    o.write_string("  \{k}: \{ids}\n")
  }
  o.write_string("strings:\n")
  for i in 0..<pool.strings.length() {
    o.write_string("  \{i + 1} \{dump_esc(pool.strings[i])}\n")
  }
  o.to_string()
}

///|
/// `parse_grammar` then `prepare_grammar`, dumping the diagnostics and either
/// the error text or the prepared grammar.
pub fn dump_grammar_json(json : String) -> String {
  let diagnostics = []
  let o = StringBuilder()
  let result : Result[PreparedGrammar, String] = try {
    let g = parse_grammar(json, diagnostics)
    prepare_grammar(g, diagnostics)
  } catch {
    e => Err(e.to_string())
  } noraise {
    g => Ok(g)
  }
  o.write_string("diagnostics:\n")
  for d in diagnostics {
    o.write_string("  \{dump_esc(d.to_string())}\n")
  }
  match result {
    Err(e) => o.write_string("error: \{dump_esc(e)}\n")
    Ok(g) => o.write_string(dump_prepared_grammar(g))
  }
  o.to_string()
}

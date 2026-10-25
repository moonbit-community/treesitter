// Canonical text form of `Tables`, identical to the upstream harness's
// `dump_tables` (`_build/tsgen/src/harness.rs`).

///|
fn sym_str(s : @generate.Symbol) -> String {
  match s.kind {
    External => "x\{s.index}"
    End => "end"
    EndOfNonTerminalExtra => "eone"
    Terminal => "t\{s.index}"
    NonTerminal => "n\{s.index}"
  }
}

///|
fn ts_str(t : @generate.TokenSet) -> String {
  t.iter().map(sym_str).join(",")
}

///|
fn action_str(a : @generate.ParseAction) -> String {
  match a {
    Accept => "accept"
    Shift(state~, is_repetition~) =>
      "shift \{state}\{if is_repetition { " rep" } else { "" }}"
    ShiftExtra => "shift_extra"
    Recover => "recover"
    Reduce(symbol~, child_count~, dynamic_precedence~, production_id~) =>
      "reduce \{sym_str(symbol)} \{child_count} \{dynamic_precedence} \{production_id}"
  }
}

///|
fn cs_str(c : @generate.CharacterSet) -> String {
  c.raw_ranges().map(r => "\{r.start}-\{r.end}").join(",")
}

///|
fn bool_digit(b : Bool) -> Int32 {
  if b {
    1
  } else {
    0
  }
}

///|
fn lex_table_str(out : StringBuilder, t : @generate.LexTable) -> Unit {
  for i, s in t.states {
    let accept = match s.accept_action {
      Some(a) => sym_str(a)
      None => "-"
    }
    let eof = match s.eof_action {
      Some(a) => "\{a.state}/\{bool_digit(a.in_main_token)}"
      None => "-"
    }
    out.write_string(" \{i} accept=\{accept} eof=\{eof}\n")
    for advance in s.advance_actions {
      let (chars, a) = advance
      out.write_string(
        "  [\{cs_str(chars)}] -> \{a.state} \{bool_digit(a.in_main_token)}\n",
      )
    }
  }
}

///|
pub fn dump_tables(
  tables : @generate.Tables,
  pool : @generate.StrPool,
) -> String {
  let out = StringBuilder()
  let pt = tables.parse_table
  out.write_string("symbols: \{pt.symbols.map(sym_str).join(" ")}\n")
  out.write_string(
    "max_aliased_production_length: \{pt.max_aliased_production_length}\n",
  )
  out.write_string("production_infos:\n")
  for i, info in pt.production_infos {
    let aliases = info.alias_sequence
      .map(a => {
        match a {
          Some(a) => "\{pool.resolve(a.value)}/\{bool_digit(a.is_named)}"
          None => "_"
        }
      })
      .join(",")
    let fields = info.field_map
      .iter()
      .map(entry => {
        let (k, locs) = entry
        let locs = locs
          .map(l => "\{l.index}\{if l.inherited { "i" } else { "" }}")
          .join("/")
        "\{k.raw()}:\{locs}"
      })
      .join(",")
    out.write_string(" \{i}: aliases=[\{aliases}] fields={\{fields}}\n")
  }
  out.write_string("external_lex_states:\n")
  for i, t in pt.external_lex_states {
    out.write_string(" \{i}: \{ts_str(t)}\n")
  }
  out.write_string("states: \{pt.states.length()}\n")
  for i, s in pt.states {
    out.write_string(
      " \{i} id=\{s.id} lex=\{s.lex_state_id} ext=\{s.external_lex_state_id} core=\{s.core_id} eofgated=\{bool_digit(s.has_eof_gated_reduce)} reserved=\{ts_str(s.reserved_words)}\n",
    )
    for entry in s.terminal_entries.items() {
      let (symbol, id) = entry
      let actions = pt.action_lists.get_index(id.index)
      out.write_string(
        "  t \{sym_str(symbol)} \{id.index} \{if id.reusable { "r" } else { "-" }} : \{actions.map(action_str).join("; ")}\n",
      )
    }
    for entry in s.nonterminal_entries.items() {
      let (symbol, action) = entry
      let a = match action {
        Goto(n) => "goto \{n}"
        ShiftExtra => "extra"
      }
      out.write_string("  n \{sym_str(symbol)} \{a}\n")
    }
  }
  out.write_string("action_lists: \{pt.action_lists.len()}\n")
  for i in 0..<pt.action_lists.len() {
    let actions = pt.action_lists.get_index(i)
    out.write_string(" \{i}: \{actions.map(action_str).join("; ")}\n")
  }
  out.write_string("main_lex_table: \{tables.main_lex_table.states.length()}\n")
  lex_table_str(out, tables.main_lex_table)
  out.write_string(
    "keyword_lex_table: \{tables.keyword_lex_table.states.length()}\n",
  )
  lex_table_str(out, tables.keyword_lex_table)
  out.write_string(
    "large_character_sets: \{tables.large_character_sets.length()}\n",
  )
  for entry in tables.large_character_sets {
    let (s, c) = entry
    let s = match s {
      Some(s) => sym_str(s)
      None => "-"
    }
    out.write_string(" \{s} [\{cs_str(c)}]\n")
  }
  out.to_string()
}

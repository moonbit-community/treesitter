//! Differential harness: serialize `build_tables` inputs and dump its output.

use std::fmt::Write as _;

use serde_json::{Value, json};

use crate::{
    Diagnostic, OptLevel,
    build_tables::{Tables, build_tables},
    grammars::{LexicalGrammar, PrecedenceEntry, SyntaxGrammar, VariableType},
    nfa::{CharacterSet, NfaState},
    node_types::get_variable_info,
    parse_grammar::parse_grammar,
    prepare_grammar::prepare_grammar,
    rules::{Associativity, Precedence, Symbol, SymbolView, TokenSet},
    strpool::{StrId, StrPool},
    tables::{GotoAction, LexTable, ParseAction},
};

fn sym(s: Symbol) -> Value {
    match s.view() {
        SymbolView::External(i) => json!([0, u32::from(i)]),
        SymbolView::End => json!([1, 0]),
        SymbolView::EndOfNonTerminalExtra => json!([2, 0]),
        SymbolView::Terminal(i) => json!([3, u32::from(i)]),
        SymbolView::NonTerminal(i) => json!([4, u32::from(i)]),
    }
}

fn kind(k: VariableType) -> u32 {
    match k {
        VariableType::Hidden => 0,
        VariableType::Auxiliary => 1,
        VariableType::Anonymous => 2,
        VariableType::Named => 3,
    }
}

fn token_set(t: &TokenSet) -> Value {
    Value::Array(t.iter().map(sym).collect())
}

fn ranges(c: &CharacterSet) -> Value {
    let mut v = Vec::new();
    for (s, e) in c.harness_ranges() {
        v.push(json!(s));
        v.push(json!(e));
    }
    Value::Array(v)
}

pub fn serialize_inputs(
    syntax: &SyntaxGrammar,
    lexical: &LexicalGrammar,
    inlines: &crate::grammars::InlinedProductionMap,
    aliases: &crate::rules::AliasMap,
    variable_info: &[crate::node_types::VariableInfo],
    pool: &StrPool,
) -> Value {
    let strings = (1..=pool.harness_len())
        .map(|i| json!(pool.resolve(StrId::from_raw(i as u32))))
        .collect::<Vec<_>>();
    let steps = syntax
        .steps
        .iter()
        .map(|st| {
            let s = st.symbol();
            let (sk, si) = match s.view() {
                SymbolView::External(i) => (0, u32::from(i)),
                SymbolView::End => (1, 0),
                SymbolView::EndOfNonTerminalExtra => (2, 0),
                SymbolView::Terminal(i) => (3, u32::from(i)),
                SymbolView::NonTerminal(i) => (4, u32::from(i)),
            };
            let (pk, pv) = match st.precedence() {
                Precedence::None => (0, 0i64),
                Precedence::Integer(n) => (1, i64::from(n)),
                Precedence::Name(id) => (2, i64::from(id.raw())),
            };
            let assoc = match st.associativity() {
                None => 0,
                Some(Associativity::Left) => 1,
                Some(Associativity::Right) => 2,
            };
            let (alias, named) = st
                .alias()
                .map_or((0, 0), |a| (a.value.raw(), u32::from(a.is_named)));
            let field = st.field().map_or(0, |f| f.raw());
            json!([sk, si, pk, pv, assoc, alias, named, field, st.reserved])
        })
        .collect::<Vec<_>>();
    let mut inline_entries = inlines
        .map
        .iter()
        .map(|(k, v)| (k.0, k.1, v.clone()))
        .collect::<Vec<_>>();
    inline_entries.sort();
    json!({
        "strings": strings,
        "syntax": {
            "variables": syntax.variables.iter().map(|v| json!([v.name.raw(), kind(v.kind)])).collect::<Vec<_>>(),
            "extra_symbols": syntax.extra_symbols.iter().map(|s| sym(*s)).collect::<Vec<_>>(),
            "expected_conflicts": syntax.expected_conflicts.iter().map(|c| c.iter().map(|s| sym(*s)).collect::<Vec<_>>()).collect::<Vec<_>>(),
            "external_tokens": syntax.external_tokens.iter().map(|t| json!([t.name.raw(), kind(t.kind), t.corresponding_internal_token.map(sym)])).collect::<Vec<_>>(),
            "supertype_symbols": syntax.supertype_symbols.iter().map(|s| sym(*s)).collect::<Vec<_>>(),
            "variables_to_inline": syntax.variables_to_inline.iter().map(|s| sym(*s)).collect::<Vec<_>>(),
            "word_token": syntax.word_token.map(sym),
            "precedence_orderings": syntax.precedence_orderings.iter().map(|l| l.iter().map(|e| match e {
                PrecedenceEntry::Name(n) => json!([0, n.raw()]),
                PrecedenceEntry::Symbol(n) => json!([1, n.raw()]),
            }).collect::<Vec<_>>()).collect::<Vec<_>>(),
            "reserved_word_sets": syntax.reserved_word_sets.iter().map(token_set).collect::<Vec<_>>(),
            "steps": steps,
            "productions": syntax.productions.iter().map(|p| json!([p.steps_start, p.steps_len, p.dynamic_precedence, u32::from(p.requires_eof_lookahead)])).collect::<Vec<_>>(),
            "var_prods": syntax.var_prods.iter().map(|(s, e)| json!([s, e])).collect::<Vec<_>>(),
        },
        "lexical": {
            "nfa": lexical.nfa.states.iter().map(|s| match s {
                NfaState::Advance { chars, state_id, is_sep, precedence } => json!([0, ranges(chars), state_id, u32::from(*is_sep), precedence]),
                NfaState::Split(a, b) => json!([1, a, b]),
                NfaState::Accept { variable_index, precedence } => json!([2, variable_index, precedence]),
            }).collect::<Vec<_>>(),
            "variables": lexical.variables.iter().map(|v| json!([v.name.raw(), kind(v.kind), v.implicit_precedence, v.start_state])).collect::<Vec<_>>(),
        },
        "inlines": inline_entries.iter().map(|(p, s, ids)| json!([p, s, ids])).collect::<Vec<_>>(),
        "aliases": aliases.iter().map(|(s, a)| json!([sym(*s), a.value.raw(), u32::from(a.is_named)])).collect::<Vec<_>>(),
        "variable_info_fields": variable_info.iter().map(|vi| {
            let mut keys = vi.fields.keys().map(|k| k.raw()).collect::<Vec<_>>();
            keys.sort_unstable();
            keys
        }).collect::<Vec<_>>(),
    })
}

fn sym_str(s: Symbol) -> String {
    match s.view() {
        SymbolView::External(i) => format!("x{}", u32::from(i)),
        SymbolView::End => "end".to_string(),
        SymbolView::EndOfNonTerminalExtra => "eone".to_string(),
        SymbolView::Terminal(i) => format!("t{}", u32::from(i)),
        SymbolView::NonTerminal(i) => format!("n{}", u32::from(i)),
    }
}

fn ts_str(t: &TokenSet) -> String {
    t.iter().map(sym_str).collect::<Vec<_>>().join(",")
}

fn action_str(a: &ParseAction) -> String {
    match a {
        ParseAction::Accept => "accept".to_string(),
        ParseAction::Shift { state, is_repetition } => {
            format!("shift {state}{}", if *is_repetition { " rep" } else { "" })
        }
        ParseAction::ShiftExtra => "shift_extra".to_string(),
        ParseAction::Recover => "recover".to_string(),
        ParseAction::Reduce { symbol, child_count, dynamic_precedence, production_id } => {
            format!("reduce {} {child_count} {dynamic_precedence} {production_id}", sym_str(*symbol))
        }
    }
}

fn cs_str(c: &CharacterSet) -> String {
    c.harness_ranges()
        .iter()
        .map(|(s, e)| format!("{s}-{e}"))
        .collect::<Vec<_>>()
        .join(",")
}

fn lex_table_str(out: &mut String, t: &LexTable) {
    for (i, s) in t.states.iter().enumerate() {
        let accept = s.accept_action.map_or("-".to_string(), sym_str);
        let eof = s
            .eof_action
            .as_ref()
            .map_or("-".to_string(), |a| format!("{}/{}", a.state, u8::from(a.in_main_token)));
        writeln!(out, " {i} accept={accept} eof={eof}").unwrap();
        for (chars, a) in &s.advance_actions {
            writeln!(out, "  [{}] -> {} {}", cs_str(chars), a.state, u8::from(a.in_main_token)).unwrap();
        }
    }
}

pub fn dump_tables(tables: &Tables, pool: &StrPool) -> String {
    let mut out = String::new();
    let pt = &tables.parse_table;
    writeln!(out, "symbols: {}", pt.symbols.iter().map(|s| sym_str(*s)).collect::<Vec<_>>().join(" ")).unwrap();
    writeln!(out, "max_aliased_production_length: {}", pt.max_aliased_production_length).unwrap();
    writeln!(out, "production_infos:").unwrap();
    for (i, info) in pt.production_infos.iter().enumerate() {
        let aliases = info
            .alias_sequence
            .iter()
            .map(|a| a.map_or("_".to_string(), |a| format!("{}/{}", pool.resolve(a.value), u8::from(a.is_named))))
            .collect::<Vec<_>>()
            .join(",");
        let fields = info
            .field_map
            .iter()
            .map(|(k, locs)| {
                format!(
                    "{}:{}",
                    k.raw(),
                    locs.iter().map(|l| format!("{}{}", l.index, if l.inherited { "i" } else { "" })).collect::<Vec<_>>().join("/")
                )
            })
            .collect::<Vec<_>>()
            .join(",");
        writeln!(out, " {i}: aliases=[{aliases}] fields={{{fields}}}").unwrap();
    }
    writeln!(out, "external_lex_states:").unwrap();
    for (i, t) in pt.external_lex_states.iter().enumerate() {
        writeln!(out, " {i}: {}", ts_str(t)).unwrap();
    }
    writeln!(out, "states: {}", pt.states.len()).unwrap();
    for (i, s) in pt.states.iter().enumerate() {
        writeln!(
            out,
            " {i} id={} lex={} ext={} core={} eofgated={} reserved={}",
            s.id,
            s.lex_state_id,
            s.external_lex_state_id,
            s.core_id,
            u8::from(s.has_eof_gated_reduce),
            ts_str(&s.reserved_words)
        )
        .unwrap();
        for (symbol, id) in s.terminal_entries.iter() {
            let actions = pt.action_lists.harness_get_index(id.index());
            writeln!(
                out,
                "  t {} {} {} : {}",
                sym_str(*symbol),
                id.index(),
                if id.reusable() { "r" } else { "-" },
                actions.iter().map(action_str).collect::<Vec<_>>().join("; ")
            )
            .unwrap();
        }
        for (symbol, action) in s.nonterminal_entries.iter() {
            let a = match action {
                GotoAction::Goto(n) => format!("goto {n}"),
                GotoAction::ShiftExtra => "extra".to_string(),
            };
            writeln!(out, "  n {} {a}", sym_str(*symbol)).unwrap();
        }
    }
    writeln!(out, "action_lists: {}", pt.action_lists.len()).unwrap();
    for i in 0..pt.action_lists.len() {
        let actions = pt.action_lists.harness_get_index(i);
        writeln!(out, " {i}: {}", actions.iter().map(action_str).collect::<Vec<_>>().join("; ")).unwrap();
    }
    writeln!(out, "main_lex_table: {}", tables.main_lex_table.states.len()).unwrap();
    lex_table_str(&mut out, &tables.main_lex_table);
    writeln!(out, "keyword_lex_table: {}", tables.keyword_lex_table.states.len()).unwrap();
    lex_table_str(&mut out, &tables.keyword_lex_table);
    writeln!(out, "large_character_sets: {}", tables.large_character_sets.len()).unwrap();
    for (s, c) in &tables.large_character_sets {
        writeln!(out, " {} [{}]", s.map_or("-".to_string(), sym_str), cs_str(c)).unwrap();
    }
    out
}

/// Returns (inputs json or None, output text, build_tables micros). With a
/// `report_symbol_name`, upstream logs its state report at info level.
pub fn run(grammar_json: &str, report_symbol_name: Option<&str>) -> (Option<String>, String, u128) {
    let mut diagnostics = Vec::new();
    let input_grammar = match parse_grammar(grammar_json, &mut diagnostics) {
        Ok(g) => g,
        Err(e) => return (None, format!("parse error: {e}\n"), 0),
    };
    let prepared = match prepare_grammar(input_grammar, &mut diagnostics) {
        Ok(p) => p,
        Err(e) => return (None, format!("prepare error: {e}\n"), 0),
    };
    let crate::prepare_grammar::PreparedGrammar {
        syntax_grammar,
        lexical_grammar,
        mut inlines,
        default_aliases,
        str_pool,
    } = prepared;
    let variable_info = match get_variable_info(
        &syntax_grammar,
        &lexical_grammar,
        &default_aliases,
        &inlines,
        &str_pool,
    ) {
        Ok(v) => v,
        Err(e) => return (None, format!("variable info error: {e}\n"), 0),
    };
    inlines.discard_fully_inlined();
    let inputs = serialize_inputs(
        &syntax_grammar,
        &lexical_grammar,
        &inlines,
        &default_aliases,
        &variable_info,
        &str_pool,
    );
    let mut diagnostics: Vec<Diagnostic> = Vec::new();
    let start = std::time::Instant::now();
    let result = build_tables(
        &syntax_grammar,
        &lexical_grammar,
        &default_aliases,
        &variable_info,
        &inlines,
        &str_pool,
        report_symbol_name,
        OptLevel::default(),
        &mut diagnostics,
    );
    let micros = start.elapsed().as_micros();
    let mut out = String::new();
    match result {
        Ok(tables) => out.push_str(&dump_tables(&tables, &str_pool)),
        Err(e) => writeln!(out, "error: {e}").unwrap(),
    }
    for d in &diagnostics {
        writeln!(out, "diagnostic: {d}").unwrap();
    }
    (Some(inputs.to_string()), out, micros)
}

pub mod fixtures {
    use crate::{grammars::{LexicalGrammar, VariableType}, prepare_grammar::{LexicalToken, expand_tokens::expand_tokens}, rules::{Precedence, RulePool}};

    fn moon_lit(pool: &RulePool, grammar: &LexicalGrammar) -> String {
        let mut out = String::new();
        out.push_str("  let names = [");
        for v in &grammar.variables {
            out.push_str(&format!("{:?}, ", pool.resolve(v.name)));
        }
        out.push_str("]\n  let states : Array[NfaState] = [\n");
        for s in &grammar.nfa.states {
            match s {
                crate::nfa::NfaState::Advance { chars, state_id, is_sep, precedence } => {
                    let r = chars.harness_ranges().iter().map(|(a, b)| format!("({a}, {b})")).collect::<Vec<_>>().join(", ");
                    out.push_str(&format!("    Advance(chars=char_set([{r}]), state_id={state_id}, is_sep={is_sep}, precedence={precedence}),\n"));
                }
                crate::nfa::NfaState::Split(a, b) => out.push_str(&format!("    Split({a}, {b}),\n")),
                crate::nfa::NfaState::Accept { variable_index, precedence } => out.push_str(&format!("    Accept(variable_index={variable_index}, precedence={precedence}),\n")),
            }
        }
        out.push_str("  ]\n  let variables = [\n");
        for (i, v) in grammar.variables.iter().enumerate() {
            out.push_str(&format!("    ({i}, {}, {}),\n", v.implicit_precedence, v.start_state));
        }
        out.push_str("  ]\n");
        out
    }

    pub fn dump_for_moonbit() {
        // test_starting_characters
        let mut pool = RulePool::default();
        let empty = pool.intern("");
        let t0 = { let v = pool.intern("[a-f]1|0x\\d"); pool.pattern(v, empty) };
        let t1 = { let v = pool.intern("d*ef"); pool.pattern(v, empty) };
        let vars = vec![
            LexicalToken { name: pool.intern("token_0"), kind: VariableType::Named, root: t0 },
            LexicalToken { name: pool.intern("token_1"), kind: VariableType::Named, root: t1 },
        ];
        let grammar = expand_tokens(&mut pool, &vars, &[]).unwrap();
        println!("=== starting_characters\n{}", moon_lit(&pool, &grammar));

        let mut pool = RulePool::default();
        let empty = pool.intern("");
        let in_tok = { let s = pool.intern("in"); pool.string(s) };
        let ident = { let v = pool.intern("\\w+"); pool.pattern(v, empty) };
        let instanceof = { let s = pool.intern("instanceof"); pool.string(s) };
        let vars = vec![
            LexicalToken { name: pool.intern("in"), kind: VariableType::Named, root: in_tok },
            LexicalToken { name: pool.intern("identifier"), kind: VariableType::Named, root: ident },
            LexicalToken { name: pool.intern("instanceof"), kind: VariableType::Named, root: instanceof },
        ];
        let grammar = expand_tokens(&mut pool, &vars, &[]).unwrap();
        println!("=== token_conflicts\n{}", moon_lit(&pool, &grammar));

        let mut pool = RulePool::default();
        let empty = pool.intern("");
        let sep = { let v = pool.intern("\\s"); pool.pattern(v, empty) };
        let x = { let s = pool.intern("x"); pool.string(s) };
        let newline = { let s = pool.intern("\n"); pool.string(s) };
        let vars = vec![
            LexicalToken { name: pool.intern("x"), kind: VariableType::Named, root: x },
            LexicalToken { name: pool.intern("newline"), kind: VariableType::Named, root: newline },
        ];
        let grammar = expand_tokens(&mut pool, &vars, &[sep]).unwrap();
        println!("=== separators\n{}", moon_lit(&pool, &grammar));

        let mut pool = RulePool::default();
        let empty = pool.intern("");
        let sep = { let v = pool.intern("\\s"); pool.pattern(v, empty) };
        let x = { let s = pool.intern("x"); pool.string(s) };
        let anything = { let v = pool.intern(".*"); let pat = pool.pattern(v, empty); pool.prec(Precedence::Integer(-1), pat) };
        let vars = vec![
            LexicalToken { name: pool.intern("x"), kind: VariableType::Named, root: x },
            LexicalToken { name: pool.intern("anything"), kind: VariableType::Named, root: anything },
        ];
        let grammar = expand_tokens(&mut pool, &vars, &[sep]).unwrap();
        println!("=== open_ended\n{}", moon_lit(&pool, &grammar));
    }

}

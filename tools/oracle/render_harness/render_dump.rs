// Differential-harness only: serialize the inputs of `render_c_code` to JSON.
use std::collections::BTreeMap;

use serde_json::{Value, json};

use crate::{
    build_tables::Tables,
    grammars::{LexicalGrammar, SyntaxGrammar, VariableType},
    nfa::CharacterSet,
    node_types::ChildType,
    rules::{Alias, AliasMap, Symbol, SymbolType, TokenSet},
    strpool::{StrId, StrPool},
    tables::{GotoAction, LexTable, ParseAction},
};

fn sym(s: Symbol) -> Value {
    let k = match s.kind() {
        SymbolType::External => 0,
        SymbolType::End => 1,
        SymbolType::EndOfNonTerminalExtra => 2,
        SymbolType::Terminal => 3,
        SymbolType::NonTerminal => 4,
    };
    let index: u32 = match s.view() {
        crate::rules::SymbolView::External(i) => usize::from(i) as u32,
        crate::rules::SymbolView::Terminal(i) => usize::from(i) as u32,
        crate::rules::SymbolView::NonTerminal(i) => usize::from(i) as u32,
        _ => 0,
    };
    json!([k, index])
}

fn osym(s: Option<Symbol>) -> Value {
    s.map_or(Value::Null, sym)
}

fn kind(k: VariableType) -> Value {
    json!(match k {
        VariableType::Hidden => 0,
        VariableType::Auxiliary => 1,
        VariableType::Anonymous => 2,
        VariableType::Named => 3,
    })
}

fn alias(a: Alias) -> Value {
    json!([a.value.raw(), a.is_named])
}

fn token_set(t: &TokenSet) -> Value {
    Value::Array(t.iter().map(sym).collect())
}

fn chars(c: &CharacterSet) -> Value {
    Value::Array(c.dump_raw_ranges().into_iter().map(|(s, e)| json!([s, e])).collect())
}

fn lex_table(t: &LexTable) -> Value {
    Value::Array(
        t.states
            .iter()
            .map(|s| {
                json!({
                    "accept": osym(s.accept_action),
                    "eof": s.eof_action.as_ref().map_or(Value::Null, |a| json!([a.state, a.in_main_token])),
                    "adv": Value::Array(s.advance_actions.iter().map(|(c, a)| json!([chars(c), a.state, a.in_main_token])).collect()),
                })
            })
            .collect(),
    )
}

fn action(a: &ParseAction) -> Value {
    match *a {
        ParseAction::Accept => json!(["Accept"]),
        ParseAction::ShiftExtra => json!(["ShiftExtra"]),
        ParseAction::Recover => json!(["Recover"]),
        ParseAction::Shift {
            state,
            is_repetition,
        } => json!(["Shift", state, is_repetition]),
        ParseAction::Reduce {
            symbol,
            child_count,
            dynamic_precedence,
            production_id,
        } => json!([
            "Reduce",
            sym(symbol),
            child_count,
            dynamic_precedence,
            production_id
        ]),
    }
}

#[allow(clippy::too_many_arguments)]
pub fn dump(
    name: StrId,
    tables: &Tables,
    syntax_grammar: &SyntaxGrammar,
    lexical_grammar: &LexicalGrammar,
    default_aliases: &AliasMap,
    str_pool: &StrPool,
    abi_version: usize,
    semantic_version: Option<(u8, u8, u8)>,
    supertype_symbol_map: &BTreeMap<Symbol, Vec<ChildType>>,
) -> String {
    let pt = &tables.parse_table;
    let states: Vec<Value> = pt
        .states
        .iter()
        .map(|s| {
            json!({
                "id": s.id,
                "t": Value::Array(s.terminal_entries.iter().map(|(k, v)| json!([sym(*k), v.index(), v.reusable()])).collect()),
                "n": Value::Array(s.nonterminal_entries.iter().map(|(k, v)| json!([sym(*k), match v { GotoAction::Goto(g) => *g as i64, GotoAction::ShiftExtra => -1 }])).collect()),
                "reserved": token_set(&s.reserved_words),
                "lex": s.lex_state_id,
                "ext": s.external_lex_state_id,
                "core": s.core_id,
                "eofg": s.has_eof_gated_reduce,
            })
        })
        .collect();
    let action_lists: Vec<Value> = (0..pt.action_lists.len())
        .map(|i| {
            Value::Array(
                pt.action_lists
                    .get(crate::tables::ActionListId::new(i as u32, false))
                    .iter()
                    .map(action)
                    .collect(),
            )
        })
        .collect();
    let production_infos: Vec<Value> = pt
        .production_infos
        .iter()
        .map(|p| {
            json!({
                "alias_sequence": Value::Array(p.alias_sequence.iter().map(|a| a.map_or(Value::Null, alias)).collect()),
                "field_map": Value::Array(p.field_map.iter().map(|(k, v)| json!([k.raw(), Value::Array(v.iter().map(|l| json!([l.index, l.inherited])).collect())])).collect()),
            })
        })
        .collect();
    let out = json!({
        "name": name.raw(),
        "abi_version": abi_version,
        "semantic_version": semantic_version.map_or(Value::Null, |(a, b, c)| json!([a, b, c])),
        "strings": str_pool.dump_strings(),
        "syntax": {
            "variables": Value::Array(syntax_grammar.variables.iter().map(|v| json!([v.name.raw(), kind(v.kind)])).collect()),
            "extra_symbols": Value::Array(syntax_grammar.extra_symbols.iter().copied().map(sym).collect()),
            "external_tokens": Value::Array(syntax_grammar.external_tokens.iter().map(|t| json!([t.name.raw(), kind(t.kind), osym(t.corresponding_internal_token)])).collect()),
            "supertype_symbols": Value::Array(syntax_grammar.supertype_symbols.iter().copied().map(sym).collect()),
            "word_token": osym(syntax_grammar.word_token),
            "steps": Value::Array(syntax_grammar.steps.iter().map(|s| json!([sym(s.symbol()), s.alias().map_or(Value::Null, alias)])).collect()),
        },
        "lexical": {
            "variables": Value::Array(lexical_grammar.variables.iter().map(|v| json!([v.name.raw(), kind(v.kind), v.implicit_precedence, v.start_state])).collect()),
        },
        "default_aliases": Value::Array(default_aliases.iter().map(|(k, v)| json!([sym(*k), alias(*v)])).collect()),
        "supertype_symbol_map": Value::Array(supertype_symbol_map.iter().map(|(k, v)| json!([sym(*k), Value::Array(v.iter().map(|c| match c { ChildType::Normal(s) => json!(["N", sym(*s)]), ChildType::Aliased(a) => json!(["A", alias(*a)]) }).collect())])).collect()),
        "tables": {
            "parse_table": {
                "states": states,
                "action_lists": action_lists,
                "symbols": Value::Array(pt.symbols.iter().copied().map(sym).collect()),
                "production_infos": production_infos,
                "max_aliased_production_length": pt.max_aliased_production_length,
                "external_lex_states": Value::Array(pt.external_lex_states.iter().map(token_set).collect()),
            },
            "main_lex_table": lex_table(&tables.main_lex_table),
            "keyword_lex_table": lex_table(&tables.keyword_lex_table),
            "large_character_sets": Value::Array(tables.large_character_sets.iter().map(|(s, c)| json!([osym(*s), chars(c)])).collect()),
        },
    });
    serde_json::to_string(&out).unwrap()
}

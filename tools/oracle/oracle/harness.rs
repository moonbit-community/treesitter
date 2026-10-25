//! Differential-oracle dumps for the MoonBit port (scratch only).
use serde_json::{Value, json};

use crate::{
    grammars::{InlinedProductionMap, LexicalGrammar, SyntaxGrammar},
    node_types::{self, ChildType, VariableInfo},
    parse_grammar::parse_grammar,
    prepare_grammar::{PreparedGrammar, prepare_grammar},
    rules::{AliasMap, Symbol, SymbolView},
    strpool::StrPool,
};

fn sym(s: Symbol) -> Value {
    let idx = match s.view() {
        SymbolView::External(i) => usize::from(i),
        SymbolView::Terminal(i) => usize::from(i),
        SymbolView::NonTerminal(i) => usize::from(i),
        _ => 0,
    };
    json!([format!("{:?}", s.kind()), idx])
}

fn child_type(t: &ChildType) -> Value {
    match t {
        ChildType::Normal(s) => json!(["Normal", sym(*s)]),
        ChildType::Aliased(a) => json!(["Aliased", a.value.raw(), a.is_named]),
    }
}

pub fn dump_inputs(
    syntax_grammar: &SyntaxGrammar,
    lexical_grammar: &LexicalGrammar,
    default_aliases: &AliasMap,
    inlines: &InlinedProductionMap,
    str_pool: &StrPool,
) -> Value {
    let mut fully: Vec<_> = inlines
        .fully_inlined
        .iter()
        .map(|(k, r)| (*k, r.start, r.end))
        .collect();
    fully.sort_unstable();
    json!({
        "strings": str_pool.all_strings(),
        "variables": syntax_grammar.variables.iter().map(|v| json!([v.name.raw(), format!("{:?}", v.kind)])).collect::<Vec<_>>(),
        "extra_symbols": syntax_grammar.extra_symbols.iter().map(|s| sym(*s)).collect::<Vec<_>>(),
        "external_tokens": syntax_grammar.external_tokens.iter().map(|t| json!([t.name.raw(), format!("{:?}", t.kind), t.corresponding_internal_token.map(sym)])).collect::<Vec<_>>(),
        "supertype_symbols": syntax_grammar.supertype_symbols.iter().map(|s| sym(*s)).collect::<Vec<_>>(),
        "variables_to_inline": syntax_grammar.variables_to_inline.iter().map(|s| sym(*s)).collect::<Vec<_>>(),
        "steps": syntax_grammar.steps.iter().map(|s| json!([
            sym(s.symbol()),
            s.alias().map(|a| json!([a.value.raw(), a.is_named])),
            s.field().map(|f| f.raw()),
        ])).collect::<Vec<_>>(),
        "productions": syntax_grammar.productions.iter().map(|p| json!([p.steps_start, p.steps_len, p.dynamic_precedence, p.requires_eof_lookahead])).collect::<Vec<_>>(),
        "var_prods": syntax_grammar.var_prods.iter().map(|(a, b)| json!([a, b])).collect::<Vec<_>>(),
        "lexical_variables": lexical_grammar.variables.iter().map(|v| json!([v.name.raw(), format!("{:?}", v.kind)])).collect::<Vec<_>>(),
        "default_aliases": default_aliases.iter().map(|(s, a)| json!([sym(*s), a.value.raw(), a.is_named])).collect::<Vec<_>>(),
        "fully_inlined": fully.iter().map(|(k, s, e)| json!([k, s, e])).collect::<Vec<_>>(),
        "fully_inlined_ids": inlines.fully_inlined_ids,
    })
}

fn field_info(f: &node_types::FieldInfo) -> Value {
    json!({
        "quantity": [f.quantity.exists(), f.quantity.required(), f.quantity.multiple()],
        "types": f.types.iter().map(child_type).collect::<Vec<_>>(),
    })
}

pub fn dump_variable_info(info: &[VariableInfo]) -> Value {
    Value::Array(
        info.iter()
            .map(|v| {
                let mut fields: Vec<_> = v.fields.iter().collect();
                fields.sort_unstable_by_key(|(k, _)| **k);
                json!({
                    "fields": fields.iter().map(|(k, f)| json!([k.raw(), field_info(f)])).collect::<Vec<_>>(),
                    "children": field_info(&v.children),
                    "children_without_fields": field_info(&v.children_without_fields),
                    "has_multi_step_production": v.has_multi_step_production,
                })
            })
            .collect(),
    )
}

/// Returns `(inputs, expected)`; `inputs` is `None` when the grammar cannot be prepared.
pub fn dump_node_types(grammar_json: &str) -> (Option<String>, String) {
    let mut diagnostics = Vec::new();
    let input = match parse_grammar(grammar_json, &mut diagnostics) {
        Ok(g) => g,
        Err(e) => return (None, json!({"parse_error": e.to_string()}).to_string()),
    };
    let PreparedGrammar {
        syntax_grammar,
        lexical_grammar,
        inlines,
        default_aliases,
        str_pool,
    } = match prepare_grammar(input, &mut diagnostics) {
        Ok(p) => p,
        Err(e) => return (None, json!({"prepare_error": e.to_string()}).to_string()),
    };
    dump_prepared(&syntax_grammar, &lexical_grammar, &default_aliases, &inlines, &str_pool)
}

pub fn dump_prepared(
    syntax_grammar: &SyntaxGrammar,
    lexical_grammar: &LexicalGrammar,
    default_aliases: &AliasMap,
    inlines: &InlinedProductionMap,
    str_pool: &StrPool,
) -> (Option<String>, String) {
    let inputs = dump_inputs(syntax_grammar, lexical_grammar, default_aliases, inlines, str_pool)
        .to_string();
    let expected = match node_types::get_variable_info(
        syntax_grammar,
        lexical_grammar,
        default_aliases,
        inlines,
        str_pool,
    ) {
        Err(e) => json!({"variable_info_error": e.to_string()}),
        Ok(info) => {
            let map = node_types::get_supertype_symbol_map(
                syntax_grammar,
                default_aliases,
                &info,
                inlines,
            );
            let node_types = match node_types::generate_node_types_json(
                syntax_grammar,
                lexical_grammar,
                default_aliases,
                &info,
                inlines,
                str_pool,
            ) {
                Ok(text) => json!({"ok": text}),
                Err(e) => json!({"error": e.to_string()}),
            };
            json!({
                "variable_info": dump_variable_info(&info),
                "supertype_symbol_map": map.iter().map(|(s, ts)| json!([sym(*s), ts.iter().map(child_type).collect::<Vec<_>>()])).collect::<Vec<_>>(),
                "node_types": node_types,
            })
        }
    };
    (Some(inputs), expected.to_string())
}

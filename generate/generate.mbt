// Port of the generation entry points in tree-sitter crates/generate/src/generate.rs.

///|
/// `LANGUAGE_VERSION`: must match `TREE_SITTER_LANGUAGE_VERSION`.
pub let language_version : Int = @language.language_version

///|
/// The products of preparing a grammar (`JSONOutput`).
priv struct JSONOutput {
  node_types_json : String
  syntax_grammar : SyntaxGrammar
  lexical_grammar : LexicalGrammar
  inlines : InlinedProductionMap
  simple_aliases : AliasMap
  variable_info : Array[VariableInfo]
  str_pool : StrPool
}

///|
/// The products of generating a parser: the `parser.c` text, the
/// `node-types.json` text and the portable language tables.
pub(all) struct GeneratedParser {
  c_code : String
  node_types_json : String
  language : @language.Language
}

///|
/// `generate_parser_for_grammar`: generate from `grammar.json` text,
/// returning the grammar name and the `parser.c` text.
pub fn generate_parser_for_grammar(
  grammar_json : String,
  semantic_version : (Int, Int, Int)?,
  optimizations : OptLevel,
  diagnostics : Array[Diagnostic],
) -> (String, String) raise {
  let input_grammar = parse_grammar(grammar_json, diagnostics)
  let name = input_grammar.pool.resolve(input_grammar.name)
  let parser = generate_parser_for_grammar_with_opts(
    input_grammar,
    language_version,
    semantic_version,
    None,
    optimizations,
    diagnostics,
  )
  (name, parser.c_code)
}

///|
/// `generate_node_types_from_grammar`.
fn generate_node_types_from_grammar(
  input_grammar : InputGrammar,
  diagnostics : Array[Diagnostic],
) -> JSONOutput raise {
  let prepared = prepare_grammar(input_grammar, diagnostics)
  let variable_info = get_variable_info(
    prepared.syntax_grammar,
    prepared.lexical_grammar,
    prepared.default_aliases,
    prepared.inlines,
    prepared.str_pool,
  )
  let node_types_json = generate_node_types_json(
    prepared.syntax_grammar,
    prepared.lexical_grammar,
    prepared.default_aliases,
    variable_info,
    prepared.inlines,
    prepared.str_pool,
  )
  {
    node_types_json,
    syntax_grammar: prepared.syntax_grammar,
    lexical_grammar: prepared.lexical_grammar,
    inlines: prepared.inlines,
    simple_aliases: prepared.default_aliases,
    variable_info,
    str_pool: prepared.str_pool,
  }
}

///|
/// `node-types.json` text only, for a grammar in `grammar.json` form (the
/// `generate --no-parser` path).
pub fn generate_node_types_for_grammar(
  grammar_json : String,
  diagnostics : Array[Diagnostic],
) -> String raise {
  let input_grammar = parse_grammar(grammar_json, diagnostics)
  generate_node_types_from_grammar(input_grammar, diagnostics).node_types_json
}

///|
/// `generate_node_types_from_grammar(input_grammar, diagnostics)?
/// .node_types_json`: the `generate --no-parser` path of
/// `generate_parser_in_directory`, for an already parsed grammar. Preparation
/// diagnostics go to `diagnostics`.
pub fn generate_node_types_for_input_grammar(
  input_grammar : InputGrammar,
  diagnostics : Array[Diagnostic],
) -> String raise {
  generate_node_types_from_grammar(input_grammar, diagnostics).node_types_json
}

///|
/// `generate_parser_for_grammar_with_opts`, also producing the portable
/// `Language` from the same tables as the C code.
pub fn generate_parser_for_grammar_with_opts(
  input_grammar : InputGrammar,
  abi_version : Int,
  semantic_version : (Int, Int, Int)?,
  report_symbol_name : String?,
  optimizations : OptLevel,
  diagnostics : Array[Diagnostic],
) -> GeneratedParser raise {
  let grammar_name = input_grammar.name
  let output = generate_node_types_from_grammar(input_grammar, diagnostics)
  let supertype_symbol_map = get_supertype_symbol_map(
    output.syntax_grammar,
    output.simple_aliases,
    output.variable_info,
    output.inlines,
  )
  output.inlines.discard_fully_inlined()
  let tables = build_tables(
    output.syntax_grammar,
    output.lexical_grammar,
    output.simple_aliases,
    output.variable_info,
    output.inlines,
    output.str_pool,
    report_symbol_name,
    optimizations,
    diagnostics,
  )
  let c_code = render_c_code(
    grammar_name,
    tables,
    output.syntax_grammar,
    output.lexical_grammar,
    output.simple_aliases,
    output.str_pool,
    abi_version,
    semantic_version,
    supertype_symbol_map,
  )
  let language = render_language(
    grammar_name,
    tables,
    output.syntax_grammar,
    output.lexical_grammar,
    output.simple_aliases,
    output.str_pool,
    abi_version,
    semantic_version,
    supertype_symbol_map,
  )
  { c_code, node_types_json: output.node_types_json, language }
}

///|
/// Generate everything from `grammar.json` text at the current ABI.
pub fn generate_from_grammar_json(
  grammar_json : String,
  semantic_version? : (Int, Int, Int),
  abi_version? : Int = language_version,
  report_symbol_name? : String,
  optimizations? : OptLevel = default_opt_level,
  diagnostics? : Array[Diagnostic] = [],
) -> GeneratedParser raise {
  let input_grammar = parse_grammar(grammar_json, diagnostics)
  generate_parser_for_grammar_with_opts(
    input_grammar, abi_version, semantic_version, report_symbol_name, optimizations,
    diagnostics,
  )
}

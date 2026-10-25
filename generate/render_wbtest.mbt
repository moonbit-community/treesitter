///|
test "sanitize_identifier" {
  let pool = StrPool::new()
  let generator = Generator::new(
    pool.intern("x"),
    {
      parse_table: ParseTable::new(),
      main_lex_table: LexTable::new(),
      keyword_lex_table: LexTable::new(),
      large_character_sets: [],
    },
    tiny_syntax_grammar([], []),
    LexicalGrammar::new(),
    @sorted_map.SortedMap([]),
    pool,
    15,
    None,
    @sorted_map.SortedMap([]),
  )
  let sanitize = (s : String) => generator.sanitize_identifier(pool.intern(s))
  inspect(sanitize("foo_bar1"), content="foo_bar1")
  inspect(sanitize(" "), content="SPACE")
  inspect(sanitize("a b"), content="ab")
  inspect(sanitize("+="), content="PLUS_EQ")
  inspect(sanitize("a->b"), content="a_DASH_GTb")
  inspect(sanitize("_-"), content="_DASH")
  inspect(sanitize("\u{0}\t\u{7f}\u{feff}"), content="NULL_TAB_DEL_BOM")
  inspect(sanitize("é😀x"), content="u00e9U0001f600x")
  inspect(sanitize("x\u{e9}+"), content="xu00e9_PLUS")
}

///|
test "sanitize_str" {
  inspect(
    Generator::sanitize_str(
      "\"?\\\u{7}\u{8}\u{b}\u{c}\n\r\t\u{0}\u{1}\u{7f}é😀a",
    ),
    content=(
      #|\"\?\\\a\b\v\f\n\r\t\0\x01\u007f\u00e9\U0001f600a
    ),
  )
}

///|
test "add_character" {
  let w = CWriter::new()
  for
    c in [
      0, '\'', '\\', '\u{c}', '\n', '\t', '\r', ' ', 'a', '~', 0x7f, 0x1, 0x1234,
    ] {
    w.add_character(c)
    w.add(" ")
  }
  inspect(
    w.buffer.to_string(),
    content=(
      #|0 '\'' '\\' '\f' '\n' '\t' '\r' ' ' 'a' '~' 0x7f 0x01 0x1234 
    ),
  )
}

///|
test "compare_strs uses code point order" {
  inspect(Generator::compare_strs("b", "aa"), content="1")
  inspect(Generator::compare_strs("a", "ab"), content="-1")
  inspect(Generator::compare_strs("\u{FFFF}", "\u{10000}"), content="-1")
  inspect(Generator::compare_strs("same", "same"), content="0")
}

///|
test "render rejects unsupported ABI versions" {
  let pool = StrPool::new()
  let (tables, syntax_grammar, lexical_grammar, default_aliases) = tiny_grammar(
    pool,
  )
  try
    render_c_code(
      pool.intern("tiny"),
      tables,
      syntax_grammar,
      lexical_grammar,
      default_aliases,
      pool,
      13,
      None,
      @sorted_map.SortedMap([]),
    )
  catch {
    e =>
      inspect(
        e,
        content="This version of Tree-sitter can only generate parsers with ABI version 14 - 15, not 13",
      )
  } noraise {
    _ => fail("expected an ABI error")
  }
}

///|
fn tiny_syntax_grammar(
  variables : Array[SyntaxVariable],
  steps : Array[ProductionStep],
) -> SyntaxGrammar {
  {
    variables,
    extra_symbols: [],
    expected_conflicts: [],
    external_tokens: [],
    supertype_symbols: [],
    variables_to_inline: [],
    word_token: None,
    precedence_orderings: [],
    reserved_word_sets: [],
    steps,
    productions: [],
    var_prods: [],
  }
}

///|
/// `source -> "a" | b`, where `b` is `/[c-z]+/` named `b+`, with the alias
/// `thing` and the field `name` on the first production.
fn tiny_grammar(
  pool : StrPool,
) -> (Tables, SyntaxGrammar, LexicalGrammar, AliasMap) {
  let source = Symbol::non_terminal(0)
  let a = Symbol::terminal(0)
  let b = Symbol::terminal(1)
  let thing : Alias = { value: pool.intern("thing"), is_named: true, }
  let syntax_grammar = tiny_syntax_grammar(
    [{ name: pool.intern("source"), kind: Named, }],
    [ProductionStep::pack(a, NoPrecedence, None, Some(thing), None, 0)],
  )
  let lexical_grammar : LexicalGrammar = {
    nfa: Nfa::new(),
    variables: [
      {
        name: pool.intern("a"),
        kind: Anonymous,
        implicit_precedence: 0,
        start_state: 0,
      },
      {
        name: pool.intern("b+"),
        kind: Named,
        implicit_precedence: 0,
        start_state: 1,
      },
    ],
  }
  let parse_table = ParseTable::new()
  ignore(parse_table.action_lists.push([]))
  ignore(parse_table.action_lists.push([Shift(state=2, is_repetition=false)]))
  ignore(
    parse_table.action_lists.push([
      Reduce(
        symbol=source,
        child_count=1,
        dynamic_precedence=0,
        production_id=0,
      ),
    ]),
  )
  ignore(parse_table.action_lists.push([Accept]))
  ignore(parse_table.action_lists.push([Recover]))
  let state = (
    terminals : Array[(Symbol, Int32)],
    nonterminals : Array[(Symbol, Int32)],
    lex_state_id : Int32,
  ) => {
    let state = ParseState::new()
    for t in terminals {
      state.terminal_entries.push(t.0, ActionListId::new(t.1, true))
    }
    for n in nonterminals {
      state.nonterminal_entries.push(n.0, Goto(n.1))
    }
    state.lex_state_id = lex_state_id
    state
  }
  parse_table.states = [
    state([(symbol_end, 4)], [], 0),
    state([(a, 1), (b, 1)], [(source, 3)], 0),
    state([(symbol_end, 2)], [], 1),
    state([(symbol_end, 3)], [], 1),
  ]
  for i, s in parse_table.states {
    s.core_id = if i == 3 { 2 } else { i }
  }
  parse_table.symbols = [symbol_end, a, b, source]
  let field_map = @sorted_map.SortedMap([])
  field_map.set(pool.intern("name"), [{ index: 0, inherited: false, }])
  parse_table.production_infos = [{ alias_sequence: [Some(thing)], field_map, }]
  parse_table.max_aliased_production_length = 1
  let lex_state = (
    accept : Symbol?,
    advance : Array[(CharacterSet, AdvanceAction)],
  ) => {
    let state = LexState::new()
    state.accept_action = accept
    state.advance_actions = advance
    state
  }
  let main_lex_table : LexTable = {
    states: [
      lex_state(None, [
        (
          CharacterSet::from_char('a'.to_int()),
          { state: 1, in_main_token: true, },
        ),
        (
          CharacterSet::from_range('c'.to_int(), 'z'.to_int()),
          { state: 2, in_main_token: true, },
        ),
        (
          CharacterSet::from_char(' '.to_int()).add_char('\n'.to_int()),
          { state: 0, in_main_token: false, },
        ),
      ]),
      lex_state(Some(a), []),
      lex_state(Some(b), [
        (
          CharacterSet::from_range('c'.to_int(), 'z'.to_int()),
          { state: 2, in_main_token: true, },
        ),
      ]),
    ],
  }
  (
    {
      parse_table,
      main_lex_table,
      keyword_lex_table: LexTable::new(),
      large_character_sets: [],
    },
    syntax_grammar,
    lexical_grammar,
    @sorted_map.SortedMap([]),
  )
}

///|
test "render a tiny grammar" {
  let pool = StrPool::new()
  let render = (abi_version : Int32) => {
    let (tables, syntax_grammar, lexical_grammar, default_aliases) = tiny_grammar(
      pool,
    )
    render_c_code(
      pool.intern("tiny"),
      tables,
      syntax_grammar,
      lexical_grammar,
      default_aliases,
      pool,
      abi_version,
      Some((1, 2, 3)),
      @sorted_map.SortedMap([]),
    )
  }
  inspect(
    render(15),
    content=(
      #|/* Automatically @generated by tree-sitter */
      #|
      #|#include "tree_sitter/parser.h"
      #|
      #|#if defined(__GNUC__) || defined(__clang__)
      #|#pragma GCC diagnostic ignored "-Wmissing-field-initializers"
      #|#endif
      #|
      #|#define LANGUAGE_VERSION 15
      #|#define STATE_COUNT 4
      #|#define LARGE_STATE_COUNT 2
      #|#define SYMBOL_COUNT 4
      #|#define ALIAS_COUNT 1
      #|#define TOKEN_COUNT 3
      #|#define EXTERNAL_TOKEN_COUNT 0
      #|#define FIELD_COUNT 1
      #|#define MAX_ALIAS_SEQUENCE_LENGTH 1
      #|#define MAX_RESERVED_WORD_SET_SIZE 0
      #|#define PRODUCTION_ID_COUNT 1
      #|#define SUPERTYPE_COUNT 0
      #|
      #|enum ts_symbol_identifiers {
      #|  anon_sym_a = 1,
      #|  sym_b_PLUS = 2,
      #|  sym_source = 3,
      #|  alias_sym_thing = 4,
      #|};
      #|
      #|static const char * const ts_symbol_names[] = {
      #|  [ts_builtin_sym_end] = "end",
      #|  [anon_sym_a] = "a",
      #|  [sym_b_PLUS] = "b+",
      #|  [sym_source] = "source",
      #|  [alias_sym_thing] = "thing",
      #|};
      #|
      #|static const TSSymbol ts_symbol_map[] = {
      #|  [ts_builtin_sym_end] = ts_builtin_sym_end,
      #|  [anon_sym_a] = anon_sym_a,
      #|  [sym_b_PLUS] = sym_b_PLUS,
      #|  [sym_source] = sym_source,
      #|  [alias_sym_thing] = alias_sym_thing,
      #|};
      #|
      #|static const TSSymbolMetadata ts_symbol_metadata[] = {
      #|  [ts_builtin_sym_end] = {
      #|    .visible = false,
      #|    .named = true,
      #|  },
      #|  [anon_sym_a] = {
      #|    .visible = true,
      #|    .named = false,
      #|  },
      #|  [sym_b_PLUS] = {
      #|    .visible = true,
      #|    .named = true,
      #|  },
      #|  [sym_source] = {
      #|    .visible = true,
      #|    .named = true,
      #|  },
      #|  [alias_sym_thing] = {
      #|    .visible = true,
      #|    .named = true,
      #|  },
      #|};
      #|
      #|enum ts_field_identifiers {
      #|  field_name = 1,
      #|};
      #|
      #|static const char * const ts_field_names[] = {
      #|  [0] = NULL,
      #|  [field_name] = "name",
      #|};
      #|
      #|static const TSMapSlice ts_field_map_slices[PRODUCTION_ID_COUNT] = {
      #|  [0] = {.index = 0, .length = 1},
      #|};
      #|
      #|static const TSFieldMapEntry ts_field_map_entries[] = {
      #|  [0] =
      #|    {field_name, 0},
      #|};
      #|
      #|static const TSSymbol ts_alias_sequences[PRODUCTION_ID_COUNT][MAX_ALIAS_SEQUENCE_LENGTH] = {
      #|  [0] = {
      #|    [0] = alias_sym_thing,
      #|  },
      #|};
      #|
      #|static const uint16_t ts_non_terminal_alias_map[] = {
      #|  0,
      #|};
      #|
      #|static const TSStateId ts_primary_state_ids[STATE_COUNT] = {
      #|  [0] = 0,
      #|  [1] = 1,
      #|  [2] = 2,
      #|  [3] = 2,
      #|};
      #|
      #|static bool ts_lex(TSLexer *lexer, TSStateId state) {
      #|  START_LEXER();
      #|  eof = lexer->eof(lexer);
      #|  switch (state) {
      #|    case 0:
      #|      if (lookahead == 'a') ADVANCE(1);
      #|      if (('c' <= lookahead && lookahead <= 'z')) ADVANCE(2);
      #|      if (lookahead == '\n' ||
      #|          lookahead == ' ') SKIP(0);
      #|      END_STATE();
      #|    case 1:
      #|      ACCEPT_TOKEN(anon_sym_a);
      #|      END_STATE();
      #|    case 2:
      #|      ACCEPT_TOKEN(sym_b_PLUS);
      #|      if (('c' <= lookahead && lookahead <= 'z')) ADVANCE(2);
      #|      END_STATE();
      #|    default:
      #|      return false;
      #|  }
      #|}
      #|
      #|static const TSLexerMode ts_lex_modes[STATE_COUNT] = {
      #|  [0] = {.lex_state = 0},
      #|  [1] = {.lex_state = 0},
      #|  [2] = {.lex_state = 1},
      #|  [3] = {.lex_state = 1},
      #|};
      #|
      #|static const uint16_t ts_parse_table[LARGE_STATE_COUNT][SYMBOL_COUNT] = {
      #|  [STATE(0)] = {
      #|    [ts_builtin_sym_end] = ACTIONS(1),
      #|  },
      #|  [STATE(1)] = {
      #|    [sym_source] = STATE(3),
      #|    [anon_sym_a] = ACTIONS(3),
      #|    [sym_b_PLUS] = ACTIONS(3),
      #|  },
      #|};
      #|
      #|static const uint16_t ts_small_parse_table[] = {
      #|  [0] = 1,
      #|    ACTIONS(5), 1,
      #|      ts_builtin_sym_end,
      #|  [4] = 1,
      #|    ACTIONS(7), 1,
      #|      ts_builtin_sym_end,
      #|};
      #|
      #|static const uint32_t ts_small_parse_table_map[] = {
      #|  [SMALL_STATE(2)] = 0,
      #|  [SMALL_STATE(3)] = 4,
      #|};
      #|
      #|static const TSParseActionEntry ts_parse_actions[] = {
      #|  [0] = {.entry = {.count = 0, .reusable = false}},
      #|  [1] = {.entry = {.count = 1, .reusable = true}}, RECOVER(),
      #|  [3] = {.entry = {.count = 1, .reusable = true}}, SHIFT(2),
      #|  [5] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_source, 1, 0, 0),
      #|  [7] = {.entry = {.count = 1, .reusable = true}},  ACCEPT_INPUT(),
      #|};
      #|
      #|#ifdef __cplusplus
      #|extern "C" {
      #|#endif
      #|#ifdef TREE_SITTER_HIDE_SYMBOLS
      #|#define TS_PUBLIC
      #|#elif defined(_WIN32)
      #|#define TS_PUBLIC __declspec(dllexport)
      #|#else
      #|#define TS_PUBLIC __attribute__((visibility("default")))
      #|#endif
      #|
      #|TS_PUBLIC const TSLanguage *tree_sitter_tiny(void) {
      #|  static const TSLanguage language = {
      #|    .abi_version = LANGUAGE_VERSION,
      #|    .symbol_count = SYMBOL_COUNT,
      #|    .alias_count = ALIAS_COUNT,
      #|    .token_count = TOKEN_COUNT,
      #|    .external_token_count = EXTERNAL_TOKEN_COUNT,
      #|    .state_count = STATE_COUNT,
      #|    .large_state_count = LARGE_STATE_COUNT,
      #|    .production_id_count = PRODUCTION_ID_COUNT,
      #|    .supertype_count = SUPERTYPE_COUNT,
      #|    .field_count = FIELD_COUNT,
      #|    .max_alias_sequence_length = MAX_ALIAS_SEQUENCE_LENGTH,
      #|    .parse_table = &ts_parse_table[0][0],
      #|    .small_parse_table = ts_small_parse_table,
      #|    .small_parse_table_map = ts_small_parse_table_map,
      #|    .parse_actions = ts_parse_actions,
      #|    .symbol_names = ts_symbol_names,
      #|    .field_names = ts_field_names,
      #|    .field_map_slices = ts_field_map_slices,
      #|    .field_map_entries = ts_field_map_entries,
      #|    .symbol_metadata = ts_symbol_metadata,
      #|    .public_symbol_map = ts_symbol_map,
      #|    .alias_map = ts_non_terminal_alias_map,
      #|    .alias_sequences = &ts_alias_sequences[0][0],
      #|    .lex_modes = (const void*)ts_lex_modes,
      #|    .lex_fn = ts_lex,
      #|    .primary_state_ids = ts_primary_state_ids,
      #|    .name = "tiny",
      #|    .max_reserved_word_set_size = 0,
      #|    .metadata = {
      #|      .major_version = 1,
      #|      .minor_version = 2,
      #|      .patch_version = 3,
      #|    },
      #|  };
      #|  return &language;
      #|}
      #|#ifdef __cplusplus
      #|}
      #|#endif
      #|
    ),
  )
  let c14 = render(14)
  inspect(c14.contains("TSLexMode ts_lex_modes"), content="true")
  inspect(c14.contains(".metadata"), content="false")
}

///|
test "render_language of a tiny grammar" {
  let pool = StrPool::new()
  let (tables, syntax_grammar, lexical_grammar, default_aliases) = tiny_grammar(
    pool,
  )
  let language = render_language(
    pool.intern("tiny"),
    tables,
    syntax_grammar,
    lexical_grammar,
    default_aliases,
    pool,
    15,
    Some((1, 2, 3)),
    @sorted_map.SortedMap([]),
  )
  debug_inspect(
    language,
    content=(
      #|{
      #|  abi_version: 15,
      #|  symbol_count: 4,
      #|  alias_count: 1,
      #|  token_count: 3,
      #|  external_token_count: 0,
      #|  state_count: 4,
      #|  large_state_count: 2,
      #|  production_id_count: 1,
      #|  field_count: 1,
      #|  max_alias_sequence_length: 1,
      #|  parse_table: [1, 0, 0, 0, 0, 3, 3, 3],
      #|  small_parse_table: [1, 5, 1, 0, 1, 7, 1, 0],
      #|  small_parse_table_map: [0, 4],
      #|  parse_actions: [
      #|    Entry(count=0, reusable=false),
      #|    Entry(count=1, reusable=true),
      #|    Recover,
      #|    Entry(count=1, reusable=true),
      #|    Shift(state=2, extra=false, repetition=false),
      #|    Entry(count=1, reusable=true),
      #|    Reduce(symbol=3, child_count=1, dynamic_precedence=0, production_id=0),
      #|    Entry(count=1, reusable=true),
      #|    Accept,
      #|  ],
      #|  symbol_names: ["end", "a", "b+", "source", "thing"],
      #|  field_names: ["", "name"],
      #|  field_map_slices: [{ index: 0, length: 1 }],
      #|  field_map_entries: [{ field_id: 1, child_index: 0, inherited: false }],
      #|  symbol_metadata: [
      #|    { visible: false, named: true, supertype: false },
      #|    { visible: true, named: false, supertype: false },
      #|    { visible: true, named: true, supertype: false },
      #|    { visible: true, named: true, supertype: false },
      #|    { visible: true, named: true, supertype: false },
      #|  ],
      #|  public_symbol_map: [0, 1, 2, 3, 4],
      #|  alias_map: [0],
      #|  alias_sequences: [4],
      #|  lex_modes: [
      #|    { lex_state: 0, external_lex_state: 0, reserved_word_set_id: 0 },
      #|    { lex_state: 0, external_lex_state: 0, reserved_word_set_id: 0 },
      #|    { lex_state: 1, external_lex_state: 0, reserved_word_set_id: 0 },
      #|    { lex_state: 1, external_lex_state: 0, reserved_word_set_id: 0 },
      #|  ],
      #|  lex_fn: {
      #|    states: [
      #|      {
      #|        accept_token: None,
      #|        eof_advance: None,
      #|        advance_map: [],
      #|        transitions: [
      #|          {
      #|            condition: {
      #|              large_set: None,
      #|              asserted: Some({ ranges: [{ start: 97, end: 97 }], is_included: true }),
      #|              negated: None,
      #|            },
      #|            state: 1,
      #|            skip: false,
      #|          },
      #|          {
      #|            condition: {
      #|              large_set: None,
      #|              asserted: Some({ ranges: [{ start: 99, end: 122 }], is_included: true }),
      #|              negated: None,
      #|            },
      #|            state: 2,
      #|            skip: false,
      #|          },
      #|          {
      #|            condition: {
      #|              large_set: None,
      #|              asserted: Some(
      #|                {
      #|                  ranges: [{ start: 10, end: 10 }, { start: 32, end: 32 }],
      #|                  is_included: true,
      #|                },
      #|              ),
      #|              negated: None,
      #|            },
      #|            state: 0,
      #|            skip: true,
      #|          },
      #|        ],
      #|      },
      #|      {
      #|        accept_token: Some(1),
      #|        eof_advance: None,
      #|        advance_map: [],
      #|        transitions: [],
      #|      },
      #|      {
      #|        accept_token: Some(2),
      #|        eof_advance: None,
      #|        advance_map: [],
      #|        transitions: [
      #|          {
      #|            condition: {
      #|              large_set: None,
      #|              asserted: Some({ ranges: [{ start: 99, end: 122 }], is_included: true }),
      #|              negated: None,
      #|            },
      #|            state: 2,
      #|            skip: false,
      #|          },
      #|        ],
      #|      },
      #|    ],
      #|    large_character_sets: [],
      #|  },
      #|  keyword_lex_fn: None,
      #|  keyword_capture_token: 0,
      #|  external_scanner: { states: [], symbol_map: [] },
      #|  primary_state_ids: [0, 1, 2, 2],
      #|  name: "tiny",
      #|  reserved_words: [],
      #|  max_reserved_word_set_size: 0,
      #|  supertype_count: 0,
      #|  supertype_symbols: [],
      #|  supertype_map_slices: [],
      #|  supertype_map_entries: [],
      #|  metadata: { major_version: 1, minor_version: 2, patch_version: 3 },
      #|}
    ),
  )
}

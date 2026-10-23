// Portable equivalent of the C `TSLanguage` struct (lib/src/parser.h, ABI 15).
//
// Every array has exactly the layout, indexing and contents of the
// corresponding array that upstream's `render.rs` emits into `parser.c`, so the
// runtime port can index it exactly as `lib/src/language.c` does. The only
// difference is the lexer: upstream emits C functions (`ts_lex`,
// `ts_lex_keywords`); here the same code is captured as a `LexProgram` whose
// interpretation is defined to be identical to the emitted C.

///|
pub let ts_builtin_sym_error : Int32 = 65535

///|
pub let ts_builtin_sym_end : Int32 = 0

///|
pub let tree_sitter_serialization_buffer_size : Int32 = 1024

///|
pub let language_version : Int32 = 15

///|
/// `TSParseAction` plus the `entry` header of `TSParseActionEntry`.
pub(all) enum ParseActionEntry {
  /// Header preceding `count` actions (`entry.count`, `entry.reusable`).
  Entry(count~ : Int32, reusable~ : Bool)
  Shift(state~ : Int32, extra~ : Bool, repetition~ : Bool)
  Reduce(
    symbol~ : Int32,
    child_count~ : Int32,
    dynamic_precedence~ : Int32,
    production_id~ : Int32
  )
  Accept
  Recover
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct FieldMapEntry {
  field_id : Int32
  child_index : Int32
  inherited : Bool
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// `TSMapSlice`: used to index the field and supertype maps.
pub(all) struct MapSlice {
  index : Int32
  length : Int32
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct SymbolMetadata {
  visible : Bool
  named : Bool
  supertype : Bool
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// `TSLexerMode`.
pub(all) struct LexMode {
  lex_state : Int32
  external_lex_state : Int32
  reserved_word_set_id : Int32
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct LanguageMetadata {
  major_version : Int32
  minor_version : Int32
  patch_version : Int32
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// An inclusive code point range, as in `TSCharacterRange`.
pub(all) struct CharacterRange {
  start : Int32
  end : Int32
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// One `add_character_range_conditions` call in `render.rs`: a disjunction
/// (`is_included`) or conjunction (`!is_included`) of per-range tests, each
/// rendered exactly as upstream renders it (including the `!eof &&` guard for
/// included ranges starting at `'\0'`).
pub(all) struct RangeCondition {
  ranges : Array[CharacterRange]
  is_included : Bool
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// The condition of one transition line:
/// `if ((large || asserted) && negated) ADVANCE/SKIP(state)`.
/// A missing part is omitted from the C expression; a transition with no part
/// at all is unconditional.
pub(all) struct LexCondition {
  /// Index into `LexProgram::large_character_sets`, and whether the C code
  /// guards the `set_contains` call with `!eof`.
  large_set : (Int32, Bool)?
  asserted : RangeCondition?
  negated : RangeCondition?
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct LexTransition {
  condition : LexCondition
  state : Int32
  /// `SKIP(state)` rather than `ADVANCE(state)`.
  skip : Bool
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// One `case` of the generated lex function, in emission order:
/// `ACCEPT_TOKEN`, `if (eof) ADVANCE`, `ADVANCE_MAP`, then the transitions.
pub(all) struct LexStateCode {
  accept_token : Int32?
  eof_advance : Int32?
  /// `(lookahead, state)` pairs of `ADVANCE_MAP`; empty when not emitted.
  advance_map : Array[(Int32, Int32)]
  transitions : Array[LexTransition]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// A generated lex function (`ts_lex` or `ts_lex_keywords`).
pub(all) struct LexProgram {
  states : Array[LexStateCode]
  /// The `TSCharacterRange` arrays referenced through `set_contains`.
  large_character_sets : Array[Array[CharacterRange]]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct ExternalScannerData {
  /// Row-major `[external_lex_state_count][external_token_count]`; row 0 is
  /// all false, exactly like `ts_external_scanner_states`.
  states : Array[Bool]
  /// `ts_external_scanner_symbol_map`.
  symbol_map : Array[Int32]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Field-for-field equivalent of `TSLanguage`.
pub(all) struct Language {
  abi_version : Int32
  symbol_count : Int32
  alias_count : Int32
  token_count : Int32
  external_token_count : Int32
  state_count : Int32
  large_state_count : Int32
  production_id_count : Int32
  field_count : Int32
  max_alias_sequence_length : Int32
  /// `[large_state_count][symbol_count]`.
  parse_table : Array[Int32]
  small_parse_table : Array[Int32]
  small_parse_table_map : Array[Int32]
  parse_actions : Array[ParseActionEntry]
  symbol_names : Array[String]
  /// Index 0 is upstream's `NULL` entry and holds `""`.
  field_names : Array[String]
  field_map_slices : Array[MapSlice]
  field_map_entries : Array[FieldMapEntry]
  symbol_metadata : Array[SymbolMetadata]
  public_symbol_map : Array[Int32]
  alias_map : Array[Int32]
  /// `[production_id_count][max_alias_sequence_length]`.
  alias_sequences : Array[Int32]
  lex_modes : Array[LexMode]
  lex_fn : LexProgram
  keyword_lex_fn : LexProgram?
  keyword_capture_token : Int32
  external_scanner : ExternalScannerData
  primary_state_ids : Array[Int32]
  name : String
  /// `[reserved word set count][max_reserved_word_set_size]`, zero padded.
  reserved_words : Array[Int32]
  max_reserved_word_set_size : Int32
  supertype_count : Int32
  supertype_symbols : Array[Int32]
  supertype_map_slices : Array[MapSlice]
  supertype_map_entries : Array[Int32]
  metadata : LanguageMetadata
} derive(Eq, Debug, ToJson, @json.FromJson)

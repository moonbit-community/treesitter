// Portable equivalent of the C `TSLanguage` struct (lib/src/parser.h, ABI 15).
//
// Every array has exactly the layout, indexing and contents of the
// corresponding array that upstream's `render.rs` emits into `parser.c`, so the
// runtime port can index it exactly as `lib/src/language.c` does. The only
// difference is the lexer: upstream emits C functions (`ts_lex`,
// `ts_lex_keywords`); here the same code is captured as a `LexProgram` whose
// interpretation is defined to be identical to the emitted C.
//
// `next/generate`'s `render_language` builds this value from the same computed
// tables that `render_c_code` prints, so the two cannot diverge. Fields that the
// C initializer leaves out (a `NULL` pointer, or a member absent for the
// requested ABI version) hold an empty array, `0` or `""`: for ABI 14,
// `name`, `reserved_words`, `max_reserved_word_set_size`, the supertype fields
// and `metadata` are empty/zero, and `LexMode::reserved_word_set_id` is 0.

///|
pub let ts_builtin_sym_error : Int = 65535

///|
pub let ts_builtin_sym_end : Int = 0

///|
pub let tree_sitter_serialization_buffer_size : Int = 1024

///|
pub let language_version : Int = 15

///|
/// `TSParseAction` plus the `entry` header of `TSParseActionEntry`.
pub(all) enum ParseActionEntry {
  /// Header preceding `count` actions (`entry.count`, `entry.reusable`).
  Entry(count~ : Int, reusable~ : Bool)
  /// `SHIFT(state)`, `SHIFT_REPEAT(state)` (`repetition`) or `SHIFT_EXTRA()`
  /// (`extra`, with `state` 0).
  Shift(state~ : Int, extra~ : Bool, repetition~ : Bool)
  Reduce(
    symbol~ : Int,
    child_count~ : Int,
    dynamic_precedence~ : Int,
    production_id~ : Int
  )
  Accept
  Recover
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct FieldMapEntry {
  field_id : Int
  child_index : Int
  inherited : Bool
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// `TSMapSlice`: used to index the field and supertype maps.
pub(all) struct MapSlice {
  index : Int
  length : Int
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct SymbolMetadata {
  visible : Bool
  named : Bool
  supertype : Bool
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// `TSLexerMode` (`TSLexMode` for ABI 14, without `reserved_word_set_id`).
/// The `(TSStateId)(-1)` mode of a state that ends a non-terminal extra is
/// `{ lex_state: 65535, external_lex_state: 0, reserved_word_set_id: 0 }`.
pub(all) struct LexMode {
  lex_state : Int
  external_lex_state : Int
  reserved_word_set_id : Int
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct LanguageMetadata {
  major_version : Int
  minor_version : Int
  patch_version : Int
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// An inclusive code point range, as in `TSCharacterRange`.
pub(all) struct CharacterRange {
  start : Int
  end : Int
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// One `add_character_range_conditions` call in `render.rs`, with the ranges
/// exactly as passed to it (sorted, disjoint, inclusive).
///
/// Evaluation, with `lookahead` and `eof` as in `LexProgram`:
/// - `is_included`: true iff some range matches, where a range starting at 0
///   matches iff `!eof && lookahead <= end` (C: `(!eof && lookahead <= end)`,
///   or `(!eof && lookahead == 0)` when `end` is 0), and any other range
///   matches iff `start <= lookahead && lookahead <= end`.
/// - `!is_included`: true iff no range contains `lookahead` (C: a
///   conjunction of `lookahead != c`, `(lookahead < start || end < lookahead)`
///   and `lookahead > end` tests). `eof` plays no part.
///
/// An asserted condition whose characters include U+10FFFF is emitted in the
/// negated form: its ranges are the complement of those characters plus
/// `'\0'`, with `is_included` false.
pub(all) struct RangeCondition {
  ranges : Array[CharacterRange]
  is_included : Bool
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// The condition of one transition line:
/// `if ((large || asserted) && negated) ADVANCE/SKIP(state)`.
/// A missing part is omitted from the C expression: the condition is the
/// conjunction of `(large || asserted)` (if either is present) and `negated`
/// (if present), so a transition with no part at all is unconditional. The
/// parts have no side effects, so evaluation order does not matter.
pub(all) struct LexCondition {
  /// Index into `LexProgram::large_character_sets`, and whether the C code
  /// guards the `set_contains` call with `!eof`. The part is true iff
  /// (`!eof`, when guarded) `lookahead` lies in one of the set's ranges
  /// (`set_contains` is a binary search over the sorted, disjoint ranges).
  large_set : (Int, Bool)?
  asserted : RangeCondition?
  negated : RangeCondition?
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct LexTransition {
  condition : LexCondition
  state : Int
  /// `SKIP(state)` rather than `ADVANCE(state)`.
  skip : Bool
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// One `case` of the generated lex function, in emission order:
/// `ACCEPT_TOKEN`, `if (eof) ADVANCE`, `ADVANCE_MAP`, then the transitions.
pub(all) struct LexStateCode {
  /// `ACCEPT_TOKEN(symbol)`: the symbol value.
  accept_token : Int?
  /// `if (eof) ADVANCE(state);`.
  eof_advance : Int?
  /// `(lookahead, state)` pairs of `ADVANCE_MAP`, in order; empty when not
  /// emitted. The first pair whose character equals `lookahead` advances.
  advance_map : Array[(Int, Int)]
  transitions : Array[LexTransition]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// A generated lex function (`ts_lex` or `ts_lex_keywords`).
///
/// `lex(lexer, state) -> Bool` is defined as the emitted C, expanded with the
/// macros of `parser.h` (`START_LEXER`, `ACCEPT_TOKEN`, `ADVANCE`,
/// `ADVANCE_MAP`, `SKIP`, `END_STATE`):
///
/// ```text
/// result = false                                // START_LEXER()
/// loop {
///   skip = false                                // start:
///   lookahead = lexer.lookahead
///   eof = lexer.eof()                           // eof = lexer->eof(lexer);
///   if state >= states.length() {
///     return false                              // default: return false;
///   }
///   code = states[state]                        // case state:
///   if code.accept_token is Some(symbol) {       // ACCEPT_TOKEN(symbol)
///     result = true
///     lexer.result_symbol = symbol
///     lexer.mark_end()
///   }
///   if eof && code.eof_advance is Some(s) {      // if (eof) ADVANCE(s);
///     next = s
///   } else if code.advance_map has a first (c, s) with c == lookahead {
///     next = s                                  // ADVANCE_MAP(...)
///   } else if code.transitions has a first t whose condition holds {
///     next = t.state                            // if (...) ADVANCE/SKIP
///     skip = t.skip
///   } else {
///     return result                             // END_STATE()
///   }
///   state = next                                // goto next_state;
///   lexer.advance(skip)                         // next_state:
/// }
/// ```
///
/// `lookahead` is the current code point (C `int32_t`; 0 at end of input).
pub(all) struct LexProgram {
  states : Array[LexStateCode]
  /// The `TSCharacterRange` arrays referenced through `set_contains`
  /// (inclusive, sorted, disjoint). This holds every large character set of
  /// the grammar, in upstream's order, whether or not this function uses it;
  /// `parser.c` only defines the ones some lex function uses.
  large_character_sets : Array[Array[CharacterRange]]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct ExternalScannerData {
  /// Row-major `[external_lex_state_count][external_token_count]`; row 0 is
  /// all false, exactly like `ts_external_scanner_states`.
  states : Array[Bool]
  /// `ts_external_scanner_symbol_map`.
  symbol_map : Array[Int]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Field-for-field equivalent of `TSLanguage`.
pub(all) struct Language {
  abi_version : Int
  symbol_count : Int
  alias_count : Int
  token_count : Int
  external_token_count : Int
  state_count : Int
  large_state_count : Int
  production_id_count : Int
  field_count : Int
  max_alias_sequence_length : Int
  /// Row-major `[large_state_count][symbol_count]`: a nonterminal's goto
  /// state, or a terminal's index into `parse_actions` (0: no action).
  parse_table : Array[Int]
  /// `ts_small_parse_table`: for each small state, its group count, then per
  /// group the value (state or `parse_actions` index), the symbol count and
  /// the symbols. Empty when every state is large.
  small_parse_table : Array[Int]
  /// Start of each small state (`state - large_state_count`) in
  /// `small_parse_table`.
  small_parse_table_map : Array[Int]
  /// `ts_parse_actions`: each `Entry` header followed by its actions; a
  /// `parse_table` value is the index of a header.
  parse_actions : Array[ParseActionEntry]
  /// Indexed by symbol value: `symbol_count` symbols, then `alias_count`
  /// aliases. Unescaped.
  symbol_names : Array[String]
  /// Index 0 is upstream's `NULL` entry and holds `""`. Empty when the grammar
  /// has no fields, as are `field_map_slices` and `field_map_entries`.
  field_names : Array[String]
  /// One per production id.
  field_map_slices : Array[MapSlice]
  field_map_entries : Array[FieldMapEntry]
  symbol_metadata : Array[SymbolMetadata]
  public_symbol_map : Array[Int]
  /// `ts_non_terminal_alias_map`: groups of `symbol, count, public symbol,
  /// aliases...` (`count` covers the public symbol and the aliases),
  /// terminated by 0.
  alias_map : Array[Int]
  /// Row-major `[production_id_count][max_alias_sequence_length]`; 0 means
  /// no alias. Empty when there are no productions.
  alias_sequences : Array[Int]
  /// One per parse state.
  lex_modes : Array[LexMode]
  lex_fn : LexProgram
  /// Present iff the grammar has a word token.
  keyword_lex_fn : LexProgram?
  /// 0 when there is no word token.
  keyword_capture_token : Int
  external_scanner : ExternalScannerData
  primary_state_ids : Array[Int]
  name : String
  /// Row-major `[reserved word set count][max_reserved_word_set_size]`, zero
  /// padded; set 0 is empty. Empty when only set 0 exists.
  reserved_words : Array[Int]
  max_reserved_word_set_size : Int
  supertype_count : Int
  supertype_symbols : Array[Int]
  /// Indexed by supertype symbol value (zero slices elsewhere), up to the
  /// largest supertype, like the designated C initializer.
  supertype_map_slices : Array[MapSlice]
  supertype_map_entries : Array[Int]
  metadata : LanguageMetadata
} derive(Eq, Debug, ToJson, @json.FromJson)

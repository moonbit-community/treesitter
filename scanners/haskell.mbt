// Port of tree-sitter-haskell src/scanner.c (v0.24.1)
// tree-sitter-haskell is distributed under the MIT license (see NOTICE).
//
// The character classes of src/unicode.h are in haskell_unicode.mbt. The
// `TREE_SITTER_DEBUG` parts of the C file (parse buffer visualization, debug
// printing) are not compiled by the reference and are not ported.
//
// C integer types: indents and columns are `uint32_t` and kept as `UInt`
// (`start_column` and `consume_block_comment` rely on wrapping arithmetic);
// lookahead indexes and counts are `uint32_t` too, but never wrap and are kept
// as `Int`.

// --------------------------------------------------------------------------------------------------------
// Symbols
// --------------------------------------------------------------------------------------------------------

///|
/// `Symbol`: mirrors the symbols in `externals` in `grammar/externals.js`.
const HS_FAIL : Int32 = 0

///|
const HS_SEMICOLON : Int32 = 1

///|
const HS_START : Int32 = 2

///|
const HS_START_DO : Int32 = 3

///|
const HS_START_CASE : Int32 = 4

///|
const HS_START_IF : Int32 = 5

///|
const HS_START_LET : Int32 = 6

///|
const HS_START_QUOTE : Int32 = 7

///|
const HS_START_EXPLICIT : Int32 = 8

///|
const HS_END : Int32 = 9

///|
const HS_END_EXPLICIT : Int32 = 10

///|
const HS_START_BRACE : Int32 = 11

///|
const HS_END_BRACE : Int32 = 12

///|
const HS_START_TEXP : Int32 = 13

///|
const HS_END_TEXP : Int32 = 14

///|
const HS_WHERE : Int32 = 15

///|
const HS_IN : Int32 = 16

///|
const HS_ARROW : Int32 = 17

///|
const HS_BAR : Int32 = 18

///|
const HS_DERIVING : Int32 = 19

///|
const HS_COMMENT : Int32 = 20

///|
const HS_HADDOCK : Int32 = 21

///|
const HS_CPP : Int32 = 22

///|
const HS_PRAGMA : Int32 = 23

///|
const HS_QQ_START : Int32 = 24

///|
const HS_QQ_BODY : Int32 = 25

///|
const HS_SPLICE : Int32 = 26

///|
const HS_QUAL_DOT : Int32 = 27

///|
const HS_TIGHT_DOT : Int32 = 28

///|
const HS_PREFIX_DOT : Int32 = 29

///|
const HS_DOTDOT : Int32 = 30

///|
const HS_TIGHT_AT : Int32 = 31

///|
const HS_PREFIX_AT : Int32 = 32

///|
const HS_TIGHT_BANG : Int32 = 33

///|
const HS_PREFIX_BANG : Int32 = 34

///|
const HS_TIGHT_TILDE : Int32 = 35

///|
const HS_PREFIX_TILDE : Int32 = 36

///|
const HS_PREFIX_PERCENT : Int32 = 37

///|
const HS_QUALIFIED_OP : Int32 = 38

///|
const HS_LEFT_SECTION_OP : Int32 = 39

///|
const HS_NO_SECTION_OP : Int32 = 40

///|
const HS_MINUS : Int32 = 41

///|
const HS_CONTEXT : Int32 = 42

///|
const HS_INFIX : Int32 = 43

///|
const HS_DATA_INFIX : Int32 = 44

///|
const HS_TYPE_INSTANCE : Int32 = 45

///|
const HS_VARSYM : Int32 = 46

///|
const HS_CONSYM : Int32 = 47

///|
const HS_UPDATE : Int32 = 48

// --------------------------------------------------------------------------------------------------------
// Data
// --------------------------------------------------------------------------------------------------------

///|
/// `ContextSort`: different sorts of layout contexts that require special
/// treatment.
const HS_DECL_LAYOUT : Int32 = 0

///|
const HS_DO_LAYOUT : Int32 = 1

///|
const HS_CASE_LAYOUT : Int32 = 2

///|
const HS_LET_LAYOUT : Int32 = 3

///|
const HS_QUOTE_LAYOUT : Int32 = 4

///|
const HS_MULTI_WAY_IF_LAYOUT : Int32 = 5

///|
const HS_BRACES : Int32 = 6

///|
const HS_TEXP : Int32 = 7

///|
const HS_MODULE_HEADER : Int32 = 8

///|
const HS_NO_CONTEXT : Int32 = 9

///|
/// `Context`: an entry of the layout context stack.
priv struct HsContext {
  /// `ContextSort sort`.
  sort : Int32
  /// `uint32_t indent`.
  mut indent : UInt32
}

///|
/// `Lexed`: the lookahead tokens that have special meaning in the scanner.
const HS_L_NOTHING : Int32 = 0

///|
const HS_L_EOF : Int32 = 1

///|
const HS_L_WHERE : Int32 = 2

///|
const HS_L_IN : Int32 = 3

///|
const HS_L_THEN : Int32 = 4

///|
const HS_L_ELSE : Int32 = 5

///|
const HS_L_DERIVING : Int32 = 6

///|
const HS_L_MODULE : Int32 = 7

///|
const HS_L_UPPER : Int32 = 8

///|
const HS_L_TICK : Int32 = 9

///|
const HS_L_SYMOP : Int32 = 10

///|
const HS_L_SYMOP_SPECIAL : Int32 = 11

///|
const HS_L_DOT_DOT : Int32 = 12

///|
const HS_L_DOT_ID : Int32 = 13

///|
const HS_L_DOT_SYMOP : Int32 = 14

///|
const HS_L_DOT_OPEN : Int32 = 15

///|
const HS_L_DOLLAR : Int32 = 16

///|
const HS_L_BANG : Int32 = 17

///|
const HS_L_TILDE : Int32 = 18

///|
const HS_L_AT : Int32 = 19

///|
const HS_L_PERCENT : Int32 = 20

///|
const HS_L_HASH : Int32 = 21

///|
const HS_L_BAR : Int32 = 22

///|
const HS_L_ARROW : Int32 = 23

///|
const HS_L_C_ARROW : Int32 = 24

///|
const HS_L_TEXP_CLOSER : Int32 = 25

///|
const HS_L_QUOTE_CLOSE : Int32 = 26

///|
const HS_L_PRAGMA : Int32 = 27

///|
const HS_L_BLOCK_COMMENT : Int32 = 28

///|
const HS_L_LINE_COMMENT : Int32 = 29

///|
const HS_L_BRACE_CLOSE : Int32 = 30

///|
const HS_L_BRACE_OPEN : Int32 = 31

///|
const HS_L_BRACKET_OPEN : Int32 = 32

///|
const HS_L_UNBOXED_CLOSE : Int32 = 33

///|
const HS_L_SEMI : Int32 = 34

///|
const HS_L_CPP_ELSE : Int32 = 35

///|
const HS_L_CPP : Int32 = 36

///|
/// `NewlineState`: `NInit` is set during newline lookahead, and `NProcess`
/// when lookahead has finished. `NResume` forces newline lookahead mode when a
/// run starts without requiring a newline.
const HS_N_INACTIVE : Int32 = 0

///|
const HS_N_INIT : Int32 = 1

///|
const HS_N_PROCESS : Int32 = 2

///|
const HS_N_RESUME : Int32 = 3

///|
/// `Newline`: the persistent state of the two newline modes.
priv struct HsNewline {
  /// `NewlineState state`.
  mut state : Int32
  /// The final token encountered after skipping comments and CPP (`Lexed`).
  mut end : Int32
  /// The indent of `end`, used to decide layout actions before parsing
  /// intermediate extras.
  mut indent : UInt32
  /// When there is no token after extras, we shouldn't start layouts.
  mut eof : Bool
  /// Prohibit layout semicolons in future runs.
  mut no_semi : Bool
  /// Prohibit layout semicolons in future runs, but can be relaxed by some
  /// actions. See `explicit_semicolon`.
  mut skip_semi : Bool
  /// Lookahead has advanced into `end`, so the scanner has to be restarted
  /// before processing the newline result.
  mut unsafe_ : Bool
}

///|
/// A zeroed `Newline` (`memset(&newline, 0, sizeof(Newline))`).
fn HsNewline::new() -> HsNewline {
  {
    state: 0,
    end: 0,
    indent: 0,
    eof: false,
    no_semi: false,
    skip_semi: false,
    unsafe_: false,
  }
}

///|
/// `Lookahead`: whenever the lexer is advanced over non-(leading-)whitespace,
/// the consumed character is appended to `contents` (its `size` is the array
/// length). `offset` can be used to reset relative indexing to the current
/// lexer position.
priv struct HsLookahead {
  contents : Array[Int32]
  mut offset : Int32
}

///|
/// `State`: the state that is persisted across scanner runs.
priv struct HsState {
  contexts : Array[HsContext]
  newline : HsNewline
  lookahead : HsLookahead
}

///|
/// `Env`: transient state and stuff provided by tree-sitter.
priv struct HsEnv {
  lexer : @runtime.Lexer
  symbols : ArrayView[Bool]
  /// `uint32_t symop`.
  mut symop : Int32
  state : HsState
}

///|
fn hs_env_new(
  l : @runtime.Lexer,
  symbols : ArrayView[Bool],
  state : HsState,
) -> HsEnv {
  { lexer: l, symbols, symop: 0, state, }
}

///|
fn HsEnv::reset_newline(self : HsEnv) -> Unit {
  let n = self.state.newline
  n.state = 0
  n.end = 0
  n.indent = 0
  n.eof = false
  n.no_semi = false
  n.skip_semi = false
  n.unsafe_ = false
}

///|
fn HsEnv::newline_active(self : HsEnv) -> Bool {
  self.state.newline.state == HS_N_INIT ||
  self.state.newline.state == HS_N_PROCESS
}

///|
fn HsEnv::newline_init(self : HsEnv) -> Bool {
  self.state.newline.state == HS_N_INIT
}

// --------------------------------------------------------------------------------------------------------
// Lexer interaction
// --------------------------------------------------------------------------------------------------------

///|
/// `PEEK`.
fn HsEnv::peek_lexer(self : HsEnv) -> Int32 {
  self.lexer.lookahead
}

///|
fn HsEnv::is_eof(self : HsEnv) -> Bool {
  self.lexer.eof()
}

///|
fn HsEnv::not_eof(self : HsEnv) -> Bool {
  !self.is_eof()
}

///|
/// The parser's position in the current line.
/// Note: This is expensive to use.
fn HsEnv::column(self : HsEnv) -> UInt32 {
  if self.is_eof() {
    0
  } else {
    self.lexer.get_column()
  }
}

///|
/// Append the lookahead character to the lookahead buffer and advance.
///
/// Don't add zeroes to the lookahead buffer when hitting EOF – it causes
/// `no_lookahead` to report false negatives.
fn HsEnv::advance(self : HsEnv) -> Unit {
  if self.not_eof() {
    self.state.lookahead.contents.push(self.peek_lexer())
    self.lexer.advance(false)
  }
}

///|
/// `S_SKIP`: move the parser position one character to the right, treating
/// the consumed character as whitespace.
fn HsEnv::skip(self : HsEnv) -> Unit {
  self.lexer.advance(true)
}

///|
/// `MARK(s)`.
fn HsEnv::mark(self : HsEnv, _marked_by : String) -> Unit {
  self.lexer.mark_end()
}

///|
fn HsEnv::set_result_symbol(self : HsEnv, result : Int32) -> Bool {
  if result != HS_FAIL {
    self.lexer.result_symbol = result
    return true
  }
  false
}

///|
fn HsEnv::valid(self : HsEnv, s : Int32) -> Bool {
  self.symbols[s]
}

// --------------------------------------------------------------------------------------------------------
// Symbol constructors
// --------------------------------------------------------------------------------------------------------

///|
fn hs_finish(s : Int32, _desc : String) -> Int32 {
  s
}

///|
fn HsEnv::finish_if_valid(self : HsEnv, s : Int32, desc : String) -> Int32 {
  if self.valid(s) {
    return hs_finish(s, desc)
  }
  HS_FAIL
}

///|
fn HsEnv::finish_marked(self : HsEnv, s : Int32, desc : String) -> Int32 {
  self.mark(desc)
  s
}

///|
fn hs_update_state(desc : String) -> Int32 {
  hs_finish(HS_UPDATE, desc)
}

// --------------------------------------------------------------------------------------------------------
// Lookahead
// --------------------------------------------------------------------------------------------------------

///|
/// Ensure that at least `abs + 1` characters are present in the lookahead
/// buffer by calling `advance` `len - abs + 1` times.
fn HsEnv::advance_over_abs(self : HsEnv, abs : Int32) -> Unit {
  let mut i = self.state.lookahead.contents.length()
  while i <= abs {
    self.advance()
    i += 1
  }
}

///|
/// Ensure that at least `rel` characters after and including the current
/// `offset` are present in the lookahead buffer.
fn HsEnv::advance_over(self : HsEnv, rel : Int32) -> Unit {
  self.advance_over_abs(self.state.lookahead.offset + rel)
}

///|
/// Skip whitespace relative to `offset`, but keep characters that have
/// already been copied to the buffer.
fn HsEnv::skip_over(self : HsEnv, rel : Int32) -> Unit {
  let l = self.state.lookahead
  // Subtraction is safe because the condition establishes that `offset` is at least 1
  if l.offset > l.contents.length() {
    self.advance_over_abs(l.offset - 1)
  }
  let abs = l.offset + rel
  let mut i = self.state.lookahead.contents.length()
  while i <= abs {
    self.skip()
    i += 1
  }
}

///|
/// Ensure that the lookahead buffer is large enough to allow reading the
/// `n`th character.
fn HsEnv::advance_before(self : HsEnv, rel : Int32) -> Unit {
  let abs = self.state.lookahead.offset + rel
  if abs > 0 {
    self.advance_over_abs(abs - 1)
  }
}

///|
/// Return the lookahead character with index `n`.
/// If the index is larger than the lookahead buffer, return 0.
fn HsEnv::unsafe_peek_abs(self : HsEnv, abs : Int32) -> Int32 {
  if abs < self.state.lookahead.contents.length() {
    self.state.lookahead.contents[abs]
  } else {
    0
  }
}

///|
/// Return the lookahead character with index `offset + n`.
fn HsEnv::unsafe_peek(self : HsEnv, rel : Int32) -> Int32 {
  self.unsafe_peek_abs(self.state.lookahead.offset + rel)
}

///|
/// Return the lookahead character with index `offset + rel`.
/// If the character is not accessible, advance the position until it is.
fn HsEnv::peek(self : HsEnv, rel : Int32) -> Int32 {
  if self.state.lookahead.offset + rel < self.state.lookahead.contents.length() {
    self.unsafe_peek(rel)
  } else {
    self.advance_before(rel)
    self.peek_lexer()
  }
}

///|
fn HsEnv::peek0(self : HsEnv) -> Int32 {
  self.peek(0)
}

///|
fn HsEnv::peek1(self : HsEnv) -> Int32 {
  self.peek(1)
}

///|
fn HsEnv::peek2(self : HsEnv) -> Int32 {
  self.peek(2)
}

///|
/// Test the lookahead character at index `offset + n` for equality.
fn HsEnv::char_at(self : HsEnv, n : Int32, c : Int32) -> Bool {
  self.peek(n) == c
}

///|
fn HsEnv::char0(self : HsEnv, c : Int32) -> Bool {
  self.char_at(0, c)
}

///|
fn HsEnv::char1(self : HsEnv, c : Int32) -> Bool {
  self.char_at(1, c)
}

///|
fn HsEnv::char2(self : HsEnv, c : Int32) -> Bool {
  self.char_at(2, c)
}

///|
/// Set the offset to `index`, so that the indexes in future calls to
/// lookahead functions like `char0` are interpreted relative to this new
/// value. Resets `symop` for soundness.
fn HsEnv::reset_lookahead_abs(self : HsEnv, abs : Int32) -> Unit {
  self.state.lookahead.offset = abs
  self.symop = 0
}

///|
fn HsEnv::reset_lookahead_to(self : HsEnv, rel : Int32) -> Unit {
  self.reset_lookahead_abs(self.state.lookahead.offset + rel)
}

///|
/// Move `offset` to the end of the consumed lookahead.
fn HsEnv::reset_lookahead(self : HsEnv) -> Unit {
  self.reset_lookahead_abs(self.state.lookahead.contents.length())
}

///|
/// Return whether the lookahead position has been advanced since starting the
/// run, not considering skipped characters.
fn HsEnv::no_lookahead(self : HsEnv) -> Bool {
  self.state.lookahead.contents.length() == 0
}

///|
/// Return the column of the first lookahead character of the current run
/// (`uint32_t` arithmetic).
fn HsEnv::start_column(self : HsEnv) -> UInt32 {
  self.column() - self.state.lookahead.contents.length().reinterpret_as_uint()
}

///|
/// Increment `i` while the predicate is true for the lookahead character at
/// that index (relative to `offset`), advancing the position when `i` points
/// beyond the end of the lookahead buffer.
fn HsEnv::advance_while(
  self : HsEnv,
  i : Int32,
  pred : (Int32) -> Bool,
) -> Int32 {
  let mut i = i
  while pred(self.peek(i)) {
    i += 1
  }
  i
}

///|
/// Same as `advance_while`, using "not equal to `c`" for the predicate.
/// Stops at EOF.
fn HsEnv::advance_until_char(self : HsEnv, i : Int32, c : Int32) -> Int32 {
  let mut i = i
  while self.not_eof() && !self.char_at(i, c) {
    i += 1
  }
  i
}

// --------------------------------------------------------------------------------------------------------
// Context manipulation and conditions
// --------------------------------------------------------------------------------------------------------

///|
fn HsEnv::has_contexts(self : HsEnv) -> Bool {
  self.state.contexts.length() != 0
}

///|
/// Push a layout context onto the stack.
fn HsEnv::push_context(self : HsEnv, sort : Int32, indent : UInt32) -> Unit {
  self.state.contexts.push({ sort, indent, })
}

///|
/// Remove a layout context from the stack.
fn HsEnv::pop(self : HsEnv) -> Unit {
  if self.has_contexts() {
    self.state.contexts.pop() |> ignore
  }
}

///|
fn HsEnv::current_context(self : HsEnv) -> Int32 {
  if self.has_contexts() {
    self.state.contexts[self.state.contexts.length() - 1].sort
  } else {
    HS_NO_CONTEXT
  }
}

///|
fn HsEnv::is_layout_context(self : HsEnv) -> Bool {
  self.current_context() < HS_BRACES
}

///|
/// Decide whether the current context requires generation of layout
/// semicolons.
fn HsEnv::is_semicolon_context(self : HsEnv) -> Bool {
  self.current_context() < HS_MULTI_WAY_IF_LAYOUT
}

///|
/// Return the indent of the innermost layout context.
/// If there are non-layout contexts at the top of the stack, search downwards.
fn HsEnv::current_indent(self : HsEnv) -> UInt32 {
  let mut i = self.state.contexts.length() - 1
  while i >= 0 {
    let cur = self.state.contexts[i]
    if cur.sort < HS_BRACES {
      return cur.indent
    }
    i -= 1
  }
  0
}

///|
fn HsEnv::indent_less(self : HsEnv, indent : UInt32) -> Bool {
  self.is_layout_context() && indent < self.current_indent()
}

///|
fn HsEnv::indent_lesseq(self : HsEnv, indent : UInt32) -> Bool {
  self.is_layout_context() && indent <= self.current_indent()
}

///|
fn HsEnv::top_layout(self : HsEnv) -> Bool {
  self.state.contexts.length() == 1
}

///|
fn HsEnv::in_module_header(self : HsEnv) -> Bool {
  self.current_context() == HS_MODULE_HEADER
}

///|
/// Return the appropriate symbol to close the given context, or FAIL if it
/// can't be closed.
fn hs_context_end_sym(s : Int32) -> Int32 {
  match s {
    HS_TEXP => HS_END_TEXP
    HS_BRACES => HS_END_BRACE
    _ => if s < HS_BRACES { HS_END } else { HS_FAIL }
  }
}

// --------------------------------------------------------------------------------------------------------
// Character and lookahead conditions
// --------------------------------------------------------------------------------------------------------

///|
/// `NEWLINE_CASES`.
fn hs_is_newline(c : Int32) -> Bool {
  match c {
    '\n' | '\r' | '\u{0C}' => true
    _ => false
  }
}

///|
fn hs_varid_start_char(c : Int32) -> Bool {
  c == '_' || hs_is_varid_start_char(c)
}

///|
fn hs_is_id_char(c : Int32) -> Bool {
  c == '_' || c == '\'' || hs_is_identifier_char(c)
}

///|
fn hs_is_inner_id_char(c : Int32) -> Bool {
  hs_is_id_char(c) || c == '#'
}

///|
fn hs_quoter_char(c : Int32) -> Bool {
  hs_is_id_char(c) || c == '.'
}

///|
fn hs_reserved_symbolic(c : Int32) -> Bool {
  match c {
    '(' | ')' | ',' | ';' | '[' | ']' | '`' | '{' | '}' | '"' | '\'' | '_' =>
      true
    _ => false
  }
}

///|
fn hs_symop_char(c : Int32) -> Bool {
  hs_is_symop_char(c) && !hs_reserved_symbolic(c)
}

///|
/// Advance the position to the first character that's not valid for a
/// symbolic operator, and return that position. If the function has been
/// called before, directly return the cached position.
fn HsEnv::symop_lookahead(self : HsEnv) -> Int32 {
  if self.symop == 0 {
    self.symop = self.advance_while(0, hs_symop_char)
  }
  self.symop
}

///|
fn HsEnv::is_symop(self : HsEnv) -> Bool {
  self.symop_lookahead() > 0
}

///|
/// The parser calls `scan` with all symbols declared as valid directly after
/// it encountered an error.
fn HsEnv::after_error(self : HsEnv) -> Bool {
  self.valid(HS_FAIL)
}

// --------------------------------------------------------------------------------------------------------
// Lookahead
// --------------------------------------------------------------------------------------------------------

///|
/// Check if lookahead contains the string `s` starting at position
/// `offset + start`. This advances only over matching characters.
/// (`s` is ASCII, so its UTF-16 code units are the C `char`s.)
fn HsEnv::seq_from(self : HsEnv, s : String, start : Int32) -> Bool {
  let len = s.length()
  for i in 0..<len {
    let c = s[i].to_int()
    let c2 = self.peek(start + i)
    if c != c2 {
      return false
    }
  }
  self.peek(start + len) |> ignore
  true
}

///|
/// Check if lookahead contains the string `s` starting at position `offset`.
fn HsEnv::seq(self : HsEnv, s : String) -> Bool {
  self.seq_from(s, 0)
}

///|
/// Advance until the next newline or EOF, used to consume the body of a
/// comment.
fn HsEnv::take_line(self : HsEnv) -> Unit {
  while self.not_eof() && !hs_is_newline(self.peek_lexer()) {
    self.advance()
  }
}

///|
fn hs_is_space_or_tab(c : Int32) -> Bool {
  c == ' ' || c == '\t'
}

///|
/// Advance until the next newline or EOF, used to consume the body of a cpp
/// directive. Escaped newlines are treated as line continuations, which allow
/// spaces and tabs between backslash and newline.
fn HsEnv::take_line_escaped_newline(self : HsEnv) -> Unit {
  while true {
    while self.not_eof() &&
          !hs_is_newline(self.peek_lexer()) &&
          self.peek_lexer() != '\\' {
      self.advance()
    }
    if self.peek_lexer() == '\\' {
      self.advance()
      if hs_is_space_or_tab(self.peek_lexer()) {
        while hs_is_space_or_tab(self.peek_lexer()) {
          self.advance()
        }
        if hs_is_newline(self.peek_lexer()) {
          self.advance()
        }
      } else {
        self.advance()
      }
    } else {
      return
    }
  }
}

///|
/// Skip the lexer until the following character is neither space nor tab.
/// Return whether any characters were skipped.
fn HsEnv::skip_space(self : HsEnv) -> Bool {
  if !hs_is_space_char(self.peek_lexer()) {
    return false
  }
  self.skip()
  while hs_is_space_char(self.peek_lexer()) {
    self.skip()
  }
  true
}

///|
/// Skip the lexer until the following character is not a newline.
/// Return whether any characters were skipped.
fn HsEnv::skip_newlines(self : HsEnv) -> Bool {
  if !hs_is_newline(self.peek_lexer()) {
    return false
  }
  self.skip()
  while hs_is_newline(self.peek_lexer()) {
    self.skip()
  }
  true
}

///|
/// `Space`.
const HS_NO_SPACE : Int32 = 0

///|
const HS_INDENTED : Int32 = 1

///|
const HS_BOL : Int32 = 2

///|
/// Alternate between skipping space and newlines, and return which was seen
/// last.
fn HsEnv::skip_whitespace(self : HsEnv) -> Int32 {
  let mut space = HS_NO_SPACE
  while true {
    if self.skip_space() {
      space = HS_INDENTED
    } else if self.skip_newlines() {
      space = HS_BOL
    } else {
      return space
    }
  }
  space
}

///|
/// Advance the lexer until the following character is neither space nor tab,
/// starting at position `offset + start`, and return the index of the next
/// character.
fn HsEnv::take_space_from(self : HsEnv, start : Int32) -> Int32 {
  self.advance_while(start, hs_is_space_char)
}

///|
/// Ensure that the character after a keyword like `module` is not a character
/// that would change its meaning to be an identifier.
fn hs_token_end(c : Int32) -> Bool {
  !hs_is_inner_id_char(c)
}

///|
/// Check if lookahead contains the string `s` starting at position
/// `offset + start`, followed by a non-id character.
fn HsEnv::token_from(self : HsEnv, s : String, start : Int32) -> Bool {
  self.seq_from(s, start) && hs_token_end(self.peek(start + s.length()))
}

///|
/// `token_from` at the current offset.
fn HsEnv::token(self : HsEnv, s : String) -> Bool {
  self.seq(s) && hs_token_end(self.peek(s.length()))
}

///|
/// Check if lookahead contains any of the strings in `tokens` starting at
/// position `offset + start`, followed by a non-id character.
fn HsEnv::any_token_from(
  self : HsEnv,
  tokens : Array[String],
  start : Int32,
) -> Bool {
  for i in 0..<tokens.length() {
    if self.token_from(tokens[i], start) {
      return true
    }
  }
  false
}

///|
fn HsEnv::match_symop(self : HsEnv, target : String) -> Bool {
  self.symop_lookahead() == target.length() && self.seq(target)
}

///|
fn HsEnv::uninitialized(self : HsEnv) -> Bool {
  !self.has_contexts()
}

///|
fn HsEnv::conid(self : HsEnv) -> Int32 {
  if !hs_is_conid_start_char(self.peek0()) {
    return 0
  }
  self.advance_while(1, hs_is_inner_id_char)
}

///|
/// `QualifiedName`.
const HS_NO_QUALIFIED_NAME : Int32 = 0

///|
const HS_QUALIFIED_TARGET : Int32 = 1

///|
const HS_QUALIFIED_CONID : Int32 = 2

///|
fn HsEnv::qualified_name(self : HsEnv, name : (HsEnv) -> Bool) -> Int32 {
  let mut qualified = false
  while true {
    let end = self.conid()
    if end == 0 {
      break
    }
    if !self.char_at(end, '.') {
      if qualified {
        return HS_QUALIFIED_CONID
      } else {
        break
      }
    }
    qualified = true
    self.reset_lookahead_to(end + 1)
    if name(self) {
      // `return true;`
      return HS_QUALIFIED_TARGET
    }
  }
  HS_NO_QUALIFIED_NAME
}

///|
/// Use the lookahead buffer to determine whether a character is escaped, by
/// counting the number of backslashes.
fn HsEnv::odd_backslashes_before(self : HsEnv, index : Int32) -> Bool {
  let mut index = index
  let mut odd = false
  while index >= 0 && self.peek(index) == '\\' {
    odd = !odd
    index -= 1
  }
  odd
}

///|
/// Advance before the next unescaped double quote.
fn HsEnv::take_string_literal(self : HsEnv) -> Int32 {
  let mut end = 1
  while true {
    end = self.advance_until_char(end, '"') + 1
    if self.is_eof() || !self.odd_backslashes_before(end - 2) {
      return end
    }
  }
  end
}

///|
/// Advance before the single quote that validly ends a character literal.
/// If there is none, return 1.
fn HsEnv::take_char_literal(self : HsEnv) -> Int32 {
  if self.char1('\\') {
    self.advance_until_char(2, '\'') + 2
  } else if self.char_at(2, '\'') {
    3
  } else {
    1
  }
}

// --------------------------------------------------------------------------------------------------------
// Lookahead: CPP
// --------------------------------------------------------------------------------------------------------

///|
/// `CppDirective`.
const HS_CPP_NOTHING : Int32 = 0

///|
const HS_CPP_START : Int32 = 1

///|
const HS_CPP_ELSE : Int32 = 2

///|
const HS_CPP_END : Int32 = 3

///|
const HS_CPP_OTHER : Int32 = 4

///|
let hs_cpp_tokens_start : Array[String] = ["if", "ifdef", "ifndef"]

///|
fn HsEnv::cpp_cond_start(self : HsEnv, start : Int32) -> Bool {
  self.any_token_from(hs_cpp_tokens_start, start)
}

///|
let hs_cpp_tokens_else : Array[String] = ["else", "elif", "elifdef", "elifndef"]

///|
fn HsEnv::cpp_cond_else(self : HsEnv, start : Int32) -> Bool {
  self.any_token_from(hs_cpp_tokens_else, start)
}

///|
fn HsEnv::cpp_cond_end(self : HsEnv, start : Int32) -> Bool {
  self.token_from("endif", start)
}

///|
let hs_cpp_tokens_other : Array[String] = [
  "define", "undef", "include", "pragma", "error", "warning", "line",
]

///|
fn HsEnv::cpp_directive_other(self : HsEnv, start : Int32) -> Bool {
  self.any_token_from(hs_cpp_tokens_other, start) ||
  // A hash followed by nothing but whitespace is CPP.
  // If non-whitespace follows whitespace, it is a parse error, unless we're in a brace layout; then it is a varsym.
  // Complete overkill to parse this, but eh!
  hs_is_newline(self.peek(start)) ||
  // shebang for scripts
  (self.char1('!') && self.uninitialized())
}

///|
/// If the first character at `offset` is a hash, skip space and try all
/// tokens that start a CPP directive.
fn HsEnv::cpp_directive(self : HsEnv) -> Int32 {
  if !self.char0('#') {
    return HS_CPP_NOTHING
  }
  let start = self.take_space_from(1)
  if self.cpp_cond_start(start) {
    HS_CPP_START
  } else if self.cpp_cond_else(start) {
    HS_CPP_ELSE
  } else if self.cpp_cond_end(start) {
    HS_CPP_END
  } else if self.cpp_directive_other(start) {
    HS_CPP_OTHER
  } else {
    HS_CPP_NOTHING
  }
}

// --------------------------------------------------------------------------------------------------------
// Starting layouts
// --------------------------------------------------------------------------------------------------------

///|
/// Opening and closing braces are always followed by a command, so this can
/// unconditionally push a context.
fn HsEnv::start_brace(self : HsEnv) -> Int32 {
  if self.valid(HS_START_BRACE) {
    self.push_context(HS_BRACES, 0)
    return hs_finish(HS_START_BRACE, "start_brace")
  }
  HS_FAIL
}

///|
/// See `start_brace`.
fn HsEnv::end_brace(self : HsEnv) -> Int32 {
  if self.valid(HS_END_BRACE) && self.current_context() == HS_BRACES {
    self.pop()
    return hs_finish(HS_END_BRACE, "end_brace")
  }
  HS_FAIL
}

///|
/// Return the first valid layout start symbol.
fn HsEnv::valid_layout_start_sym(self : HsEnv) -> Int32 {
  for i = HS_START; i < HS_END; i = i + 1 {
    if self.valid(i) {
      return i
    }
  }
  HS_FAIL
}

///|
/// Map `Symbol` to `ContextSort`.
fn hs_layout_sort(s : Int32) -> Int32 {
  match s {
    HS_START_DO => HS_DO_LAYOUT
    HS_START_CASE => HS_CASE_LAYOUT
    HS_START_IF => HS_MULTI_WAY_IF_LAYOUT
    HS_START_LET => HS_LET_LAYOUT
    HS_START_QUOTE => HS_QUOTE_LAYOUT
    _ => HS_DECL_LAYOUT
  }
}

///|
/// `StartLayout`.
priv struct HsStartLayout {
  mut sym : Int32
  mut sort : Int32
}

///|
/// Determine whether the layout sort corresponding to the potentially valid
/// symbol can start at this position.
fn HsEnv::valid_layout_start(self : HsEnv, next : Int32) -> HsStartLayout {
  let start : HsStartLayout = {
    sym: self.valid_layout_start_sym(),
    sort: HS_NO_CONTEXT,
  }
  if self.uninitialized() || start.sym == HS_FAIL {
    return start
  }
  let mut sort = hs_layout_sort(start.sym)
  match next {
    HS_L_BAR => ()
    HS_L_BRACE_OPEN => {
      if self.newline_active() {
        return start
      }
      sort = HS_BRACES
      start.sym = HS_START_EXPLICIT
    }
    _ => if sort == HS_MULTI_WAY_IF_LAYOUT { return start }
  }
  start.sort = sort
  start
}

///|
/// If the current context is a brace layout, any indent is legal for a new
/// layout. Otherwise, compare with the indent of the current context.
fn HsEnv::indent_can_start_layout(
  self : HsEnv,
  sort : Int32,
  indent : UInt32,
) -> Bool {
  if self.current_context() == HS_BRACES {
    return true
  }
  let cur = self.current_indent()
  indent > cur || (indent == cur && sort == HS_DO_LAYOUT)
}

///|
/// Start the given layout if the position allows it.
fn HsEnv::start_layout(
  self : HsEnv,
  start : HsStartLayout,
  indent : UInt32,
  desc : String,
) -> Int32 {
  if self.in_module_header() {
    self.pop()
  } else if start.sort == HS_BRACES {
    self.mark("start_layout brace")
  } else if !self.indent_can_start_layout(start.sort, indent) {
    return HS_FAIL
  }
  self.push_context(start.sort, indent)
  hs_finish(start.sym, desc)
}

///|
/// The indent of a layout started at an interior token can only be determined
/// by calling `get_column`.
fn HsEnv::start_layout_interior(self : HsEnv, next : Int32) -> Int32 {
  let start = self.valid_layout_start(next)
  if start.sort == HS_NO_CONTEXT {
    return HS_FAIL
  }
  self.start_layout(start, self.start_column(), "interior")
}

///|
/// The indent of a layout started at the beginning of a line is determined by
/// `newline_lookahead`, so this does not have to compute it.
fn HsEnv::start_layout_newline(self : HsEnv) -> Int32 {
  let start = self.valid_layout_start(self.state.newline.end)
  if start.sort == HS_NO_CONTEXT {
    return HS_FAIL
  }
  let result = self.start_layout(start, self.state.newline.indent, "newline")
  if result != HS_FAIL {
    self.state.newline.no_semi = true
  }
  result
}

///|
/// See `token_end_layout_texp`.
fn HsEnv::texp_context(self : HsEnv) -> Int32 {
  if self.valid(HS_START_TEXP) {
    self.push_context(HS_TEXP, 0)
    hs_finish(HS_START_TEXP, "texp_context")
  } else if self.valid(HS_END_TEXP) && self.current_context() == HS_TEXP {
    self.pop()
    hs_finish(HS_END_TEXP, "texp_context")
  } else {
    HS_FAIL
  }
}

// --------------------------------------------------------------------------------------------------------
// Ending layouts
// --------------------------------------------------------------------------------------------------------

///|
fn HsEnv::end_layout_unchecked(self : HsEnv, desc : String) -> Int32 {
  self.pop()
  hs_finish(HS_END, desc)
}

///|
/// If a layout end is valid at this position, pop a context and succeed with
/// layout end.
fn HsEnv::end_layout(self : HsEnv, desc : String) -> Int32 {
  if self.valid(HS_END) {
    self.end_layout_unchecked(desc)
  } else {
    HS_FAIL
  }
}

///|
/// Explicit brace layouts need a dedicated symbol. Includes the brace in the
/// range.
fn HsEnv::end_layout_brace(self : HsEnv) -> Int32 {
  if self.valid(HS_END_EXPLICIT) && self.current_context() == HS_BRACES {
    self.advance_over(0)
    self.mark("end_layout_brace")
    self.pop()
    hs_finish(HS_END_EXPLICIT, "brace")
  } else {
    HS_FAIL
  }
}

///|
/// End a layout based on indent decrease.
fn HsEnv::end_layout_indent(self : HsEnv) -> Int32 {
  if self.valid(HS_END) && self.indent_less(self.state.newline.indent) {
    if self.top_layout() {
      self.state.contexts[self.state.contexts.length() - 1].indent = self.state.newline.indent
      return hs_update_state("end top layout")
    } else {
      self.state.newline.skip_semi = false
      return self.end_layout_unchecked("indent")
    }
  }
  HS_FAIL
}

///|
/// An expression layout may be closed by an infix operator when it is not
/// valid at that position.
fn HsEnv::end_layout_infix(self : HsEnv) -> Int32 {
  if !self.valid(HS_VARSYM) && !self.valid(HS_CONSYM) {
    return self.end_layout("symop invalid")
  }
  HS_FAIL
}

///|
/// End any layout when `where` is parsed, but invalid.
fn HsEnv::end_layout_where(self : HsEnv) -> Int32 {
  if self.valid(HS_END) && !self.valid(HS_WHERE) && self.is_layout_context() {
    return self.end_layout("where")
  }
  HS_FAIL
}

///|
/// If `in` is not valid (i.e. a parse error), we pop any layout.
fn HsEnv::end_layout_in(self : HsEnv) -> Int32 {
  if self.valid(HS_END) &&
    (!self.valid(HS_IN) || self.current_context() == HS_LET_LAYOUT) {
    return self.end_layout("in")
  }
  HS_FAIL
}

///|
/// For GADT constructor layouts.
fn HsEnv::end_layout_deriving(self : HsEnv) -> Int32 {
  if self.valid(HS_END) &&
    !self.valid(HS_DERIVING) &&
    !self.top_layout() &&
    self.current_context() == HS_DECL_LAYOUT {
    return self.end_layout("deriving")
  }
  HS_FAIL
}

///|
/// Return `true` if there is a `TExp` context on the stack and only layouts
/// above it.
fn HsEnv::layouts_in_texp(self : HsEnv) -> Bool {
  if self.is_layout_context() && self.state.contexts.length() > 1 {
    let mut i = self.state.contexts.length() - 2
    while i >= 0 {
      let cur = self.state.contexts[i]
      if cur.sort == HS_TEXP || cur.sort == HS_BRACES {
        return true
      } else if cur.sort > HS_BRACES {
        break
      }
      i -= 1
    }
  }
  false
}

///|
/// Expression layouts can be closed by commas, vertical bars and closing
/// brackets and parens when they are elements in a list or tuple-like
/// construct.
fn HsEnv::token_end_layout_texp(self : HsEnv) -> Int32 {
  if self.valid(HS_END) && self.layouts_in_texp() {
    self.end_layout("texp")
  } else {
    HS_FAIL
  }
}

///|
fn HsEnv::force_end_context(self : HsEnv) -> Int32 {
  let mut i = self.state.contexts.length() - 1
  while i >= 0 {
    let ctx = self.state.contexts[i].sort
    let s = hs_context_end_sym(ctx)
    self.pop()
    if s != HS_FAIL && self.valid(s) {
      return hs_finish(s, "force_end_context")
    }
    i -= 1
  }
  HS_FAIL
}

// --------------------------------------------------------------------------------------------------------
// Operators
// --------------------------------------------------------------------------------------------------------

///|
/// Opening tokens are a class of characters that may immediately follow
/// prefix operators like bang pattern `!` or type application `@`.
fn HsEnv::opening_token(self : HsEnv, i : Int32) -> Bool {
  let c = self.peek(i)
  match c {
    0x27e6 | 0x2987 | '(' | '[' | '"' => true // ⟦ ⦇
    '{' => self.peek(i + 1) != '-'
    // Includes single quote
    _ => hs_is_id_char(c)
  }
}

///|
/// Test for reserved operators of two characters.
fn hs_valid_symop_two_chars(first_char : Int32, second_char : Int32) -> Bool {
  match first_char {
    '=' => second_char != '>'
    '<' => second_char != '-'
    ':' => second_char != ':'
    _ => true
  }
}

///|
/// If a prefix operator is not followed by an opening token, it may still be
/// a valid varsym.
fn HsEnv::lex_prefix(self : HsEnv, t : Int32) -> Int32 {
  if self.opening_token(1) {
    t
  } else {
    HS_L_SYMOP
  }
}

///|
/// If a splice operator is not followed by an opening token, it may still be
/// a valid varsym.
fn hs_lex_splice(c : Int32) -> Int32 {
  if hs_varid_start_char(c) || c == '(' {
    HS_L_DOLLAR
  } else {
    HS_L_SYMOP
  }
}

///|
/// Lex special occurrences of symbolic operator characters, or declare a
/// valid operator.
fn HsEnv::lex_symop(self : HsEnv) -> Int32 {
  let len = self.symop_lookahead()
  if len == 0 {
    return HS_L_NOTHING
  }
  let c1 = self.unsafe_peek(0)
  if len == 1 {
    match c1 {
      // A `?` can be the head of an implicit parameter, if followed by a varid.
      '?' =>
        return if hs_varid_start_char(self.peek1()) {
          HS_L_NOTHING
        } else {
          HS_L_SYMOP
        }
      '#' => return if self.char1(')') { HS_L_UNBOXED_CLOSE } else { HS_L_HASH }
      '|' => return if self.char1(']') { HS_L_QUOTE_CLOSE } else { HS_L_BAR }
      '!' => return self.lex_prefix(HS_L_BANG)
      '~' => return self.lex_prefix(HS_L_TILDE)
      '@' => return self.lex_prefix(HS_L_AT)
      '%' => return self.lex_prefix(HS_L_PERCENT)
      '$' => return hs_lex_splice(self.peek1())
      '.' =>
        if hs_is_id_char(self.peek1()) {
          return HS_L_DOT_ID
        } else if self.opening_token(1) {
          return HS_L_DOT_OPEN
        } else {
          return HS_L_SYMOP
        }
      0x2192 | 0x22b8 => return HS_L_ARROW // → ⊸
      0x21d2 => return HS_L_C_ARROW // ⇒
      '=' | 0x27e7 | 0x2988 => return HS_L_TEXP_CLOSER // ⟧ ⦈
      '*' | '-' => return HS_L_SYMOP_SPECIAL
      // \ ← ∀ ∷ ★ ⟦ ⤙ ⤚ ⤛ ⤜ ⦇
      '\\'
      | 0x2190
      | 0x2200
      | 0x2237
      | 0x2605
      | 0x27e6
      | 0x2919
      | 0x291a
      | 0x291b
      | 0x291c
      | 0x2987 => return HS_L_NOTHING
      _ => ()
    }
  } else if len == 2 {
    if self.seq("->") {
      return HS_L_ARROW
    }
    if self.seq("=>") {
      return HS_L_C_ARROW
    }
    let c2 = self.unsafe_peek(1)
    match c1 {
      '$' => if c2 == '$' { return hs_lex_splice(self.peek2()) }
      '|' => if c2 == '|' && self.char2(']') { return HS_L_QUOTE_CLOSE }
      '.' => if c2 == '.' { return HS_L_DOT_DOT } else { return HS_L_DOT_SYMOP }
      // Unboxed unit `(##)` and unboxed sum with missing space `(#| Int #)`
      '#' => if c2 == '#' || c2 == '|' { return HS_L_SYMOP_SPECIAL }
      _ => if !hs_valid_symop_two_chars(c1, c2) { return HS_L_NOTHING }
    }
  } else {
    match c1 {
      '-' => if self.seq("->.") { return HS_L_ARROW }
      '.' => return HS_L_DOT_SYMOP
      _ => ()
    }
  }
  HS_L_SYMOP
}

///|
/// If the next character after whitespace starting from `start` is a closing
/// parenthesis, finish with `LEFT_SECTION_OP`.
fn HsEnv::left_section_op(self : HsEnv, start : Int32) -> Int32 {
  if self.valid(HS_LEFT_SECTION_OP) {
    self.advance_before(start)
    let space = self.skip_whitespace()
    if self.char_at(start, ')') {
      return hs_finish(HS_LEFT_SECTION_OP, "left section")
    }
    if space != HS_NO_SPACE {
      return self.finish_if_valid(HS_NO_SECTION_OP, "left section")
    }
  }
  HS_FAIL
}

///|
/// Specialization of `left_section_op` for ticked infix identifiers.
fn HsEnv::left_section_ticked(self : HsEnv) -> Int32 {
  if self.valid(HS_LEFT_SECTION_OP) {
    let end_tick = self.advance_until_char(1, '`')
    // Could be EOF
    if self.char_at(end_tick, '`') {
      return self.left_section_op(end_tick + 1)
    }
  }
  HS_FAIL
}

///|
/// This calls `symop_lookahead` to ensure that the position has advanced
/// beyond the end of the symop. This marks the range to emit a terminal.
fn HsEnv::finish_symop(self : HsEnv, s : Int32) -> Int32 {
  if self.valid(s) || self.valid(HS_LEFT_SECTION_OP) {
    let after_symop = self.symop_lookahead()
    let res = self.left_section_op(after_symop)
    if res != 0 {
      return res
    }
    self.mark("symop")
    return s
  }
  HS_FAIL
}

///|
/// Tight ops like `dot.syntax` require that no initial whitespace was skipped.
fn HsEnv::tight_op(self : HsEnv, whitespace : Bool, s : Int32) -> Int32 {
  if !whitespace {
    self.finish_if_valid(s, "tight_op")
  } else {
    HS_FAIL
  }
}

///|
/// Only used for `%` (modifier).
fn HsEnv::prefix_or_varsym(self : HsEnv, whitespace : Bool, s : Int32) -> Int32 {
  if whitespace {
    let res = self.finish_if_valid(s, "prefix_or_varsym")
    if res != 0 {
      return res
    }
  }
  self.finish_symop(HS_VARSYM)
}

///|
/// Only used for `.`, when a projection selector `(.fieldname)` is not valid
/// at this position, so the dot becomes the composition operator.
fn HsEnv::tight_or_varsym(self : HsEnv, whitespace : Bool, s : Int32) -> Int32 {
  let res = self.tight_op(whitespace, s)
  if res != 0 {
    return res
  }
  self.finish_symop(HS_VARSYM)
}

///|
/// Used for `!`, `~` and `@`.
fn HsEnv::infix_or_varsym(
  self : HsEnv,
  whitespace : Bool,
  prefix : Int32,
  tight : Int32,
) -> Int32 {
  let res = self.finish_if_valid(
    if whitespace {
      prefix
    } else {
      tight
    },
    "infix_or_varsym",
  )
  if res != 0 {
    return res
  }
  self.finish_symop(HS_VARSYM)
}

///|
fn HsEnv::qualified_op(self : HsEnv) -> Int32 {
  if self.qualified_name(HsEnv::is_symop) == HS_QUALIFIED_TARGET {
    let res = self.left_section_op(self.symop_lookahead())
    if res != 0 {
      return res
    }
    return HS_QUALIFIED_OP
  }
  HS_FAIL
}

// --------------------------------------------------------------------------------------------------------
// Token lookahead
// --------------------------------------------------------------------------------------------------------

///|
/// Detect the start of a quasiquote: An opening bracket followed by an
/// optional varid and a vertical bar, all without whitespace in between.
fn HsEnv::is_qq_start(self : HsEnv) -> Bool {
  let end = self.advance_while(1, hs_quoter_char)
  self.char_at(end, '|')
}

///|
/// An end token is a keyword like `else` or `deriving` that can end a layout
/// without newline or indent.
fn HsEnv::try_end_token(self : HsEnv, target : String, match_ : Int32) -> Int32 {
  if self.token(target) {
    match_
  } else {
    HS_L_NOTHING
  }
}

///|
/// Check that a symop consists only of minuses after the second character.
fn HsEnv::only_minus(self : HsEnv) -> Bool {
  let mut i = 2
  while self.peek(i) == '-' {
    i += 1
  }
  !hs_symop_char(self.peek(i))
}

///|
/// Check that a symop consists only of minuses, making it a comment herald.
fn HsEnv::line_comment_herald(self : HsEnv) -> Bool {
  self.seq("--") && self.only_minus()
}

///|
fn HsEnv::lex_cpp(self : HsEnv) -> Int32 {
  match self.cpp_directive() {
    HS_CPP_ELSE => HS_L_CPP_ELSE
    HS_CPP_NOTHING => HS_L_NOTHING
    _ => HS_L_CPP
  }
}

///|
/// Lex pragmas, comments and CPP.
fn HsEnv::lex_extras(self : HsEnv, bol : Bool) -> Int32 {
  match self.peek0() {
    '{' =>
      if self.char1('-') {
        return if self.char2('#') { HS_L_PRAGMA } else { HS_L_BLOCK_COMMENT }
      }
    '#' => if bol { return self.lex_cpp() }
    '-' => if self.line_comment_herald() { return HS_L_LINE_COMMENT }
    _ => ()
  }
  HS_L_NOTHING
}

///|
/// The main lexing entry point, branching on the first character, then
/// advancing as far as necessary to identify all interesting tokens.
fn HsEnv::lex(self : HsEnv, bol : Bool) -> Int32 {
  let res = self.lex_extras(bol)
  if res != 0 {
    return res
  }
  if hs_symop_char(self.peek0()) {
    let res = self.lex_symop()
    if res != 0 {
      return res
    }
  } else {
    match self.peek0() {
      'w' => return self.try_end_token("where", HS_L_WHERE)
      'i' => return self.try_end_token("in", HS_L_IN)
      't' => return self.try_end_token("then", HS_L_THEN)
      'e' => return self.try_end_token("else", HS_L_ELSE)
      'd' => return self.try_end_token("deriving", HS_L_DERIVING)
      'm' =>
        if (self.uninitialized() || self.in_module_header()) &&
          self.token("module") {
          return HS_L_MODULE
        }
      '{' => return HS_L_BRACE_OPEN
      '}' => return HS_L_BRACE_CLOSE
      ';' => return HS_L_SEMI
      '`' => return HS_L_TICK
      '[' =>
        if self.valid(HS_QQ_START) && self.is_qq_start() {
          return HS_L_BRACKET_OPEN
        }
      ']' | ')' | ',' => return HS_L_TEXP_CLOSER
      _ => if hs_is_conid_start_char(self.peek0()) { return HS_L_UPPER }
    }
  }
  HS_L_NOTHING
}

// --------------------------------------------------------------------------------------------------------
// CPP
// --------------------------------------------------------------------------------------------------------

///|
/// This tests for `#endif` directly after taking a line, so it only matches
/// it at the first column.
fn HsEnv::cpp_else(self : HsEnv, emit : Bool) -> Int32 {
  let mut nesting = 1
  while true {
    self.take_line_escaped_newline()
    if emit {
      self.mark("cpp_else")
    }
    self.advance()
    self.reset_lookahead()
    match self.cpp_directive() {
      HS_CPP_START => nesting += 1
      HS_CPP_END => nesting -= 1
      _ => ()
    }
    if !(self.not_eof() && nesting > 0) {
      break
    }
  }
  if emit {
    hs_finish(HS_CPP, "cpp-else")
  } else {
    HS_FAIL
  }
}

///|
fn HsEnv::cpp_line(self : HsEnv) -> Int32 {
  self.take_line_escaped_newline()
  self.finish_marked(HS_CPP, "cpp")
}

// --------------------------------------------------------------------------------------------------------
// Comments
// --------------------------------------------------------------------------------------------------------

///|
/// Distinguish between haddocks and plain comments by matching on the first
/// non-whitespace character.
fn HsEnv::comment_type(self : HsEnv) -> Int32 {
  let mut i = 2
  while self.peek(i) == '-' {
    i += 1
  }
  while self.not_eof() {
    let c = self.peek(i)
    i += 1
    if c == '|' || c == '^' {
      return HS_HADDOCK
    } else if !hs_is_space_char(c) {
      break
    }
  }
  HS_COMMENT
}

///|
/// Inline comments extend over all consecutive lines that start with
/// comments.
fn HsEnv::inline_comment(self : HsEnv) -> Int32 {
  let sym = self.comment_type()
  while true {
    self.take_line()
    self.mark("inline comment")
    self.advance()
    self.reset_lookahead()
    if !self.line_comment_herald() {
      break
    }
  }
  sym
}

///|
fn HsEnv::consume_block_comment(self : HsEnv, col : UInt32) -> UInt32 {
  let mut col = col
  let mut level : UInt32 = 0
  while true {
    if self.is_eof() {
      return col
    }
    col += 1
    match self.peek_lexer() {
      '{' => {
        self.advance()
        if self.peek_lexer() == '-' {
          self.advance()
          col += 1
          level += 1
        }
      }
      '-' => {
        self.advance()
        if self.peek_lexer() == '}' {
          self.advance()
          col += 1
          if level == 0 {
            return col
          }
          level -= 1
        }
      }
      '\n' | '\r' | '\u{0C}' => {
        self.advance()
        col = 0
      }
      '\t' => {
        self.advance()
        col += 7
      }
      _ => self.advance()
    }
  }
  col
}

///|
/// Since {- -} comments can be nested arbitrarily, this has to keep track of
/// how many have been opened, so that the outermost comment isn't closed
/// prematurely.
fn HsEnv::block_comment(self : HsEnv) -> Int32 {
  let sym = self.comment_type()
  self.consume_block_comment(
    self.state.lookahead.contents.length().reinterpret_as_uint(),
  )
  |> ignore
  self.finish_marked(sym, "block_comment")
}

// --------------------------------------------------------------------------------------------------------
// Pragma
// --------------------------------------------------------------------------------------------------------

///|
fn HsEnv::consume_pragma(self : HsEnv) -> Bool {
  if self.seq("{-#") {
    while !self.seq("#-}") && self.not_eof() {
      self.reset_lookahead()
      self.advance_over(0)
    }
    return true
  }
  false
}

///|
/// Pragmas set `NResume` to continue newline processing with the indent of
/// the pragma.
fn HsEnv::pragma(self : HsEnv) -> Int32 {
  if self.consume_pragma() {
    self.mark("pragma")
    if self.state.newline.state != HS_N_INACTIVE {
      self.state.newline.state = HS_N_RESUME
    }
    return hs_finish(HS_PRAGMA, "newline")
  }
  HS_FAIL
}

// --------------------------------------------------------------------------------------------------------
// Quasiquote
// --------------------------------------------------------------------------------------------------------

///|
fn HsEnv::qq_body(self : HsEnv) -> Int32 {
  while true {
    if self.is_eof() {
      return hs_finish(HS_QQ_BODY, "qq_body")
    } else if self.peek_lexer() == 0x27e7 {
      return self.finish_marked(HS_QQ_BODY, "qq_body")
    } else if self.peek_lexer() == '|' {
      self.mark("qq_body")
      self.advance()
      if self.peek_lexer() == ']' {
        return hs_finish(HS_QQ_BODY, "qq_body")
      }
    } else {
      self.advance()
    }
  }
  HS_FAIL
}

// --------------------------------------------------------------------------------------------------------
// Semicolon
// --------------------------------------------------------------------------------------------------------

///|
/// When encountering explicit semicolons, we want to ensure that a subsequent
/// newline doesn't trigger a layout semicolon, so we set `skip_semi`.
fn HsEnv::explicit_semicolon(self : HsEnv) -> Int32 {
  if self.valid(HS_SEMICOLON) && !self.state.newline.skip_semi {
    self.state.newline.skip_semi = true
    return hs_update_state("explicit semicolon enable")
  }
  HS_FAIL
}

///|
fn HsEnv::resolve_semicolon(self : HsEnv, next : Int32) -> Int32 {
  if self.state.newline.skip_semi {
    match next {
      HS_L_LINE_COMMENT | HS_L_BLOCK_COMMENT | HS_L_PRAGMA | HS_L_SEMI => ()
      _ => {
        self.state.newline.skip_semi = false
        return hs_update_state("explicit semicolon disable")
      }
    }
  }
  HS_FAIL
}

///|
/// Generate a layout semicolon after a newline if the indent is less or equal
/// to the current layout's indent, unless prohibited.
fn HsEnv::semicolon(self : HsEnv) -> Int32 {
  if self.is_semicolon_context() &&
    !(self.state.newline.no_semi || self.state.newline.skip_semi) &&
    self.indent_lesseq(self.state.newline.indent) {
    self.state.newline.no_semi = true
    hs_finish(HS_SEMICOLON, "newline")
  } else {
    HS_FAIL
  }
}

// --------------------------------------------------------------------------------------------------------
// High-level `Lexed` dispatch
// --------------------------------------------------------------------------------------------------------

///|
/// Process a `Lexed` token if it results in a layout end or an extra.
fn HsEnv::process_token_safe(self : HsEnv, next : Int32) -> Int32 {
  match next {
    HS_L_WHERE => return self.end_layout_where()
    HS_L_IN => return self.end_layout_in()
    HS_L_THEN | HS_L_ELSE => return self.end_layout("then/else")
    HS_L_DERIVING => return self.end_layout_deriving()
    HS_L_BAR => if !self.valid(HS_BAR) { return self.end_layout("bar") }
    HS_L_PRAGMA => return self.pragma()
    HS_L_BLOCK_COMMENT => return self.block_comment()
    HS_L_LINE_COMMENT => return self.inline_comment()
    HS_L_CPP_ELSE => return self.cpp_else(true)
    HS_L_CPP => return self.cpp_line()
    HS_L_SYMOP | HS_L_TICK | HS_L_HASH => return self.end_layout_infix()
    HS_L_UNBOXED_CLOSE => {
      let res = self.token_end_layout_texp()
      if res != 0 {
        return res
      }
      return self.end_layout_infix()
    }
    HS_L_ARROW =>
      if !self.valid(HS_ARROW) {
        return self.token_end_layout_texp()
      }
    HS_L_TEXP_CLOSER => return self.token_end_layout_texp()
    HS_L_QUOTE_CLOSE => return self.end_layout("quote bracket")
    _ => ()
  }
  HS_FAIL
}

///|
/// Process a `Lexed` token if it results in a symbolic operator.
fn HsEnv::process_token_symop(
  self : HsEnv,
  whitespace : Bool,
  next : Int32,
) -> Int32 {
  match next {
    HS_L_DOT_DOT => {
      let res = self.finish_if_valid(HS_DOTDOT, "symop")
      if res != 0 {
        return res
      }
      return self.tight_op(whitespace, HS_QUAL_DOT)
    }
    HS_L_DOT_ID => {
      let res = self.finish_if_valid(
        if whitespace {
          HS_PREFIX_DOT
        } else {
          HS_TIGHT_DOT
        },
        "symop",
      )
      if res != 0 {
        return res
      }
      return self.tight_op(whitespace, HS_QUAL_DOT)
    }
    HS_L_DOT_SYMOP => return self.tight_or_varsym(whitespace, HS_QUAL_DOT)
    HS_L_DOT_OPEN => return self.prefix_or_varsym(whitespace, HS_PREFIX_DOT)
    HS_L_BANG =>
      return self.infix_or_varsym(whitespace, HS_PREFIX_BANG, HS_TIGHT_BANG)
    HS_L_TILDE =>
      return self.infix_or_varsym(whitespace, HS_PREFIX_TILDE, HS_TIGHT_TILDE)
    HS_L_AT =>
      return self.infix_or_varsym(whitespace, HS_PREFIX_AT, HS_TIGHT_AT)
    HS_L_PERCENT => return self.prefix_or_varsym(whitespace, HS_PREFIX_PERCENT)
    HS_L_SYMOP =>
      if self.char0(':') {
        return self.finish_symop(HS_CONSYM)
      } else {
        return self.finish_symop(HS_VARSYM)
      }
    // The following are handled here despite not being purely symop tokens because `process_token_symop` is executed
    // last, and these handlers all have potentially quite far lookahead and can fail.
    HS_L_SYMOP_SPECIAL => {
      let res = self.left_section_op(self.symop_lookahead())
      if res != 0 {
        return res
      }
      if self.valid(HS_MINUS) && self.match_symop("-") {
        return hs_finish(HS_MINUS, "symop")
      }
    }
    HS_L_UNBOXED_CLOSE | HS_L_HASH =>
      return self.left_section_op(self.symop_lookahead())
    HS_L_TICK => return self.left_section_ticked()
    HS_L_UPPER =>
      if self.valid(HS_QUALIFIED_OP) || self.valid(HS_LEFT_SECTION_OP) {
        let res = self.qualified_op()
        if res != 0 {
          return res
        }
      }
    _ => ()
  }
  HS_FAIL
}

///|
fn HsEnv::process_token_splice(self : HsEnv, next : Int32) -> Int32 {
  match next {
    HS_L_DOLLAR => return self.finish_if_valid(HS_SPLICE, "symop")
    _ => ()
  }
  HS_FAIL
}

///|
/// Process a `Lexed` token for an interior position.
fn HsEnv::process_token_interior(self : HsEnv, next : Int32) -> Int32 {
  match next {
    HS_L_BRACE_CLOSE => {
      let res = self.end_layout_brace()
      if res != 0 {
        return res
      }
      return self.token_end_layout_texp()
    }
    // Skip layout start
    HS_L_MODULE => return HS_FAIL
    HS_L_SEMI => return self.explicit_semicolon()
    HS_L_BRACKET_OPEN => return hs_finish(HS_QQ_START, "qq_start")
    _ => ()
  }
  let res = self.process_token_safe(next)
  if res != 0 {
    return res
  }
  self.start_layout_interior(next)
}

///|
/// Process a `Lexed` token to initialize the context stack.
fn HsEnv::process_token_init(
  self : HsEnv,
  indent : UInt32,
  next : Int32,
) -> Int32 {
  match next {
    HS_L_MODULE => {
      self.push_context(HS_MODULE_HEADER, 0)
      hs_update_state("init")
    }
    HS_L_BRACE_OPEN => {
      self.advance_over(0)
      self.mark("init brace")
      self.push_context(HS_BRACES, indent)
      hs_finish(HS_START_EXPLICIT, "init")
    }
    _ => {
      self.push_context(HS_DECL_LAYOUT, indent)
      hs_finish(HS_START, "init")
    }
  }
}

// --------------------------------------------------------------------------------------------------------
// Newline actions
// --------------------------------------------------------------------------------------------------------

///|
/// `NoSpace` + `newline_init()` means that we're at the very beginning of the
/// file, where we start in `NResume` mode without a newline character that can
/// tell us where we are.
fn HsEnv::newline_extras(self : HsEnv, space : Int32) -> Int32 {
  let bol = space == HS_BOL || (space == HS_NO_SPACE && self.newline_init())
  let next = self.lex_extras(bol)
  self.process_token_safe(next)
}

///|
/// Don't finish newline processing before pragmas.
fn HsEnv::newline_process(self : HsEnv) -> Int32 {
  let indent = self.state.newline.indent
  let end = self.state.newline.end
  let res = self.end_layout_indent()
  if res != 0 {
    return res
  }
  let res = self.process_token_safe(end)
  if res != 0 {
    return res
  }
  let space = self.skip_whitespace()
  self.mark("newline_post")
  if self.state.newline.unsafe_ {
    let res = self.newline_extras(space)
    if res != 0 {
      return res
    }
  }
  if !self.state.newline.eof {
    let res = self.start_layout_newline()
    if res != 0 {
      return res
    }
  }
  // TODO it is only necessary to run this late because of very few situations, like nondecreasing indent.
  // But it has the consequence that whitespace is included in the parent in nested layouts.
  // Maybe there's a way to run it before and after `start_layout_newline` with conditions.
  let res = self.semicolon()
  if res != 0 {
    return res
  }
  self.reset_newline()
  if self.uninitialized() {
    let res = self.process_token_init(indent, end)
    if res != 0 {
      return res
    }
  } else {
    let res = self.process_token_symop(true, end)
    if res != 0 {
      return res
    }
    let res = self.process_token_splice(end)
    if res != 0 {
      return res
    }
  }
  hs_update_state("newline final")
}

///|
fn HsEnv::newline_post(self : HsEnv) -> Int32 {
  let res = self.newline_process()
  if self.newline_init() {
    self.state.newline.state = HS_N_PROCESS
  }
  res
}

///|
/// Repeatedly lex lookahead until encountering something that is neither a
/// comment nor CPP, skipping whitespace and newlines in between.
fn HsEnv::newline_lookahead(self : HsEnv, newline : HsNewline) -> Unit {
  while true {
    // Using `peek0` to look for whitespace requires the lookahead buffer to have been reset immediately before this
    // statement – so before the call to this function or at the end of the for loop body.
    match self.peek0() {
      '\n' | '\r' | '\u{0C}' => {
        self.skip_over(0)
        newline.indent = 0
      }
      '\t' => {
        self.skip_over(0)
        newline.indent += 8
      }
      _ =>
        if hs_is_space_char(self.peek0()) {
          self.skip_over(0)
          newline.indent += 1
        } else {
          newline.end = self.lex(newline.indent == 0)
          // Newlines without extras are only safe if `lex` didn't advance the lexer over non-whitespace.
          newline.unsafe_ = newline.unsafe_ || !self.no_lookahead()
          match newline.end {
            HS_L_EOF => {
              newline.indent = 0
              newline.eof = true
              return
            }
            // If/then blocks can have semicolons, but don't have a layout.
            // Allowing layout semicolons costs 100kB.
            HS_L_THEN | HS_L_ELSE | HS_L_SEMI => {
              newline.no_semi = true
              return
            }
            HS_L_BLOCK_COMMENT =>
              newline.indent = self.consume_block_comment(newline.indent + 2)
            HS_L_LINE_COMMENT => {
              newline.indent = 0
              self.take_line()
            }
            HS_L_CPP_ELSE => {
              self.cpp_else(false) |> ignore
              self.take_line_escaped_newline()
            }
            HS_L_CPP => self.take_line_escaped_newline()
            _ => return
          }
        }
    }
    self.reset_lookahead()
  }
}

///|
/// Perform newline lookahead, then either finish the run if the position was
/// advanced into the next token, or directly start newline processing if not.
fn HsEnv::newline_start(self : HsEnv) -> Int32 {
  self.state.newline.state = HS_N_INIT
  self.newline_lookahead(self.state.newline)
  if self.state.newline.unsafe_ {
    hs_update_state("newline lookahead")
  } else {
    self.newline_post()
  }
}

///|
/// Perform newline lookahead with preset indent, used at the beginning of a
/// file and after pragmas.
fn HsEnv::newline_resume(self : HsEnv) -> Int32 {
  let indent = self.state.newline.indent
  // Skip space between the pragma end and the next token, which might be the first real token (or another pragma or
  // comment, or newline).
  // We don't want to count the space as indent.
  self.skip_space() |> ignore
  self.reset_newline()
  self.state.newline.indent = indent
  self.newline_start()
}

// --------------------------------------------------------------------------------------------------------
// Constraints
// --------------------------------------------------------------------------------------------------------

///|
/// `CtrResult`: result of constraint lookahead.
const HS_CTR_UNDECIDED : Int32 = 0

///|
const HS_CTR_IMPOSSIBLE : Int32 = 1

///|
const HS_CTR_ARROW_FOUND : Int32 = 2

///|
const HS_CTR_INFIX_FOUND : Int32 = 3

///|
const HS_CTR_EQUALS_FOUND : Int32 = 4

///|
const HS_CTR_BAR_FOUND : Int32 = 5

///|
/// `CtrState`: constraint lookahead state.
priv struct HsCtrState {
  /// The amount of characters to skip after an iteration.
  mut reset : Int32
  /// The number of nested brackets.
  mut brackets : UInt32
  /// A context arrow was found.
  mut context : Bool
  /// An infix operator was found.
  mut infix : Bool
  mut data_infix : Bool
  mut type_instance : Bool
}

///|
/// Increment the bracket count.
fn hs_ctr_bracket_open(state : HsCtrState) -> Int32 {
  state.brackets += 1
  state.reset = 1
  HS_CTR_UNDECIDED
}

///|
/// Decrement the bracket count. If the count was zero already, parsing
/// started inside of brackets that are closed here, so lookahead is
/// terminated.
fn hs_ctr_bracket_close(state : HsCtrState) -> Int32 {
  if state.brackets == 0 {
    return HS_CTR_IMPOSSIBLE
  }
  state.brackets -= 1
  state.reset = 1
  HS_CTR_UNDECIDED
}

///|
/// If the given token is ahead, terminate lookahead unsuccessfully.
fn HsEnv::ctr_stop_on_token(self : HsEnv, target : String) -> Int32 {
  if self.token(target) {
    HS_CTR_IMPOSSIBLE
  } else {
    HS_CTR_UNDECIDED
  }
}

///|
/// Check if the lexed token is `=>` or an infix operator.
fn HsEnv::ctr_top(self : HsEnv, next : Int32) -> Int32 {
  match next {
    HS_L_C_ARROW => return HS_CTR_ARROW_FOUND
    HS_L_SYMOP | HS_L_SYMOP_SPECIAL | HS_L_TILDE | HS_L_TICK =>
      return HS_CTR_INFIX_FOUND
    HS_L_BAR => return HS_CTR_BAR_FOUND
    HS_L_ARROW | HS_L_WHERE | HS_L_DOT_DOT | HS_L_SEMI => ()
    HS_L_TEXP_CLOSER =>
      match self.peek0() {
        '=' => return HS_CTR_EQUALS_FOUND
        _ => ()
      }
    _ =>
      match self.peek0() {
        // Symop is processed in `ctr_lookahead_step`, so `=` and `::` can not be a prefix
        '=' => return HS_CTR_EQUALS_FOUND
        0x2200 => () // ∀
        ':' => if !self.char1(':') { return HS_CTR_UNDECIDED }
        'f' => {
          let res = self.ctr_stop_on_token("forall")
          if res != 0 {
            return res
          }
          return self.ctr_stop_on_token("family")
        }
        'i' => return self.ctr_stop_on_token("instance")
        _ => return HS_CTR_UNDECIDED
      }
  }
  HS_CTR_IMPOSSIBLE
}

///|
/// Process a lexed token for constraint lookahead.
fn HsEnv::ctr_lookahead_step(
  self : HsEnv,
  state : HsCtrState,
  next : Int32,
) -> Int32 {
  state.reset = 1
  match next {
    HS_L_BRACE_CLOSE => return hs_ctr_bracket_close(state)
    HS_L_UNBOXED_CLOSE => {
      let res = hs_ctr_bracket_close(state)
      if res != 0 {
        return res
      }
      state.reset = 2
      return HS_CTR_UNDECIDED
    }
    HS_L_BRACE_OPEN => return hs_ctr_bracket_open(state)
    HS_L_SYMOP_SPECIAL | HS_L_SYMOP => state.reset = self.symop_lookahead()
    HS_L_UPPER => {
      state.reset = self.conid()
      return HS_CTR_UNDECIDED
    }
    HS_L_DOT_ID => return HS_CTR_UNDECIDED
    HS_L_PRAGMA => {
      if self.consume_pragma() {
        state.reset = 3
      }
      return HS_CTR_UNDECIDED
    }
    HS_L_TEXP_CLOSER | HS_L_NOTHING =>
      match self.peek0() {
        ')' | ']' => return hs_ctr_bracket_close(state)
        '(' | '[' => return hs_ctr_bracket_open(state)
        '"' => {
          state.reset = self.take_string_literal()
          return HS_CTR_UNDECIDED
        }
        '\'' => {
          state.reset = self.take_char_literal()
          return HS_CTR_UNDECIDED
        }
        _ =>
          if hs_varid_start_char(self.peek0()) {
            state.reset = self.advance_while(1, hs_is_id_char)
          }
      }
    // (falls through to `default: break;`)
    _ => ()
  }
  if state.brackets != 0 {
    return HS_CTR_UNDECIDED
  }
  self.ctr_top(next)
}

///|
/// Main loop for context lookahead.
fn HsEnv::constraint_lookahead(self : HsEnv) -> Int32 {
  let state : HsCtrState = {
    reset: 0,
    brackets: 0,
    context: false,
    infix: false,
    data_infix: false,
    type_instance: false,
  }
  let mut done = false
  while !done && self.not_eof() {
    // Setting indent to 99999 only to not trigger the following termination condition when no newline was advanced over
    let newline = HsNewline::new()
    newline.indent = 99999
    self.newline_lookahead(newline)
    if newline.indent <= self.current_indent() &&
      self.current_context() != HS_BRACES {
      break
    }
    let result = self.ctr_lookahead_step(state, newline.end)
    match result {
      HS_CTR_ARROW_FOUND => {
        state.context = true
        done = true
      }
      HS_CTR_INFIX_FOUND => {
        if self.char0(':') || self.char0('`') {
          state.data_infix = true
        }
        state.infix = true
        // Context has precedence, e.g. `instance a + a => A` finds `+` first and would treat that as the class name of
        // the head, then failing on the right operand.
        done = !self.valid(HS_CONTEXT)
      }
      HS_CTR_EQUALS_FOUND => {
        done = !self.valid(HS_TYPE_INSTANCE)
        state.type_instance = true
      }
      HS_CTR_BAR_FOUND => {
        done = true
        state.type_instance = false
      }
      HS_CTR_IMPOSSIBLE => done = true
      _ => ()
    }
    self.reset_lookahead_to(state.reset)
    state.reset = 0
  }
  if state.context {
    let res = self.finish_if_valid(HS_CONTEXT, "ctr")
    if res != 0 {
      return res
    }
  }
  if state.infix {
    let res = self.finish_if_valid(HS_INFIX, "ctr")
    if res != 0 {
      return res
    }
  }
  if state.data_infix {
    let res = self.finish_if_valid(HS_DATA_INFIX, "ctr")
    if res != 0 {
      return res
    }
  }
  if state.type_instance {
    let res = self.finish_if_valid(HS_TYPE_INSTANCE, "ctr")
    if res != 0 {
      return res
    }
  }
  HS_FAIL
}

// --------------------------------------------------------------------------------------------------------
// Actions that are executed for interior positions
// --------------------------------------------------------------------------------------------------------

///|
fn HsEnv::process_token_constraint(self : HsEnv) -> Int32 {
  if self.valid(HS_CONTEXT) ||
    self.valid(HS_INFIX) ||
    self.valid(HS_DATA_INFIX) ||
    self.valid(HS_TYPE_INSTANCE) {
    return self.constraint_lookahead()
  }
  HS_FAIL
}

///|
fn HsEnv::interior(self : HsEnv, whitespace : Bool) -> Int32 {
  let next = self.lex(false)
  let res = self.resolve_semicolon(next)
  if res != 0 {
    return res
  }
  let res = self.process_token_interior(next)
  if res != 0 {
    return res
  }
  let res = self.process_token_symop(whitespace, next)
  if res != 0 {
    return res
  }
  let res = self.process_token_constraint()
  if res != 0 {
    return res
  }
  let res = self.process_token_splice(next)
  if res != 0 {
    return res
  }
  HS_FAIL
}

// --------------------------------------------------------------------------------------------------------
// Initial actions
// --------------------------------------------------------------------------------------------------------

///|
/// These are conditioned only on symbols and don't advance, except for
/// `qq_body`, which cannot fail.
fn HsEnv::pre_ws_commands(self : HsEnv) -> Int32 {
  let res = self.texp_context()
  if res != 0 {
    return res
  }
  let res = self.start_brace()
  if res != 0 {
    return res
  }
  let res = self.end_brace()
  if res != 0 {
    return res
  }
  // Leading whitespace must be included in the node.
  if self.valid(HS_QQ_BODY) {
    return self.qq_body()
  }
  if self.newline_active() {
    let res = self.newline_post()
    if res != 0 {
      return res
    }
  } else if self.state.newline.state == HS_N_RESUME {
    let res = self.newline_resume()
    if res != 0 {
      return res
    }
  }
  HS_FAIL
}

///|
fn HsEnv::scan_main(self : HsEnv) -> Int32 {
  self.mark("main")
  let res = self.pre_ws_commands()
  if res != 0 {
    return res
  }
  let whitespace = self.skip_space()
  if hs_is_newline(self.peek_lexer()) {
    return self.newline_start()
  } else if self.not_eof() {
    return self.interior(whitespace)
  }
  HS_FAIL
}

///|
fn HsEnv::process_result(self : HsEnv, result : Int32) -> Bool {
  let mut result = result
  if result == HS_FAIL && self.is_eof() && self.no_lookahead() {
    self.mark("eof whitespace")
    // Inlined `end_layout` because of perf glitch
    if self.valid(HS_END) {
      result = self.end_layout_unchecked("eof")
    } else if self.valid(HS_SEMICOLON) {
      result = hs_finish(HS_SEMICOLON, "eof")
    } else {
      result = self.force_end_context()
    }
  }
  self.set_result_symbol(result)
}

///|
fn HsEnv::scan(self : HsEnv) -> Bool {
  if self.after_error() {
    return false
  }
  let result = self.scan_main()
  self.process_result(result)
}

// --------------------------------------------------------------------------------------------------------
// API
// --------------------------------------------------------------------------------------------------------

///|
/// `sizeof(Persist)`: `unsigned contexts` followed by `Newline` (two enums, a
/// `uint32_t` and four `bool`s), without padding.
const HS_PERSIST_SIZE : Int32 = 20

///|
/// `sizeof(Context)`: an enum and a `uint32_t`.
const HS_CONTEXT_SIZE : Int32 = 8

///|
fn hs_write_u32(buffer : FixedArray[Byte], at : Int32, value : UInt32) -> Unit {
  buffer[at] = (value & 0xFF).to_byte()
  buffer[at + 1] = ((value >> 8) & 0xFF).to_byte()
  buffer[at + 2] = ((value >> 16) & 0xFF).to_byte()
  buffer[at + 3] = ((value >> 24) & 0xFF).to_byte()
}

///|
fn hs_read_u32(buffer : BytesView, at : Int32) -> UInt32 {
  buffer[at].to_uint() |
  (buffer[at + 1].to_uint() << 8) |
  (buffer[at + 2].to_uint() << 16) |
  (buffer[at + 3].to_uint() << 24)
}

///|
fn hs_bool_byte(b : Bool) -> Byte {
  if b {
    1
  } else {
    0
  }
}

///|
fn HsState::serialize(self : HsState, buffer : FixedArray[Byte]) -> Int32 {
  // `Persist persist = {.contexts = state->contexts.size, .newline = state->newline};`
  let contexts = self.contexts.length()
  let contexts_size = contexts * HS_CONTEXT_SIZE
  hs_write_u32(buffer, 0, contexts.reinterpret_as_uint())
  hs_write_u32(buffer, 4, self.newline.state.reinterpret_as_uint())
  hs_write_u32(buffer, 8, self.newline.end.reinterpret_as_uint())
  hs_write_u32(buffer, 12, self.newline.indent)
  buffer[16] = hs_bool_byte(self.newline.eof)
  buffer[17] = hs_bool_byte(self.newline.no_semi)
  buffer[18] = hs_bool_byte(self.newline.skip_semi)
  buffer[19] = hs_bool_byte(self.newline.unsafe_)
  let to_copy = HS_PERSIST_SIZE + contexts_size
  if to_copy > SERIALIZATION_BUFFER_SIZE {
    return 0
  }
  for i in 0..<contexts {
    let at = HS_PERSIST_SIZE + i * HS_CONTEXT_SIZE
    hs_write_u32(buffer, at, self.contexts[i].sort.reinterpret_as_uint())
    hs_write_u32(buffer, at + 4, self.contexts[i].indent)
  }
  to_copy
}

///|
fn HsState::deserialize(self : HsState, buffer : BytesView) -> Unit {
  let length = buffer.length()
  let n = self.newline
  self.contexts.clear()
  if length > 0 {
    let contexts = hs_read_u32(buffer, 0).reinterpret_as_int()
    n.state = hs_read_u32(buffer, 4).reinterpret_as_int()
    n.end = hs_read_u32(buffer, 8).reinterpret_as_int()
    n.indent = hs_read_u32(buffer, 12)
    n.eof = buffer[16] != 0
    n.no_semi = buffer[17] != 0
    n.skip_semi = buffer[18] != 0
    n.unsafe_ = buffer[19] != 0
    for i in 0..<contexts {
      let at = HS_PERSIST_SIZE + i * HS_CONTEXT_SIZE
      self.contexts.push({
        sort: hs_read_u32(buffer, at).reinterpret_as_int(),
        indent: hs_read_u32(buffer, at + 4),
      })
    }
  } else {
    // `p = (Persist) {.contexts = 0}; persist->newline.state = NResume;`
    n.state = HS_N_RESUME
    n.end = 0
    n.indent = 0
    n.eof = false
    n.no_semi = false
    n.skip_semi = false
    n.unsafe_ = false
  }
  self.lookahead.contents.clear()
  self.lookahead.offset = 0
}

///|
/// `tree_sitter_haskell_external_scanner_create`: a zeroed `State`.
fn haskell_scanner() -> @runtime.ExternalScanner {
  let state : HsState = {
    contexts: [],
    newline: HsNewline::new(),
    lookahead: { contents: [], offset: 0, },
  }
  {
    scan: (lexer, valid_symbols) => {
      hs_env_new(lexer, valid_symbols, state).scan()
    },
    serialize: buffer => state.serialize(buffer),
    deserialize: buffer => state.deserialize(buffer),
    destroy: () => {
      state.contexts.clear()
      state.lookahead.contents.clear()
    },
  }
}

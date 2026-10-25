// Port of tree-sitter-scala src/scanner.c (v0.26.3)
// tree-sitter-scala is distributed under the MIT license (see NOTICE).

// Order must mirror the externals array in grammar.js exactly: tree-sitter
// couples the two by index.

///|
/// `enum TokenType`.
const SCALA_AUTOMATIC_SEMICOLON : Int32 = 0

///|
const SCALA_INDENT : Int32 = 1

///|
const SCALA_OUTDENT : Int32 = 2

///|
const SCALA_COMMA_OUTDENT : Int32 = 3

///|
const SCALA_SIMPLE_STRING_START : Int32 = 4

///|
const SCALA_SIMPLE_STRING_MIDDLE : Int32 = 5

///|
const SCALA_SIMPLE_MULTILINE_STRING_START : Int32 = 6

///|
const SCALA_INTERPOLATED_STRING_MIDDLE : Int32 = 7

///|
const SCALA_INTERPOLATED_MULTILINE_STRING_MIDDLE : Int32 = 8

///|
const SCALA_RAW_STRING_START : Int32 = 9

///|
const SCALA_RAW_STRING_MIDDLE : Int32 = 10

///|
const SCALA_RAW_STRING_MULTILINE_MIDDLE : Int32 = 11

///|
const SCALA_SINGLE_LINE_STRING_END : Int32 = 12

///|
const SCALA_MULTILINE_STRING_END : Int32 = 13

///|
const SCALA_ELSE : Int32 = 14

///|
const SCALA_CATCH : Int32 = 15

///|
const SCALA_FINALLY : Int32 = 16

///|
const SCALA_EXTENDS : Int32 = 17

///|
const SCALA_DERIVES : Int32 = 18

///|
const SCALA_WITH : Int32 = 19

///|
const SCALA_BLOCK_COMMENT : Int32 = 20

///|
const SCALA_SUPPRESS_BLOCK_COMMENT : Int32 = 21

///|
const SCALA_ERROR_SENTINEL : Int32 = 22

///|
const SCALA_COLON_EOL : Int32 = 23

///|
const SCALA_POSTFIX_OP : Int32 = 24

///|
const SCALA_POSTFIX_STAR : Int32 = 25

///|
const SCALA_FLOATING_POINT_WITH_SEPARATORS : Int32 = 26

///|
const SCALA_END_KEYWORD : Int32 = 27

///|
/// Zero-width, emitted right before a control-tail keyword (catch, finally,
/// else, then, or yield) where the grammar allows one, so construct bodies
/// share one follow column instead of per-keyword ones.
const SCALA_CONTROL_TAIL_GATE : Int32 = 28

///|
const SCALA_XML_TAG_START : Int32 = 29

///|
const SCALA_ERASED_MODIFIER : Int32 = 30

///|
const SCALA_OPEN_MODIFIER : Int32 = 31

///|
const SCALA_OPAQUE_MODIFIER : Int32 = 32

///|
const SCALA_INFIX_MODIFIER : Int32 = 33

///|
const SCALA_TRACKED_MODIFIER : Int32 = 34

///|
const SCALA_TRANSPARENT_MODIFIER : Int32 = 35

///|
const SCALA_INLINE_MODIFIER : Int32 = 36

///|
const SCALA_INTO_MODIFIER : Int32 = 37

///|
const SCALA_UPDATE_MODIFIER : Int32 = 38

///|
const SCALA_CONSUME_MODIFIER : Int32 = 39

///|
const SCALA_USES : Int32 = 40

///|
const SCALA_OP_LEFT_OR : Int32 = 41

///|
const SCALA_OP_LEFT_XOR : Int32 = 42

///|
const SCALA_OP_LEFT_AND : Int32 = 43

///|
const SCALA_OP_LEFT_EQ : Int32 = 44

///|
const SCALA_OP_LEFT_REL : Int32 = 45

///|
const SCALA_OP_LEFT_COLON : Int32 = 46

///|
const SCALA_OP_LEFT_ADD : Int32 = 47

///|
const SCALA_OP_LEFT_MUL : Int32 = 48

///|
const SCALA_OP_LEFT_OTHER : Int32 = 49

///|
const SCALA_OP_NAME : Int32 = 50

///|
const SCALA_USING_DIRECTIVE_START : Int32 = 51

///|
const SCALA_CASE_DEFINITION_KEYWORD : Int32 = 52

///|
const SCALA_DEF_SEMICOLON : Int32 = 53

///|
const SCALA_WILDCARD_BOUND_START : Int32 = 54

///|
/// C conversion of an `int` to `int16_t` (wraps on this platform).
fn scala_i16(x : Int32) -> Int32 {
  ((x & 0xFFFF) ^ 0x8000) - 0x8000
}

///|
priv struct ScalaScanner {
  /// `Array(int16_t) indents`, each entry in the `int16_t` range.
  indents : Array[Int32]
  /// `int16_t last_indentation_size`.
  mut last_indentation_size : Int32
  /// `int16_t last_newline_count`.
  mut last_newline_count : Int32
  /// `int16_t last_column`.
  mut last_column : Int32
  // The lookahead at the position last_column names. Two lines can share a
  // column, so the character keeps the saved newline from being recovered at
  // an unrelated position further down.
  /// `int16_t last_char`.
  mut last_char : Int32
  /// `int16_t after_colon_eol`.
  mut after_colon_eol : Int32
}

///|
fn scala_scanner() -> @runtime.ExternalScanner {
  // `ts_calloc` zeroes the struct.
  let scanner : ScalaScanner = {
    indents: [],
    last_indentation_size: -1,
    last_newline_count: 0,
    last_column: -1,
    last_char: 0,
    after_colon_eol: 0,
  }
  {
    scan: (lexer, valid_symbols) => scanner.external_scan(lexer, valid_symbols),
    serialize: buffer => scanner.serialize(buffer),
    deserialize: buffer => scanner.deserialize(buffer),
    destroy: () => (),
  }
}

///|
fn scala_write_i16(
  buffer : FixedArray[Byte],
  at : Int32,
  value : Int32,
) -> Unit {
  buffer[at] = (value & 0xFF).to_byte()
  buffer[at + 1] = ((value >> 8) & 0xFF).to_byte()
}

///|
fn scala_read_i16(buffer : BytesView, at : Int32) -> Int32 {
  scala_i16(buffer[at].to_int() | (buffer[at + 1].to_int() << 8))
}

///|
fn ScalaScanner::serialize(
  self : ScalaScanner,
  buffer : FixedArray[Byte],
) -> Int32 {
  // `(indents.size + 5) * sizeof(int16_t)` in `size_t`.
  if (self.indents.length().to_int64() + 5L) * 2L >
    SERIALIZATION_BUFFER_SIZE.to_int64() {
    return 0
  }
  let mut size = 0
  scala_write_i16(buffer, size, self.last_indentation_size)
  size += 2
  scala_write_i16(buffer, size, self.last_newline_count)
  size += 2
  scala_write_i16(buffer, size, self.last_column)
  size += 2
  scala_write_i16(buffer, size, self.last_char)
  size += 2
  scala_write_i16(buffer, size, self.after_colon_eol)
  size += 2
  for i in 0..<self.indents.length() {
    scala_write_i16(buffer, size, self.indents[i])
    size += 2
  }
  size
}

///|
fn ScalaScanner::deserialize(self : ScalaScanner, buffer : BytesView) -> Unit {
  let length = buffer.length()
  self.indents.clear()
  self.last_indentation_size = -1
  self.last_column = -1
  self.last_char = 0
  self.last_newline_count = 0
  self.after_colon_eol = 0
  if length == 0 {
    return
  }
  let mut size = 0
  self.last_indentation_size = scala_read_i16(buffer, size)
  size += 2
  self.last_newline_count = scala_read_i16(buffer, size)
  size += 2
  self.last_column = scala_read_i16(buffer, size)
  size += 2
  self.last_char = scala_read_i16(buffer, size)
  size += 2
  self.after_colon_eol = scala_read_i16(buffer, size)
  size += 2
  // The serializer always writes the five fields, so `length - size` does
  // not wrap.
  let count = (length - size) / 2
  if count > 0 {
    for i in 0..<count {
      self.indents.push(scala_read_i16(buffer, size + i * 2))
    }
  }
}

// The C locale sets of iswspace, iswalpha and iswalnum, spelled out. No locale
// is ever installed here, and the library calls showed up in the parse profile.

///|
fn scala_is_space(c : Int32) -> Bool {
  c == ' ' || (c >= '\t' && c <= '\r')
}

///|
fn scala_is_alpha(c : Int32) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn scala_is_alnum(c : Int32) -> Bool {
  scala_is_alpha(c) || (c >= '0' && c <= '9')
}

///|
fn scala_is_word_start(c : Int32) -> Bool {
  scala_is_alpha(c) || c == '_' || c == '$'
}

///|
fn scala_advance_past_blanks(lexer : @runtime.Lexer) -> Bool {
  let mut found = false
  while lexer.lookahead == ' ' || lexer.lookahead == '\t' {
    lexer.advance(false)
    found = true
  }
  found
}

///|
/// Marks an indent region whose `case` clauses align with their `match`/`catch`
/// (Scala 3 same-width case). Such a region also closes on a same-width line
/// that is not another `case` clause. The flag is packed into the int16 width.
const SCALA_CASE_INDENT_FLAG : Int32 = 0x4000

///|
fn scala_indent_width(entry : Int32) -> Int32 {
  if entry == -1 {
    -1
  } else {
    scala_i16(entry & 0x3FFF)
  }
}

///|
/// Does a line at `width` sit exactly at the width of a flagged same-width
/// case region `prev`? Shared by every close site of such regions.
fn scala_at_case_region_width(prev : Int32, width : Int32) -> Bool {
  prev != -1 &&
  (prev & SCALA_CASE_INDENT_FLAG) != 0 &&
  width == scala_indent_width(prev)
}

///|
/// ASCII opchars, deliberately without `/`, which could open a comment. An
/// operator starting with `/` or a Unicode opchar never takes the external
/// layout paths gated on this; the internal operator tokens handle it.
/// See: https://www.scala-lang.org/api/3.x/docs/changed-features/operators.html
fn scala_is_op_char(c : Int32) -> Bool {
  match c {
    '!' | '#' | '%' | '&' => true
    '*' | '+' | '-' | '<' => true
    '=' | '>' | '?' | '@' => true
    '\\' | '^' | '|' | '~' => true
    ':' => true
    _ => false
  }
}

///|
/// SLS 6.12.3 gives an operator its precedence by its first character. An
/// operator ending in `/` is never right-associative and never an assignment,
/// so the left-associative class is the whole answer. The partition matches
/// OP_TOKEN in grammar.js, whose first-character sets it has to agree with.
/// `/` is absent because is_op_char rejects it, so no caller can pass one.
fn scala_op_left_class(first : Int32) -> Int32 {
  match first {
    '|' => SCALA_OP_LEFT_OR
    '^' => SCALA_OP_LEFT_XOR
    '&' => SCALA_OP_LEFT_AND
    '=' | '!' => SCALA_OP_LEFT_EQ
    '<' | '>' => SCALA_OP_LEFT_REL
    ':' => SCALA_OP_LEFT_COLON
    '+' | '-' => SCALA_OP_LEFT_ADD
    '*' | '%' => SCALA_OP_LEFT_MUL
    _ => SCALA_OP_LEFT_OTHER
  }
}

///|
/// Mirrors the start class of XML_NAME in grammar.js. Every non-ASCII
/// character is accepted, since the letter test is ASCII-only and the internal
/// lexer rejects the name if it is not a letter after all.
fn scala_is_xml_name_start(c : Int32) -> Bool {
  scala_is_alpha(c) || c == '_' || c > 127
}

///|
/// An operator directly before one of these ends its expression, so no right
/// operand can follow and the operator is postfix.
fn scala_is_close_or_separator(c : Int32) -> Bool {
  c == ')' || c == ']' || c == '}' || c == ',' || c == ';'
}

///|
/// We enumerate 3 types of strings that we need to handle differently:
/// 1. Simple strings, `"..."` or `"""..."""`
/// 2. Interpolated strings, `s"..."` or `f"..."` or `foo"..."` or foo"""...""".
/// 3. Raw strings, `raw"..."`
priv enum ScalaStringMode {
  Simple
  Interpolated
  Raw
} derive(Eq)

///|
fn scala_scan_string_content(
  lexer : @runtime.Lexer,
  is_multiline : Bool,
  string_mode : ScalaStringMode,
) -> Bool {
  // `unsigned closing_quote_count`.
  let mut closing_quote_count : UInt32 = 0
  for ;; {
    if lexer.lookahead == '"' {
      lexer.advance(false)
      closing_quote_count += 1
      if !is_multiline {
        lexer.result_symbol = SCALA_SINGLE_LINE_STRING_END
        lexer.mark_end()
        return true
      }
      if closing_quote_count >= 3 && lexer.lookahead != '"' {
        lexer.result_symbol = SCALA_MULTILINE_STRING_END
        lexer.mark_end()
        return true
      }
    } else if lexer.lookahead == '$' && string_mode != Simple {
      match string_mode {
        Interpolated =>
          lexer.result_symbol = if is_multiline {
            SCALA_INTERPOLATED_MULTILINE_STRING_MIDDLE
          } else {
            SCALA_INTERPOLATED_STRING_MIDDLE
          }
        Raw =>
          lexer.result_symbol = if is_multiline {
            SCALA_RAW_STRING_MULTILINE_MIDDLE
          } else {
            SCALA_RAW_STRING_MIDDLE
          }
        _ => abort("assert(false)")
      }
      lexer.mark_end()
      return true
    } else {
      closing_quote_count = 0
      if lexer.lookahead == '\\' {
        // Multiline strings ignore escape sequences
        if is_multiline || string_mode == Raw {
          // FIXME: In raw string mode, we have to jump over escaped quotes.
          lexer.advance(false)
          // In single-line raw strings, `\"` is not translated to `"`, but it also does
          // not close the string. Likewise, `\\` is not translated to `\`, but it does
          // stop the second `\` from stopping a double-quote from closing the string.
          if !is_multiline &&
            string_mode == Raw &&
            (lexer.lookahead == '"' || lexer.lookahead == '\\') {
            lexer.advance(false)
          }
        } else {
          lexer.result_symbol = if string_mode == Simple {
            SCALA_SIMPLE_STRING_MIDDLE
          } else {
            SCALA_INTERPOLATED_STRING_MIDDLE
          }
          lexer.mark_end()
          return true
        }
        // During error recovery and dynamic precedence resolution, the external
        // scanner will be invoked with all valid_symbols set to true, which means
        // we will be asked to scan a string token when we are not actually in a
        // string context. Here we detect these cases and return false.
      } else if lexer.lookahead == '\n' && !is_multiline {
        return false
      } else if lexer.eof() {
        return false
      } else {
        lexer.advance(false)
      }
    }
  }
}

///|
/// Consumes a block comment body, nesting per SLS 1.4. The caller has consumed
/// the leading "/*". With stop_at_newline it stops at the first newline.
/// Returns whether the comment closed on the line it started on.
fn scala_consume_block_comment_body_ex(
  lexer : @runtime.Lexer,
  stop_at_newline : Bool,
) -> Bool {
  // `unsigned depth`.
  let mut depth : UInt32 = 1
  while depth > 0 {
    if lexer.eof() || (stop_at_newline && lexer.lookahead == '\n') {
      return false
    }
    if lexer.lookahead == '/' {
      lexer.advance(false)
      if lexer.lookahead == '*' {
        lexer.advance(false)
        depth += 1
      }
    } else if lexer.lookahead == '*' {
      lexer.advance(false)
      if lexer.lookahead == '/' {
        lexer.advance(false)
        depth -= 1
      }
    } else {
      lexer.advance(false)
    }
  }
  true
}

///|
/// Stops just past the matching "*/" (or at EOF).
fn scala_consume_block_comment_body(lexer : @runtime.Lexer) -> Unit {
  ignore(scala_consume_block_comment_body_ex(lexer, false))
}

///|
/// Stops at a newline. Returns whether the comment ended on the line it
/// started on. A comment crossing the line end means the line ends there.
fn scala_consume_block_comment_body_on_line(lexer : @runtime.Lexer) -> Bool {
  scala_consume_block_comment_body_ex(lexer, true)
}

///|
fn scala_finish_block_comment(lexer : @runtime.Lexer) -> Bool {
  lexer.mark_end()
  lexer.result_symbol = SCALA_BLOCK_COMMENT
  true
}

///|
/// The caller has consumed the leading "/*".
fn scala_lex_block_comment(lexer : @runtime.Lexer) -> Bool {
  scala_consume_block_comment_body(lexer)
  scala_finish_block_comment(lexer)
}

///|
fn scala_scan_word(lexer : @runtime.Lexer, word : String) -> Bool {
  for i in 0..<word.length() {
    if lexer.lookahead != word[i].to_int() {
      return false
    }
    lexer.advance(false)
  }
  // `match_` must not match the keyword `match`.
  !(scala_is_alnum(lexer.lookahead) ||
  lexer.lookahead == '_' ||
  lexer.lookahead == '$')
}

///|
/// Reads one identifier-like word into a buffer of `cap` chars. The length is
/// -1 when the word cannot be an ASCII keyword. The whole word is always
/// consumed, so a failed keyword check never leaves the lexer mid-identifier.
/// The third result, `underscore_tail`, reports a final `_` that is not the
/// whole word. The reference scanner reads a lone `_` as the wildcard.
fn scala_read_word(
  lexer : @runtime.Lexer,
  cap : Int32,
) -> (Int32, String, Bool) {
  let buf = StringBuilder()
  let mut len = 0
  let mut count = 0
  let mut not_keyword = false
  let mut last = 0
  while scala_is_alnum(lexer.lookahead) ||
        lexer.lookahead == '_' ||
        lexer.lookahead == '$' {
    if lexer.lookahead > 127 || len >= cap - 1 {
      not_keyword = true
    } else {
      buf.write_char(lexer.lookahead.unsafe_to_char())
      len += 1
    }
    last = lexer.lookahead
    count += 1
    lexer.advance(false)
  }
  let underscore_tail = count > 1 && last == '_'
  (if not_keyword { -1 } else { len }, buf.to_string(), underscore_tail)
}

///|
fn scala_word_in(word : String, words : Array[String]) -> Bool {
  for w in words {
    if word == w {
      return true
    }
  }
  false
}

///|
/// Whether a name follows the word just read, which is what makes an `end`
/// tag a marker and an `open` a modifier. Block comments in between are
/// transparent, as they are to the parser.
fn scala_skip_blanks_and_block_comments(lexer : @runtime.Lexer) -> Unit {
  for ;; {
    ignore(scala_advance_past_blanks(lexer))
    if lexer.lookahead != '/' {
      return
    }
    lexer.advance(false)
    if lexer.lookahead != '*' {
      return
    }
    lexer.advance(false)
    scala_consume_block_comment_body(lexer)
  }
}

///|
fn scala_name_follows_word(lexer : @runtime.Lexer) -> Bool {
  scala_skip_blanks_and_block_comments(lexer)
  scala_is_alpha(lexer.lookahead) ||
  lexer.lookahead == '_' ||
  lexer.lookahead == '$' ||
  lexer.lookahead == '`' ||
  lexer.lookahead > 127
}

///|
let scala_expression_tails : Array[String] = [
  "match", "catch", "finally", "else", "then", "do", "yield", "while", "with", "extends",
]

///|
/// The words that continue the expression before them instead of starting one.
/// `if` is missing on purpose, since it does start one. A word longer than the
/// buffer reads as -1, so grow the buffer along with the table.
fn scala_word_is_expression_tail(lexer : @runtime.Lexer) -> Bool {
  // `char word[sizeof "finally"]`.
  let (len, word, _) = scala_read_word(lexer, 8)
  len > 0 && scala_word_in(word, scala_expression_tails)
}

///|
/// No modifier precedes such a word, so `update match` stays a plain name. A
/// definition keyword does follow one (`inline val`), which is why the two
/// readers below keep their own names over the one table.
fn scala_modifier_word_allowed(lexer : @runtime.Lexer) -> Bool {
  !scala_word_is_expression_tail(lexer)
}

///|
/// The right operand of an operator has to start an expression, so `??? match`
/// on its own line is a statement rather than the tail of the line above.
fn scala_operand_word_allowed(lexer : @runtime.Lexer) -> Bool {
  !scala_word_is_expression_tail(lexer)
}

///|
fn scala_modifier_name_follows(lexer : @runtime.Lexer) -> Bool {
  scala_name_follows_word(lexer) && scala_modifier_word_allowed(lexer)
}

///|
let scala_definition_starts : Array[String] = [
  "def", "val", "var", "type", "given", "class", "object", "trait", "enum", "final",
  "lazy", "override", "private", "protected", "sealed", "abstract", "implicit",
]

///|
/// `inline` also prefixes the scrutinee of `inline 1 match`, and it can end a
/// modifier line whose definition is on the next one.
fn scala_inline_modifier_follows(lexer : @runtime.Lexer) -> Bool {
  if scala_name_follows_word(lexer) {
    return scala_modifier_word_allowed(lexer)
  }
  // A scrutinee starts an expression. See canStartExprTokens in the
  // reference parser.
  if (lexer.lookahead >= '0' && lexer.lookahead <= '9') ||
    lexer.lookahead == '"' ||
    lexer.lookahead == '\'' ||
    lexer.lookahead == '(' ||
    lexer.lookahead == '{' ||
    lexer.lookahead == '-' {
    return true
  }
  if lexer.lookahead != '\n' && lexer.lookahead != '\r' {
    return false
  }
  while scala_is_space(lexer.lookahead) {
    lexer.advance(false)
  }
  // Across a line break only a reserved word counts. A soft modifier there
  // would be a name too, and `val b = inline` followed by such a line is a
  // value rather than a modifier list.
  // `char word[sizeof "transparent"]`.
  let (len, word, _) = scala_read_word(lexer, 12)
  len > 0 && scala_word_in(word, scala_definition_starts)
}

///|
/// True when `class` or `object` follows `case`, marking a definition not a
/// clause. Reads the whole word so an identifier like `cobject` is not misread
/// as `c` plus `object` by chained scan_word calls. Advances the lexer.
fn scala_is_case_definition_word(lexer : @runtime.Lexer) -> Bool {
  ignore(scala_advance_past_blanks(lexer))
  // `char word[sizeof "object"]`.
  let (len, word, _) = scala_read_word(lexer, 7)
  len > 0 && (word == "class" || word == "object")
}

///|
/// True when the line starts a `case` clause and not a `case class`/`case
/// object` definition. Advances the lexer. The caller must have called
/// mark_end already, or must return false.
fn scala_is_case_clause_intro(lexer : @runtime.Lexer) -> Bool {
  scala_scan_word(lexer, "case") && !scala_is_case_definition_word(lexer)
}

///|
/// Result of looking for a comment at a layout boundary (INDENT/OUTDENT).
priv enum ScalaCommentAtLayout {
  /// not a comment; the lexer may have advanced past a lone '/'
  CommentNone
  /// a block comment was lexed as BLOCK_COMMENT: return true
  CommentLexed
  /// a comment starts here: give up on the layout token
  CommentAbort
  /// comments skipped, code follows on the same line and its column is the
  /// indentation
  CommentSameLineCode
}

///|
/// Comments must not affect indentation. Block comments have to be lexed
/// here because the internal lexer no longer knows them.
fn scala_check_comment_at_layout(
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> ScalaCommentAtLayout {
  if lexer.lookahead != '/' {
    return CommentNone
  }
  lexer.advance(false)
  if lexer.lookahead == '*' && valid_symbols[SCALA_BLOCK_COMMENT] {
    lexer.advance(false)
    for ;; {
      scala_consume_block_comment_body(lexer)
      ignore(scala_advance_past_blanks(lexer))
      if lexer.eof() || lexer.lookahead == '\n' || lexer.lookahead == '\r' {
        ignore(scala_finish_block_comment(lexer))
        return CommentLexed
      }
      if lexer.lookahead == '/' {
        lexer.advance(false)
        if lexer.lookahead == '*' {
          lexer.advance(false)
          continue // another block comment on the same line
        }
        if lexer.lookahead == '/' {
          // The extent cannot be re-marked back, so consume the trailing
          // line comment into the comment token.
          while !lexer.eof() && lexer.lookahead != '\n' {
            lexer.advance(false)
          }
          ignore(scala_finish_block_comment(lexer))
          return CommentLexed
        }
        // A lone '/' is code. The off-by-one column is harmless.
        return CommentSameLineCode
      }
      return CommentSameLineCode
    }
  }
  if lexer.lookahead == '/' || lexer.lookahead == '*' {
    return CommentAbort
  }
  // A lone '/' is not a comment. The lexer stays advanced past it.
  CommentNone
}

///|
/// Skips a delimited body (a string or a back-ticked identifier) whose opening
/// delimiter the caller has consumed. Stops after the closing `close` or at
/// EOL/EOF. With escapes, a backslash escapes the next character.
fn scala_skip_delimited(
  lexer : @runtime.Lexer,
  close : Int32,
  escapes : Bool,
) -> Unit {
  while !lexer.eof() && lexer.lookahead != close && lexer.lookahead != '\n' {
    if escapes && lexer.lookahead == '\\' {
      lexer.advance(false)
    }
    lexer.advance(false)
  }
  if lexer.lookahead == close {
    lexer.advance(false)
  }
}

///|
/// After an opening `'`. A character literal reveals no code and returns 0. A
/// quote reveals its first character, which the caller still needs for bracket
/// depth, so that character is returned instead.
fn scala_skip_char_or_quote_tail(lexer : @runtime.Lexer) -> Int32 {
  if lexer.lookahead == '\\' {
    lexer.advance(false)
    if !lexer.eof() && lexer.lookahead != '\n' {
      lexer.advance(false)
    }
    if lexer.lookahead == '\'' {
      lexer.advance(false)
    }
    return 0
  }
  if lexer.eof() || lexer.lookahead == '\n' {
    return 0
  }
  let quoted = lexer.lookahead
  lexer.advance(false)
  if lexer.lookahead == '\'' {
    lexer.advance(false) // a character literal: `quoted` was not code
    return 0
  }
  quoted
}

///|
/// Whether the rest of the line holds only blanks and comments. A comment
/// running past the line end still counts as blank because comments are
/// transparent to scalac, but code after a closed block comment does not.
fn scala_rest_of_line_is_blank_or_comments(lexer : @runtime.Lexer) -> Bool {
  for ;; {
    ignore(scala_advance_past_blanks(lexer))
    if lexer.eof() || lexer.lookahead == '\n' || lexer.lookahead == '\r' {
      return true
    }
    if lexer.lookahead != '/' {
      return false
    }
    lexer.advance(false)
    if lexer.lookahead == '/' {
      while !lexer.eof() && lexer.lookahead != '\n' {
        lexer.advance(false)
      }
      return true
    }
    if lexer.lookahead != '*' {
      return false // a lone '/' is code
    }
    lexer.advance(false)
    if !scala_consume_block_comment_body_on_line(lexer) {
      return true // the comment runs past the line end
    }
  }
}

///|
/// Whether a real operand follows the operator. Comments and line breaks are
/// transparent, so scalac reads the next real token across them. A comment-only
/// tail to EOF, a closing delimiter and a list separator are all no operand.
fn scala_has_operand(lexer : @runtime.Lexer) -> Bool {
  for ;; {
    if lexer.eof() {
      return false
    }
    if scala_is_space(lexer.lookahead) {
      lexer.advance(false)
      continue
    }
    if lexer.lookahead != '/' {
      return !scala_is_close_or_separator(lexer.lookahead)
    }
    lexer.advance(false)
    if lexer.lookahead == '/' {
      while !lexer.eof() && lexer.lookahead != '\n' {
        lexer.advance(false)
      }
      continue
    }
    if lexer.lookahead != '*' {
      return true // a lone '/' is code
    }
    lexer.advance(false)
    scala_consume_block_comment_body(lexer)
  }
}

///|
/// Reads the run of opchars at the lookahead. Only the first 3 are kept (the
/// second result), since a longer run is never a symbolic keyword. Returns the
/// full length and advances the lexer past the run.
fn scala_read_op_chars(lexer : @runtime.Lexer) -> (Int32, String) {
  let op = StringBuilder()
  let mut len = 0
  while scala_is_op_char(lexer.lookahead) {
    if len < 3 {
      op.write_char(lexer.lookahead.unsafe_to_char())
    }
    len += 1
    lexer.advance(false)
  }
  (len, op.to_string())
}

///|
/// The keywords made of opchars, `<%` aside, which is Scala 2 only. Each lexes
/// as its own token and never as an identifier, so the leading infix test,
/// which asks for an identifier, always rejects one.
/// See: https://docs.scala-lang.org/scala3/reference/syntax.html#regular-keywords
fn scala_is_symbolic_keyword(op : String, len : Int32) -> Bool {
  match len {
    1 => op is ("=" | ":" | "#" | "@")
    2 => op is ("=>" | "<-" | "<:" | "<%" | ">:")
    3 => op is ("?=>" | "=>>")
    _ => false
  }
}

///|
/// The operator names that can start an expression. Every other one is binary,
/// so it leaves no operand for the operator ahead of it. See isUnary in the
/// reference compiler.
fn scala_is_unary_op(op : String, len : Int32) -> Bool {
  len == 1 && op is ("-" | "+" | "~" | "!")
}

///|
/// Blanks and then something that can be the right operand.
fn scala_operand_follows(lexer : @runtime.Lexer) -> Bool {
  if !scala_advance_past_blanks(lexer) || !scala_has_operand(lexer) {
    return false
  }
  if scala_is_op_char(lexer.lookahead) {
    let (len, op) = scala_read_op_chars(lexer)
    // This also covers the symbolic keywords, none of which is unary.
    return scala_is_unary_op(op, len)
  }
  scala_operand_word_allowed(lexer)
}

///|
/// Returns true if the lookahead starts a leading infix operator — a symbolic
/// operator or back-ticked identifier followed by whitespace and then an
/// operand. Such a line is a continuation of the previous expression, so
/// neither AUTOMATIC_SEMICOLON nor OUTDENT should fire ahead of it. Advances
/// the lexer; the caller must not rely on position. A name ending in operator
/// characters is one too, but it is left out here because the OUTDENT caller
/// reads a word of its own right after this call.
fn scala_is_leading_infix_continuation(lexer : @runtime.Lexer) -> Bool {
  if scala_is_op_char(lexer.lookahead) {
    let (len, op) = scala_read_op_chars(lexer)
    if scala_is_symbolic_keyword(op, len) {
      return false
    }
    return scala_operand_follows(lexer)
  }
  if lexer.lookahead == '`' {
    lexer.advance(false)
    while lexer.lookahead != '`' && !lexer.eof() {
      lexer.advance(false)
    }
    if lexer.lookahead != '`' {
      return false
    }
    lexer.advance(false)
    return scala_operand_follows(lexer)
  }
  false
}

///|
/// Walks the rest of the line, tracking bracket depth and skipping strings,
/// characters, back-ticks and comments. Reports whether the line ends in a
/// depth-0 `then`/`do` and whether it carries a depth-0 `=>` (Scala 2 `⇒`).
priv struct ScalaLineScan {
  mut ends_conditional : Bool
  mut has_case_arrow : Bool
  mut closes_bracket : Bool
}

///|
fn scala_scan_rest_of_line(lexer : @runtime.Lexer) -> ScalaLineScan {
  let mut depth = 0
  let r : ScalaLineScan = {
    ends_conditional: false,
    has_case_arrow: false,
    closes_bracket: false,
  }
  while !lexer.eof() && lexer.lookahead != '\n' && lexer.lookahead != '\r' {
    let c = lexer.lookahead
    if c == ' ' || c == '\t' {
      lexer.advance(false)
    } else if c == '(' || c == '[' || c == '{' {
      depth += 1
      r.ends_conditional = false
      lexer.advance(false)
    } else if c == ')' || c == ']' || c == '}' {
      depth -= 1
      if depth < 0 {
        r.closes_bracket = true
      }
      r.ends_conditional = false
      lexer.advance(false)
    } else if c == '"' || c == '`' {
      // A string or a back-ticked identifier; only a string honours escapes.
      r.ends_conditional = false
      lexer.advance(false)
      scala_skip_delimited(lexer, c, c == '"')
    } else if c == '\'' {
      r.ends_conditional = false
      lexer.advance(false)
      let quoted = scala_skip_char_or_quote_tail(lexer)
      if quoted == '(' || quoted == '[' || quoted == '{' {
        depth += 1
      } else if quoted == ')' || quoted == ']' || quoted == '}' {
        depth -= 1
      }
    } else if c == '/' {
      lexer.advance(false)
      if lexer.lookahead == '/' {
        break // rest of the line is a comment
      }
      if lexer.lookahead == '*' {
        lexer.advance(false)
        if !scala_consume_block_comment_body_on_line(lexer) {
          break // the comment runs past the line end
        }
      } else {
        r.ends_conditional = false // a lone '/' is code
      }
    } else if c == 0x21D2 { // `⇒`, the Scala 2 spelling of `=>`
      if depth == 0 {
        r.has_case_arrow = true
      }
      r.ends_conditional = false
      lexer.advance(false)
    } else if scala_is_op_char(c) {
      let starts_eq = c == '='
      lexer.advance(false)
      let second_gt = lexer.lookahead == '>'
      let mut extra = 0
      while scala_is_op_char(lexer.lookahead) {
        lexer.advance(false)
        extra += 1
      }
      // A plain `=>` at depth 0, not `==>` or `=>>`.
      if depth == 0 && starts_eq && second_gt && extra == 1 {
        r.has_case_arrow = true
      }
      r.ends_conditional = false
    } else if scala_is_word_start(c) {
      // `char word[sizeof "then"]`.
      let (len, word, _) = scala_read_word(lexer, 5)
      r.ends_conditional = depth == 0 &&
        len > 0 &&
        (word == "then" || word == "do")
    } else {
      r.ends_conditional = false
      lexer.advance(false)
    }
  }
  r
}

///|
/// Consumes `digit (digit | '_' digit)*`. Sets `saw_sep` if a separator appears.
fn scala_consume_digit_group(
  lexer : @runtime.Lexer,
  saw_sep : Ref[Bool]?,
) -> Bool {
  if lexer.lookahead < '0' || lexer.lookahead > '9' {
    return false
  }
  lexer.advance(false)
  for ;; {
    if lexer.lookahead >= '0' && lexer.lookahead <= '9' {
      lexer.advance(false)
    } else if lexer.lookahead == '_' {
      lexer.advance(false)
      if lexer.lookahead < '0' || lexer.lookahead > '9' {
        return false
      }
      if saw_sep is Some(saw_sep) {
        saw_sep.val = true
      }
      lexer.advance(false)
    } else {
      return true
    }
  }
}

///|
/// Lexes a floating point literal whose integer part uses digit separators, e.g.
/// `1_000.5`. The internal regex cannot. After an underscore-containing group
/// its DFA loses the transition to the following `.`.
fn scala_scan_float_with_separator(lexer : @runtime.Lexer) -> Bool {
  let int_sep = Ref(false)
  if !scala_consume_digit_group(lexer, Some(int_sep)) {
    return false
  }
  // Only the integer-part separator is ours. Without one the internal lexer
  // lexes the number, so bail before walking the fraction and exponent.
  if !int_sep.val {
    return false
  }
  let mut is_float = false
  if lexer.lookahead == '.' {
    lexer.advance(false)
    if !scala_consume_digit_group(lexer, None) {
      return false
    }
    is_float = true
  }
  if lexer.lookahead == 'e' || lexer.lookahead == 'E' {
    lexer.advance(false)
    if lexer.lookahead == '+' || lexer.lookahead == '-' {
      lexer.advance(false)
    }
    if !scala_consume_digit_group(lexer, None) {
      return false
    }
    is_float = true
  }
  if lexer.lookahead == 'd' ||
    lexer.lookahead == 'D' ||
    lexer.lookahead == 'f' ||
    lexer.lookahead == 'F' {
    lexer.advance(false)
    is_float = true
  }
  // A bare integer with separators (`1_000`) is the internal lexer's job.
  if !is_float {
    return false
  }
  lexer.mark_end()
  lexer.result_symbol = SCALA_FLOATING_POINT_WITH_SEPARATORS
  true
}

///|
/// `tree_sitter_scala_external_scanner_scan`.
fn ScalaScanner::external_scan(
  self : ScalaScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  let res = self.scan_impl(lexer, valid_symbols)
  // Track whether the last returned token was a fewer-braces colon. Comments
  // in between keep the flag. A false return does not persist state anyway.
  if res {
    if lexer.result_symbol == SCALA_COLON_EOL {
      self.after_colon_eol = 1
    } else if lexer.result_symbol != SCALA_BLOCK_COMMENT {
      self.after_colon_eol = 0
    }
  }
  res
}

///|
let scala_block_opening_stoppers : Array[String] = [
  "else", "catch", "finally", "yield", "do",
]

///|
let scala_gated_stoppers : Array[String] = ["else", "catch", "finally", "yield"]

///|
/// `continuing_words`: word, symbol and whether it is gated.
let scala_continuing_words : Array[(String, Int32, Bool)] = [
  ("else", SCALA_ELSE, true),
  ("catch", SCALA_CATCH, true),
  ("finally", SCALA_FINALLY, true),
  ("extends", SCALA_EXTENDS, false),
  ("with", SCALA_WITH, false),
  ("derives", SCALA_DERIVES, false),
  ("uses", SCALA_USES, false),
]

///|
let scala_block_closing_words : Array[String] = ["else", "catch", "finally"]

///|
/// `soft_modifiers`: first character, word and symbol.
let scala_soft_modifiers : Array[(Int32, String, Int32)] = [
  ('e', "erased", SCALA_ERASED_MODIFIER),
  ('o', "open", SCALA_OPEN_MODIFIER),
  ('o', "opaque", SCALA_OPAQUE_MODIFIER),
  ('i', "infix", SCALA_INFIX_MODIFIER),
  ('t', "tracked", SCALA_TRACKED_MODIFIER),
  ('t', "transparent", SCALA_TRANSPARENT_MODIFIER),
  ('i', "inline", SCALA_INLINE_MODIFIER),
  ('i', "into", SCALA_INTO_MODIFIER),
  ('u', "update", SCALA_UPDATE_MODIFIER),
  ('c', "consume", SCALA_CONSUME_MODIFIER),
]

///|
let scala_reserved_ops : Array[String] = [
  "=", "#", "@", "=>", "<-", "<:", ">:", "<%", "?=>", "=>>",
]

///|
let scala_definition_words : Array[String] = [
  "abstract", "class", "def", "enum", "export", "final", "given", "import", "implicit",
  "lazy", "object", "override", "package", "private", "protected", "sealed", "trait",
  "type", "val", "var",
]

///|
let scala_tail_words : Array[String] = [
  "catch", "else", "finally", "then", "yield",
]

///|
fn ScalaScanner::scan_impl(
  self : ScalaScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  // The `>` of a using directive. It is immediate after the `//`, so this has
  // to run before the blanks are skipped below.
  if valid_symbols[SCALA_USING_DIRECTIVE_START] &&
    !valid_symbols[SCALA_ERROR_SENTINEL] &&
    lexer.lookahead == '>' {
    lexer.advance(false)
    lexer.mark_end()
    ignore(scala_advance_past_blanks(lexer))
    if !scala_scan_word(lexer, "using") {
      return false
    }
    lexer.result_symbol = SCALA_USING_DIRECTIVE_START
    return true
  }

  // The grammar takes this `?` only in front of a type lambda, so the bracket
  // has to be here before the word is handed over. The blanks are skipped
  // rather than advanced, which keeps them out of the token.
  if valid_symbols[SCALA_WILDCARD_BOUND_START] &&
    !valid_symbols[SCALA_ERROR_SENTINEL] {
    while lexer.lookahead == ' ' || lexer.lookahead == '\t' {
      lexer.advance(true)
    }
  }
  if valid_symbols[SCALA_WILDCARD_BOUND_START] &&
    !valid_symbols[SCALA_ERROR_SENTINEL] &&
    lexer.lookahead == '?' {
    lexer.advance(false)
    lexer.mark_end()
    ignore(scala_advance_past_blanks(lexer))
    if lexer.lookahead != '<' && lexer.lookahead != '>' {
      return false
    }
    lexer.advance(false)
    if lexer.lookahead != ':' {
      return false
    }
    lexer.advance(false)
    ignore(scala_advance_past_blanks(lexer))
    if lexer.lookahead != '[' {
      return false
    }
    lexer.result_symbol = SCALA_WILDCARD_BOUND_START
    return true
  }
  let prev = if self.indents.length() > 0 {
    self.indents[self.indents.length() - 1]
  } else {
    -1
  }
  let prev_width = scala_indent_width(prev)
  // `int16_t newline_count`, `int16_t indentation_size`.
  let mut newline_count = 0
  let mut indentation_size = 0
  while scala_is_space(lexer.lookahead) {
    if lexer.lookahead == '\n' {
      newline_count = scala_i16(newline_count + 1)
      indentation_size = 0
    } else {
      indentation_size = scala_i16(indentation_size + 1)
    }
    lexer.advance(true)
  }

  // COMMA_OUTDENT is a distinct token so tree-sitter only makes it valid
  // where comma termination is expected (colon_argument,
  // _indentable_expression).
  if valid_symbols[SCALA_COMMA_OUTDENT] && lexer.lookahead == ',' && prev != -1 {
    lexer.mark_end()
    // Error recovery makes every symbol valid, so keep the eager pop there.
    if !valid_symbols[SCALA_ERROR_SENTINEL] {
      lexer.advance(false)
      let mut ends_line = false
      for ;; {
        ignore(scala_advance_past_blanks(lexer))
        if lexer.eof() || lexer.lookahead == '\n' || lexer.lookahead == '\r' {
          ends_line = true
          break
        }
        if lexer.lookahead != '/' {
          break
        }
        lexer.advance(false)
        if lexer.lookahead == '/' {
          ends_line = true // line comment runs to the line end
          break
        }
        if lexer.lookahead != '*' {
          break // a lone '/' is code
        }
        lexer.advance(false)
        scala_consume_block_comment_body(lexer)
      }
      // POSTFIX_OP is offered only where an operand just ended, so the comma
      // separates arguments rather than continuing a list of names. The closer
      // catches what is left, where no operand ended before the comma.
      if !ends_line &&
        !valid_symbols[SCALA_POSTFIX_OP] &&
        !scala_scan_rest_of_line(lexer).closes_bracket {
        return false
      }
    }
    if self.indents.length() > 0 {
      ignore(self.indents.pop())
    }
    lexer.result_symbol = SCALA_COMMA_OUTDENT
    return true
  }

  // Closes a same-width case region mid-cascade after a deeper region popped and
  // the line sits at this region's width. It stays open only for another `case`
  // clause, and returning false is safe because `case` is the only token that can
  // follow. The column check guards against a stale last_indentation_size when
  // intervening states emit no external token.
  if valid_symbols[SCALA_OUTDENT] &&
    !valid_symbols[SCALA_ERROR_SENTINEL] &&
    self.last_indentation_size != -1 &&
    scala_at_case_region_width(prev, self.last_indentation_size) &&
    (if lexer.eof() {
      self.last_column == -1
    } else {
      scala_i16(lexer.get_column().reinterpret_as_int()) == self.last_column
    }) {
    lexer.mark_end()
    if scala_is_case_clause_intro(lexer) {
      return false
    }
    ignore(self.indents.pop())
    lexer.result_symbol = SCALA_OUTDENT
    return true
  }

  // Before advancing the lexer, check if we can double outdent
  if valid_symbols[SCALA_OUTDENT] &&
    (
      lexer.lookahead == 0 ||
      (
        prev != -1 &&
        (
          lexer.lookahead == ')' ||
          lexer.lookahead == ']' ||
          lexer.lookahead == '}'
        )
      ) ||
      (
        self.last_indentation_size != -1 &&
        prev != -1 &&
        self.last_indentation_size < prev_width
      )
    ) {
    if self.indents.length() > 0 {
      ignore(self.indents.pop())
    }
    lexer.result_symbol = SCALA_OUTDENT
    return true
  }
  self.last_indentation_size = -1

  // True when the line is deeper than the current region. An empty stack has
  // prev_width == -1, so any width counts as deeper. A same-width line right
  // after a fewer-braces colon also opens a block (the body may sit there).
  let indent_geometry = indentation_size > prev_width ||
    (self.after_colon_eol != 0 && indentation_size == prev_width)
  if valid_symbols[SCALA_INDENT] &&
    newline_count > 0 &&
    // An indented block cannot start with a closing delimiter, e.g. the
    // `}` after an empty-bodied lambda: `foo { x =>` + newline + `}`.
    lexer.lookahead != '}' &&
    lexer.lookahead != ')' &&
    lexer.lookahead != ']' &&
    (
      indent_geometry ||
      // A comment at exactly the region width can hide a deeper line
      // behind it. Probe it and let the code's column decide below.
      (indentation_size == prev_width && lexer.lookahead == '/')
    ) {
    lexer.mark_end()
    match scala_check_comment_at_layout(lexer, valid_symbols) {
      CommentLexed => return true
      CommentAbort => return false
      CommentSameLineCode => {
        // The line's content starts after the comment; its column is the
        // effective indentation (`if x then` + `  /* c */ body`).
        let effective = scala_i16(lexer.get_column().reinterpret_as_int())
        if effective > prev_width {
          indentation_size = effective
        } else {
          // The code does not open a block after all, so lex the comment.
          return scala_finish_block_comment(lexer)
        }
      }
      CommentNone =>
        if !indent_geometry {
          return false // entered only to probe a comment; this is code
        }
    }
    // An indented block cannot start with else/catch/finally, nor with
    // yield/do, which belong to an enclosing `for (...)` whose body is also
    // indentable. Read the word whole so a partial match cannot mislead.
    let mut entry = indentation_size
    match lexer.lookahead {
      'e' | 'c' | 'f' | 'y' | 'd' => {
        // `char word[sizeof "finally"]`.
        let (len, word, _) = scala_read_word(lexer, 8)
        if len > 0 && scala_word_in(word, scala_block_opening_stoppers) {
          // The keyword belongs to an enclosing construct. Where its gate is
          // valid and the word is a gated one, emit it (zero width: mark_end
          // ran above) so the keyword can shift; otherwise no block opens
          // here. `do` stays ungated: it can start a statement, and gate
          // validity blends in from unrelated GLR forks.
          if valid_symbols[SCALA_CONTROL_TAIL_GATE] &&
            scala_word_in(word, scala_gated_stoppers) {
            lexer.result_symbol = SCALA_CONTROL_TAIL_GATE
            return true
          }
          return false
        }
        // At top level the stack is empty, so the same-width `case` close at
        // the bottom of scan() never sees a width-0 `match`/`case`. Flag the
        // region here instead. The arrow rules out an enum `case Foo`, which
        // has none and must not open a case region.
        if self.indents.length() == 0 &&
          len == 4 &&
          word == "case" &&
          !scala_is_case_definition_word(lexer) &&
          scala_scan_rest_of_line(lexer).has_case_arrow {
          entry = scala_i16(entry | SCALA_CASE_INDENT_FLAG)
        }
      }
      '|' | '&' =>
        // Nor with a leading `|`/`&` infix operator, which continues the
        // previous expression. Only these two run here, and not after a colon,
        // where the line can only be the body.
        if self.after_colon_eol == 0 &&
          scala_is_leading_infix_continuation(lexer) {
          return false
        }
      _ => ()
    }
    self.indents.push(entry)
    lexer.result_symbol = SCALA_INDENT
    return true
  }

  // This saves the indentation_size and newline_count so it can be used
  // in subsequent calls for multiple outdent or auto-semicolon.
  // A same-width case region also closes on a line at its own width when
  // that line does not start another `case` clause.
  let case_region_close = newline_count > 0 &&
    scala_at_case_region_width(prev, indentation_size)
  if valid_symbols[SCALA_OUTDENT] &&
    (
      lexer.lookahead == 0 ||
      (newline_count > 0 && prev != -1 && indentation_size < prev_width) ||
      case_region_close
    ) {
    lexer.mark_end()
    match scala_check_comment_at_layout(lexer, valid_symbols) {
      CommentLexed => return true
      CommentAbort => return false
      CommentSameLineCode => {
        // The line's content starts after the comment; its column is the
        // effective indentation (` /** doc */ override def f...` inside a
        // braced body must not close the region at the comment's column).
        let effective = scala_i16(lexer.get_column().reinterpret_as_int())
        if effective < prev_width {
          indentation_size = effective
        } else {
          // Not an outdent after all. The automatic semicolon has its own
          // suppression rules, so lex the comment and let the next scan
          // decide, carrying the newline through the recovery below.
          self.last_newline_count = newline_count
          self.last_column = effective
          self.last_char = scala_i16(lexer.lookahead & 0x7FFF)
          return scala_finish_block_comment(lexer)
        }
      }
      CommentNone => ()
    }
    self.last_indentation_size = indentation_size
    self.last_newline_count = newline_count
    if lexer.eof() {
      self.last_column = -1
      self.last_char = 0
    } else {
      self.last_column = scala_i16(lexer.get_column().reinterpret_as_int())
      self.last_char = scala_i16(lexer.lookahead & 0x7FFF)
    }
    // Keep the indented block open when the next line starts with a leading
    // infix operator, which continues the previous expression. But a line
    // ending in depth-0 `then`/`do` closes the regions up to its conditional.
    if lexer.lookahead != 0 &&
      scala_is_leading_infix_continuation(lexer) &&
      !scala_scan_rest_of_line(lexer).ends_conditional {
      return false
    }
    // A same-width `case` line continues the case region instead.
    if case_region_close && scala_is_case_clause_intro(lexer) {
      return false
    }
    if self.indents.length() > 0 {
      ignore(self.indents.pop())
    }
    lexer.result_symbol = SCALA_OUTDENT
    return true
  }

  // Recover newline_count from the outdent reset. Skipped when this scan
  // crossed a newline itself, because the saved count belongs to an
  // earlier line at the same column.
  // Nothing to recover when the count is zero, and get_column costs a rescan
  // of the line, so gate the whole test on it.
  if self.last_newline_count > 0 {
    let is_eof = lexer.eof()
    if (is_eof && self.last_column == -1) ||
      (
        !is_eof &&
        newline_count == 0 &&
        scala_i16(lexer.lookahead & 0x7FFF) == self.last_char &&
        // `get_column(lexer) == (uint32_t)last_column`.
        lexer.get_column() == self.last_column.reinterpret_as_uint()
      ) {
      newline_count = scala_i16(newline_count + self.last_newline_count)
    }
  }
  self.last_newline_count = 0

  // END_KEYWORD is only valid right after the semicolon the grammar puts
  // in front of a marker. Emit it when the tag word confirms the marker
  // shape.
  if valid_symbols[SCALA_END_KEYWORD] &&
    !valid_symbols[SCALA_ERROR_SENTINEL] &&
    lexer.lookahead == 'e' {
    if scala_scan_word(lexer, "end") && scala_name_follows_word(lexer) {
      lexer.mark_end()
      lexer.result_symbol = SCALA_END_KEYWORD
      return true
    }
    return false
  }

  // Runs before the plain semicolon below, so the header break wins where the
  // parser offers it.
  if valid_symbols[SCALA_DEF_SEMICOLON] &&
    !valid_symbols[SCALA_ERROR_SENTINEL] &&
    newline_count > 0 &&
    (lexer.lookahead == '(' || lexer.lookahead == '[' || lexer.lookahead == ':') {
    lexer.mark_end()
    lexer.result_symbol = SCALA_DEF_SEMICOLON
    return true
  }
  if valid_symbols[SCALA_AUTOMATIC_SEMICOLON] && newline_count > 0 {
    // AUTOMATIC_SEMICOLON should not be issued in the middle of expressions
    // Thus, we exit this branch when encountering comments, else/catch clauses, etc.

    lexer.mark_end()
    lexer.result_symbol = SCALA_AUTOMATIC_SEMICOLON

    // Probably, a multi-line field expression, e.g.
    // a
    //  .b
    //  .c
    if lexer.lookahead == '.' {
      return false
    }

    // A statement never ends right before a closing bracket, and marker
    // slots would otherwise ask for a semicolon here.
    if lexer.lookahead == ')' ||
      lexer.lookahead == ']' ||
      lexer.lookahead == ',' {
      return false
    }

    // Same, and it keeps a braced else-if chain from forking one marker
    // head per nested if. A `}` line that continues with more code
    // (`} | Mate`) keeps the semicolon and the old reading of its tail. A
    // trailing comment counts as the line end.
    if lexer.lookahead == '}' {
      lexer.advance(false)
      for ;; {
        ignore(scala_advance_past_blanks(lexer))
        if lexer.lookahead == '}' ||
          lexer.lookahead == ')' ||
          lexer.lookahead == ']' {
          lexer.advance(false)
          continue
        }
        if lexer.lookahead == '/' {
          lexer.advance(false)
          if lexer.lookahead == '/' {
            return false
          }
          if lexer.lookahead == '*' {
            lexer.advance(false)
            scala_consume_block_comment_body(lexer)
            continue
          }
        }
        break
      }
      if lexer.lookahead == '\n' || lexer.lookahead == '\r' || lexer.eof() {
        return false
      }
      return true
    }

    // Single-line and multi-line comments
    if lexer.lookahead == '/' {
      lexer.advance(false)
      if lexer.lookahead == '/' {
        return false
      }
      if lexer.lookahead == '*' && valid_symbols[SCALA_BLOCK_COMMENT] {
        lexer.advance(false)
        // The suppression rules must also see code after the comment
        // (`/* c */ else 2` must not be split). Lex the comment and carry
        // the pending newline to the next scan through the recovery above.
        scala_consume_block_comment_body(lexer)
        ignore(scala_advance_past_blanks(lexer))
        if !(lexer.lookahead == '\n' || lexer.lookahead == '\r' || lexer.eof()) {
          self.last_newline_count = newline_count
          self.last_column = scala_i16(lexer.get_column().reinterpret_as_int())
          self.last_char = scala_i16(lexer.lookahead & 0x7FFF)
        }
        return scala_finish_block_comment(lexer)
      }
      // A lone '/' falls through with the lexer advanced past it, matching
      // the old flow.
    }

    // A blank line still separates the statements, here and in the word
    // branch below.
    if scala_is_op_char(lexer.lookahead) {
      let (len, op) = scala_read_op_chars(lexer)
      // No statement break before a symbolic keyword, which cannot start a
      // statement. `@` is the one that can, since it opens an annotation.
      if scala_is_symbolic_keyword(op, len) {
        return len == 1 && op == "@"
      }
      if newline_count == 1 && scala_operand_follows(lexer) {
        return false
      }
      return true
    }
    if lexer.lookahead == '`' {
      if newline_count == 1 && scala_is_leading_infix_continuation(lexer) {
        return false
      }
      return true
    }

    // A keyword that continues the enclosing expression suppresses the
    // semicolon, even when several are valid at once. Names and keywords
    // start alike, so the word is read once here and matched whole.
    if scala_is_word_start(lexer.lookahead) {
      // `char word[sizeof "finally"]`.
      let (len, word, underscore_tail) = scala_read_word(lexer, 8)
      // A name whose last characters are operator ones is an operator too,
      // so a line starting with it continues the line above. See isOperator
      // in the reference scanner.
      if underscore_tail && scala_is_op_char(lexer.lookahead) {
        while scala_is_op_char(lexer.lookahead) {
          lexer.advance(false)
        }
        if newline_count == 1 && scala_operand_follows(lexer) {
          return false
        }
        return true
      }
      if len <= 0 {
        return true
      }
      // The first three also open a control tail, whose gate is zero width
      // since mark_end ran above.
      for entry in scala_continuing_words {
        let (cword, symbol, gated) = entry
        let gate = gated && valid_symbols[SCALA_CONTROL_TAIL_GATE]
        // Validity first: it rules out most words without the comparison.
        if (!gate && !valid_symbols[symbol]) || word != cword {
          continue
        }
        if gate {
          lexer.result_symbol = SCALA_CONTROL_TAIL_GATE
          return true
        }
        return false
      }
      // A case clause line needs no separator, and suppressing it keeps
      // a long else-if chain from forking one marker head per nested if
      // right before it. A case definition keeps its separator, and so
      // does a clause line that closes an enclosing bracket, whose
      // separator belongs to the surrounding expression.
      if word == "case" && !scala_is_case_definition_word(lexer) {
        let line = scala_scan_rest_of_line(lexer)
        if line.has_case_arrow && !line.closes_bracket {
          return false
        }
        return true
      }
      // `match` is a reserved word that never starts a statement, so it
      // always continues the previous expression.
      if word == "match" {
        return false
      }
    }
    return true
  }

  // An else/catch/finally that is not directly shiftable must first close the
  // open indented region (a dedented `else` after a braceless match closes it),
  // and `erased` is the modifier when a name follows. Both read the word, so it
  // is read once here. Skipped during error recovery, where every symbol looks
  // valid.
  let outdent_arm = valid_symbols[SCALA_OUTDENT] &&
    !valid_symbols[SCALA_CONTROL_TAIL_GATE] &&
    newline_count == 0 &&
    prev != -1 &&
    (
      (lexer.lookahead == 'e' && !valid_symbols[SCALA_ELSE]) ||
      (lexer.lookahead == 'c' && !valid_symbols[SCALA_CATCH]) ||
      (lexer.lookahead == 'f' && !valid_symbols[SCALA_FINALLY])
    )
  // These are names too, and an alternative for each in every name position
  // cost the parse tables about 150KB per word. Lexing them here means the
  // parser only sees one where a modifier can stand.
  // Character first: it rules out most positions without the array load.
  let mut modifier_arm = false
  for entry in scala_soft_modifiers {
    let (first, _, symbol) = entry
    if lexer.lookahead == first && valid_symbols[symbol] {
      modifier_arm = true
      break
    }
  }
  // The reader below cannot rewind, so `case` compares there rather than
  // scanning on its own and eating the start of another word.
  let case_definition_arm = valid_symbols[SCALA_CASE_DEFINITION_KEYWORD] &&
    lexer.lookahead == 'c'
  if !valid_symbols[SCALA_ERROR_SENTINEL] &&
    (outdent_arm || modifier_arm || case_definition_arm) {
    if outdent_arm {
      // OUTDENT is zero-width at the word, and the lexer cannot rewind once
      // read_word has consumed it.
      lexer.mark_end()
    }
    // Sized for the longest word above: `char word[sizeof "transparent"]`.
    let (len, word, _) = scala_read_word(lexer, 12)
    // read_word returns -1 when the word overflows the buffer, which would
    // otherwise leave a truncated prefix to compare against.
    if len > 0 {
      if case_definition_arm && word == "case" {
        lexer.mark_end()
        if scala_is_case_definition_word(lexer) {
          lexer.result_symbol = SCALA_CASE_DEFINITION_KEYWORD
          return true
        }
        return false
      }
      let mut modifier = 0
      for entry in scala_soft_modifiers {
        let (_, mword, symbol) = entry
        if valid_symbols[symbol] && word == mword {
          modifier = symbol
          break
        }
      }
      if modifier != 0 {
        // The modifier spans the word, unlike the zero-width OUTDENT.
        lexer.mark_end()
        // A name follows a modifier, so `def open(p)` and `a.infix` keep
        // reading as plain identifiers.
        let follows = if modifier == SCALA_INLINE_MODIFIER {
          scala_inline_modifier_follows(lexer)
        } else {
          scala_modifier_name_follows(lexer)
        }
        if follows {
          lexer.result_symbol = modifier
          return true
        }
        return false
      }
      if outdent_arm && scala_word_in(word, scala_block_closing_words) {
        if self.indents.length() > 0 {
          ignore(self.indents.pop())
        }
        lexer.result_symbol = SCALA_OUTDENT
        return true
      }
    }
    // The lexer has advanced past the word; nothing else can match it.
    return false
  }
  while scala_is_space(lexer.lookahead) {
    if lexer.lookahead == '\n' {
      newline_count = scala_i16(newline_count + 1)
    }
    lexer.advance(true)
  }

  // XML mode (SLS §10) starts only where the grammar makes XML_TAG_START
  // valid and the `<` is immediately followed by a name-start character, so
  // `< b` and `<-`, `<:`, `<=` fall through to the regular operator tokens.
  if valid_symbols[SCALA_XML_TAG_START] &&
    !valid_symbols[SCALA_ERROR_SENTINEL] &&
    lexer.lookahead == '<' {
    lexer.advance(false)
    if scala_is_xml_name_start(lexer.lookahead) {
      lexer.mark_end()
      lexer.result_symbol = SCALA_XML_TAG_START
      return true
    }
    return false
  }

  // A floating point literal whose integer part uses digit separators.
  if valid_symbols[SCALA_FLOATING_POINT_WITH_SEPARATORS] &&
    !valid_symbols[SCALA_ERROR_SENTINEL] &&
    lexer.lookahead >= '0' &&
    lexer.lookahead <= '9' {
    return scala_scan_float_with_separator(lexer)
  }

  // A symbolic operator in postfix position is lexed here, as is the
  // fewer-braces colon. An operator that continues its expression, on the
  // same line or over a line break, stays with the internal per-class
  // tokens: since the postfix reading only exists through this branch, the
  // internal tokens admit no statement split after `left op`.
  // COLON_EOL only ever lexes a lone `:`, so that leg needs a colon first.
  // The branch also carries every operator ending in `/`, which the internal
  // tokens cannot express, so an operator class alone opens it too.
  if !valid_symbols[SCALA_ERROR_SENTINEL] &&
    scala_is_op_char(lexer.lookahead) &&
    (
      (valid_symbols[SCALA_COLON_EOL] && lexer.lookahead == ':') ||
      valid_symbols[SCALA_POSTFIX_OP] ||
      valid_symbols[SCALA_POSTFIX_STAR] ||
      valid_symbols[scala_op_left_class(lexer.lookahead)] ||
      valid_symbols[SCALA_OP_NAME]
    ) {
    // Collect the operator. Only the first 3 chars are kept, since anything
    // longer cannot be one of the reserved sequences checked below. The
    // entry condition already checked the first character.
    let op_buf = StringBuilder()
    let mut op_len = 0
    for ;; {
      if op_len < 3 {
        op_buf.write_char(lexer.lookahead.unsafe_to_char())
      }
      op_len += 1
      lexer.advance(false)
      if !scala_is_op_char(lexer.lookahead) {
        break
      }
    }
    let op = op_buf.to_string()
    lexer.mark_end()
    // A `/` next carries the operator on, so the colon is not a lone one.
    if op_len == 1 && op == ":" && lexer.lookahead != '/' {
      // A lone `:` ending its line is the fewer-braces colon (scalac's
      // COLONeol). Deciding it at the token level kills the cross-newline
      // ascription fork that GLR would otherwise keep alive across the region.
      if valid_symbols[SCALA_COLON_EOL] &&
        scala_rest_of_line_is_blank_or_comments(lexer) {
        lexer.result_symbol = SCALA_COLON_EOL
        return true
      }
      return false
    }
    // An operator may end in `/` when that `/` does not open a comment. A
    // regex cannot see the character after it, so this is the only reading,
    // and the first character alone fixes the SLS 6.12.3 precedence class.
    // `#!` opens a script header, whose path is not part of an operator.
    let shebang = op_len >= 2 && op[0] == '#' && op[1] == '!'
    let op_class = scala_op_left_class(op[0].to_int())
    if lexer.lookahead == '/' &&
      !shebang &&
      (valid_symbols[op_class] || valid_symbols[SCALA_OP_NAME]) {
      // One step per OP_STEP in grammar.js. A `/` is taken only when what
      // follows it cannot open a comment, so the token never needs to give
      // characters back and the end is marked once, on the way out.
      let mut ends_in_slash = false
      let mut at_comment = false
      while !at_comment {
        let c = lexer.lookahead
        if c == '/' {
          lexer.advance(false)
          at_comment = lexer.lookahead == '/' || lexer.lookahead == '*'
        } else if scala_is_op_char(c) {
          lexer.advance(false)
        } else {
          break
        }
        ends_in_slash = !at_comment && c == '/'
      }
      // A Unicode opchar would carry the operator past what this reads, so
      // hand the whole token back to the internal lexer.
      if ends_in_slash && lexer.lookahead < 0x80 {
        lexer.mark_end()
        lexer.result_symbol = if valid_symbols[op_class] {
          op_class
        } else {
          SCALA_OP_NAME
        }
        return true
      }
      return false
    }
    // The branch is also entered for COLON_EOL-only states. Everything from
    // here on emits a postfix token, so bail out early where none is valid.
    let postfix_sym = if op_len == 1 && op == "*" {
      SCALA_POSTFIX_STAR
    } else {
      SCALA_POSTFIX_OP
    }
    if !valid_symbols[postfix_sym] {
      return false
    }
    // These sequences are not infix operators, so the line does not
    // continue. They mirror the grammar's reserved string tokens. Entries
    // must stay at most 3 characters, or op[] above must grow. The
    // first-character gate skips the scan for the common operators.
    if op[0] == '=' ||
      op[0] == '<' ||
      op[0] == '>' ||
      op[0] == '#' ||
      op[0] == '@' ||
      op[0] == '?' {
      if op_len <= 3 && scala_word_in(op, scala_reserved_ops) {
        return false
      }
    }
    // A trailing comment counts as the line end because scalac treats it as
    // transparent, so `p || // c` still continues on the next line.
    if !scala_rest_of_line_is_blank_or_comments(lexer) {
      // Mid-line, the call left the lookahead at the next real character (or
      // just past a lone `/`). An operator directly before a closing
      // delimiter or a list separator is postfix: the vararg splice `f(xs*)`
      // or `(p | q.r +) ^^ t`. The external token makes the whole
      // lower-precedence chain reduce first, which the per-class infix
      // tokens would not allow.
      if scala_is_close_or_separator(lexer.lookahead) {
        lexer.result_symbol = postfix_sym
        return true
      }
      // The assignment `=` starts no expression either, so the operator is
      // the postfix one an update calls (`v<1> = 10`). The end is marked,
      // so reading past it to rule out `=>` and `==` is free.
      if lexer.lookahead == '=' {
        lexer.advance(false)
        if !scala_is_op_char(lexer.lookahead) {
          lexer.result_symbol = postfix_sym
          return true
        }
      }
      return false
    }
    // The right operand must be able to start an expression. Comments and line
    // breaks before it are transparent. A comment-only tail to EOF is postfix.
    if !scala_has_operand(lexer) {
      lexer.result_symbol = postfix_sym
      return true
    }
    // A `.` or a `=` next also ends the infix reading, but those lines read
    // best with the internal tokens, as before.
    if lexer.lookahead == '.' || lexer.lookahead == '=' {
      return false
    }
    // No expression starts with `@` either. The next line is an annotated
    // definition, so the operator was postfix (`x --?` + `@deprecated val
    // y = 1`).
    if lexer.lookahead == '@' {
      lexer.result_symbol = postfix_sym
      return true
    }
    // A next line starting with a definition or modifier keyword begins a new
    // statement, so the operator was postfix (`x --?` + `val y = ...`, Scala 2
    // postfixOps).
    if lexer.lookahead >= 'a' && lexer.lookahead <= 'z' {
      // Hard keywords that can only begin a definition. Soft modifiers
      // (`inline`, `open`, `opaque`, `transparent`, `infix`) stay out: they
      // are ordinary identifiers, so such a line can be the right operand.
      // Sized for the longest word above. read_word reports a longer or
      // non-ASCII identifier as -1, which correctly skips the check.
      // `char word[sizeof "protected"]`.
      let (len, word, _) = scala_read_word(lexer, 10)
      if len > 0 && scala_word_in(word, scala_definition_words) {
        lexer.result_symbol = postfix_sym
        return true
      }
    }
    // Any other operand continues the expression, on this line or over the
    // break; the internal per-class token carries the operator's precedence.
    return false
  }

  // Mid-line block comments with no layout decision pending. `/*` is plain
  // text where SUPPRESS_BLOCK_COMMENT or a string-content state is valid.
  // In error recovery all symbols look valid and lexing the comment is safe.
  if valid_symbols[SCALA_BLOCK_COMMENT] &&
    lexer.lookahead == '/' &&
    (
      valid_symbols[SCALA_ERROR_SENTINEL] ||
      !(valid_symbols[SCALA_SUPPRESS_BLOCK_COMMENT] ||
      valid_symbols[SCALA_SIMPLE_STRING_MIDDLE] ||
      valid_symbols[SCALA_INTERPOLATED_STRING_MIDDLE] ||
      valid_symbols[SCALA_RAW_STRING_MIDDLE] ||
      valid_symbols[SCALA_RAW_STRING_MULTILINE_MIDDLE] ||
      valid_symbols[SCALA_INTERPOLATED_MULTILINE_STRING_MIDDLE] ||
      valid_symbols[SCALA_MULTILINE_STRING_END])
    ) {
    lexer.advance(false)
    if lexer.lookahead == '*' {
      lexer.advance(false)
      return scala_lex_block_comment(lexer)
    }
    // A lone '/' or a line comment. Nothing else external can match here.
    return false
  }
  if valid_symbols[SCALA_SIMPLE_STRING_START] && lexer.lookahead == '"' {
    lexer.advance(false)
    lexer.mark_end()
    if lexer.lookahead == '"' {
      lexer.advance(false)
      if lexer.lookahead == '"' {
        lexer.advance(false)
        lexer.result_symbol = SCALA_SIMPLE_MULTILINE_STRING_START
        lexer.mark_end()
        return true
      }
    }
    lexer.result_symbol = SCALA_SIMPLE_STRING_START
    return true
  }

  // We need two tokens of lookahead to determine if we are parsing a raw string,
  // the `raw` and the `"`, which is why we need to do it in the external scanner.
  if valid_symbols[SCALA_RAW_STRING_START] && lexer.lookahead == 'r' {
    lexer.advance(false)
    if lexer.lookahead == 'a' {
      lexer.advance(false)
      if lexer.lookahead == 'w' {
        lexer.advance(false)
        if lexer.lookahead == '"' {
          lexer.mark_end()
          lexer.result_symbol = SCALA_RAW_STRING_START
          return true
        }
      }
    }
  }
  if valid_symbols[SCALA_SIMPLE_STRING_MIDDLE] {
    return scala_scan_string_content(lexer, false, Simple)
  }
  if valid_symbols[SCALA_INTERPOLATED_STRING_MIDDLE] {
    return scala_scan_string_content(lexer, false, Interpolated)
  }
  if valid_symbols[SCALA_RAW_STRING_MIDDLE] {
    return scala_scan_string_content(lexer, false, Raw)
  }
  if valid_symbols[SCALA_RAW_STRING_MULTILINE_MIDDLE] {
    return scala_scan_string_content(lexer, true, Raw)
  }
  if valid_symbols[SCALA_INTERPOLATED_MULTILINE_STRING_MIDDLE] {
    return scala_scan_string_content(lexer, true, Interpolated)
  }

  // We still need to handle the simple multiline string case, but there is
  // no `MULTILINE_STRING_MIDDLE` token, and `MULTILINE_STRING_END` is used
  // by all three of simple raw, and interpolated multiline strings. So this
  // check needs to come after the `INTERPOLATED_MULTILINE_STRING_MIDDLE` and
  // `RAW_STRING_MULTILINE_MIDDLE` check, so that we can be sure we are in a
  // simple multiline string context.
  if valid_symbols[SCALA_MULTILINE_STRING_END] {
    return scala_scan_string_content(lexer, true, Simple)
  }

  // Scala 3 lets a `match`/`catch`'s `case` clauses align with the enclosing
  // region instead of indenting deeper. Open a flagged region so the OUTDENT
  // logic above closes it on a same-width non-case line. Only states after
  // `match`/`catch` or a case `=>` reach here, so no new grammar production is
  // needed. Returning false is safe because lookahead 'c' lets no other external
  // token fire.
  if valid_symbols[SCALA_INDENT] &&
    !valid_symbols[SCALA_ERROR_SENTINEL] &&
    newline_count > 0 &&
    lexer.lookahead == 'c' &&
    prev != -1 &&
    indentation_size == prev_width {
    lexer.mark_end()
    if scala_is_case_clause_intro(lexer) {
      self.indents.push(scala_i16(indentation_size | SCALA_CASE_INDENT_FLAG))
      lexer.result_symbol = SCALA_INDENT
      return true
    }
    // The word was not `case`. A `catch` at this width belongs to an
    // enclosing try. The `case` probe above stopped at its `t`, so the
    // remainder is `tch` (zero width: mark_end ran above).
    if valid_symbols[SCALA_CONTROL_TAIL_GATE] && scala_scan_word(lexer, "tch") {
      lexer.result_symbol = SCALA_CONTROL_TAIL_GATE
      return true
    }
    return false
  }

  // Zero-width gate before a control-tail keyword (see _control_tail_gate in
  // the grammar). Tails on the same line, and tails the semicolon machinery
  // never sees (inside parentheses, or after an emitted semicolon slot),
  // arrive here.
  if valid_symbols[SCALA_CONTROL_TAIL_GATE] &&
    !valid_symbols[SCALA_ERROR_SENTINEL] {
    match lexer.lookahead {
      'c' | 'e' | 'f' | 't' | 'y' => {
        lexer.mark_end()
        // `do` and `while` stay ungated: they can start a statement, and
        // gate validity blends in from unrelated GLR forks.
        // `char word[sizeof "finally"]`.
        let (len, word, _) = scala_read_word(lexer, 8)
        if len > 0 && scala_word_in(word, scala_tail_words) {
          lexer.result_symbol = SCALA_CONTROL_TAIL_GATE
          return true
        }
        return false
      }
      _ => ()
    }
  }
  false
}

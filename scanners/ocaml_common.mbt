// Port of the ocaml grammar's common/scanner.h (v0.26.0), shared by the
// ocaml, ocaml_interface and ocaml_type scanners.
// tree-sitter-ocaml is distributed under the MIT license (see NOTICE).

///|
/// `enum TokenType`.
const OCAML_COMMENT : Int32 = 0

///|
const OCAML_LEFT_QUOTED_STRING_DELIM : Int32 = 1

///|
const OCAML_RIGHT_QUOTED_STRING_DELIM : Int32 = 2

///|
const OCAML_STRING_DELIM : Int32 = 3

///|
const OCAML_LINE_NUMBER_DIRECTIVE : Int32 = 4

///|
const OCAML_NULL_CHARACTER : Int32 = 5

///|
const OCAML_ERROR_SENTINEL : Int32 = 6

///|
/// `Scanner`.
///
/// `quoted_string_id` is an `int32_t *` buffer, but `quoted_string_id_copy`
/// and `quoted_string_id_assign` `memcpy` only `quoted_string_id_length`
/// *bytes* of it (not `length * sizeof(int32_t)`). The buffer is therefore
/// kept as its raw little-endian bytes (`capacity * 4` of them), so that a
/// deserialized id combines the copied bytes with whatever the buffer held
/// before, exactly as in C. Bytes that C leaves uninitialized (fresh
/// `ts_realloc` memory) are zero here.
priv struct OcamlScanner {
  mut in_string : Bool
  /// `size_t quoted_string_id_length` (in `int32_t` elements).
  mut quoted_string_id_length : Int32
  /// `size_t quoted_string_id_capacity` (in `int32_t` elements).
  mut quoted_string_id_capacity : Int32
  /// The bytes of `int32_t *quoted_string_id`.
  mut quoted_string_id : FixedArray[Byte]
}

///|
fn OcamlScanner::quoted_string_id_get(self : OcamlScanner, i : Int32) -> Int32 {
  let b = self.quoted_string_id
  b[4 * i].to_int() |
  (b[4 * i + 1].to_int() << 8) |
  (b[4 * i + 2].to_int() << 16) |
  (b[4 * i + 3].to_int() << 24)
}

///|
fn OcamlScanner::quoted_string_id_clear(self : OcamlScanner) -> Unit {
  self.quoted_string_id_length = 0
}

///|
fn OcamlScanner::quoted_string_id_resize(
  self : OcamlScanner,
  min_capacity : Int32,
) -> Unit {
  let mut capacity = self.quoted_string_id_capacity
  if capacity >= min_capacity {
    return
  }
  if capacity < 16 {
    capacity = 16
  }
  while capacity < min_capacity {
    capacity = capacity << 1
  }
  self.quoted_string_id_capacity = capacity
  // ts_realloc: the old contents are kept, the new bytes are uninitialized.
  let bytes = FixedArray::make(capacity * 4, b'\x00')
  let old = self.quoted_string_id
  for i in 0..<old.length() {
    bytes[i] = old[i]
  }
  self.quoted_string_id = bytes
}

///|
fn OcamlScanner::quoted_string_id_assign(
  self : OcamlScanner,
  buffer : BytesView,
  length : Int32,
) -> Unit {
  if length > 0 {
    self.quoted_string_id_resize(length)
    // memcpy(scanner->quoted_string_id, buffer, length)
    for i in 0..<length {
      self.quoted_string_id[i] = buffer[i]
    }
  }
  self.quoted_string_id_length = length
}

///|
fn OcamlScanner::quoted_string_id_copy(
  self : OcamlScanner,
  buffer : FixedArray[Byte],
  offset : Int32,
) -> Int32 {
  let length = self.quoted_string_id_length
  if length > 0 {
    // memcpy(buffer, scanner->quoted_string_id, length)
    for i in 0..<length {
      buffer[offset + i] = self.quoted_string_id[i]
    }
  }
  length
}

///|
fn OcamlScanner::quoted_string_id_push(self : OcamlScanner, c : Int32) -> Unit {
  self.quoted_string_id_resize(self.quoted_string_id_length + 1)
  let i = self.quoted_string_id_length
  self.quoted_string_id_length += 1
  let b = self.quoted_string_id
  b[4 * i] = c.to_byte()
  b[4 * i + 1] = (c >> 8).to_byte()
  b[4 * i + 2] = (c >> 16).to_byte()
  b[4 * i + 3] = (c >> 24).to_byte()
}

///|
fn ocaml_scan_string(lexer : @runtime.Lexer) -> Unit {
  for ;; {
    match lexer.lookahead {
      '\\' => {
        lexer.advance(false)
        lexer.advance(false)
      }
      '"' => {
        lexer.advance(false)
        return
      }
      '\u{0}' => {
        if lexer.eof() {
          return
        }
        lexer.advance(false)
      }
      _ => lexer.advance(false)
    }
  }
}

///|
/// https://github.com/ocaml/ocaml/blob/5.3.0-rc1/utils/misc.ml#L281-L298
let ocaml_lower_utf8_chars : FixedArray[Int32] = [
  0xdf, // ß
   0xe0, // à
   0xe1, // á
   0xe2, // â
   0xe3, // ã
   0xe4, // ä
   0xe5, // å
   0xe6, // æ
   0xe7, // ç
   0xe8, // è
   0xe9, // é
   0xea, // ê
   0xeb, // ë
   0xec, // ì
   0xed, // í
   0xee, // î
   0xef, // ï
   0xf0, // ð
   0xf1, // ñ
   0xf2, // ò
   0xf3, // ó
   0xf4, // ô
   0xf5, // õ
   0xf6, // ö
   0xf8, // ø
   0xf9, // ù
   0xfa, // ú
   0xfb, // û
   0xfc, // ü
   0xfd, // ý
   0xfe, // þ
   0xff, // ÿ
   0x153, // œ
   0x161, // š
   0x17e, // ž
]

///|
/// https://github.com/ocaml/ocaml/blob/5.3.0-rc1/utils/misc.ml#L326-L340
let ocaml_lower_utf8_pairs : FixedArray[(Int32, Int32, Int32)] = [
  ('a', 0x300, 0xe0), // à
  ('a', 0x301, 0xe1), // á
  ('a', 0x302, 0xe2), // â
  ('a', 0x303, 0xe3), // ã
  ('a', 0x308, 0xe4), // ä
  ('a', 0x30a, 0xe5), // å
  ('c', 0x327, 0xe7), // ç
  ('e', 0x300, 0xe8), // è
  ('e', 0x301, 0xe9), // é
  ('e', 0x302, 0xea), // ê
  ('e', 0x308, 0xeb), // ë
  ('i', 0x300, 0xec), // ì
  ('i', 0x301, 0xed), // í
  ('i', 0x302, 0xee), // î
  ('i', 0x308, 0xef), // ï
  ('n', 0x303, 0xf1), // ñ
  ('o', 0x300, 0xf2), // ò
  ('o', 0x301, 0xf3), // ó
  ('o', 0x302, 0xf4), // ô
  ('o', 0x303, 0xf5), // õ
  ('o', 0x308, 0xf6), // ö
  ('s', 0x30c, 0x161), // š
  ('u', 0x300, 0xf9), // ù
  ('u', 0x301, 0xfa), // ú
  ('u', 0x302, 0xfb), // û
  ('u', 0x308, 0xfc), // ü
  ('y', 0x301, 0xfd), // ý
  ('y', 0x308, 0xff), // ÿ
  ('z', 0x30c, 0x17e), // ž
]

///|
fn ocaml_search_lower_utf8_char(c : Int32) -> Int32 {
  let mut base = 0
  let size = ocaml_lower_utf8_chars.length()
  let mut range = size
  while range != 0 {
    let probe = base + (range >> 1)
    if c == ocaml_lower_utf8_chars[probe] {
      return ocaml_lower_utf8_chars[probe]
    } else if c > ocaml_lower_utf8_chars[probe] {
      base = probe + 1
      range -= 1
    }
    range = range >> 1
  }
  0
}

///|
fn ocaml_search_lower_utf8_pair(c : Int32, diacritic : Int32) -> Int32 {
  let mut base = 0
  let size = ocaml_lower_utf8_pairs.length()
  let mut range = size
  while range != 0 {
    let (p0, p1, p2) = ocaml_lower_utf8_pairs[base + (range >> 1)]
    if c == p0 && diacritic == p1 {
      return p2
    } else if c > p0 || (c == p0 && diacritic > p1) {
      base = base + (range >> 1) + 1
      range -= 1
    }
    range = range >> 1
  }
  0
}

///|
fn ocaml_scan_quoted_string_delim_char(lexer : @runtime.Lexer) -> Int32 {
  let c = lexer.lookahead
  if c == '|' {
    return 0
  }
  if c == '_' {
    lexer.advance(false)
    return c
  }
  if c >= 'a' && c <= 'z' {
    lexer.advance(false)
    if lexer.lookahead >= 0x300 && lexer.lookahead <= 0x327 {
      let r = ocaml_search_lower_utf8_pair(c, lexer.lookahead)
      if r != 0 {
        lexer.advance(false)
        return r
      }
    }
    return c
  }
  let r = ocaml_search_lower_utf8_char(c)
  if r != 0 {
    lexer.advance(false)
    return r
  }
  0
}

///|
fn OcamlScanner::scan_left_quoted_string_delimiter(
  self : OcamlScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  for ;; {
    let c = ocaml_scan_quoted_string_delim_char(lexer)
    if c == 0 {
      break
    }
    self.quoted_string_id_push(c)
  }
  if lexer.lookahead == '|' {
    lexer.advance(false)
    self.in_string = true
    true
  } else {
    self.quoted_string_id_clear()
    false
  }
}

///|
fn OcamlScanner::scan_right_quoted_string_delimiter(
  self : OcamlScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  for i in 0..<self.quoted_string_id_length {
    if ocaml_scan_quoted_string_delim_char(lexer) !=
      self.quoted_string_id_get(i) {
      return false
    }
  }
  if lexer.lookahead == '}' {
    self.in_string = false
    self.quoted_string_id_clear()
    true
  } else {
    false
  }
}

///|
fn OcamlScanner::scan_quoted_string(
  self : OcamlScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  if !self.scan_left_quoted_string_delimiter(lexer) {
    return false
  }
  for ;; {
    match lexer.lookahead {
      '|' => {
        lexer.advance(false)
        if self.scan_right_quoted_string_delimiter(lexer) {
          return true
        }
      }
      '\u{0}' => {
        if lexer.eof() {
          return false
        }
        lexer.advance(false)
      }
      _ => lexer.advance(false)
    }
  }
}

///|
fn ocaml_scan_character(lexer : @runtime.Lexer) -> Int32 {
  let mut last = 0
  match lexer.lookahead {
    '\\' => {
      lexer.advance(false)
      if iswdigit(lexer.lookahead) {
        lexer.advance(false)
        for _ in 0..<2 {
          if !iswdigit(lexer.lookahead) {
            return 0
          }
          lexer.advance(false)
        }
      } else {
        match lexer.lookahead {
          'x' => {
            lexer.advance(false)
            for _ in 0..<2 {
              if !iswdigit(lexer.lookahead) &&
                (
                  towupper(lexer.lookahead) < 'A' ||
                  towupper(lexer.lookahead) > 'F'
                ) {
                return 0
              }
              lexer.advance(false)
            }
          }
          'o' => {
            lexer.advance(false)
            for _ in 0..<3 {
              if !iswdigit(lexer.lookahead) || lexer.lookahead > '7' {
                return 0
              }
              lexer.advance(false)
            }
          }
          '\'' | '"' | '\\' | 'n' | 't' | 'b' | 'r' | ' ' => {
            last = lexer.lookahead
            lexer.advance(false)
          }
          _ => return 0
        }
      }
    }
    '\'' => ()
    '\r' => {
      lexer.advance(false)
      while lexer.lookahead == '\r' {
        lexer.advance(false)
      }
      if lexer.lookahead != '\n' {
        return 0
      }
      lexer.advance(false)
    }
    '\u{0}' => {
      if lexer.eof() {
        return 0
      }
      lexer.advance(false)
    }
    _ =>
      if lexer.lookahead < 256 {
        last = lexer.lookahead
        lexer.advance(false)
      } else {
        return 0
      }
  }
  if lexer.lookahead == '\'' {
    lexer.advance(false)
    return 0
  }
  last
}

///|
fn ocaml_is_lowercase_ext(c : Int32) -> Bool {
  (c >= 'a' && c <= 'z') || c == '_' || c >= 192
}

///|
fn ocaml_is_identstart(c : Int32) -> Bool {
  ocaml_is_lowercase_ext(c) || (c >= 'A' && c <= 'Z')
}

///|
fn ocaml_is_identchar(c : Int32) -> Bool {
  ocaml_is_identstart(c) || (c >= '0' && c <= '9') || c == '\''
}

///|
fn ocaml_scan_identifier(lexer : @runtime.Lexer) -> Bool {
  if ocaml_is_identstart(lexer.lookahead) {
    lexer.advance(false)
    while ocaml_is_identchar(lexer.lookahead) {
      lexer.advance(false)
    }
    return true
  }
  false
}

///|
fn ocaml_scan_extattrident(lexer : @runtime.Lexer) -> Bool {
  while ocaml_scan_identifier(lexer) {
    if lexer.lookahead != '.' {
      return true
    }
    lexer.advance(false)
  }
  false
}

///|
fn OcamlScanner::scan_comment(
  self : OcamlScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  let mut last = 0
  if lexer.lookahead != '*' {
    return false
  }
  lexer.advance(false)
  for ;; {
    match (if last != 0 { last } else { lexer.lookahead }) {
      '(' => {
        if last != 0 {
          last = 0
        } else {
          lexer.advance(false)
        }
        ignore(self.scan_comment(lexer))
      }
      '*' => {
        if last != 0 {
          last = 0
        } else {
          lexer.advance(false)
        }
        if lexer.lookahead == ')' {
          lexer.advance(false)
          return true
        }
      }
      '\'' => {
        if last != 0 {
          last = 0
        } else {
          lexer.advance(false)
        }
        last = ocaml_scan_character(lexer)
      }
      '"' => {
        if last != 0 {
          last = 0
        } else {
          lexer.advance(false)
        }
        ocaml_scan_string(lexer)
      }
      '{' => {
        if last != 0 {
          last = 0
        } else {
          lexer.advance(false)
        }
        if lexer.lookahead == '%' {
          lexer.advance(false)
          if lexer.lookahead == '%' {
            lexer.advance(false)
          }
          if ocaml_scan_extattrident(lexer) {
            while iswspace(lexer.lookahead) {
              lexer.advance(false)
            }
          } else {
            continue
          }
        }
        if self.scan_quoted_string(lexer) {
          lexer.advance(false)
        }
      }
      '\u{0}' => {
        if lexer.eof() {
          return true
        }
        if last != 0 {
          last = 0
        } else {
          lexer.advance(false)
        }
      }
      _ =>
        if ocaml_scan_identifier(lexer) || last != 0 {
          last = 0
        } else {
          lexer.advance(false)
        }
    }
  }
}

///|
fn OcamlScanner::serialize(
  self : OcamlScanner,
  buffer : FixedArray[Byte],
) -> Int32 {
  buffer[0] = if self.in_string { 1 } else { 0 }
  if self.quoted_string_id_length < SERIALIZATION_BUFFER_SIZE {
    self.quoted_string_id_copy(buffer, 1) + 1
  } else {
    1
  }
}

///|
fn OcamlScanner::deserialize(self : OcamlScanner, buffer : BytesView) -> Unit {
  let length = buffer.length()
  if length > 0 {
    self.in_string = buffer[0] != 0
    self.quoted_string_id_assign(buffer[1:], length - 1)
  } else {
    self.in_string = false
    self.quoted_string_id_clear()
  }
}

///|
fn OcamlScanner::scan(
  self : OcamlScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  if !valid_symbols[OCAML_ERROR_SENTINEL] &&
    valid_symbols[OCAML_LEFT_QUOTED_STRING_DELIM] &&
    (ocaml_is_lowercase_ext(lexer.lookahead) || lexer.lookahead == '|') {
    lexer.result_symbol = OCAML_LEFT_QUOTED_STRING_DELIM
    return self.scan_left_quoted_string_delimiter(lexer)
  }
  if !valid_symbols[OCAML_ERROR_SENTINEL] &&
    valid_symbols[OCAML_RIGHT_QUOTED_STRING_DELIM] &&
    lexer.lookahead == '|' {
    lexer.advance(false)
    lexer.result_symbol = OCAML_RIGHT_QUOTED_STRING_DELIM
    return self.scan_right_quoted_string_delimiter(lexer)
  }
  if self.in_string &&
    valid_symbols[OCAML_STRING_DELIM] &&
    lexer.lookahead == '"' {
    lexer.advance(false)
    self.in_string = false
    lexer.result_symbol = OCAML_STRING_DELIM
    return true
  }
  while iswspace(lexer.lookahead) {
    lexer.advance(true)
  }
  if !self.in_string &&
    valid_symbols[OCAML_STRING_DELIM] &&
    lexer.lookahead == '"' {
    lexer.advance(false)
    self.in_string = true
    lexer.result_symbol = OCAML_STRING_DELIM
    return true
  }
  if !self.in_string &&
    valid_symbols[OCAML_LINE_NUMBER_DIRECTIVE] &&
    lexer.lookahead == '#' &&
    lexer.get_column() == 0 {
    lexer.advance(false)
    while lexer.lookahead == ' ' || lexer.lookahead == '\t' {
      lexer.advance(false)
    }
    if !iswdigit(lexer.lookahead) {
      return false
    }
    while iswdigit(lexer.lookahead) {
      lexer.advance(false)
    }
    while lexer.lookahead == ' ' || lexer.lookahead == '\t' {
      lexer.advance(false)
    }
    if lexer.lookahead != '"' {
      return false
    }
    lexer.advance(false)
    while lexer.lookahead != '\n' &&
          lexer.lookahead != '\r' &&
          lexer.lookahead != '"' &&
          !lexer.eof() {
      lexer.advance(false)
    }
    if lexer.lookahead != '"' {
      return false
    }
    lexer.advance(false)
    while lexer.lookahead != '\n' && lexer.lookahead != '\r' && !lexer.eof() {
      lexer.advance(false)
    }
    lexer.result_symbol = OCAML_LINE_NUMBER_DIRECTIVE
    return true
  }
  if !self.in_string && valid_symbols[OCAML_COMMENT] && lexer.lookahead == '(' {
    lexer.advance(false)
    lexer.result_symbol = OCAML_COMMENT
    return self.scan_comment(lexer)
  }
  if valid_symbols[OCAML_NULL_CHARACTER] &&
    lexer.lookahead == '\u{0}' &&
    !lexer.eof() {
    lexer.advance(false)
    lexer.result_symbol = OCAML_NULL_CHARACTER
    return true
  }
  false
}

///|
/// `create()` (`ts_calloc`) wrapped as a scanner; shared by the three
/// grammars' scanner.c files.
fn ocaml_external_scanner() -> @runtime.ExternalScanner {
  let scanner : OcamlScanner = {
    in_string: false,
    quoted_string_id_length: 0,
    quoted_string_id_capacity: 0,
    quoted_string_id: FixedArray::make(0, b'\x00'),
  }
  {
    scan: (lexer, valid_symbols) => scanner.scan(lexer, valid_symbols),
    serialize: buffer => scanner.serialize(buffer),
    deserialize: buffer => scanner.deserialize(buffer),
    destroy: () => (),
  }
}

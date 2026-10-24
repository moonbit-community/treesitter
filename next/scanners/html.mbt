// Port of the html grammar's src/scanner.c (v0.23.2). The tag tables of
// src/tag.h are in html_tag.mbt.

///|
const HTML_START_TAG_NAME : Int32 = 0

///|
const HTML_SCRIPT_START_TAG_NAME : Int32 = 1

///|
const HTML_STYLE_START_TAG_NAME : Int32 = 2

///|
const HTML_END_TAG_NAME : Int32 = 3

///|
const HTML_ERRONEOUS_END_TAG_NAME : Int32 = 4

///|
const HTML_SELF_CLOSING_TAG_DELIMITER : Int32 = 5

///|
const HTML_IMPLICIT_END_TAG : Int32 = 6

///|
const HTML_RAW_TEXT : Int32 = 7

///|
const HTML_COMMENT : Int32 = 8

///|
priv struct HtmlScanner {
  tags : Array[HtmlTag]
}

///|
fn html_scanner() -> @runtime.ExternalScanner {
  let scanner : HtmlScanner = { tags: [], }
  {
    scan: (lexer, valid_symbols) => scanner.scan(lexer, valid_symbols),
    serialize: buffer => scanner.serialize(buffer),
    deserialize: buffer => scanner.deserialize(buffer),
    destroy: () => scanner.tags.clear(),
  }
}

///|
fn html_write_u16(buffer : FixedArray[Byte], at : Int32, value : Int32) -> Unit {
  buffer[at] = value.to_byte()
  buffer[at + 1] = (value >> 8).to_byte()
}

///|
fn HtmlScanner::serialize(
  self : HtmlScanner,
  buffer : FixedArray[Byte],
) -> Int32 {
  let tag_count = if self.tags.length() > 0xFFFF {
    0xFFFF
  } else {
    self.tags.length()
  }
  let mut serialized_tag_count = 0
  let mut size = 2
  html_write_u16(buffer, size, tag_count)
  size += 2
  while serialized_tag_count < tag_count {
    let tag = self.tags[serialized_tag_count]
    if tag.type_ == HTML_CUSTOM {
      let mut name_length = tag.custom_tag_name.length()
      if name_length > 0xFF {
        name_length = 0xFF
      }
      if size + 2 + name_length >= SERIALIZATION_BUFFER_SIZE {
        break
      }
      buffer[size] = tag.type_.to_byte()
      size += 1
      buffer[size] = name_length.to_byte()
      size += 1
      // strncpy: copy up to `name_length` bytes, padding with zeros after a
      // NUL.
      let mut nul = false
      for i in 0..<name_length {
        if !nul && tag.custom_tag_name[i] == 0 {
          nul = true
        }
        buffer[size + i] = if nul { 0 } else { tag.custom_tag_name[i] }
      }
      size += name_length
    } else {
      if size + 1 >= SERIALIZATION_BUFFER_SIZE {
        break
      }
      buffer[size] = tag.type_.to_byte()
      size += 1
    }
    serialized_tag_count += 1
  }
  html_write_u16(buffer, 0, serialized_tag_count)
  size
}

///|
fn HtmlScanner::deserialize(self : HtmlScanner, buffer : BytesView) -> Unit {
  self.tags.clear()
  if buffer.length() > 0 {
    let mut size = 0
    let serialized_tag_count = buffer[size].to_int() |
      (buffer[size + 1].to_int() << 8)
    size += 2
    let tag_count = buffer[size].to_int() | (buffer[size + 1].to_int() << 8)
    size += 2
    if tag_count > 0 {
      let mut iter = 0
      while iter < serialized_tag_count {
        // `(TagType)buffer[size++]` reads a signed `char`.
        let type_ = to_c_char(buffer[size].to_int())
        size += 1
        if type_ == HTML_CUSTOM {
          let name_length = buffer[size].to_int()
          size += 1
          let name = Array::makei(name_length, i => buffer[size + i])
          size += name_length
          self.tags.push({ type_, custom_tag_name: name, })
        } else {
          self.tags.push({ type_, custom_tag_name: [], })
        }
        iter += 1
      }
      // add zero tags if we didn't read enough, this is because the
      // buffer had no more room but we held more tags.
      while iter < tag_count {
        self.tags.push(html_tag_new())
        iter += 1
      }
    }
  }
}

///|
fn html_scan_tag_name(lexer : @runtime.Lexer) -> Array[Byte] {
  let tag_name : Array[Byte] = []
  while iswalnum(lexer.lookahead) ||
        lexer.lookahead == '-' ||
        lexer.lookahead == ':' {
    // `array_push` into an `Array(char)` keeps the low byte.
    tag_name.push(towupper(lexer.lookahead).to_byte())
    lexer.advance(false)
  }
  tag_name
}

///|
fn html_scan_comment(lexer : @runtime.Lexer) -> Bool {
  if lexer.lookahead != '-' {
    return false
  }
  lexer.advance(false)
  if lexer.lookahead != '-' {
    return false
  }
  lexer.advance(false)
  let mut dashes = 0U
  while lexer.lookahead != 0 {
    match lexer.lookahead {
      '-' => dashes += 1
      '>' if dashes >= 2 => {
        lexer.result_symbol = HTML_COMMENT
        lexer.advance(false)
        lexer.mark_end()
        return true
      }
      _ => dashes = 0
    }
    lexer.advance(false)
  }
  false
}

///|
fn HtmlScanner::scan_raw_text(
  self : HtmlScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  if self.tags.length() == 0 {
    return false
  }
  lexer.mark_end()
  let end_delimiter = if self.tags[self.tags.length() - 1].type_ == HTML_SCRIPT {
    "</SCRIPT"
  } else {
    "</STYLE"
  }
  let mut delimiter_index = 0
  while lexer.lookahead != 0 {
    if towupper(lexer.lookahead) == end_delimiter[delimiter_index].to_int() {
      delimiter_index += 1
      if delimiter_index == end_delimiter.length() {
        break
      }
      lexer.advance(false)
    } else {
      delimiter_index = 0
      lexer.advance(false)
      lexer.mark_end()
    }
  }
  lexer.result_symbol = HTML_RAW_TEXT
  true
}

///|
fn HtmlScanner::pop_tag(self : HtmlScanner) -> Unit {
  ignore(self.tags.pop())
}

///|
fn HtmlScanner::scan_implicit_end_tag(
  self : HtmlScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  let parent = if self.tags.length() == 0 {
    None
  } else {
    Some(self.tags[self.tags.length() - 1])
  }
  let mut is_closing_tag = false
  if lexer.lookahead == '/' {
    is_closing_tag = true
    lexer.advance(false)
  } else if parent is Some(parent) && parent.is_void() {
    self.pop_tag()
    lexer.result_symbol = HTML_IMPLICIT_END_TAG
    return true
  }
  let tag_name = html_scan_tag_name(lexer)
  if tag_name.length() == 0 && !lexer.eof() {
    return false
  }
  let next_tag = html_tag_for_name(tag_name)
  if is_closing_tag {
    // The tag correctly closes the topmost element on the stack
    if self.tags.length() > 0 && self.tags[self.tags.length() - 1].eq(next_tag) {
      return false
    }

    // Otherwise, dig deeper and queue implicit end tags (to be nice in
    // the case of malformed HTML)
    for i = self.tags.length(); i > 0; i = i - 1 {
      if self.tags[i - 1].type_ == next_tag.type_ {
        self.pop_tag()
        lexer.result_symbol = HTML_IMPLICIT_END_TAG
        return true
      }
    }
  } else if parent is Some(parent) &&
    (
      !parent.can_contain(next_tag) ||
      (
        (
          parent.type_ == HTML_HTML ||
          parent.type_ == HTML_HEAD ||
          parent.type_ == HTML_BODY
        ) &&
        lexer.eof()
      )
    ) {
    self.pop_tag()
    lexer.result_symbol = HTML_IMPLICIT_END_TAG
    return true
  }
  false
}

///|
fn HtmlScanner::scan_start_tag_name(
  self : HtmlScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  let tag_name = html_scan_tag_name(lexer)
  if tag_name.length() == 0 {
    return false
  }
  let tag = html_tag_for_name(tag_name)
  self.tags.push(tag)
  lexer.result_symbol = match tag.type_ {
    HTML_SCRIPT => HTML_SCRIPT_START_TAG_NAME
    HTML_STYLE => HTML_STYLE_START_TAG_NAME
    _ => HTML_START_TAG_NAME
  }
  true
}

///|
fn HtmlScanner::scan_end_tag_name(
  self : HtmlScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  let tag_name = html_scan_tag_name(lexer)
  if tag_name.length() == 0 {
    return false
  }
  let tag = html_tag_for_name(tag_name)
  if self.tags.length() > 0 && self.tags[self.tags.length() - 1].eq(tag) {
    self.pop_tag()
    lexer.result_symbol = HTML_END_TAG_NAME
  } else {
    lexer.result_symbol = HTML_ERRONEOUS_END_TAG_NAME
  }
  true
}

///|
fn HtmlScanner::scan_self_closing_tag_delimiter(
  self : HtmlScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  lexer.advance(false)
  if lexer.lookahead == '>' {
    lexer.advance(false)
    if self.tags.length() > 0 {
      self.pop_tag()
      lexer.result_symbol = HTML_SELF_CLOSING_TAG_DELIMITER
    }
    return true
  }
  false
}

///|
fn HtmlScanner::scan(
  self : HtmlScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  if valid_symbols[HTML_RAW_TEXT] &&
    !valid_symbols[HTML_START_TAG_NAME] &&
    !valid_symbols[HTML_END_TAG_NAME] {
    return self.scan_raw_text(lexer)
  }
  while iswspace(lexer.lookahead) {
    lexer.advance(true)
  }
  match lexer.lookahead {
    '<' => {
      lexer.mark_end()
      lexer.advance(false)
      if lexer.lookahead == '!' {
        lexer.advance(false)
        return html_scan_comment(lexer)
      }
      if valid_symbols[HTML_IMPLICIT_END_TAG] {
        return self.scan_implicit_end_tag(lexer)
      }
    }
    '\u{0}' =>
      if valid_symbols[HTML_IMPLICIT_END_TAG] {
        return self.scan_implicit_end_tag(lexer)
      }
    '/' =>
      if valid_symbols[HTML_SELF_CLOSING_TAG_DELIMITER] {
        return self.scan_self_closing_tag_delimiter(lexer)
      }
    _ =>
      if (
          valid_symbols[HTML_START_TAG_NAME] || valid_symbols[HTML_END_TAG_NAME]
        ) &&
        !valid_symbols[HTML_RAW_TEXT] {
        return if valid_symbols[HTML_START_TAG_NAME] {
          self.scan_start_tag_name(lexer)
        } else {
          self.scan_end_tag_name(lexer)
        }
      }
  }
  false
}

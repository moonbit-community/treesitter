// Port of `Parser`, `ParseOptions`, `ParseState`, `Decode` and
// `IncludedRangesError` from tree-sitter lib/binding_rust/lib.rs.

///|
/// A callback that receives log messages during parsing.
pub type Logger = (LogType, String) -> Unit

///|
/// The result of a progress callback: whether to continue or to stop the
/// operation (Rust's `ControlFlow<()>`).
pub(all) enum ControlFlow {
  Continue
  Break
} derive(Eq, Debug)

///|
/// The state of the parser that is passed to a parse progress callback.
pub struct ParseState {
  priv current_byte_offset : Int32
  priv has_error : Bool
}

///|
/// The byte offset the parser has reached.
pub fn ParseState::current_byte_offset(self : ParseState) -> Int32 {
  self.current_byte_offset
}

///|
/// Whether the parser has encountered an error.
pub fn ParseState::has_error(self : ParseState) -> Bool {
  self.has_error
}

///|
/// Options for parsing; currently a progress callback that can cancel the
/// parse by returning `Break`.
pub(all) struct ParseOptions {
  progress_callback : ((ParseState) -> ControlFlow)?
}

///|
/// Create parse options.
pub fn ParseOptions::new(
  progress_callback? : (ParseState) -> ControlFlow,
) -> ParseOptions {
  { progress_callback, }
}

///|
fn parse_options_to_ts(options : ParseOptions?) -> @runtime.ParseOptions {
  match options {
    Some({ progress_callback: Some(callback), }) =>
      {
        progress_callback: Some(state => {
          let state : ParseState = {
            current_byte_offset: from_u32(state.current_byte_offset),
            has_error: state.has_error,
          }
          callback(state) is Break
        }),
      }
    _ => { progress_callback: None, }
  }
}

///|
/// An error that occurred in [`Parser::set_included_ranges`]: the index of
/// the first incorrect range.
pub(all) suberror IncludedRangesError {
  IncludedRangesError(Int32)
} derive(Eq, Debug)

///|
pub impl Show for IncludedRangesError with fn output(self, logger) {
  let IncludedRangesError(index) = self
  logger.write_string("Incorrect range by index: \{index}")
}

///|
/// A stateful object that is used to produce a [`Tree`] based on some
/// source code.
pub struct Parser {
  priv raw : @runtime.Parser
  priv mut language : Language?
  priv mut logger : Logger?
}

///|
/// Create a new parser.
pub fn Parser::new() -> Parser {
  { raw: @runtime.Parser::new(), language: None, logger: None, }
}

///|
/// Set the language that the parser should use for parsing.
///
/// Assignment fails if the language cannot be used for parsing, or if it was
/// generated with an incompatible version of the Tree-sitter CLI. Check this
/// using [`Language::is_parseable`] and [`Language::abi_version`].
pub fn Parser::set_language(
  self : Parser,
  language : Language,
) -> Unit raise LanguageError {
  let version = language.abi_version()
  if version < min_compatible_language_version || version > language_version {
    raise Version(version)
  }
  if !language.is_parseable() {
    raise NotParseable
  }
  let ok = match language.external_scanner {
    Some(scanner) => self.raw.set_language(Some(language.raw), scanner~)
    None => self.raw.set_language(Some(language.raw))
  }
  if !ok {
    self.language = None
    raise NotParseable
  }
  self.language = Some(language)
}

///|
/// Get the parser's current language.
pub fn Parser::language(self : Parser) -> Language? {
  self.language
}

///|
/// Get the parser's current logger.
pub fn Parser::logger(self : Parser) -> Logger? {
  self.logger
}

///|
/// Set the logging callback that the parser should use during parsing.
pub fn Parser::set_logger(self : Parser, logger : Logger?) -> Unit {
  self.logger = logger
  match logger {
    Some(logger) =>
      self.raw.set_logger(
        Some((log_type, message) => {
          let log_type : LogType = match log_type {
            Parse => Parse
            Lex => Lex
          }
          logger(log_type, message)
        }),
      )
    None => self.raw.set_logger(None)
  }
}

///|
/// Set the destination to which the parser should write debugging graphs
/// during parsing. The graphs are formatted in the DOT language; `writer`
/// receives the output in pieces.
pub fn Parser::print_dot_graphs(
  self : Parser,
  writer : (String) -> Unit,
) -> Unit {
  self.raw.print_dot_graphs(Some(writer))
}

///|
/// Stop the parser from printing debugging graphs while parsing.
pub fn Parser::stop_printing_dot_graphs(self : Parser) -> Unit {
  self.raw.print_dot_graphs(None)
}

///|
fn Parser::parse_input(
  self : Parser,
  input : @runtime.Input,
  old_tree : Tree?,
  options : ParseOptions?,
) -> Tree? {
  guard self.language is Some(language) else { return None }
  let old = match old_tree {
    Some(tree) => Some(tree.raw)
    None => None
  }
  match self.raw.parse_with_options(old, input, parse_options_to_ts(options)) {
    Some(raw) => Some({ raw, language, })
    None => None
  }
}

///|
/// Parse a slice of UTF8 text.
///
/// * `text`: the UTF8-encoded text to parse.
/// * `old_tree`: a previous syntax tree parsed from the same document. If the
///   text of the document has changed since `old_tree` was created, then you
///   must edit `old_tree` to match the new text using [`Tree::edit`].
///
/// Returns a [`Tree`] if parsing succeeded, or `None` if the parser has not
/// yet had a language assigned with [`Parser::set_language`].
pub fn Parser::parse(
  self : Parser,
  text : BytesView,
  old_tree? : Tree,
) -> Tree? {
  let len = text.length()
  self.parse_with_options(
    (i, _) => if i < len { text[i:] } else { b""[:] },
    old_tree?,
  )
}

///|
/// Parse text provided in chunks by a callback.
///
/// * `callback`: a function that takes a byte offset and position and
///   returns a slice of UTF8-encoded text starting at that byte offset and
///   position. The slices can be of any length. If the given position is at
///   the end of the text, the callback should return an empty slice.
/// * `old_tree`: a previous syntax tree parsed from the same document.
/// * `options`: options for parsing the text, e.g. a progress callback.
pub fn Parser::parse_with_options(
  self : Parser,
  callback : (Int32, Point) -> BytesView,
  old_tree? : Tree,
  options? : ParseOptions,
) -> Tree? {
  self.parse_input(
    {
      read: (byte, position) => {
        callback(from_u32(byte), Point::from_ts(position)).to_owned()
      },
      encoding: UTF8,
      decode: None,
    },
    old_tree,
    options,
  )
}

///|
/// The bytes of UTF-16 code units in memory order on a little-endian host,
/// which is what lib.rs hands to the C library for both UTF-16 encodings.
fn utf16_memory_bytes(units : ArrayView[UInt16]) -> Bytes {
  Bytes::makei(units.length() * 2, i => {
    let unit = units[i / 2].to_int()
    (if i % 2 == 0 { unit & 0xFF } else { unit >> 8 }).to_byte()
  })
}

///|
fn utf16_input(
  callback : (Int32, Point) -> ArrayView[UInt16],
  encoding : @runtime.InputEncoding,
) -> @runtime.Input {
  {
    read: (byte, position) => {
      let point : Point = {
        row: from_u32(position.row),
        column: from_u32(position.column) / 2,
      }
      utf16_memory_bytes(callback(from_u32(byte) / 2, point))
    },
    encoding,
    decode: None,
  }
}

///|
/// Parse a slice of UTF16 little-endian text.
///
/// * `input`: the UTF16-encoded text to parse.
/// * `old_tree`: a previous syntax tree parsed from the same document.
pub fn Parser::parse_utf16_le(
  self : Parser,
  input : ArrayView[UInt16],
  old_tree? : Tree,
) -> Tree? {
  let len = input.length()
  self.parse_utf16_le_with_options(
    (i, _) => if i < len { input[i:] } else { [][:] },
    old_tree?,
  )
}

///|
/// Parse UTF16 little-endian text provided in chunks by a callback.
///
/// * `callback`: a function that takes a code unit offset and position and
///   returns a slice of UTF16-encoded text starting at that offset and
///   position. If the given position is at the end of the text, the callback
///   should return an empty slice.
/// * `old_tree`: a previous syntax tree parsed from the same document.
/// * `options`: options for parsing the text, e.g. a progress callback.
pub fn Parser::parse_utf16_le_with_options(
  self : Parser,
  callback : (Int32, Point) -> ArrayView[UInt16],
  old_tree? : Tree,
  options? : ParseOptions,
) -> Tree? {
  self.parse_input(utf16_input(callback, UTF16LE), old_tree, options)
}

///|
/// Parse a slice of UTF16 big-endian text.
///
/// As in lib.rs, the code units are passed to the parser in memory order of
/// a little-endian host, so big-endian input is given as byte-swapped units
/// (Rust's `u16::to_be`).
pub fn Parser::parse_utf16_be(
  self : Parser,
  input : ArrayView[UInt16],
  old_tree? : Tree,
) -> Tree? {
  let len = input.length()
  self.parse_utf16_be_with_options(
    (i, _) => if i < len { input[i:] } else { [][:] },
    old_tree?,
  )
}

///|
/// Parse UTF16 big-endian text provided in chunks by a callback. See
/// [`Parser::parse_utf16_be`] for how the code units are interpreted.
pub fn Parser::parse_utf16_be_with_options(
  self : Parser,
  callback : (Int32, Point) -> ArrayView[UInt16],
  old_tree? : Tree,
  options? : ParseOptions,
) -> Tree? {
  self.parse_input(utf16_input(callback, UTF16BE), old_tree, options)
}

///|
/// Parse text provided in chunks by a callback using a custom encoding.
/// This is useful for parsing text in encodings that are not UTF-8 or UTF-16.
///
/// * `decode`: decodes the next code point from the start of the given bytes,
///   returning `(code point, bytes consumed)`; the code point is `-1` if
///   decoding fails (upstream's `Decode::decode`).
/// * `callback`: a function that takes a byte offset and position and
///   returns a slice of text starting at that byte offset and position.
/// * `old_tree`: a previous syntax tree parsed from the same document.
/// * `options`: options for parsing the text, e.g. a progress callback.
pub fn Parser::parse_custom_encoding(
  self : Parser,
  decode : (BytesView) -> (Int32, Int32),
  callback : (Int32, Point) -> BytesView,
  old_tree? : Tree,
  options? : ParseOptions,
) -> Tree? {
  self.parse_input(
    {
      read: (byte, position) => {
        callback(from_u32(byte), Point::from_ts(position)).to_owned()
      },
      encoding: Custom,
      decode: Some(bytes => {
        let (code_point, length) = decode(bytes)
        (length.reinterpret_as_uint(), code_point)
      }),
    },
    old_tree,
    options,
  )
}

///|
/// Instruct the parser to start the next parse from the beginning.
///
/// If the parser previously failed because of a callback, then by default,
/// it will resume where it left off on the next call to
/// [`parse`](Parser::parse) or other parsing functions. If you don't want to
/// resume, and instead intend to use this parser to parse some other
/// document, you must call `reset` first.
pub fn Parser::reset(self : Parser) -> Unit {
  self.raw.reset()
}

///|
/// Release the parser, as dropping the Rust `Parser` does: stop printing dot
/// graphs, remove the logger and delete the C parser, which destroys the
/// external scanner of a parse that was cancelled and not reset.
///
/// MoonBit has no destructors, so this is explicit; without it, an
/// outstanding scanner's `destroy` callback is never called. The parser is
/// left without a language and can be given a new one.
pub fn Parser::delete(self : Parser) -> Unit {
  self.stop_printing_dot_graphs()
  self.set_logger(None)
  self.raw.delete()
  self.language = None
}

///|
/// Set the ranges of text that the parser should include when parsing.
///
/// By default, the parser will always include entire documents. This
/// function allows you to parse only a *portion* of a document but still
/// return a syntax tree whose ranges match up with the document as a whole.
/// You can also pass multiple disjoint ranges.
///
/// If `ranges` is empty, then the entire document will be parsed. Otherwise,
/// the given ranges must be ordered from earliest to latest in the document,
/// and they must not overlap. That is, `ranges[i].end_byte <=
/// ranges[i + 1].start_byte` must hold. If this requirement is not satisfied,
/// this raises [`IncludedRangesError`] with the index of the first incorrect
/// range.
pub fn Parser::set_included_ranges(
  self : Parser,
  ranges : ArrayView[Range],
) -> Unit raise IncludedRangesError {
  let ts_ranges = ranges.iter().map(r => r.to_ts()).to_array()
  if !self.raw.set_included_ranges(ts_ranges) {
    let mut prev_end_byte = 0
    for i, range in ranges {
      if range.start_byte < prev_end_byte || range.end_byte < range.start_byte {
        raise IncludedRangesError(i)
      }
      prev_end_byte = range.end_byte
    }
    raise IncludedRangesError(0)
  }
}

///|
/// Get the ranges of text that the parser will include when parsing.
pub fn Parser::included_ranges(self : Parser) -> Array[Range] {
  self.raw.included_ranges().map(Range::from_ts)
}

// Port of the data types in tree-sitter lib/include/tree_sitter/api.h.

///|
/// `TSDecodeFunction`: decode one code point from the start of `string`,
/// returning `(bytes consumed, code point)`; the code point is -1 when the
/// input is invalid.
pub type DecodeFunction = (BytesView) -> (UInt32, Int32)

///|
pub(all) enum InputEncoding {
  UTF8
  UTF16LE
  UTF16BE
  Custom
} derive(Eq, Debug)

///|
pub(all) struct Range {
  start_point : Point
  end_point : Point
  start_byte : UInt32
  end_byte : UInt32
} derive(Eq, Hash, Debug)

///|
/// `TSInput`. `read(byte_index, position)` returns the chunk of text starting
/// at `byte_index`; an empty chunk signals the end of the input.
pub(all) struct Input {
  read : (UInt32, Point) -> BytesView
  encoding : InputEncoding
  decode : DecodeFunction?
}

///|
/// `TSParseState`: what a progress callback can observe.
pub(all) struct ParseState {
  current_byte_offset : UInt32
  has_error : Bool
} derive(Eq, Debug)

///|
/// `TSParseOptions`.
pub(all) struct ParseOptions {
  progress_callback : ((ParseState) -> Bool)?
}

///|
pub(all) enum LogType {
  Parse
  Lex
} derive(Eq, Debug)

///|
/// `TSLogger`.
pub type Logger = (LogType, String) -> Unit

///|
pub(all) struct InputEdit {
  start_byte : UInt32
  old_end_byte : UInt32
  new_end_byte : UInt32
  start_point : Point
  old_end_point : Point
  new_end_point : Point
} derive(Eq, Debug)

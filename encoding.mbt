///|
pub(all) enum InputEncoding {
  Utf8
  Utf16LE
  Utf16BE
  Custom(InputDecoder)
} derive(Eq, Debug)

///|
fn decode_input_codepoint(
  source : Bytes,
  offset : Int32,
  encoding : InputEncoding,
) -> (Int32, Int32) {
  if encoding == Utf8 {
    return @lex.decode(source, offset)
  }
  if encoding is Custom(decoder) {
    let (scalar, consumed) = (decoder.decode)(source[offset:])
    if consumed <= 0 || consumed > source.length() - offset {
      return (0xfffd, 1)
    }
    let scalar = if scalar < 0 ||
      scalar > 0x10ffff ||
      (scalar >= 0xd800 && scalar <= 0xdfff) {
      0xfffd
    } else {
      scalar
    }
    return (scalar, consumed)
  }
  if offset + 1 >= source.length() {
    return (0xfffd, 1)
  }
  fn unit(index : Int32) -> Int32 {
    let first = source[index].to_int()
    let second = source[index + 1].to_int()
    if encoding == Utf16LE {
      first | (second << 8)
    } else {
      (first << 8) | second
    }
  }
  let first = unit(offset)
  if first >= 0xd800 && first <= 0xdbff {
    if offset + 3 < source.length() {
      let second = unit(offset + 2)
      if second >= 0xdc00 && second <= 0xdfff {
        return (0x10000 + ((first - 0xd800) << 10) + second - 0xdc00, 4)
      }
    }
    (0xfffd, 2)
  } else if first >= 0xdc00 && first <= 0xdfff {
    (0xfffd, 2)
  } else {
    (first, 2)
  }
}

///|
fn input_text(source : BytesView, encoding : InputEncoding) -> String {
  if encoding == Utf8 {
    return @utf8.decode_lossy(source)
  }
  let source = source.to_owned()
  let output = StringBuilder()
  let mut offset = 0
  while offset < source.length() {
    let (code, size) = decode_input_codepoint(source, offset, encoding)
    output.write_char(code.unsafe_to_char())
    offset += size
  }
  output.to_string()
}

///|
fn input_lines(source : Bytes, encoding : InputEncoding) -> Array[Int32] {
  if encoding == Utf8 {
    return line_starts(source)
  }
  let lines = [0]
  let mut offset = 0
  while offset < source.length() {
    let (code, size) = decode_input_codepoint(source, offset, encoding)
    offset += size
    if code == 10 {
      lines.push(offset)
    }
  }
  lines
}

///|
pub fn Tree::encoding(self : Tree) -> InputEncoding {
  self.root.data.encoding
}

///|
/// Decode a source byte range using the tree's input encoding.
pub fn Tree::text(self : Tree, start : Int32, end : Int32) -> String {
  input_text(self.source[start:end], self.encoding())
}

///|
/// Parse UTF-8, UTF-16, or a custom encoding, retaining source byte coordinates.
/// Included ranges are concatenated before decoding, so a scalar may span ranges.
/// Malformed code units become replacement characters and always make progress.
/// `max_steps=0` has no step limit, as in `parse`.
pub fn Parser::parse_encoded(
  self : Parser,
  source : Bytes,
  encoding : InputEncoding,
  old_tree? : Tree,
  included_ranges~ : Array[Range] = [],
  max_steps~ : Int32 = 0,
  max_branches~ : Int32 = 10000,
  max_errors~ : Int32 = 20,
  cancelled~ : () -> Bool = () => false,
) -> Tree raise ParseError {
  if max_steps < 0 {
    raise ParseLimit("max_steps must be non-negative")
  }
  if encoding == Utf8 {
    return self.parse(
      source,
      old_tree?,
      included_ranges~,
      max_steps~,
      max_branches~,
      max_errors~,
      cancelled~,
    )
  }
  self.reset()
  if cancelled() {
    raise Cancelled
  }
  if old_tree is Some(old) &&
    physical_equal(old.language, self.language) &&
    old.encoding() == encoding &&
    same_scanner(old.scanner, self.scanner) {
    self.next_id = Int32::max(self.next_id, old.root.id() + 1)
    if !old.edited &&
      old.source == source &&
      old.source_ranges == included_ranges {
      return { ..old, identity: Ref(0), reused_subtrees: 1, parse_steps: 0, }
    }
  }
  let lines = input_lines(source, encoding)
  let ranges = if included_ranges.is_empty() {
    [
      {
        start_byte: 0,
        end_byte: source.length(),
        start_point: { row: 0, column: 0, },
        end_point: point_at(lines, source.length()),
      },
    ]
  } else {
    included_ranges
  }
  let raw : Array[Byte] = []
  let raw_starts = [0]
  let raw_ends = [0]
  let mut previous = 0
  for range in ranges {
    if range.start_byte < previous ||
      range.end_byte < range.start_byte ||
      range.end_byte > source.length() ||
      range.start_point != point_at(lines, range.start_byte) ||
      range.end_point != point_at(lines, range.end_byte) {
      raise InvalidRanges("invalid encoded input range")
    }
    raw_starts[raw_starts.length() - 1] = range.start_byte
    if raw.is_empty() {
      raw_ends[0] = range.start_byte
    }
    for index in range.start_byte..<range.end_byte {
      if index % 4096 == 0 && cancelled() {
        raise Cancelled
      }
      raw.push(source[index])
      raw_starts.push(index + 1)
      raw_ends.push(index + 1)
    }
    previous = range.end_byte
  }
  let raw = Bytes::from_array(raw)
  let utf8 : Array[Byte] = []
  let starts = [raw_starts[0]]
  let ends = [raw_ends[0]]
  let mut offset = 0
  while offset < raw.length() {
    if cancelled() {
      raise Cancelled
    }
    let (code, size) = decode_input_codepoint(raw, offset, encoding)
    let encoded = @utf8.encode(code.unsafe_to_char().to_string())
    for i, byte in encoded {
      utf8.push(byte)
      let boundary = if i == encoded.length() - 1 {
        offset + size
      } else {
        offset
      }
      starts.push(raw_starts[boundary])
      ends.push(raw_ends[boundary])
    }
    offset += size
  }
  let projection : Projection = {
    source,
    starts,
    ends,
    lines,
    ranges: included_ranges.copy(),
    encoding,
  }
  let tree = self.parse_source(
    Bytes::from_array(utf8),
    projection=Some(projection),
    max_steps~,
    max_branches~,
    max_errors~,
    cancelled~,
  )
  {
    ..tree,
    root: project_node(tree.root, starts, ends, lines, encoding~),
    source,
    edited_length: source.length(),
    source_ranges: included_ranges.copy(),
  }
}

///|
pub extend InputEncoding with Eq::{equal, not_equal}

///|
pub extend InputEncoding with @debug.Debug::{to_repr}

///|
/// Return the byte-based point of an offset in the original encoded source.
pub fn Tree::point_at(self : Tree, offset : Int32) -> Point {
  guard! offset >= 0 && offset <= self.source.length()
  point_at(input_lines(self.source, self.encoding()), offset)
}

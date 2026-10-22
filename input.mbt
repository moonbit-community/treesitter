///|
/// Read UTF-8 chunks through a callback. The callback receives a byte offset
/// and byte-based point and returns an empty chunk at EOF. Chunk boundaries may
/// split UTF-8 sequences. Input is collected before table execution; byte/point
/// coordinates and incremental tree semantics are identical to `parse`.
pub fn Parser::parse_with(
  self : Parser,
  read : (Int32, Point) -> Bytes,
  old_tree? : Tree,
  included_ranges~ : Array[Range] = [],
  max_input_bytes~ : Int32 = 2147483647,
  max_steps~ : Int32 = 100000,
  max_branches~ : Int32 = 10000,
  max_errors~ : Int32 = 20,
  cancelled~ : () -> Bool = () => false,
) -> Tree raise ParseError {
  let buffer = @buffer.Buffer()
  let mut point : Point = { row: 0, column: 0, }
  for ;; {
    if cancelled() {
      raise Cancelled
    }
    let chunk = read(buffer.length(), point)
    if chunk.is_empty() {
      break
    }
    if chunk.length() > max_input_bytes - buffer.length() {
      raise ParseLimit("input byte limit exceeded")
    }
    buffer.write_bytes(chunk[:])
    for byte in chunk {
      point = if byte == 10 {
        { row: point.row + 1, column: 0, }
      } else {
        { row: point.row, column: point.column + 1, }
      }
    }
  }
  self.parse(
    buffer.to_bytes(),
    old_tree?,
    included_ranges~,
    max_steps~,
    max_branches~,
    max_errors~,
    cancelled~,
  )
}

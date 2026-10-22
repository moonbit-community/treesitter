///|
/// Zero-based row and UTF-8 byte column, matching Tree-sitter locations.
pub(all) struct Point {
  row : Int32
  column : Int32
} derive(Debug, Eq, Compare, ToJson)

///|
pub(all) struct Range {
  start_byte : Int32
  end_byte : Int32
  start_point : Point
  end_point : Point
} derive(Debug, Eq, ToJson)

///|
fn line_starts(source : Bytes) -> Array[Int32] {
  let starts = [0]
  for i, b in source {
    if b == b'\n' {
      starts.push(i + 1)
    }
  }
  starts
}

///|
fn point_at(starts : Array[Int32], offset : Int32) -> Point {
  for lo = 0, hi = starts.length(); lo + 1 < hi; {
    let mid = (lo + hi) / 2
    if starts[mid] <= offset {
      continue mid, hi
    } else {
      continue lo, mid
    }
  } nobreak {
    { row: lo, column: offset - starts[lo], }
  }
}

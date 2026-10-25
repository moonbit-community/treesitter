// Port of tree-sitter lib/src/point.h and lib/src/length.h.

///|
/// `TSPoint`. Rows and columns are unsigned 32-bit values, as in C.
#valtype
pub(all) struct Point {
  row : UInt32
  column : UInt32
} derive(Eq, Hash, Debug)

///|
pub let point_zero : Point = { row: 0, column: 0, }

///|
pub let point_max : Point = { row: 0xFFFFFFFFU, column: 0xFFFFFFFFU, }

///|
pub fn point_add(a : Point, b : Point) -> Point {
  if b.row > 0 {
    { row: a.row + b.row, column: b.column, }
  } else {
    { row: a.row, column: a.column + b.column, }
  }
}

///|
pub fn point_sub(a : Point, b : Point) -> Point {
  if a.row > b.row {
    { row: a.row - b.row, column: a.column, }
  } else {
    {
      row: 0,
      column: if a.column >= b.column {
        a.column - b.column
      } else {
        0
      },
    }
  }
}

///|
pub fn point_lte(a : Point, b : Point) -> Bool {
  a.row < b.row || (a.row == b.row && a.column <= b.column)
}

///|
pub fn point_lt(a : Point, b : Point) -> Bool {
  a.row < b.row || (a.row == b.row && a.column < b.column)
}

///|
pub fn point_gt(a : Point, b : Point) -> Bool {
  a.row > b.row || (a.row == b.row && a.column > b.column)
}

///|
pub fn point_gte(a : Point, b : Point) -> Bool {
  a.row > b.row || (a.row == b.row && a.column >= b.column)
}

///|
pub fn point_eq(a : Point, b : Point) -> Bool {
  a.row == b.row && a.column == b.column
}

///|
#valtype
pub(all) struct Length {
  bytes : UInt32
  extent : Point
} derive(Eq, Hash, Debug)

///|
pub let length_undefined : Length = {
  bytes: 0,
  extent: { row: 0, column: 1, },
}

///|
pub let length_max : Length = { bytes: 0xFFFFFFFFU, extent: point_max, }

///|
pub fn length_is_undefined(length : Length) -> Bool {
  length.bytes == 0 && length.extent.column != 0
}

///|
pub fn length_min(len1 : Length, len2 : Length) -> Length {
  if len1.bytes < len2.bytes {
    len1
  } else {
    len2
  }
}

///|
pub fn length_add(len1 : Length, len2 : Length) -> Length {
  {
    bytes: len1.bytes + len2.bytes,
    extent: point_add(len1.extent, len2.extent),
  }
}

///|
pub fn length_sub(len1 : Length, len2 : Length) -> Length {
  {
    bytes: if len1.bytes >= len2.bytes {
      len1.bytes - len2.bytes
    } else {
      0
    },
    extent: point_sub(len1.extent, len2.extent),
  }
}

///|
pub fn length_zero() -> Length {
  { bytes: 0, extent: point_zero, }
}

///|
pub fn length_saturating_sub(len1 : Length, len2 : Length) -> Length {
  if len1.bytes > len2.bytes {
    length_sub(len1, len2)
  } else {
    length_zero()
  }
}

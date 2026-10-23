// Port of `Point`, `Range`, `InputEdit` and `LogType` from tree-sitter
// lib/binding_rust/lib.rs. Offsets and coordinates are `Int`s (upstream:
// `usize`) and are converted to the runtime's `u32` fields like lib.rs's
// `From` impls do, except that `Int::max_value()` stands for `u32::MAX` (the
// "unbounded" sentinel upstream users write as `usize::MAX`): it converts to
// `u32::MAX`, and runtime values that do not fit in an `Int` convert back to
// `Int::max_value()`.

///|
let int_max : Int32 = 0x7FFFFFFF

///|
fn to_u32(x : Int32) -> UInt32 {
  if x == int_max {
    0xFFFFFFFFU
  } else {
    x.reinterpret_as_uint()
  }
}

///|
fn from_u32(x : UInt32) -> Int32 {
  if x > 0x7FFFFFFFU {
    int_max
  } else {
    x.reinterpret_as_int()
  }
}

///|
/// A position in a multi-line text document, in terms of rows and columns.
///
/// Rows and columns are zero-based.
pub(all) struct Point {
  row : Int32
  column : Int32
} derive(Eq, Hash, Compare, Debug, Default)

///|
/// Create a point.
pub fn Point::new(row : Int32, column : Int32) -> Point {
  { row, column, }
}

///|
/// Formats as `(row, column)`.
pub impl Show for Point with fn output(self, logger) {
  logger.write_string("(\{self.row}, \{self.column})")
}

///|
fn Point::to_ts(self : Point) -> @runtime.Point {
  { row: to_u32(self.row), column: to_u32(self.column), }
}

///|
fn Point::from_ts(point : @runtime.Point) -> Point {
  { row: from_u32(point.row), column: from_u32(point.column), }
}

///|
/// A range of positions in a multi-line text document, both in terms of bytes
/// and of rows and columns.
pub(all) struct Range {
  start_byte : Int32
  end_byte : Int32
  start_point : Point
  end_point : Point
} derive(Eq, Hash, Debug)

///|
fn Range::to_ts(self : Range) -> @runtime.Range {
  {
    start_byte: to_u32(self.start_byte),
    end_byte: to_u32(self.end_byte),
    start_point: self.start_point.to_ts(),
    end_point: self.end_point.to_ts(),
  }
}

///|
fn Range::from_ts(range : @runtime.Range) -> Range {
  {
    start_byte: from_u32(range.start_byte),
    end_byte: from_u32(range.end_byte),
    start_point: Point::from_ts(range.start_point),
    end_point: Point::from_ts(range.end_point),
  }
}

///|
/// A summary of a change to a text document.
pub(all) struct InputEdit {
  start_byte : Int32
  old_end_byte : Int32
  new_end_byte : Int32
  start_position : Point
  old_end_position : Point
  new_end_position : Point
} derive(Eq, Debug)

///|
fn InputEdit::to_ts(self : InputEdit) -> @runtime.InputEdit {
  {
    start_byte: to_u32(self.start_byte),
    old_end_byte: to_u32(self.old_end_byte),
    new_end_byte: to_u32(self.new_end_byte),
    start_point: self.start_position.to_ts(),
    old_end_point: self.old_end_position.to_ts(),
    new_end_point: self.new_end_position.to_ts(),
  }
}

///|
/// Edit a point to keep it in-sync with source code that has been edited.
///
/// This function updates a single point's byte offset and row/column position
/// based on this edit operation, returning the edited `(point, byte)`. This
/// is useful for editing points without requiring a tree or node instance.
pub fn InputEdit::edit_point(
  self : InputEdit,
  point : Point,
  byte : Int32,
) -> (Point, Int32) {
  let (p, b) = @runtime.point_edit(point.to_ts(), to_u32(byte), self.to_ts())
  (Point::from_ts(p), from_u32(b))
}

///|
/// Edit a range to keep it in-sync with source code that has been edited,
/// returning the edited range.
///
/// This function updates a range's start and end positions based on this
/// edit operation. This is useful for editing ranges without requiring a tree
/// or node instance.
pub fn InputEdit::edit_range(self : InputEdit, range : Range) -> Range {
  Range::from_ts(range.to_ts().edit(self.to_ts()))
}

///|
/// A type of log message.
pub(all) enum LogType {
  Parse
  Lex
} derive(Eq, Debug)

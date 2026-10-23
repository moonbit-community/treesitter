///|
fn validate_edit(edit : InputEdit) -> Unit raise EditError {
  if edit.start_byte < 0 ||
    edit.old_end_byte < edit.start_byte ||
    edit.new_end_byte < edit.start_byte ||
    edit.start_point.row < 0 ||
    edit.start_point.column < 0 ||
    edit.old_end_point.row < 0 ||
    edit.old_end_point.column < 0 ||
    edit.new_end_point.row < 0 ||
    edit.new_end_point.column < 0 ||
    edit.old_end_point < edit.start_point ||
    edit.new_end_point < edit.start_point {
    raise InvalidEdit("invalid byte or point bounds")
  }
}

///|
fn validate_point(point : Point, byte : Int32) -> Unit raise EditError {
  if byte < 0 || point.row < 0 || point.column < 0 {
    raise InvalidEdit("negative location")
  }
}

///|
fn shifted_location(
  point : Point,
  byte : Int32,
  edit : InputEdit,
) -> (Point, Int32) raise EditError {
  if point < edit.old_end_point {
    raise InvalidEdit("byte and point positions disagree with edit boundary")
  }
  let byte = edit.new_end_byte.to_int64() +
    byte.to_int64() -
    edit.old_end_byte.to_int64()
  let row = edit.new_end_point.row.to_int64() +
    point.row.to_int64() -
    edit.old_end_point.row.to_int64()
  let column = if point.row == edit.old_end_point.row {
    edit.new_end_point.column.to_int64() +
    point.column.to_int64() -
    edit.old_end_point.column.to_int64()
  } else {
    point.column.to_int64()
  }
  if byte > 2147483647L || row > 2147483647L || column > 2147483647L {
    raise InvalidEdit("edited location exceeds portable coordinate limit")
  }
  ({ row: row.to_int(), column: column.to_int(), }, byte.to_int())
}

///|
/// Return this point and its byte offset after an edit. Positions strictly
/// inside replaced text move to the replacement's end. Positions at or after
/// the old end shift by the edit's byte and row/column deltas.
/// Invalid coordinates and overflow of signed 32-bit coordinates raise EditError.
pub fn Point::edited(
  self : Point,
  byte : Int32,
  edit : InputEdit,
) -> (Point, Int32) raise EditError {
  validate_edit(edit)
  validate_point(self, byte)
  if byte >= edit.old_end_byte {
    shifted_location(self, byte, edit)
  } else if byte > edit.start_byte {
    (edit.new_end_point, edit.new_end_byte)
  } else {
    (self, byte)
  }
}

///|
/// Return a source range after an edit, following Tree-sitter's included-range
/// rules: endpoints strictly inside replaced text collapse to the edit's start.
/// An end byte of Int32::max_value is an unbounded end and remains unchanged.
pub fn Range::edited(self : Range, edit : InputEdit) -> Range raise EditError {
  validate_edit(edit)
  validate_point(self.start_point, self.start_byte)
  validate_point(self.end_point, self.end_byte)
  if self.end_byte < self.start_byte || self.end_point < self.start_point {
    raise InvalidEdit("reversed range")
  }
  edited_range(self, edit)
}

///|
fn edited_range(range : Range, edit : InputEdit) -> Range raise EditError {
  fn endpoint(point : Point, byte : Int32) -> (Point, Int32) raise EditError {
    if byte >= edit.old_end_byte {
      shifted_location(point, byte, edit)
    } else if byte > edit.start_byte {
      (edit.start_point, edit.start_byte)
    } else {
      (point, byte)
    }
  }
  let (start_point, start_byte) = endpoint(range.start_point, range.start_byte)
  let (end_point, end_byte) = if range.end_byte == 2147483647 {
    (range.end_point, range.end_byte)
  } else {
    endpoint(range.end_point, range.end_byte)
  }
  { start_point, start_byte, end_point, end_byte, }
}

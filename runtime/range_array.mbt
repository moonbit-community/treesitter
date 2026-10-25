// Port of the `TSRangeArray` helpers and `ts_range_edit` from
// tree-sitter lib/src/get_changed_ranges.c.

///|
fn range_array_add(ranges : Array[Range], start : Length, end : Length) -> Unit {
  if ranges.length() > 0 {
    let last_range = ranges[ranges.length() - 1]
    if start.bytes <= last_range.end_byte {
      ranges[ranges.length() - 1] = {
        ..last_range,
        end_byte: end.bytes,
        end_point: end.extent,
      }
      return
    }
  }
  if start.bytes < end.bytes {
    ranges.push({
      start_point: start.extent,
      end_point: end.extent,
      start_byte: start.bytes,
      end_byte: end.bytes,
    })
  }
}

///|
/// `ts_range_array_intersects`.
pub fn range_array_intersects(
  ranges : Array[Range],
  start_index : Int32,
  start_byte : UInt32,
  end_byte : UInt32,
) -> Bool {
  for i in start_index..<ranges.length() {
    let range = ranges[i]
    if range.end_byte > start_byte {
      if range.start_byte >= end_byte {
        break
      }
      return true
    }
  }
  false
}

///|
/// `ts_range_array_get_changed_ranges`.
pub fn range_array_get_changed_ranges(
  old_ranges : Array[Range],
  new_ranges : Array[Range],
  differences : Array[Range],
) -> Unit {
  let old_range_count = old_ranges.length()
  let new_range_count = new_ranges.length()
  let mut new_index = 0
  let mut old_index = 0
  let mut current_position = length_zero()
  let mut in_old_range = false
  let mut in_new_range = false
  while old_index < old_range_count || new_index < new_range_count {
    let next_old_position : Length = if in_old_range {
      let old_range = old_ranges[old_index]
      { bytes: old_range.end_byte, extent: old_range.end_point, }
    } else if old_index < old_range_count {
      let old_range = old_ranges[old_index]
      { bytes: old_range.start_byte, extent: old_range.start_point, }
    } else {
      length_max
    }
    let next_new_position : Length = if in_new_range {
      let new_range = new_ranges[new_index]
      { bytes: new_range.end_byte, extent: new_range.end_point, }
    } else if new_index < new_range_count {
      let new_range = new_ranges[new_index]
      { bytes: new_range.start_byte, extent: new_range.start_point, }
    } else {
      length_max
    }
    if next_old_position.bytes < next_new_position.bytes {
      if in_old_range != in_new_range {
        range_array_add(differences, current_position, next_old_position)
      }
      if in_old_range {
        old_index += 1
      }
      current_position = next_old_position
      in_old_range = !in_old_range
    } else if next_new_position.bytes < next_old_position.bytes {
      if in_old_range != in_new_range {
        range_array_add(differences, current_position, next_new_position)
      }
      if in_new_range {
        new_index += 1
      }
      current_position = next_new_position
      in_new_range = !in_new_range
    } else {
      if in_old_range != in_new_range {
        range_array_add(differences, current_position, next_new_position)
      }
      if in_old_range {
        old_index += 1
      }
      if in_new_range {
        new_index += 1
      }
      in_old_range = !in_old_range
      in_new_range = !in_new_range
      current_position = next_new_position
    }
  }
}

///|
/// `ts_range_edit`.
pub fn Range::edit(self : Range, edit : InputEdit) -> Range {
  let mut range = self
  if range.end_byte >= edit.old_end_byte {
    if range.end_byte != 0xFFFFFFFFU {
      range = {
        ..range,
        end_byte: edit.new_end_byte + (range.end_byte - edit.old_end_byte),
        end_point: point_add(
          edit.new_end_point,
          point_sub(range.end_point, edit.old_end_point),
        ),
      }
      if range.end_byte < edit.new_end_byte {
        range = { ..range, end_byte: 0xFFFFFFFFU, end_point: point_max, }
      }
    }
  } else if range.end_byte > edit.start_byte {
    range = { ..range, end_byte: edit.start_byte, end_point: edit.start_point, }
  }
  if range.start_byte >= edit.old_end_byte {
    range = {
      ..range,
      start_byte: edit.new_end_byte + (range.start_byte - edit.old_end_byte),
      start_point: point_add(
        edit.new_end_point,
        point_sub(range.start_point, edit.old_end_point),
      ),
    }
    if range.start_byte < edit.new_end_byte {
      range = { ..range, start_byte: 0xFFFFFFFFU, start_point: point_max, }
    }
  } else if range.start_byte > edit.start_byte {
    range = {
      ..range,
      start_byte: edit.start_byte,
      start_point: edit.start_point,
    }
  }
  range
}

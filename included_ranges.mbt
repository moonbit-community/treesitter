///|
pub fn Tree::included_ranges(self : Tree) -> Array[Range] {
  self.source_ranges.copy()
}

///|
fn project_node(
  node : Node,
  starts : Array[Int32],
  ends : Array[Int32],
  lines : Array[Int32],
  encoding~ : InputEncoding = Utf8,
) -> Node {
  let start_byte = starts[node.start_byte()]
  let end_byte = if node.start_byte() == node.end_byte() {
    start_byte
  } else {
    ends[node.end_byte()]
  }
  {
    data: {
      ..node.data,
      encoding,
      dependency_end: if node.data.dependency_end >= ends.length() {
        ends.last().unwrap() + 1
      } else {
        ends[node.data.dependency_end]
      },
      start_byte,
      end_byte,
      origin_start: start_byte,
      origin_end: end_byte,
      start_point: point_at(lines, start_byte),
      end_point: point_at(lines, end_byte),
      children: child_entries(
        node.data.children
        .entries()
        .map(c => (c.0, project_node(c.1, starts, ends, lines, encoding~))),
      ),
    },
  }
}

///|
/// Parse the logical concatenation of included ranges, then restore original
/// source coordinates. Tokens may span range boundaries. This path deliberately
/// reparses: its coordinate projection is not eligible for ordinary subtree reuse.
fn Parser::parse_ranges(
  self : Parser,
  source : Bytes,
  ranges : Array[Range],
  max_steps : Int32,
  max_branches : Int32,
  max_errors : Int32,
  cancelled : () -> Bool,
) -> Tree raise ParseError {
  let lines = line_starts(source)
  let bytes : Array[Byte] = []
  let starts = [0]
  let ends = [0]
  let mut previous_end = 0
  for range in ranges {
    if range.start_byte < previous_end ||
      range.end_byte < range.start_byte ||
      range.end_byte > source.length() ||
      range.start_byte < 0 {
      raise InvalidRanges(
        "ranges must be ordered, non-overlapping, and within the source",
      )
    }
    if range.start_point != point_at(lines, range.start_byte) ||
      range.end_point != point_at(lines, range.end_byte) {
      raise InvalidRanges("range points do not match UTF-8 byte offsets")
    }
    if cancelled() {
      raise Cancelled
    }
    starts[starts.length() - 1] = range.start_byte
    if bytes.is_empty() {
      ends[0] = range.start_byte
    }
    for i in range.start_byte..<range.end_byte {
      if i % 4096 == 0 && cancelled() {
        raise Cancelled
      }
      bytes.push(source[i])
      starts.push(i + 1)
      ends.push(i + 1)
    }
    previous_end = range.end_byte
  }
  let parsed = self.parse_source(
    Bytes::from_array(bytes),
    max_steps~,
    projection=Some({
      source,
      starts,
      ends,
      lines,
      ranges: ranges.copy(),
      encoding: Utf8,
    }),
    max_branches~,
    max_errors~,
    cancelled~,
  )
  {
    root: project_node(parsed.root, starts, ends, lines),
    source,
    language: self.language,
    edited: false,
    edited_length: source.length(),
    source_ranges: ranges.copy(),
    scanner: self.scanner,
    reused_subtrees: 0,
    parse_steps: parsed.parse_steps,
  }
}

///|
fn edited_range(range : Range, edit : InputEdit) -> Range {
  if range.end_byte < edit.start_byte {
    return range
  }
  let delta = edit.new_end_byte - edit.old_end_byte
  let start_byte = if range.start_byte >= edit.old_end_byte {
    range.start_byte + delta
  } else if range.start_byte > edit.start_byte {
    edit.start_byte
  } else {
    range.start_byte
  }
  let end_byte = if range.end_byte <= edit.start_byte {
    range.end_byte
  } else if range.end_byte >= edit.old_end_byte {
    range.end_byte + delta
  } else {
    edit.new_end_byte
  }
  {
    start_byte,
    end_byte,
    start_point: if range.start_byte >= edit.old_end_byte {
      shift_point(range.start_point, edit)
    } else if range.start_byte > edit.start_byte {
      edit.start_point
    } else {
      range.start_point
    },
    end_point: if range.end_byte <= edit.start_byte {
      range.end_point
    } else if range.end_byte >= edit.old_end_byte {
      shift_point(range.end_point, edit)
    } else {
      edit.new_end_point
    },
  }
}

// The parts of `bstr` 1.13.1 that `query_testing.rs` relies on:
// `ByteSlice::lines_with_terminator` and `ByteSlice::grapheme_indices`
// (src/ext_slice.rs, src/lines.rs, src/unicode/grapheme.rs, src/utf8.rs).
// Grapheme clusters are found with bstr's own forward DFA (grapheme_dfa.mbt),
// so that segmentation (including its Unicode version) matches upstream.

///|
priv struct GraphemeDfa {
  is_match : FixedArray[Bool]
  is_dead : FixedArray[Bool]
  eoi : FixedArray[Int32]
  /// `next[state * 256 + byte]`.
  next : FixedArray[Int32]
}

///|
let grapheme_dfa : GraphemeDfa = {
  let lines = grapheme_dfa_text
    .split("\n")
    .filter(l => !l.is_empty())
    .to_array()
  let n = lines.length()
  let is_match = FixedArray::make(n, false)
  let is_dead = FixedArray::make(n, false)
  let eoi = FixedArray::make(n, 0)
  let next = FixedArray::make(n * 256, 0)
  for state, line in lines {
    let fields = line.split(" ").to_array()
    is_match[state] = fields[0] == "M"
    is_dead[state] = fields[0] == "D"
    eoi[state] = parse_int(fields[1])
    for i = 2; i + 2 < fields.length(); i = i + 3 {
      let lo = parse_int(fields[i])
      let hi = parse_int(fields[i + 1])
      let target = parse_int(fields[i + 2])
      for b in lo..<=hi {
        next[state * 256 + b] = target
      }
    }
  }
  { is_match, is_dead, eoi, next, }
}

///|
fn parse_int(s : StringView) -> Int32 {
  let mut n = 0
  for c in s {
    n = n * 10 + (c.to_int() - '0'.to_int())
  }
  n
}

///|
/// regex-automata's `find_fwd` for bstr's anchored grapheme DFA: the end of
/// the leftmost-first match at the start of `bs`, if any.
fn grapheme_dfa_search(bs : BytesView) -> Int32? {
  let dfa = grapheme_dfa
  let mut state = 0
  let mut result = None
  for i, b in bs {
    state = dfa.next[state * 256 + b.to_int()]
    if dfa.is_match[state] {
      result = Some(i)
    } else if dfa.is_dead[state] {
      return result
    }
  }
  state = dfa.eoi[state]
  if dfa.is_match[state] {
    result = Some(bs.length())
  }
  result
}

///|
/// `u8::is_ascii_whitespace`.
fn is_ascii_whitespace(b : Byte) -> Bool {
  b == b' ' || b == b'\t' || b == b'\n' || b == b'\x0c' || b == b'\r'
}

///|
/// bstr's `utf8::decode_lossy(bs).1`: the number of bytes of the code point
/// (or of the maximal invalid prefix, at least 1) at the start of `bs`.
fn decode_lossy_size(bs : BytesView) -> Int32 {
  let len = bs.length()
  if len == 0 {
    return 0
  }
  let b0 = bs[0].to_int()
  if b0 <= 0x7F {
    return 1
  }
  let (width, lo1, hi1) = if b0 >= 0xC2 && b0 <= 0xDF {
    (2, 0x80, 0xBF)
  } else if b0 == 0xE0 {
    (3, 0xA0, 0xBF)
  } else if (b0 >= 0xE1 && b0 <= 0xEC) || b0 == 0xEE || b0 == 0xEF {
    (3, 0x80, 0xBF)
  } else if b0 == 0xED {
    (3, 0x80, 0x9F)
  } else if b0 == 0xF0 {
    (4, 0x90, 0xBF)
  } else if b0 >= 0xF1 && b0 <= 0xF3 {
    (4, 0x80, 0xBF)
  } else if b0 == 0xF4 {
    (4, 0x80, 0x8F)
  } else {
    // The decoder rejects at the first byte: `max(1, 1 - 1)`.
    return 1
  }
  // `i` counts the bytes fed to the decoder, including the rejected one.
  for i in 1..<width {
    if i >= len {
      // Ran out of input in an incomplete sequence.
      return len
    }
    let b = bs[i].to_int()
    let (lo, hi) = if i == 1 { (lo1, hi1) } else { (0x80, 0xBF) }
    if b < lo || b > hi {
      // Rejected after `i + 1` bytes: `max(1, (i + 1) - 1)`.
      return i
    }
  }
  width
}

///|
/// bstr's `decode_grapheme(bs).1`: the number of bytes of the grapheme at the
/// start of `bs` (0 when `bs` is empty).
fn decode_grapheme_size(bs : BytesView) -> Int32 {
  if bs.length() == 0 {
    0
  } else if bs.length() >= 2 &&
    bs[0] < b'\x80' &&
    bs[1] < b'\x80' &&
    !is_ascii_whitespace(bs[0]) {
    1
  } else if grapheme_dfa_search(bs) is Some(end) {
    end
  } else {
    decode_lossy_size(bs)
  }
}

///|
/// The end offsets of the graphemes of `bs` (`grapheme_indices().map(|(_,
/// end, _)| end)`).
pub fn grapheme_ends(bs : BytesView) -> Array[Int32] {
  grapheme_ends_iter(bs).collect()
}

///|
/// `grapheme_ends(bs)` as an iterator, which decodes graphemes only as far as
/// it is consumed (`grapheme_indices()` is lazy).
fn grapheme_ends_iter(bs : BytesView) -> Iter[Int32] {
  let mut index = 0
  Iter::new(() => {
    let size = decode_grapheme_size(bs[index:])
    if size == 0 {
      None
    } else {
      index += size
      Some(index)
    }
  })
}

///|
/// `lines_with_terminator(bs).get(n)`, scanning `bs` only up to the end of
/// that line (`lines_with_terminator().nth(n)`).
fn nth_line_with_terminator(bs : BytesView, n : Int32) -> BytesView? {
  let mut start = 0
  let mut row = 0
  while start < bs.length() {
    let end = match bs[start:].find(b"\n"[:]) {
      Some(i) => start + i + 1
      None => bs.length()
    }
    if row == n {
      return Some(bs[start:end])
    }
    row += 1
    start = end
  }
  None
}

///|
/// `ByteSlice::lines_with_terminator`: the lines of `bs`, each including its
/// trailing `\n`; a final line without terminator is included when it is
/// non-empty.
pub fn lines_with_terminator(bs : BytesView) -> Array[BytesView] {
  let result = []
  let mut start = 0
  for i, b in bs {
    if b == b'\n' {
      result.push(bs[start:i + 1])
      start = i + 1
    }
  }
  if start < bs.length() {
    result.push(bs[start:])
  }
  result
}

// The LZ77 layer and the base64 text layer of the compact language format
// (see compact.mbt).
//
// LZ77 stream: a sequence of `u` literal count, that many literal bytes, then
// (unless the output is complete) `u` (match length - lz_min_match) and `u`
// (distance - 1); a match copies `length` bytes starting `distance` bytes
// back in the output, possibly overlapping the bytes it writes. The stream
// ends when the output has the declared raw length, after a literal run.

///|
let lz_min_match : Int = 4

///|
let lz_hash_bits : Int = 16

///|
/// Maximum number of earlier positions tried per position. Fixed, so the
/// output is a deterministic function of the input.
let lz_max_chain : Int = 32

///|
let lz_max_distance : Int = 1 << 22

///|
let lz_max_match : Int = 1 << 16

///|
fn lz_write_uint(buf : @buffer.Buffer, value : Int) -> Unit {
  let mut v = value
  while v >= 0x80 {
    buf.write_byte(((v & 0x7f) | 0x80).to_byte())
    v = v >> 7
  }
  buf.write_byte(v.to_byte())
}

///|
fn lz_hash(data : Bytes, i : Int) -> Int {
  let v = data[i].to_uint() |
    (data[i + 1].to_uint() << 8) |
    (data[i + 2].to_uint() << 16) |
    (data[i + 3].to_uint() << 24)
  ((v * 2654435761U) >> (32 - lz_hash_bits)).reinterpret_as_int()
}

///|
/// Compress `data` with a greedy LZ77 over hash chains.
fn lz_compress(data : Bytes) -> Bytes {
  let n = data.length()
  let out = @buffer.Buffer(size_hint=n / 4 + 16)
  let head = FixedArray::make(1 << lz_hash_bits, -1)
  let prev = FixedArray::make(n, -1)
  fn insert(p : Int) {
    if p + lz_min_match <= n {
      let h = lz_hash(data, p)
      prev[p] = head[h]
      head[h] = p
    }
  }

  let mut i = 0
  let mut literal_start = 0
  while i < n {
    let mut best_length = 0
    let mut best_distance = 0
    if i + lz_min_match <= n {
      let limit = if n - i < lz_max_match { n - i } else { lz_max_match }
      let mut candidate = head[lz_hash(data, i)]
      let mut depth = 0
      while candidate >= 0 &&
            depth < lz_max_chain &&
            i - candidate <= lz_max_distance {
        let mut length = 0
        while length < limit && data[candidate + length] == data[i + length] {
          length += 1
        }
        if length > best_length {
          best_length = length
          best_distance = i - candidate
          if length == limit {
            break
          }
        }
        candidate = prev[candidate]
        depth += 1
      }
    }
    if best_length >= lz_min_match {
      lz_write_uint(out, i - literal_start)
      out.write_bytes(data[literal_start:i])
      lz_write_uint(out, best_length - lz_min_match)
      lz_write_uint(out, best_distance - 1)
      for p in i..<(i + best_length) {
        insert(p)
      }
      i += best_length
      literal_start = i
    } else {
      insert(i)
      i += 1
    }
  }
  lz_write_uint(out, n - literal_start)
  out.write_bytes(data[literal_start:n])
  out.to_bytes()
}

///|
/// Decompress the LZ77 stream starting at `data[start]` into `raw_length`
/// bytes.
fn lz_decompress(
  data : FixedArray[Byte],
  start : Int,
  raw_length : Int,
) -> FixedArray[Byte] raise CompactError {
  let out : FixedArray[Byte] = FixedArray::make(raw_length, 0)
  let r = CompactReader::{ data, pos: start, }
  let mut o = 0
  for ;; {
    let literals = r.uint()
    if literals > raw_length - o || literals > data.length() - r.pos {
      raise CompactError("literal run out of range")
    }
    FixedArray::unsafe_blit(out, o, data, r.pos, literals)
    r.pos += literals
    o += literals
    if o == raw_length {
      break
    }
    let length = r.uint() + lz_min_match
    let distance = r.uint() + 1
    if distance > o || length > raw_length - o {
      raise CompactError("match out of range")
    }
    let from = o - distance
    if distance >= length {
      FixedArray::unsafe_blit(out, o, out, from, length)
    } else {
      for k in 0..<length {
        out[o + k] = out[from + k]
      }
    }
    o += length
  }
  if r.pos != data.length() {
    raise CompactError(
      "\{data.length() - r.pos} trailing bytes after the compressed data",
    )
  }
  out
}

///|
let base64_alphabet : String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

///|
fn base64_encode(data : Bytes) -> String {
  let n = data.length()
  let sb = StringBuilder(size_hint=(n + 2) / 3 * 4)
  let mut i = 0
  while i + 3 <= n {
    let v = (data[i].to_int() << 16) |
      (data[i + 1].to_int() << 8) |
      data[i + 2].to_int()
    sb.write_char(base64_alphabet[(v >> 18) & 63].unsafe_to_char())
    sb.write_char(base64_alphabet[(v >> 12) & 63].unsafe_to_char())
    sb.write_char(base64_alphabet[(v >> 6) & 63].unsafe_to_char())
    sb.write_char(base64_alphabet[v & 63].unsafe_to_char())
    i += 3
  }
  let rest = n - i
  if rest > 0 {
    let v = (data[i].to_int() << 16) |
      (if rest == 2 { data[i + 1].to_int() << 8 } else { 0 })
    sb.write_char(base64_alphabet[(v >> 18) & 63].unsafe_to_char())
    sb.write_char(base64_alphabet[(v >> 12) & 63].unsafe_to_char())
    if rest == 2 {
      sb.write_char(base64_alphabet[(v >> 6) & 63].unsafe_to_char())
    } else {
      sb.write_char('=')
    }
    sb.write_char('=')
  }
  sb.to_string()
}

///|
fn base64_digit(c : UInt16) -> Int {
  match c {
    'A'..<='Z' => c.to_int() - 'A'.to_int()
    'a'..<='z' => c.to_int() - 'a'.to_int() + 26
    '0'..<='9' => c.to_int() - '0'.to_int() + 52
    '+' => 62
    '/' => 63
    ' ' | '\n' | '\r' | '\t' => -1
    '=' => -2
    _ => -3
  }
}

///|
fn base64_decode(text : StringView) -> FixedArray[Byte] raise CompactError {
  let out = @buffer.Buffer(size_hint=text.length() / 4 * 3)
  let mut acc = 0
  let mut count = 0
  let mut padding = 0
  for i in 0..<text.length() {
    let d = base64_digit(text[i])
    if d == -1 {
      continue
    }
    if d == -3 || (d >= 0 && padding > 0) {
      raise CompactError("invalid base64 text")
    }
    if d == -2 {
      padding += 1
      acc = acc << 6
    } else {
      acc = (acc << 6) | d
    }
    count += 1
    if count == 4 {
      out.write_byte((acc >> 16).to_byte())
      if padding < 2 {
        out.write_byte((acc >> 8).to_byte())
      }
      if padding < 1 {
        out.write_byte(acc.to_byte())
      }
      acc = 0
      count = 0
    }
  }
  if count != 0 || padding > 2 {
    raise CompactError("truncated base64 text")
  }
  FixedArray::from_iter(out.to_bytes().iter())
}

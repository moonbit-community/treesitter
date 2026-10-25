// Decoding of the generated tables of regex-syntax 0.8.11
// `src/unicode_tables/*.rs` (see tools/oracle/import_regex_unicode.py).

///|
fn hex_digit(c : Char) -> Int32 {
  match c {
    '0'..<='9' => c.to_int() - '0'.to_int()
    'a'..<='f' => c.to_int() - 'a'.to_int() + 10
    _ => abort("invalid hex digit in Unicode table")
  }
}

///|
/// Decode a `start-end,start,...` string (hex code points) into the inclusive
/// ranges of the corresponding `&[(char, char)]` table, in table order.
pub fn decode_ranges(encoded : String) -> Array[(Int32, Int32)] {
  let result = []
  let mut start = 0
  let mut value = 0
  let mut in_end = false
  for c in encoded {
    match c {
      ',' => {
        result.push(if in_end { (start, value) } else { (value, value) })
        value = 0
        in_end = false
      }
      '-' => {
        start = value
        value = 0
        in_end = true
      }
      _ => value = value * 16 + hex_digit(c)
    }
  }
  if encoded.length() > 0 {
    result.push(if in_end { (start, value) } else { (value, value) })
  }
  result
}

///|
/// Binary search a `BY_NAME` table for `name`, mirroring
/// `binary_search_by_key(&name, |x| x.0)` (only exact matches matter).
pub fn lookup_by_name(
  table : Array[(String, String)],
  name : String,
) -> Array[(Int32, Int32)]? {
  match binary_search_str(table.length(), i => table[i].0, name) {
    Some(i) => Some(decode_ranges(table[i].1))
    None => None
  }
}

///|
/// Byte-wise (Rust `str` `Ord`) comparison of two ASCII strings.
pub fn compare_str(a : String, b : String) -> Int32 {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    let x = a[i].to_int()
    let y = b[i].to_int()
    if x != y {
      return if x < y { -1 } else { 1 }
    }
  }
  a.length().compare(b.length())
}

///|
/// `binary_search_by_key` over `len` sorted string keys; `Some(index)` on an
/// exact match.
pub fn binary_search_str(
  len : Int32,
  key : (Int32) -> String,
  needle : String,
) -> Int32? {
  let mut lo = 0
  let mut hi = len
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let cmp = compare_str(key(mid), needle)
    if cmp == 0 {
      return Some(mid)
    } else if cmp < 0 {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  None
}

///|
let case_folding_simple_cache : Ref[
  (FixedArray[Int32], FixedArray[FixedArray[Int32]])?,
] = { val: None, }

///|
/// `CASE_FOLDING_SIMPLE` as parallel arrays: sorted keys and, for each key,
/// its equivalence class (excluding the key itself), in table order.
pub fn case_folding_simple_table() -> (
  FixedArray[Int32],
  FixedArray[FixedArray[Int32]],
) {
  match case_folding_simple_cache.val {
    Some(table) => table
    None => {
      let keys = []
      let values = []
      for entry in case_folding_simple.split(",") {
        guard! entry.split(":").collect() is [key, targets]
        keys.push(decode_hex(key))
        values.push(
          FixedArray::from_array(targets.split(".").map(decode_hex).collect()),
        )
      }
      let table = (FixedArray::from_array(keys), FixedArray::from_array(values))
      case_folding_simple_cache.val = Some(table)
      table
    }
  }
}

///|
fn decode_hex(s : StringView) -> Int32 {
  let mut value = 0
  for c in s {
    value = value * 16 + hex_digit(c)
  }
  value
}

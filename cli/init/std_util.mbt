// The Rust standard library operations that version.rs and init.rs rely on:
// `fs::read_to_string`, `fs::write`, `fs::create_dir_all`, `Path::exists`
// and `str::lines`, with Rust's `io::Error` display texts; the Unicode
// properties and case mappings of `char` and `str::to_lowercase` (tables in
// unicode_data.mbt).

///|
/// A `std::io::Error`, carrying its display text.
priv suberror IoError {
  IoError(String)
}

///|
/// `fs::read_to_string`.
async fn read_to_string(path : String) -> String raise IoError {
  let data = @fs.read_file(path) catch {
    e => raise IoError(@support.io_error_message(e))
  }
  match @support.utf8_strict(data.binary()) {
    Some(s) => s
    None => raise IoError("stream did not contain valid UTF-8")
  }
}

///|
/// `fs::write`.
async fn fs_write(path : String, contents : String) -> Unit raise IoError {
  @fs.write_file(path, contents, create_mode=CreateOrTruncate, permission=0o666) catch {
    e => raise IoError(@support.io_error_message(e))
  }
}

///|
/// `fs::create_dir_all`.
async fn create_dir_all(path : String) -> Unit raise IoError {
  @support.create_dir_all(path) catch {
    e => raise IoError(@support.io_error_message(e))
  }
}

///|
/// `fs::remove_file`.
async fn remove_file(path : String) -> Unit raise IoError {
  @fs.remove(path) catch {
    e => raise IoError(@support.io_error_message(e))
  }
}

///|
/// `Path::exists`.
async fn path_exists(path : String) -> Bool {
  @fs.exists(path) catch {
    _ => false
  }
}

///|
/// `str::lines`: split at `\n`, dropping a trailing `\r` of each line; a
/// final empty line after a trailing newline is not produced.
fn rust_lines(s : String) -> Array[String] {
  let lines = []
  if s.is_empty() {
    return lines
  }
  let parts = s.split("\n").map(v => v.to_owned()).collect()
  if s.has_suffix("\n") {
    ignore(parts.pop())
  }
  for part in parts {
    lines.push(
      if part.has_suffix("\r") {
        part.view(end_offset=part.length() - 1).to_owned()
      } else {
        part
      },
    )
  }
  lines
}

///|
/// `indoc::indoc!`: strip the leading newline and the common indentation of
/// a string literal (computed over the lines after the first that are not
/// whitespace-only).
fn indoc(s : String) -> String {
  let ignore_first_line = s.has_prefix("\n") || s.has_prefix("\r\n")
  let text = if s.has_prefix("\r\n") {
    s.view(start_offset=1).to_owned()
  } else {
    s
  }
  let lines = text.split("\n").map(v => v.to_owned()).collect()
  let mut spaces : Int32? = None
  for i, line in lines {
    if i == 0 {
      continue
    }
    let mut count : Int32? = None
    for j, ch in line {
      if ch != ' ' && ch != '\t' {
        count = Some(j)
        break
      }
    }
    if count is Some(n) {
      spaces = Some(
        match spaces {
          Some(m) if m < n => m
          _ => n
        },
      )
    }
  }
  let spaces = spaces.unwrap_or(0)
  let result = StringBuilder()
  for i, line in lines {
    if i > 1 || (i == 1 && !ignore_first_line) {
      result.write_char('\n')
    }
    if i == 0 {
      result.write_string(line)
    } else if line.length() > spaces {
      result.write_view(line.view(start_offset=spaces))
    }
  }
  result.to_string()
}

///|
/// `char::is_whitespace` (White_Space).
fn char_is_whitespace(c : Char) -> Bool {
  if c <= '\u{7F}' {
    c == ' ' || (c >= '\t' && c <= '\r')
  } else {
    c.is_whitespace()
  }
}

///|
/// `str::trim`: without leading and trailing `char::is_whitespace`
/// characters.
fn rust_trim(s : String) -> String {
  let chars = s.to_array()
  let mut start = 0
  while start < chars.length() && char_is_whitespace(chars[start]) {
    start += 1
  }
  let mut end = chars.length()
  while end > start && char_is_whitespace(chars[end - 1]) {
    end -= 1
  }
  String::from_array(chars[start:end])
}

///|
/// Whether `c` lies in one of the inclusive ranges of `table` (a flat array
/// of `lo, hi` pairs in ascending order; see unicode_data.mbt).
fn in_char_table(table : FixedArray[UInt32], c : Char) -> Bool {
  let v = c.to_uint()
  for lo = 0, hi = table.length() / 2; lo < hi; {
    let mid = lo + (hi - lo) / 2
    if v < table[2 * mid] {
      continue lo, mid
    } else if v > table[2 * mid + 1] {
      continue mid + 1, hi
    } else {
      break true
    }
  } nobreak {
    false
  }
}

///|
/// `char::is_alphanumeric`.
fn char_is_alphanumeric(c : Char) -> Bool {
  in_char_table(alphanumeric_table, c)
}

///|
/// `char::is_lowercase`.
fn char_is_lowercase(c : Char) -> Bool {
  in_char_table(lowercase_table, c)
}

///|
/// `char::is_uppercase`.
fn char_is_uppercase(c : Char) -> Bool {
  in_char_table(uppercase_table, c)
}

///|
/// The mapping of `c` in a case-mapping table of unicode_data.mbt, if `c`
/// does not map to itself.
fn case_mapping(
  keys : FixedArray[UInt32],
  values : FixedArray[String],
  c : Char,
) -> String? {
  let v = c.to_uint()
  for lo = 0, hi = keys.length(); lo < hi; {
    let mid = lo + (hi - lo) / 2
    if v < keys[mid] {
      continue lo, mid
    } else if v > keys[mid] {
      continue mid + 1, hi
    } else {
      break Some(values[mid])
    }
  } nobreak {
    None
  }
}

///|
/// `write!(out, "{}", c.to_lowercase())`.
fn write_char_lowercase(out : StringBuilder, c : Char) -> Unit {
  match case_mapping(to_lowercase_keys, to_lowercase_values, c) {
    Some(m) => out.write_string(m)
    None => out.write_char(c)
  }
}

///|
/// `write!(out, "{}", c.to_uppercase())`.
fn write_char_uppercase(out : StringBuilder, c : Char) -> Unit {
  match case_mapping(to_uppercase_keys, to_uppercase_values, c) {
    Some(m) => out.write_string(m)
    None => out.write_char(c)
  }
}

///|
/// `case_ignorable_then_cased` of `map_uppercase_sigma`: the first
/// character of `chars` that is not case-ignorable is cased.
fn case_ignorable_then_cased(chars : Iter[Char]) -> Bool {
  for c in chars {
    if !in_char_table(case_ignorable_table, c) {
      return in_char_table(cased_not_case_ignorable_table, c)
    }
  }
  false
}

///|
/// `str::to_lowercase`: `char::to_lowercase` of every character, except
/// that `Σ` maps to `ς` at the end of a word (`map_uppercase_sigma`).
fn str_to_lowercase(s : String) -> String {
  let chars = s.to_array()
  let out = StringBuilder()
  for i, c in chars {
    if c == 'Σ' {
      // Σ maps to σ, except at the end of a word where it maps to ς.
      let is_word_final = case_ignorable_then_cased(chars[:i].rev_iter()) &&
        !case_ignorable_then_cased(chars[i + 1:].iter())
      out.write_char(if is_word_final { 'ς' } else { 'σ' })
    } else {
      write_char_lowercase(out, c)
    }
  }
  out.to_string()
}

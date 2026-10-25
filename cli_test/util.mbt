// Helpers standing in for the Rust standard library string and path
// functions that test.rs, parse.rs and fuzz/ use (`str::lines`, `str::trim`,
// `Path::file_stem`, ...), plus a line diff replacing `similar::TextDiff`.

///|
/// `std::env::consts::OS`.
let current_os : String = @support.current_os

///|
/// `log::warn!` (the CLI's logger: `Warning: ...` on standard error).
fn warn(message : String) -> Unit {
  @support.log_warn(message)
}

///|
/// Whether a UTF-16 code unit is a Unicode `White_Space` character (they are
/// all in the BMP, so surrogates never are).
fn is_ws_unit(unit : UInt16) -> Bool {
  let code = unit.to_int()
  if code >= 0xD800 && code <= 0xDFFF {
    return false
  }
  Int32::unsafe_to_char(code).is_whitespace()
}

///|
/// `str::trim_start` (Unicode whitespace).
fn trim_ws_start(s : StringView) -> StringView {
  let mut start = 0
  while start < s.length() && is_ws_unit(s[start]) {
    start += 1
  }
  s[start:]
}

///|
/// `str::trim_end` (Unicode whitespace).
fn trim_ws_end(s : StringView) -> StringView {
  let mut end = s.length()
  while end > 0 && is_ws_unit(s[end - 1]) {
    end -= 1
  }
  s[:end]
}

///|
/// `str::trim` (Unicode whitespace).
fn trim_ws(s : StringView) -> StringView {
  trim_ws_end(trim_ws_start(s))
}

///|
/// `str::lines`: split at `\n`, dropping a `\r` before it; a trailing empty
/// line is not yielded.
fn rust_lines(s : StringView) -> Array[StringView] {
  let result = []
  let mut start = 0
  for i in 0..<s.length() {
    if s[i] == '\n' {
      let end = if i > start && s[i - 1] == '\r' { i - 1 } else { i }
      result.push(s[start:end])
      start = i + 1
    }
  }
  // An unterminated last line keeps a final `\r`.
  if start < s.length() {
    result.push(s[start:])
  }
  result
}

///|
/// `str::split_inclusive('\n')`.
fn split_inclusive_newline(s : StringView) -> Array[StringView] {
  let result = []
  let mut start = 0
  for i in 0..<s.length() {
    if s[i] == '\n' {
      result.push(s[start:i + 1])
      start = i + 1
    }
  }
  if start < s.length() {
    result.push(s[start:])
  }
  result
}

///|
/// `str::split_whitespace`.
fn split_whitespace(s : StringView) -> Array[StringView] {
  let result = []
  let mut start = -1
  for i in 0..<s.length() {
    if is_ws_unit(s[i]) {
      if start >= 0 {
        result.push(s[start:i])
        start = -1
      }
    } else if start < 0 {
      start = i
    }
  }
  if start >= 0 {
    result.push(s[start:])
  }
  result
}

///|
/// `s.split(c).next().unwrap()`: the part of `s` before the first `c`.
fn split_first(s : StringView, c : Char) -> StringView {
  for i in 0..<s.length() {
    if s[i].to_int() == c.to_int() {
      return s[:i]
    }
  }
  s
}

///|
/// `s.strip_prefix(prefix).and_then(|s| s.strip_suffix(suffix))`.
fn strip_wrapped(
  s : StringView,
  prefix : String,
  suffix : String,
) -> StringView? {
  if !s.has_prefix(prefix) {
    return None
  }
  let rest = s[prefix.length():]
  if !rest.has_suffix(suffix) {
    return None
  }
  Some(rest[:rest.length() - suffix.length()])
}

///|
/// The length of `s` in UTF-8 bytes (Rust's `str::len`).
fn utf8_len(s : StringView) -> Int32 {
  let mut n = 0
  for c in s {
    let code = c.to_int()
    n += if code < 0x80 {
      1
    } else if code < 0x800 {
      2
    } else if code < 0x10000 {
      3
    } else {
      4
    }
  }
  n
}

///|
/// Compare two strings in UTF-8 byte order (= code point order), the order of
/// `OsStr` on Unix.
fn compare_bytes(a : String, b : String) -> Int32 {
  let a = a.iter().to_array()
  let b = b.iter().to_array()
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    if a[i] != b[i] {
      return a[i].to_int() - b[i].to_int()
    }
  }
  a.length() - b.length()
}

///|
/// `Path::file_name`.
fn file_name_of(path : String) -> String {
  match path.rev_find("/") {
    Some(i) => path[i + 1:].to_owned()
    None => path
  }
}

///|
/// `Path::file_stem`.
fn file_stem(path : String) -> String {
  let name = file_name_of(path)
  match name.rev_find(".") {
    Some(i) if i > 0 => name[:i].to_owned()
    _ => name
  }
}

///|
/// `Path::is_dir` (follows symbolic links).
async fn is_dir(path : String) -> Bool {
  if !@fs.exists(path) {
    return false
  }
  @fs.kind(path, follow_symlink=true) == Directory
}

///|
priv enum ChangeTag {
  Equal
  Delete
  Insert
}

///|
/// A line diff from `old` to `new` (`similar::TextDiff::from_lines`): the
/// lines keep their trailing newline. Computed from a longest common
/// subsequence of lines, with deletions before insertions in each changed
/// region.
fn diff_lines(old : String, new : String) -> Array[(ChangeTag, StringView)] {
  let a = split_inclusive_newline(old)
  let b = split_inclusive_newline(new)
  let n = a.length()
  let m = b.length()
  // lcs[i][j]: the LCS length of a[i:] and b[j:].
  let lcs = Array::makei(n + 1, _ => Array::make(m + 1, 0))
  for i = n - 1; i >= 0; i = i - 1 {
    for j = m - 1; j >= 0; j = j - 1 {
      lcs[i][j] = if a[i] == b[j] {
        lcs[i + 1][j + 1] + 1
      } else if lcs[i + 1][j] >= lcs[i][j + 1] {
        lcs[i + 1][j]
      } else {
        lcs[i][j + 1]
      }
    }
  }
  let result = []
  let mut i = 0
  let mut j = 0
  while i < n || j < m {
    if i < n && j < m && a[i] == b[j] {
      result.push((ChangeTag::Equal, a[i]))
      i += 1
      j += 1
    } else if i < n && (j >= m || lcs[i + 1][j] >= lcs[i][j + 1]) {
      result.push((Delete, a[i]))
      i += 1
    } else {
      result.push((Insert, b[j]))
      j += 1
    }
  }
  result
}

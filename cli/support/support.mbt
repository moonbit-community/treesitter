// Host helpers shared by the ports of tree-sitter's CLI, loader and config
// crates: the parts of Rust's standard library (`std::io` output and error
// messages, `std::path::Path`, `std::process::exit`, `Instant`) and of
// serde_json (`to_string_pretty`) whose exact behaviour shows in the CLI's
// output.

///|
extern "C" fn ts_cli_now_ns() -> Int64 = "ts_cli_now_ns"

///|
extern "C" fn ts_cli_isatty(fd : Int32) -> Int32 = "ts_cli_isatty"

///|
extern "C" fn ts_cli_strerror(err : Int32) -> Bytes = "ts_cli_strerror"

///|
/// Nanoseconds from a monotonic clock (`Instant`).
pub fn now_ns() -> Int64 {
  ts_cli_now_ns()
}

///|
pub fn is_terminal(fd : Int32) -> Bool {
  ts_cli_isatty(fd) != 0
}

///|
/// Rust's `Display for std::io::Error` of an OS error:
/// `"<strerror> (os error <errno>)"`; other errors are shown as they are.
pub fn io_error_message(err : Error) -> String {
  match err {
    @os_error.OSError(errno, ..) =>
      "\{@utf8.decode_lossy(ts_cli_strerror(errno))} (os error \{errno})"
    _ => "\{err}"
  }
}

///|
/// An I/O error annotated with a path (`IoError` of the loader, config and
/// generate crates): `"<error> (<path>)"`.
pub fn io_error_with_path(err : Error, path : String?) -> String {
  match path {
    Some(p) => "\{io_error_message(err)} (\{p})"
    None => io_error_message(err)
  }
}

///|
pub fn is_not_found(err : Error) -> Bool {
  match err {
    @os_error.OSError(_) as e => e.is_ENOENT()
    _ => false
  }
}

// Paths (`std::path::Path`, Unix semantics).

///|
pub fn is_absolute(path : String) -> Bool {
  path.has_prefix("/")
}

///|
/// `Path::join`.
pub fn path_join(base : String, rel : String) -> String {
  if is_absolute(rel) || base.is_empty() {
    rel
  } else if base.has_suffix("/") {
    base + rel
  } else {
    base + "/" + rel
  }
}

///|
/// The normal components of a path (`.` components and repeated or trailing
/// separators dropped, as `Path::components` does).
fn components(path : String) -> Array[String] {
  let result = []
  for i, part in path.split("/") {
    let part = part.to_owned()
    if part.is_empty() || (part == "." && i > 0) {
      continue
    }
    result.push(part)
  }
  result
}

///|
/// `Path::file_name`.
pub fn file_name(path : String) -> String? {
  let comps = components(path)
  match comps.last() {
    Some("..") | Some(".") | None => None
    Some(name) => Some(name)
  }
}

///|
/// `Path::parent`.
pub fn parent(path : String) -> String? {
  if path == "/" || path.is_empty() {
    return None
  }
  let comps = components(path)
  if comps.is_empty() {
    return None
  }
  let rest = comps[:comps.length() - 1].to_owned().join("/")
  if is_absolute(path) {
    Some("/" + rest)
  } else {
    Some(rest)
  }
}

///|
/// `Path::extension`.
pub fn extension(path : String) -> String? {
  guard file_name(path) is Some(name) else { return None }
  match name.rev_find(".") {
    Some(i) if i > 0 =>
      Some(name.unsafe_substring(start=i + 1, end=name.length()))
    _ => None
  }
}

///|
/// `Path::file_stem`.
pub fn file_stem(path : String) -> String? {
  guard file_name(path) is Some(name) else { return None }
  match name.rev_find(".") {
    Some(i) if i > 0 => Some(name.unsafe_substring(start=0, end=i))
    _ => Some(name)
  }
}

///|
/// `Path::with_extension`.
pub fn with_extension(path : String, ext : String) -> String {
  guard file_name(path) is Some(name) else { return path }
  let stem = file_stem(path).unwrap_or(name)
  let dir = path.unsafe_substring(start=0, end=path.length() - name.length())
  if ext.is_empty() {
    dir + stem
  } else {
    dir + stem + "." + ext
  }
}

///|
/// `Path::starts_with` (component-wise).
pub fn path_starts_with(path : String, prefix : String) -> Bool {
  let a = components(path)
  let b = components(prefix)
  if is_absolute(path) != is_absolute(prefix) || b.length() > a.length() {
    return false
  }
  for i, c in b {
    if a[i] != c {
      return false
    }
  }
  true
}

///|
extern "C" fn ts_cli_passwd_home() -> Bytes = "ts_cli_passwd_home"

///|
/// `etcetera::home_dir`, i.e. `std::env::home_dir`: `HOME` when it is set
/// and not empty, otherwise the home directory of the current user in the
/// account database (`getpwuid_r`).
pub fn home_dir() -> String? {
  match @env.get_env_var("HOME") {
    Some(home) if !home.is_empty() => Some(home)
    _ => {
      let entry = ts_cli_passwd_home()
      if entry[0] == 1 {
        Some(@utf8.decode_lossy(entry[1:]))
      } else {
        None
      }
    }
  }
}

///|
/// `etcetera::choose_base_strategy().config_dir()` (XDG).
pub fn config_dir() -> String? {
  match @env.get_env_var("XDG_CONFIG_HOME") {
    Some(dir) if is_absolute(dir) => Some(dir)
    _ => home_dir().map(home => path_join(home, ".config"))
  }
}

///|
/// `etcetera::choose_base_strategy().cache_dir()` (XDG).
pub fn cache_dir() -> String? {
  match @env.get_env_var("XDG_CACHE_HOME") {
    Some(dir) if is_absolute(dir) => Some(dir)
    _ => home_dir().map(home => path_join(home, ".cache"))
  }
}

///|
extern "C" fn ts_cli_default_temp_dir() -> Bytes = "ts_cli_default_temp_dir"

///|
/// `std::env::temp_dir`: `TMPDIR` when it is set (also when it is empty,
/// which makes temporary paths relative to the current directory), else the
/// per-user temporary directory on macOS (`_CS_DARWIN_USER_TEMP_DIR`) or
/// `/tmp`.
pub fn temp_dir() -> String {
  match @env.get_env_var("TMPDIR") {
    Some(dir) => dir
    None => utf8_lossy(ts_cli_default_temp_dir())
  }
}

///|
/// `String::from_utf8_lossy`.
pub fn utf8_lossy(bytes : BytesView) -> String {
  @utf8.decode_lossy(bytes)
}

///|
/// `str::from_utf8`.
pub fn utf8_strict(bytes : BytesView) -> String? {
  try @utf8.decode(bytes) catch {
    _ => None
  } noraise {
    s => Some(s)
  }
}

///|
/// UTF-8 encoding of a string.
pub fn utf8(s : String) -> Bytes {
  @utf8.encode(s)
}

///|
/// The UTF-8 length of a string (Rust's `str::len`).
pub fn utf8_len(s : String) -> Int32 {
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
/// The number of `char`s in a string (`str::chars().count()`).
pub fn char_count(s : String) -> Int32 {
  let mut n = 0
  for _ in s {
    n += 1
  }
  n
}

///|
/// `std::env::consts::OS`. (Taken from the C compiler's target macros:
/// `#cfg(platform=...)` conditions are not set by every build of moon.)
pub let current_os : String = target_os()

///|
/// `fs::create_dir_all`: create a directory and its parents; existing
/// directories are fine.
pub async fn create_dir_all(path : String) -> Unit {
  if path.is_empty() {
    return
  }
  let kind = @fs.kind(path, follow_symlink=true) catch {
    _ => @fs.FileKind::Unknown
  }
  if kind is Directory {
    return
  }
  if parent(path) is Some(p) && !p.is_empty() {
    create_dir_all(p)
  }
  @fs.mkdir(path, permission=0o777) catch {
    e => {
      let kind = @fs.kind(path, follow_symlink=true) catch { _ => raise e }
      if !(kind is Directory) {
        raise e
      }
    }
  }
}

// `std::path::Path` component semantics on Unix (Rust 1.97 std
// `path.rs`): `Path::components`, `PartialEq for Path`, `Path::file_name`
// and `Path::strip_prefix`. Paths are compared purely lexically: `.`
// components (except a leading one) and repeated or trailing separators are
// ignored, but `..` and symbolic links are not resolved.

///|
/// `std::path::Component` (Unix: no `Prefix`).
pub(all) enum PathComponent {
  RootDir
  CurDir
  ParentDir
  Normal(String)
} derive(Eq, Debug)

///|
/// `Component::as_os_str`.
pub fn PathComponent::as_str(self : PathComponent) -> String {
  match self {
    RootDir => "/"
    CurDir => "."
    ParentDir => ".."
    Normal(s) => s
  }
}

///|
/// `Components::include_cur_dir`: a leading `.` component is kept when the
/// path has no root and is `.` or starts with `./`.
fn include_cur_dir(path : String) -> Bool {
  if path.has_prefix("/") {
    return false
  }
  path == "." || path.has_prefix("./")
}

///|
/// `Components::parse_single_component`.
fn parse_single_component(comp : String) -> PathComponent? {
  match comp {
    "." | "" => None
    ".." => Some(ParentDir)
    _ => Some(Normal(comp))
  }
}

///|
/// The components of `path` together with the index just past each of them
/// (where the forward `Components` iterator stands after yielding it).
fn components_with_ends(path : String) -> (Array[PathComponent], Array[Int32]) {
  let comps = []
  let ends = []
  let len = path.length()
  let mut pos = 0
  // State::StartDir
  if path.has_prefix("/") {
    pos = 1
    comps.push(RootDir)
    ends.push(pos)
  } else if include_cur_dir(path) {
    pos = 1
    comps.push(CurDir)
    ends.push(pos)
  }
  // State::Body
  while pos < len {
    let (size, comp) = match find_separator(path, pos) {
      None => (len - pos, path.unsafe_substring(start=pos, end=len))
      Some(i) => (i - pos + 1, path.unsafe_substring(start=pos, end=i))
    }
    pos += size
    if parse_single_component(comp) is Some(c) {
      comps.push(c)
      ends.push(pos)
    }
  }
  (comps, ends)
}

///|
/// The index of the first `/` at or after `start`.
fn find_separator(path : String, start : Int32) -> Int32? {
  for i in start..<path.length() {
    if path[i] == '/' {
      return Some(i)
    }
  }
  None
}

///|
/// `Path::components`.
pub fn path_components(path : String) -> Array[PathComponent] {
  components_with_ends(path).0
}

///|
/// `PartialEq for Path`: `a == b` when their components are equal.
pub fn path_eq(a : String, b : String) -> Bool {
  a == b || path_components(a) == path_components(b)
}

///|
/// `Path::file_name`: the last component if it is a normal one.
pub fn path_file_name(path : String) -> String? {
  match path_components(path).last() {
    Some(Normal(name)) => Some(name)
    _ => None
  }
}

///|
/// `Path::strip_prefix`: the rest of `path` after the components of `base`,
/// or `None` if `base` is not a component-wise prefix of `path`. As
/// `Components::as_path` does, leading and trailing separators and `.`
/// components of the rest are trimmed; inner ones are kept.
pub fn path_strip_prefix(path : String, base : String) -> String? {
  let (comps, ends) = components_with_ends(path)
  let prefix = path_components(base)
  if prefix.length() > comps.length() {
    return None
  }
  for i, c in prefix {
    if comps[i] != c {
      return None
    }
  }
  let k = prefix.length()
  let mut start = 0
  // `len_before_body` while the front is still before the body.
  let mut floor = 0
  if k > 0 {
    start = ends[k - 1]
    // trim_left
    let len = path.length()
    while start < len {
      let (size, comp) = match find_separator(path, start) {
        None => (len - start, path.unsafe_substring(start~, end=len))
        Some(i) => (i - start + 1, path.unsafe_substring(start~, end=i))
      }
      if parse_single_component(comp) is Some(_) {
        break
      }
      start += size
    }
    floor = start
  } else if path.has_prefix("/") || include_cur_dir(path) {
    floor = 1
  }
  // trim_right
  let mut end = path.length()
  while end > floor {
    let body = path.unsafe_substring(start=floor, end~)
    let (size, comp) = match body.rev_find("/") {
      None => (body.length(), body)
      Some(i) =>
        (
          body.length() - i,
          body.unsafe_substring(start=i + 1, end=body.length()),
        )
    }
    if parse_single_component(comp) is Some(_) {
      break
    }
    end -= size
  }
  Some(path.unsafe_substring(start~, end~))
}

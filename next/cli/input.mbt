// Port of tree-sitter crates/cli/src/input.rs.

///|
pub(all) enum CliInput {
  Paths(Array[String])
  Test(name~ : String, contents~ : Bytes, languages~ : Array[String])
  Stdin(Bytes)
}

///|
pub async fn get_input(
  paths_file : String?,
  paths : Array[String]?,
  test_number : Int32?,
  current_dir : String,
) -> CliInput {
  if paths_file is Some(paths_file) {
    let text = @fs.read_file(paths_file).text() catch {
      e => raise with_context(e, "Failed to read paths file \{paths_file}")
    }
    return Paths(rust_lines(text.trim().to_owned()))
  }
  if test_number is Some(test_number) {
    let test_dir = @support.path_join(current_dir, "test/corpus")
    if !@fs.exists(test_dir) {
      raise anyhow(
        "Test corpus directory not found in current directory, see https://tree-sitter.github.io/tree-sitter/creating-parsers/5-writing-tests",
      )
    }
    let test_entry = @cli_test.parse_tests(test_dir)
    let test_num = Ref(0)
    let target = if test_number > 1 { test_number - 1 } else { 0 }
    match get_test_info(test_entry, target, test_num) {
      Some((name, contents, languages)) =>
        return Test(name~, contents~, languages~)
      None => raise anyhow("Failed to fetch contents of test #\{test_number}")
    }
  }
  if paths is Some(paths) {
    let result : Array[String] = []
    let incorporate_path = (path : String, positive : Bool) => {
      if positive {
        result.push(path)
      } else if result.search(path) is Some(index) {
        result.remove(index) |> ignore
      }
    }
    for path in paths {
      let mut path = path
      let mut positive = true
      if path.has_prefix("!") &&
        @support.strip_path_prefix(path, "!") is Some(_) {
        positive = false
        path = @support.strip_path_prefix(path, "!").unwrap()
      }
      if @fs.exists(path) {
        incorporate_path(path, positive)
      } else {
        for p in glob(path) {
          incorporate_path(p, positive)
        }
      }
    }
    if result.is_empty() {
      raise anyhow(
        "No files were found at or matched by the provided pathname/glob",
      )
    }
    return Paths(result)
  }
  let input = read_all_stdin()
  Stdin(input)
}

///|
async fn read_all_stdin() -> Bytes {
  let buffer = @buffer.Buffer()
  let chunk = FixedArray::make(1024, b'\x00')
  for ;; {
    let n = @stdio.stdin.read(chunk) catch { _ => 0 }
    if n <= 0 {
      break
    }
    for i in 0..<n {
      buffer.write_byte(chunk[i])
    }
  }
  buffer.to_bytes()
}

///|
/// `str::lines`.
pub fn rust_lines(text : String) -> Array[String] {
  let result = []
  let parts = text.split("\n").map(p => p.to_owned()).collect()
  for i, part in parts {
    if i == parts.length() - 1 && part.is_empty() {
      break
    }
    result.push(
      if part.has_suffix("\r") {
        part.unsafe_substring(start=0, end=part.length() - 1)
      } else {
        part
      },
    )
  }
  result
}

///|
pub fn get_test_info(
  test_entry : @cli_test.TestEntry,
  target_test : Int32,
  test_num : Ref[Int32],
) -> (String, Bytes, Array[String])? {
  match test_entry {
    Example(name~, input~, attributes~, ..) => {
      if test_num.val == target_test {
        return Some((name, input, attributes.languages))
      }
      test_num.val += 1
    }
    Group(children~, ..) =>
      for child in children {
        if get_test_info(child, target_test, test_num) is Some(info) {
          return Some(info)
        }
      }
  }
  None
}

///|
/// Writes `contents` to a temporary file and returns the path to that file.
pub async fn get_tmp_source_file(contents : Bytes) -> String {
  let parse_path = @support.path_join(@support.temp_dir(), ".tree-sitter-temp")
  @fs.write_file(parse_path, contents, create_mode=CreateOrTruncate)
  parse_path
}

// A port of the `glob` crate's matching (`*`, `?`, `[...]`, `**`), with
// results in the crate's order (directory entries sorted by name).

///|
fn glob_match_component(pattern : String, name : String) -> Bool {
  let p = pattern.iter().collect()
  let n = name.iter().collect()
  fn go(pi : Int32, ni : Int32) -> Bool {
    if pi == p.length() {
      return ni == n.length()
    }
    match p[pi] {
      '*' => {
        for k in ni..<=n.length() {
          if go(pi + 1, k) {
            return true
          }
        }
        false
      }
      '?' => ni < n.length() && go(pi + 1, ni + 1)
      '[' => {
        guard ni < n.length() else { return false }
        let mut i = pi + 1
        let negate = i < p.length() && (p[i] == '!' || p[i] == '^')
        if negate {
          i += 1
        }
        let mut matched = false
        let mut first = true
        while i < p.length() && (first || p[i] != ']') {
          first = false
          if i + 2 < p.length() && p[i + 1] == '-' && p[i + 2] != ']' {
            if n[ni] >= p[i] && n[ni] <= p[i + 2] {
              matched = true
            }
            i += 3
          } else {
            if n[ni] == p[i] {
              matched = true
            }
            i += 1
          }
        }
        if i >= p.length() {
          // Unterminated class: match `[` literally.
          return n[ni] == '[' && go(pi + 1, ni + 1)
        }
        matched != negate && go(i + 1, ni + 1)
      }
      c => ni < n.length() && n[ni] == c && go(pi + 1, ni + 1)
    }
  }
  go(0, 0)
}

///|
/// Directory entries sorted as `glob` sorts paths (byte order).
fn sorted_names(names : Array[String]) -> Array[String] {
  let names = names.copy()
  names.sort_by(compare_bytes)
  names
}

///|
fn has_glob_chars(s : String) -> Bool {
  s.contains_any(chars="*?[")
}

///|
/// Paths matching a glob pattern.
pub async fn glob(pattern : String) -> Array[String] {
  let absolute = pattern.has_prefix("/")
  let parts = pattern
    .split("/")
    .map(p => p.to_owned())
    .filter(p => !p.is_empty())
    .collect()
  let results = []
  async fn walk(base : String, prefix : String, i : Int32) -> Unit {
    if i == parts.length() {
      results.push(prefix)
      return
    }
    let part = parts[i]
    let join = (name : String) => {
      if prefix.is_empty() {
        name
      } else if prefix == "/" {
        "/" + name
      } else {
        prefix + "/" + name
      }
    }
    let dir = if base.is_empty() { "." } else { base }
    if part == "**" {
      walk(base, prefix, i + 1)
      let entries = sorted_names(@fs.readdir(dir) catch { _ => return })
      for name in entries {
        let full = @support.path_join(dir, name)
        if (@fs.kind(full) catch { _ => @fs.FileKind::Unknown }) is Directory {
          walk(full, join(name), i)
        }
      }
    } else if has_glob_chars(part) {
      let entries = sorted_names(@fs.readdir(dir) catch { _ => return })
      for name in entries {
        if name.has_prefix(".") && !part.has_prefix(".") {
          continue
        }
        if glob_match_component(part, name) {
          let full = @support.path_join(dir, name)
          if i + 1 < parts.length() &&
            !((@fs.kind(full) catch { _ => @fs.FileKind::Unknown }) is Directory) {
            continue
          }
          walk(full, join(name), i + 1)
        }
      }
    } else {
      let full = @support.path_join(dir, part)
      if @fs.exists(full) {
        walk(full, join(part), i + 1)
      }
    }
  }
  walk(if absolute { "/" } else { "" }, if absolute { "/" } else { "" }, 0)
  results
}

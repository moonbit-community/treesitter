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
  test_number : UInt32?,
  current_dir : String,
) -> CliInput {
  if paths_file is Some(paths_file) {
    let text = @support.read_to_string(paths_file) catch {
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
    let test_num : Ref[UInt32] = Ref(0)
    let target = (if test_number > 1U { test_number } else { 1U }) - 1U
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
      } else if result.search_by(p => @support.path_eq(p, path)) is Some(index) {
        result.remove(index) |> ignore
      }
    }
    for path in paths {
      let mut path = path
      let mut positive = true
      // `path.starts_with("!")` and `path.strip_prefix("!")` (component-wise)
      if @support.path_strip_prefix(path, "!") is Some(rest) {
        positive = false
        path = rest
      }
      if path_exists(path) {
        incorporate_path(path, positive)
      } else {
        let paths = @glob.glob(path) catch {
          e => raise with_context(e, "Invalid glob pattern \{path}")
        }
        while paths.next() is Some(path) {
          match path {
            Ok(path) => incorporate_path(path, positive)
            Err(e) => raise e
          }
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
  target_test : UInt32,
  test_num : Ref[UInt32],
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

///|
/// `Path::exists`: `fs::metadata(path).is_ok()`.
async fn path_exists(path : String) -> Bool {
  try @fs.kind(path, follow_symlink=true) catch {
    _ => false
  } noraise {
    _ => true
  }
}

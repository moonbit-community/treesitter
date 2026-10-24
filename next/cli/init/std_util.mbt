// The Rust standard library operations that version.rs and init.rs rely on:
// `fs::read_to_string`, `fs::write`, `fs::create_dir_all`, `Path::exists`
// and `str::lines`, with Rust's `io::Error` display texts.

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
  @fs.mkdir(path, recursive=true, permission=0o777) catch {
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
  let text = if s.has_prefix("\r\n") { s.view(start_offset=1).to_owned() } else { s }
  let lines = text.split("\n").map(v => v.to_owned()).collect()
  let mut spaces : Int? = None
  for i, line in lines {
    if i == 0 {
      continue
    }
    let mut count : Int? = None
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

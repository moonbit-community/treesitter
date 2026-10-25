// `std::fs::read` and `std::fs::read_to_string`: blocking sequential reads
// until end of file. Unlike `@fs.read_file`, they also read the special
// files that `std::fs::read` accepts (`/dev/null`, FIFOs and other character
// devices), whose descriptors the event loop cannot poll.

///|
#borrow(path)
extern "C" fn ts_cli_read_file(path : Bytes) -> Bytes = "ts_cli_read_file"

///|
extern "C" fn ts_cli_read_error() -> Int32 = "ts_cli_read_error"

///|
/// `std::fs::read`.
pub fn read_file(path : String) -> Bytes raise {
  // `CString::new` of the path in `File::open`.
  if path.contains_char('\u{0}') {
    raise Custom(
      kind="InvalidInput",
      error="file name contained an unexpected NUL byte",
    )
  }
  let contents = ts_cli_read_file(c_string(path))
  let errno = ts_cli_read_error()
  if errno != 0 {
    raise @os_error.OSError(errno, context="read")
  }
  contents
}

///|
/// `std::fs::read_to_string`.
pub fn read_to_string(path : String) -> String raise {
  let contents = read_file(path)
  match utf8_strict(contents) {
    Some(s) => s
    None =>
      raise Custom(
        kind="InvalidData",
        error="stream did not contain valid UTF-8",
      )
  }
}

///|
/// A string as a NUL-terminated UTF-8 C string.
fn c_string(s : String) -> Bytes {
  @utf8.encode(s + "\u{0}")
}

// Rust std `BufRead::lines` over `BufReader::new(File::open(path)?)`, as the
// loader uses it to read the first lines of a file: only the bytes up to the
// requested line are interpreted, and each line must be valid UTF-8.

///|
/// The `io::Error` of `BufRead::read_line` for a line that is not UTF-8
/// (`ErrorKind::InvalidData`).
priv suberror StreamNotUtf8

///|
/// Rust's `Display` of the `io::Error` raised while reading lines.
fn line_error_message(e : Error) -> String {
  match e {
    StreamNotUtf8 => "stream did not contain valid UTF-8"
    e => @support.io_error_message(e)
  }
}

///|
/// `BufReader<File>` with the iterator state of `Lines`.
priv struct LineReader {
  file : @fs.File
  /// Bytes read from the file but not consumed yet.
  buf : Array[Byte]
  mut eof : Bool
}

///|
/// `fs::File::open(path)` wrapped in a `BufReader`.
async fn LineReader::open(path : String) -> LineReader {
  { file: @fs.open(path, mode=ReadOnly), buf: [], eof: false }
}

///|
fn LineReader::close(self : LineReader) -> Unit {
  self.file.close()
}

///|
/// `Lines::next`: the next line without its `\n` or `\r\n` terminator,
/// `None` at the end of the file. Raises the read error, or `StreamNotUtf8`
/// if the line is not valid UTF-8 (its bytes are consumed, as `read_line`
/// does).
async fn LineReader::next_line(self : LineReader) -> String? {
  let chunk = FixedArray::make(8192, b'\x00')
  // `read_until(b'\n')`
  let mut end = None
  let mut scanned = 0
  for ;; {
    for i in scanned..<self.buf.length() {
      if self.buf[i] == b'\n' {
        end = Some(i + 1)
        break
      }
    }
    if end is Some(_) || self.eof {
      break
    }
    scanned = self.buf.length()
    let n = self.file.read(chunk)
    if n == 0 {
      self.eof = true
    } else {
      for i in 0..<n {
        self.buf.push(chunk[i])
      }
    }
  }
  let end = end.unwrap_or(self.buf.length())
  if end == 0 {
    return None
  }
  let line = Bytes::from_array(self.buf[:end])
  let rest = self.buf[end:].to_owned()
  self.buf.clear()
  self.buf.append(rest)
  guard @support.utf8_strict(line) is Some(text) else { raise StreamNotUtf8 }
  // `Lines` strips the `\n` and a `\r` before it.
  let text = if text.has_suffix("\n") {
    let text = text.unsafe_substring(start=0, end=text.length() - 1)
    if text.has_suffix("\r") {
      text.unsafe_substring(start=0, end=text.length() - 1)
    } else {
      text
    }
  } else {
    text
  }
  Some(text)
}

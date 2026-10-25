// The parts of Rust's `std::io` (and of the runtime around `main`) whose
// behaviour shows in the CLI's output:
//
// - standard output is a process-wide `LineWriter` (1024-byte buffer) over
//   the unbuffered file descriptor; standard error is unbuffered;
// - `BufWriter`s buffer in front of it and write their contents when they
//   are dropped, ignoring errors (`BufWriter::drop`);
// - `print!`/`eprint!` panic when the write fails (`failed printing to
//   stdout: ...`); a panic prints Rust's panic message, drops the live
//   `BufWriter`s and exits with status 101;
// - `std::process::exit` and returning from `main` flush standard output,
//   ignoring errors;
// - `SIGPIPE` is ignored, so writes to a closed pipe fail with `EPIPE`.
//
// Writes are all-or-error: a write to a blocking descriptor that succeeds
// writes the whole buffer, as it does for the terminals, files and pipes the
// CLI writes to.

///|
#borrow(data)
extern "C" fn ts_cli_write(
  fd : Int32,
  data : Bytes,
  offset : Int32,
  len : Int32,
) -> Int32 = "ts_cli_write"

///|
#borrow(data)
extern "C" fn ts_cli_write_buf(
  fd : Int32,
  data : FixedArray[Byte],
  offset : Int32,
  len : Int32,
) -> Int32 = "ts_cli_write"

///|
extern "C" fn ts_cli_flush() = "ts_cli_flush"

///|
extern "C" fn ts_cli_exit(code : Int32) = "ts_cli_exit"

///|
extern "C" fn ts_cli_errno_kind(err : Int32) -> Bytes = "ts_cli_errno_kind"

///|
extern "C" fn ts_cli_epipe() -> Int32 = "ts_cli_epipe"

///|
extern "C" fn ts_cli_ignore_sigpipe() = "ts_cli_ignore_sigpipe"

///|
extern "C" fn ts_cli_thread_id() -> UInt64 = "ts_cli_thread_id"

///|
/// An `std::io::Error` that is not an OS error: `io::Error::new(kind, msg)`
/// (displayed as `msg`).
pub(all) suberror IoError {
  Custom(kind~ : String, error~ : String)
}

///|
pub impl Show for IoError with fn output(self, logger) {
  let Custom(error~, ..) = self
  logger.write_string(error)
}

///|
/// The `ErrorKind` of an I/O error (`io::Error::kind`).
pub fn io_error_kind(err : Error) -> String {
  match err {
    @os_error.OSError(errno, ..) => @utf8.decode_lossy(ts_cli_errno_kind(errno))
    Custom(kind~, ..) => kind
    _ => "Other"
  }
}

///|
/// Rust's `Debug for std::io::Error`:
/// `Os { code: 32, kind: BrokenPipe, message: "Broken pipe" }` or
/// `Custom { kind: NotFound, error: "..." }`.
pub fn io_error_debug(err : Error) -> String {
  match err {
    @os_error.OSError(errno, ..) => {
      let message = @utf8.decode_lossy(ts_cli_strerror(errno))
      "Os { code: \{errno}, kind: \{io_error_kind(err)}, message: \{rust_debug_string(message)} }"
    }
    Custom(kind~, error~) =>
      "Custom { kind: \{kind}, error: \{rust_debug_string(error)} }"
    _ => "Custom { kind: Other, error: \{rust_debug_string(err.to_string())} }"
  }
}

///|
/// Whether an error is an I/O error of kind `BrokenPipe`.
pub fn is_broken_pipe(err : Error) -> Bool {
  match err {
    @os_error.OSError(errno, ..) => errno == ts_cli_epipe()
    Custom(kind="BrokenPipe", ..) => true
    _ => false
  }
}

///|
/// `Debug for str`.
fn rust_debug_string(s : String) -> String {
  let sb = StringBuilder()
  sb.write_char('"')
  for c in s {
    match c {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      '\u{0}' => sb.write_string("\\0")
      c if c.to_int() < 0x20 || c.to_int() == 0x7f => {
        let hex = c.to_int().to_string(radix=16)
        sb.write_string("\\u{\{hex}}")
      }
      c => sb.write_char(c)
    }
  }
  sb.write_char('"')
  sb.to_string()
}

///|
/// A failed write of the raw descriptor `fd`.
fn write_error(code : Int32) -> Error {
  if code < 0 {
    Custom(kind="WriteZero", error="failed to write whole buffer")
  } else {
    @os_error.OSError(code, context="write")
  }
}

///|
/// `write_all` on the unbuffered descriptor (`StdoutRaw`/`StderrRaw`).
fn raw_write_all(fd : Int32, data : BytesView) -> Unit raise {
  if data.is_empty() {
    return
  }
  let code = ts_cli_write(fd, data.data(), data.start_offset(), data.length())
  if code != 0 {
    raise write_error(code)
  }
}

///|
/// The writer a `BufWriter` writes its buffer to.
priv enum Inner {
  /// The unbuffered standard output descriptor.
  RawStdout
  /// The process-wide `LineWriter` of standard output.
  LineStdout
}

///|
/// `std::io::BufWriter`.
pub struct BufWriter {
  priv buf : FixedArray[Byte]
  priv mut len : Int32
  priv inner : Inner
  priv mut live : Bool
}

///|
fn BufWriter::spare_capacity(self : BufWriter) -> Int32 {
  self.buf.length() - self.len
}

///|
/// `BufWriter::flush_buf`: write the buffered data to the inner writer. On
/// error the data stays buffered.
fn BufWriter::flush_buf(self : BufWriter) -> Unit raise {
  if self.len == 0 {
    return
  }
  let len = self.len
  match self.inner {
    RawStdout => {
      let code = ts_cli_write_buf(1, self.buf, 0, len)
      if code != 0 {
        raise write_error(code)
      }
    }
    LineStdout => {
      // `BufWriter::flush_buf` writes with `write`, which `LineWriterShim`
      // may only partly accept.
      let data = Bytes::from_array(self.buf.exact_view(end=len))
      let mut written = 0
      // `BufGuard`: on error, only the data that was not written stays
      // buffered.
      errdefer {
        self.buf.blit_from_bytesview(0, data[written:])
        self.len = len - written
      }
      while written < len {
        let n = line_writer_write(data[written:])
        if n == 0 {
          raise Custom(
            kind="WriteZero",
            error="failed to write the buffered data",
          )
        }
        written += n
      }
    }
  }
  self.len = 0
}

///|
/// Write `data` to the inner writer (`get_mut().write_all`).
fn BufWriter::inner_write_all(self : BufWriter, data : BytesView) -> Unit raise {
  match self.inner {
    RawStdout => raw_write_all(1, data)
    LineStdout => line_writer_write_all(data)
  }
}

///|
/// `BufWriter::write_to_buf`: buffer as much of `data` as fits.
fn BufWriter::write_to_buf(self : BufWriter, data : BytesView) -> Int32 {
  let available = @cmp.minimum(self.spare_capacity(), data.length())
  self.buf.blit_from_bytesview(self.len, data[:available])
  self.len += available
  available
}

///|
/// `Write::write` of a `BufWriter`.
fn BufWriter::write(self : BufWriter, data : BytesView) -> Int32 raise {
  if data.length() < self.spare_capacity() {
    self.buf.blit_from_bytesview(self.len, data)
    self.len += data.length()
    return data.length()
  }
  // write_cold
  if data.length() > self.spare_capacity() {
    self.flush_buf()
  }
  if data.length() >= self.buf.length() {
    match self.inner {
      RawStdout => {
        raw_write_all(1, data)
        data.length()
      }
      LineStdout => line_writer_write(data)
    }
  } else {
    self.buf.blit_from_bytesview(self.len, data)
    self.len += data.length()
    data.length()
  }
}

///|
/// `Write::write_all` of a `BufWriter`.
pub fn BufWriter::write_bytes(self : BufWriter, data : BytesView) -> Unit raise {
  if data.length() < self.spare_capacity() {
    self.buf.blit_from_bytesview(self.len, data)
    self.len += data.length()
    return
  }
  // write_all_cold
  if data.length() > self.spare_capacity() {
    self.flush_buf()
  }
  if data.length() >= self.buf.length() {
    self.inner_write_all(data)
  } else {
    self.buf.blit_from_bytesview(self.len, data)
    self.len += data.length()
  }
}

///|
/// `write!(writer, "{s}")`: write a string as UTF-8.
pub fn BufWriter::write_string(self : BufWriter, s : StringView) -> Unit raise {
  if s.is_empty() {
    return
  }
  self.write_bytes(@utf8.encode(s))
}

///|
/// `Write::flush`: write the buffer and flush the inner writer.
pub fn BufWriter::flush(self : BufWriter) -> Unit raise {
  self.flush_buf()
  match self.inner {
    RawStdout => ()
    LineStdout => line_writer_flush()
  }
}

///|
/// The `BufWriter`s that have not been dropped yet, innermost last: a panic
/// drops them while unwinding.
let live_writers : Array[BufWriter] = []

///|
/// `io::BufWriter::with_capacity(capacity, io::stdout().lock())`. Call
/// `drop` when the writer goes out of scope.
pub fn BufWriter::stdout(capacity~ : Int32) -> BufWriter {
  let writer = {
    buf: FixedArray::make(capacity, b'\x00'),
    len: 0,
    inner: LineStdout,
    live: true,
  }
  live_writers.push(writer)
  writer
}

///|
/// `io::stdout().lock()`: writes go straight to the process-wide
/// `LineWriter` (a `BufWriter` without a buffer behaves the same).
pub fn stdout_lock() -> BufWriter {
  { buf: FixedArray::make(0, b'\x00'), len: 0, inner: LineStdout, live: false, }
}

///|
/// `Drop for BufWriter`: write the buffered data, ignoring errors.
pub fn BufWriter::drop(self : BufWriter) -> Unit {
  if !self.live {
    return
  }
  self.live = false
  self.flush_buf() catch {
    _ => ()
  }
  match live_writers.search_by(w => physical_equal(w, self)) {
    Some(i) => ignore(live_writers.remove(i))
    None => ()
  }
}

// The process-wide standard output `LineWriter` (`Stdout`), a `BufWriter`
// of 1024 bytes over the raw descriptor wrapped in `LineWriterShim`.

///|
let stdout_buffer : BufWriter = {
  buf: FixedArray::make(1024, b'\x00'),
  len: 0,
  inner: RawStdout,
  live: false,
}

///|
/// `LineWriterShim::flush_if_completed_line`.
fn line_writer_flush_if_completed_line() -> Unit raise {
  let b = stdout_buffer
  if b.len > 0 && b.buf[b.len - 1] == b'\n' {
    b.flush_buf()
  }
}

///|
fn last_newline(data : BytesView) -> Int32? {
  for i = data.length() - 1; i >= 0; i = i - 1 {
    if data[i] == b'\n' {
      return Some(i)
    }
  }
  None
}

///|
/// `LineWriterShim::write`.
fn line_writer_write(data : BytesView) -> Int32 raise {
  let buffer = stdout_buffer
  let newline_idx = match last_newline(data) {
    None => {
      line_writer_flush_if_completed_line()
      return buffer.write(data)
    }
    Some(i) => i + 1
  }
  buffer.flush_buf()
  let lines = data[:newline_idx]
  raw_write_all(1, lines)
  let flushed = lines.length()
  let tail = data[flushed:]
  let buffered = buffer.write_to_buf(tail)
  flushed + buffered
}

///|
/// `LineWriterShim::write_all`.
fn line_writer_write_all(data : BytesView) -> Unit raise {
  let buffer = stdout_buffer
  match last_newline(data) {
    None => {
      line_writer_flush_if_completed_line()
      buffer.write_bytes(data)
    }
    Some(newline_idx) => {
      let lines = data[:newline_idx + 1]
      let tail = data[newline_idx + 1:]
      if buffer.len == 0 {
        raw_write_all(1, lines)
      } else {
        buffer.write_bytes(lines)
        buffer.flush_buf()
      }
      buffer.write_bytes(tail)
    }
  }
}

///|
/// `LineWriterShim::flush`.
fn line_writer_flush() -> Unit raise {
  stdout_buffer.flush_buf()
}

///|
/// `io::stdout().write_all(data)`.
pub fn stdout_write_all(data : BytesView) -> Unit raise {
  line_writer_write_all(data)
}

///|
/// `write!(io::stdout(), "{s}")`.
pub fn stdout_write_string(s : StringView) -> Unit raise {
  if s.is_empty() {
    return
  }
  line_writer_write_all(@utf8.encode(s))
}

///|
/// `io::stdout().flush()`.
pub fn stdout_flush() -> Unit raise {
  line_writer_flush()
}

///|
/// `print!`: write a string to standard output, panicking on failure.
pub fn print_out(s : String) -> Unit {
  stdout_write_string(s) catch {
    e =>
      rust_panic(
        "failed printing to stdout: \{io_error_message(e)}",
        std_print_location,
      )
  }
}

///|
/// `eprint!`: write a string to standard error, panicking on failure.
pub fn print_err(s : String) -> Unit {
  if s.is_empty() {
    return
  }
  raw_write_all(2, @utf8.encode(s)) catch {
    e =>
      rust_panic(
        "failed printing to stderr: \{io_error_message(e)}",
        std_print_location,
      )
  }
}

///|
/// Write raw bytes to standard error (`io::stderr().write_all`), ignoring
/// errors.
pub fn write_stderr_bytes(data : BytesView) -> Unit {
  raw_write_all(2, data) catch {
    _ => ()
  }
}

///|
/// Flush standard output (and C stdio), ignoring errors: before handing the
/// terminal to a child process or a prompt.
pub fn flush() -> Unit {
  line_writer_flush() catch {
    _ => ()
  }
  ts_cli_flush()
}

///|
/// `rt::init`: what the Rust runtime does before `main` (ignore `SIGPIPE`).
pub fn runtime_init() -> Unit {
  ts_cli_ignore_sigpipe()
}

///|
/// `std::process::exit` (and the end of `main`): flush standard output,
/// ignoring errors, and exit.
pub fn exit(code : Int32) -> Unit {
  flush()
  ts_cli_exit(code)
}

///|
/// The location of the `panic!` in `std::io::stdio::print_to` of the Rust
/// toolchain that the pinned CLI is built with (1.97.1).
pub let std_print_location : String = "/rustc/8bab26f4f68e0e26f0bb7960be334d5b520ea452/library/std/src/io/stdio.rs:1166:9"

///|
/// The location of a panic in a crates.io dependency, as a binary built by
/// cargo on this machine reports it:
/// `$CARGO_HOME/registry/src/index.crates.io-1949cf8c6b5b557f/<crate>/<file>`.
pub fn crate_location(crate_and_file : String) -> String {
  let cargo_home = match @env.get_env_var("CARGO_HOME") {
    Some(dir) if !dir.is_empty() => dir
    _ => path_join(home_dir().unwrap_or(""), ".cargo")
  }
  path_join(
    cargo_home,
    "registry/src/index.crates.io-1949cf8c6b5b557f/" + crate_and_file,
  )
}

///|
/// A Rust panic in the main thread: print the panic message (with the
/// default hook's format), drop the live `BufWriter`s as unwinding does and
/// exit with status 101.
pub fn[T] rust_panic(message : String, location : String) -> T {
  let backtrace_note = match @env.get_env_var("RUST_BACKTRACE") {
    None | Some("0") =>
      "note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace\n"
    Some(_) => ""
  }
  write_stderr_bytes(
    @utf8.encode(
      "\nthread 'main' (\{ts_cli_thread_id()}) panicked at \{location}:\n\{message}\n\{backtrace_note}",
    ),
  )
  while live_writers.pop() is Some(writer) {
    writer.live = true
    writer.drop()
  }
  exit(101)
  panic()
}

///|
#borrow(data)
extern "C" fn ts_cli_write_fd_blocking(
  fd : Int32,
  data : Bytes,
  offset : Int32,
  len : Int32,
) = "ts_cli_write_fd_blocking"

///|
/// Write all of `data` to the file descriptor `fd` (which may be
/// non-blocking), waiting until it is writable and ignoring errors: the C
/// library's writes of dot graphs to the file `ts_parser_print_dot_graphs`
/// was given.
pub fn write_fd_blocking(fd : Int32, data : BytesView) -> Unit {
  ts_cli_write_fd_blocking(fd, data.data(), data.start_offset(), data.length())
}

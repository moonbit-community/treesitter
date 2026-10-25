// Names of next/cli/support used throughout the CLI.

///|
using @support {
  paint,
  color_enabled,
  log_info,
  log_warn,
  log_error,
  type Color,
  type Style,
  black,
  red,
  green,
  yellow,
  blue,
  magenta,
  cyan,
  white,
  bright_red,
  bright_green,
  bright_yellow,
  bright_blue,
  bright_magenta,
  bright_cyan,
  bright_white,
}

///|
fn rust_debug_str(s : String) -> String {
  @loader.rust_debug_str(s)
}

///|
fn split_inclusive_newline(s : String) -> Array[String] {
  let result = []
  let mut start = 0
  for i in 0..<s.length() {
    if s[i] == '\n' {
      result.push(s.unsafe_substring(start~, end=i + 1))
      start = i + 1
    }
  }
  if start < s.length() {
    result.push(s.unsafe_substring(start~, end=s.length()))
  }
  result
}

///|
fn push_bytes(output : Array[Byte], bytes : Bytes) -> Unit {
  for b in bytes {
    output.push(b)
  }
}

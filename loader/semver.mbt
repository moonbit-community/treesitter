// Port of the subset of the `semver` crate (1.0.28) that the loader and the
// CLI use: `Version::parse` (`src/parse.rs`), `Display for Version` and the
// error messages of `src/error.rs`.

///|
pub(all) struct SemverVersion {
  major : UInt64
  minor : UInt64
  patch : UInt64
  pre : String
  build : String
} derive(Eq, Debug)

///|
pub fn SemverVersion::new(
  major : UInt64,
  minor : UInt64,
  patch : UInt64,
) -> SemverVersion {
  { major, minor, patch, pre: "", build: "" }
}

///|
pub impl Show for SemverVersion with fn output(self, logger) {
  logger.write_string("\{self.major}.\{self.minor}.\{self.patch}")
  if !self.pre.is_empty() {
    logger.write_string("-\{self.pre}")
  }
  if !self.build.is_empty() {
    logger.write_string("+\{self.build}")
  }
}

///|
/// `semver::Error`, carrying its `Display` text.
pub(all) suberror SemverError {
  SemverError(String)
}

///|
pub impl Show for SemverError with fn output(self, logger) {
  let SemverError(message) = self
  logger.write_string(message)
}

///|
/// `error::Position`.
priv enum Position {
  Major
  Minor
  Patch
  Pre
  Build
} derive(Eq)

///|
impl Show for Position with fn output(self, formatter) {
  formatter.write_string(
    match self {
      Major => "major version number"
      Minor => "minor version number"
      Patch => "patch version number"
      Pre => "pre-release identifier"
      Build => "build metadata"
    },
  )
}

///|
/// `error::ErrorKind` (the variants `Version::parse` produces).
priv enum ErrorKind {
  Empty
  UnexpectedEnd(Position)
  UnexpectedChar(Position, Char)
  UnexpectedCharAfter(Position, Char)
  LeadingZero(Position)
  Overflow(Position)
  EmptySegment(Position)
}

///|
/// `QuotedChar`: `{:?}` of the char, except that `'\0'` is printed the same
/// way on every Rust version.
fn quoted_char(c : Char) -> String {
  if c == '\u{0}' {
    "'\\0'"
  } else {
    @support.rust_debug_char(c)
  }
}

///|
/// `Display for Error`.
impl Show for ErrorKind with fn output(self, formatter) {
  match self {
    Empty => formatter.write_string("empty string, expected a semver version")
    UnexpectedEnd(pos) =>
      formatter.write_string("unexpected end of input while parsing \{pos}")
    UnexpectedChar(pos, ch) =>
      formatter.write_string(
        "unexpected character \{quoted_char(ch)} while parsing \{pos}",
      )
    UnexpectedCharAfter(pos, ch) =>
      formatter.write_string(
        "unexpected character \{quoted_char(ch)} after \{pos}",
      )
    LeadingZero(pos) => formatter.write_string("invalid leading zero in \{pos}")
    Overflow(pos) => formatter.write_string("value of \{pos} exceeds u64::MAX")
    EmptySegment(pos) =>
      formatter.write_string("empty identifier segment in \{pos}")
  }
}

///|
/// `Error::new`.
fn semver_error(kind : ErrorKind) -> SemverError {
  SemverError("\{kind}")
}

///|
/// `FromStr for Version`. The text is a char array and the remaining input
/// is the suffix starting at an index; the parser only ever consumes ASCII
/// characters, so char and byte lengths agree.
pub fn SemverVersion::parse(text : String) -> SemverVersion raise SemverError {
  let input : Array[Char] = text.iter().collect()
  if input.is_empty() {
    raise semver_error(Empty)
  }
  let mut pos = Major
  let (major, text) = numeric_identifier(input, 0, pos)
  let text = dot(input, text, pos)
  pos = Minor
  let (minor, text) = numeric_identifier(input, text, pos)
  let text = dot(input, text, pos)
  pos = Patch
  let (patch, text) = numeric_identifier(input, text, pos)
  if text == input.length() {
    return SemverVersion::new(major, minor, patch)
  }
  let (pre, text) = if input[text] == '-' {
    pos = Pre
    let (pre, text) = prerelease_identifier(input, text + 1)
    if pre.is_empty() {
      raise semver_error(EmptySegment(pos))
    }
    (pre, text)
  } else {
    ("", text)
  }
  let (build, text) = if input.get(text) is Some('+') {
    pos = Build
    let (build, text) = build_identifier(input, text + 1)
    if build.is_empty() {
      raise semver_error(EmptySegment(pos))
    }
    (build, text)
  } else {
    ("", text)
  }
  if input.get(text) is Some(unexpected) {
    raise semver_error(UnexpectedCharAfter(pos, unexpected))
  }
  { major, minor, patch, pre, build }
}

///|
fn numeric_identifier(
  input : Array[Char],
  start : Int,
  pos : Position,
) -> (UInt64, Int) raise SemverError {
  let mut len = 0
  let mut value = 0UL
  while input.get(start + len) is Some(digit) {
    if digit < '0' || digit > '9' {
      break
    }
    if value == 0 && len > 0 {
      raise semver_error(LeadingZero(pos))
    }
    // `value.checked_mul(10).and_then(|value| value.checked_add(digit))`
    let digit = (digit.to_int() - '0'.to_int()).to_uint64()
    if value > (18446744073709551615UL - digit) / 10UL {
      raise semver_error(Overflow(pos))
    }
    value = value * 10UL + digit
    len += 1
  }
  if len > 0 {
    (value, start + len)
  } else if input.get(start + len) is Some(unexpected) {
    raise semver_error(UnexpectedChar(pos, unexpected))
  } else {
    raise semver_error(UnexpectedEnd(pos))
  }
}

///|
fn dot(input : Array[Char], start : Int, pos : Position) -> Int raise SemverError {
  match input.get(start) {
    Some('.') => start + 1
    Some(unexpected) => raise semver_error(UnexpectedCharAfter(pos, unexpected))
    None => raise semver_error(UnexpectedEnd(pos))
  }
}

///|
fn prerelease_identifier(
  input : Array[Char],
  start : Int,
) -> (String, Int) raise SemverError {
  identifier(input, start, Pre)
}

///|
fn build_identifier(
  input : Array[Char],
  start : Int,
) -> (String, Int) raise SemverError {
  identifier(input, start, Build)
}

///|
fn identifier(
  input : Array[Char],
  start : Int,
  pos : Position,
) -> (String, Int) raise SemverError {
  let mut accumulated_len = 0
  let mut segment_len = 0
  let mut segment_has_nondigit = false
  for ;; {
    match input.get(start + accumulated_len + segment_len) {
      Some('A'..='Z' | 'a'..='z' | '-') => {
        segment_len += 1
        segment_has_nondigit = true
      }
      Some('0'..='9') => segment_len += 1
      boundary => {
        if segment_len == 0 {
          if accumulated_len == 0 && boundary != Some('.') {
            return ("", start)
          } else {
            raise semver_error(EmptySegment(pos))
          }
        }
        if pos == Pre &&
          segment_len > 1 &&
          !segment_has_nondigit &&
          input[start + accumulated_len] == '0' {
          raise semver_error(LeadingZero(pos))
        }
        accumulated_len += segment_len
        if boundary == Some('.') {
          accumulated_len += 1
          segment_len = 0
          segment_has_nondigit = false
        } else {
          let end = start + accumulated_len
          return (String::from_array(input[start:end]), end)
        }
      }
    }
  }
}

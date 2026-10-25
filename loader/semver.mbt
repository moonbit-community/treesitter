// The subset of the `semver` crate (1.0) that the loader and the CLI use:
// `Version::parse`, `Display` and its error messages.

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
  { major, minor, patch, pre: "", build: "", }
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
/// `semver::Error`.
pub(all) suberror SemverError {
  SemverError(String)
}

///|
pub impl Show for SemverError with fn output(self, logger) {
  let SemverError(message) = self
  logger.write_string(message)
}

///|
fn char_desc(c : Char) -> String {
  "'\{c}'"
}

///|
fn parse_number(
  chars : Array[Char],
  pos : Ref[Int32],
  what : String,
) -> UInt64 raise SemverError {
  let start = pos.val
  if start >= chars.length() {
    raise SemverError("unexpected end of input while parsing \{what}")
  }
  if !(chars[start] >= '0' && chars[start] <= '9') {
    raise SemverError(
      "unexpected character \{char_desc(chars[start])} while parsing \{what}",
    )
  }
  let mut value : UInt64 = 0
  while pos.val < chars.length() &&
        chars[pos.val] >= '0' &&
        chars[pos.val] <= '9' {
    if pos.val > start && chars[start] == '0' {
      raise SemverError("invalid leading zero in \{what}")
    }
    let digit = (chars[pos.val].to_int() - '0'.to_int()).to_uint64()
    if value > (18446744073709551615UL - digit) / 10UL {
      raise SemverError("value of \{what} exceeds u64::MAX")
    }
    value = value * 10UL + digit
    pos.val += 1
  }
  value
}

///|
fn parse_identifier(
  chars : Array[Char],
  pos : Ref[Int32],
  what : String,
) -> String raise SemverError {
  let start = pos.val
  while pos.val < chars.length() {
    let c = chars[pos.val]
    if c.is_ascii_alphabetic() || (c >= '0' && c <= '9') || c == '-' || c == '.' {
      pos.val += 1
    } else {
      break
    }
  }
  let ident = String::from_array(chars[start:pos.val])
  if ident.is_empty() {
    if pos.val < chars.length() {
      raise SemverError(
        "unexpected character \{char_desc(chars[pos.val])} while parsing \{what}",
      )
    }
    raise SemverError("empty identifier segment in \{what}")
  }
  for segment in ident.split(".") {
    if segment.is_empty() {
      raise SemverError("empty identifier segment in \{what}")
    }
  }
  ident
}

///|
/// `Version::parse`.
pub fn SemverVersion::parse(text : String) -> SemverVersion raise SemverError {
  let chars = text.iter().collect()
  if chars.is_empty() {
    raise SemverError("empty string, expected a semver version")
  }
  let pos = Ref(0)
  let major = parse_number(chars, pos, "major version number")
  if pos.val >= chars.length() {
    raise SemverError(
      "unexpected end of input while parsing major version number",
    )
  }
  if chars[pos.val] != '.' {
    raise SemverError(
      "unexpected character \{char_desc(chars[pos.val])} after major version number",
    )
  }
  pos.val += 1
  let minor = parse_number(chars, pos, "minor version number")
  if pos.val >= chars.length() {
    raise SemverError(
      "unexpected end of input while parsing minor version number",
    )
  }
  if chars[pos.val] != '.' {
    raise SemverError(
      "unexpected character \{char_desc(chars[pos.val])} after minor version number",
    )
  }
  pos.val += 1
  let patch = parse_number(chars, pos, "patch version number")
  let mut pre = ""
  let mut build = ""
  if pos.val < chars.length() && chars[pos.val] == '-' {
    pos.val += 1
    pre = parse_identifier(chars, pos, "pre-release identifier")
  }
  if pos.val < chars.length() && chars[pos.val] == '+' {
    pos.val += 1
    build = parse_identifier(chars, pos, "build metadata")
  }
  if pos.val < chars.length() {
    let after = if !build.is_empty() {
      "build metadata"
    } else if !pre.is_empty() {
      "pre-release identifier"
    } else {
      "patch version number"
    }
    raise SemverError(
      "unexpected character \{char_desc(chars[pos.val])} after \{after}",
    )
  }
  { major, minor, patch, pre, build, }
}

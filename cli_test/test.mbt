// Port of the corpus-file parsing and formatting parts of tree-sitter
// crates/cli/src/test.rs: `TestEntry`, `parse_tests`, the expected-output
// normalization, `render_test_output` and the diff display. The `test`
// command runner itself (`run_tests_at_path`, `TestSummary`, ...) is not
// ported yet. Output is never colored (`color_enabled()` is false).

///|
/// Check if a line consists of 3+ repetitions of `ch` followed by an optional
/// suffix.
///
/// Returns `Some((delim_len, suffix))` if so, where `suffix` is the part after
/// the repeated characters (empty string if no suffix). Returns `None`
/// otherwise.
fn parse_delimiter_line(line : StringView, c : Char) -> (Int32, StringView)? {
  let mut delim_len = 0
  while delim_len < line.length() && line[delim_len].to_int() == c.to_int() {
    delim_len += 1
  }
  if delim_len < 3 {
    return None
  }
  let suffix = line[delim_len:].trim_end(chars="\r\n")
  Some((delim_len, suffix))
}

///|
/// Normalize expected sexp output: remove comment lines (lines starting with
/// `;`), collapse whitespace, and remove spaces before closing parens.
fn normalize_sexp_output(raw : StringView) -> (String, Bool) {
  let result : Array[Char] = []
  let mut prev_was_space = false
  for line in rust_lines(raw) {
    // Skip comment lines: lines whose first non-whitespace character is `;`
    if trim_ws_start(line).has_prefix(";") {
      continue
    }
    for ch in line {
      if ch.is_whitespace() {
        if !prev_was_space && !result.is_empty() {
          result.push(' ')
          prev_was_space = true
        }
      } else {
        if ch == ')' && prev_was_space {
          ignore(result.pop()) // remove trailing space before `)`
        }
        result.push(ch)
        prev_was_space = false
      }
    }
    // Line boundary counts as whitespace
    if !result.is_empty() && !prev_was_space {
      result.push(' ')
      prev_was_space = true
    }
  }

  // No leading whitespace
  let result = trim_ws_end(String::from_array(result)).to_owned()
  let has_fields = result.contains(": (")
  (result, has_fields)
}

///|
pub(all) enum TestEntry {
  Group(name~ : String, children~ : Array[TestEntry], file_path~ : String?)
  Example(
    name~ : String,
    input~ : Bytes,
    output~ : String,
    header_delim_len~ : Int32,
    divider_delim_len~ : Int32,
    has_fields~ : Bool,
    attributes_str~ : String,
    attributes~ : TestAttributes,
    file_name~ : String?
  )
} derive(Eq, Debug)

///|
pub(all) struct TestAttributes {
  platform : Bool
  fail_fast : Bool
  expectation : TestExpectation
  cst : Bool
  languages : Array[String]
} derive(Eq, Debug)

///|
pub(all) enum TestExpectation {
  Pass
  Error
  Skip
} derive(Eq, Debug)

///|
#warnings("-unused_value")
fn TestAttributes::skip(self : TestAttributes) -> Bool {
  self.expectation == Skip
}

///|
#warnings("-unused_value")
fn TestAttributes::error(self : TestAttributes) -> Bool {
  self.expectation == Error
}

///|
pub fn TestEntry::default() -> TestEntry {
  Group(name="", children=[], file_path=None)
}

///|
pub fn TestAttributes::default() -> TestAttributes {
  {
    platform: true,
    fail_fast: false,
    expectation: Pass,
    cst: false,
    languages: [""],
  }
}

///|
pub struct DiffKey {}

///|
pub impl Show for DiffKey with fn output(_self, logger) {
  logger.write_string("\ncorrect / expected / unexpected")
}

///|
/// Writes [`DiffKey`] to stdout
pub fn DiffKey::print() -> Unit {
  @support.print_out(DiffKey::{ }.to_string() + "\n")
}

///|
pub struct TestDiff {
  actual : String
  expected : String
  /// Force `+`/`-` markers even when color is enabled. Markers are always
  /// shown when color is disabled, regardless of this flag.
  use_markers : Bool
}

///|
pub fn TestDiff::new(actual : String, expected : String) -> TestDiff {
  { actual, expected, use_markers: false, }
}

///|
pub fn TestDiff::with_markers(self : TestDiff, use_markers : Bool) -> TestDiff {
  { ..self, use_markers, }
}

///|
pub impl Show for TestDiff with fn output(self, f) {
  // Color is never enabled, so the markers are always shown.
  for change in diff_lines(self.actual, self.expected) {
    let (tag, line) = change
    let symbol = match tag {
      ChangeTag::Equal => ' '
      ChangeTag::Insert => '+'
      ChangeTag::Delete => '-'
    }
    f.write_char(symbol)
    f.write_view(line)
    // `similar::Change`'s `Display` adds the newline a last line lacks.
    if !line.has_suffix("\n") {
      f.write_char('\n')
    }
  }
}

///|
priv struct TestCorrection {
  name : String
  input : String
  output : String
  attributes_str : String
  header_delim_len : Int32
  divider_delim_len : Int32
}

///|
#warnings("-unused_value")
fn TestCorrection::new(
  name : String,
  input : String,
  output : String,
  attributes_str : String,
  header_delim_len : Int32,
  divider_delim_len : Int32,
) -> TestCorrection {
  { name, input, output, attributes_str, header_delim_len, divider_delim_len, }
}

///|
/// Convenience wrapper to render a CST for a test entry.
fn render_test_cst(input : Bytes, tree : @treesitter.Tree) -> String {
  let rendered_cst = StringBuilder()
  let cursor = tree.walk()
  render_cst(input, tree, cursor, rendered_cst)
  trim_ws(rendered_cst.to_string()).to_owned()
}

///|
/// Render a parsed tree in the output format expected by a corpus test.
pub fn render_test_output(
  input : Bytes,
  tree : @treesitter.Tree,
  cst : Bool,
  include_fields : Bool,
) -> String {
  if cst {
    render_test_cst(input, tree)
  } else {
    let out = tree.root_node().to_sexp()
    if include_fields {
      out
    } else {
      strip_sexp_fields(out)
    }
  }
}

///|
#warnings("-unused_value")
fn write_tests_to_buffer(
  buffer : StringBuilder,
  corrected_entries : Array[TestCorrection],
) -> Unit {
  for i, entry in corrected_entries {
    let {
      name,
      input,
      output,
      attributes_str,
      header_delim_len,
      divider_delim_len,
    } = entry
    if i > 0 {
      buffer.write_char('\n')
    }
    let header = "=".repeat(header_delim_len)
    let attributes = if attributes_str.is_empty() {
      attributes_str
    } else {
      "\{attributes_str}\n"
    }
    buffer.write_string(
      "\{header}\n\{name}\n\{attributes}\{header}\n\{input}\n\{"-".repeat(divider_delim_len)}\n\n\{trim_ws(output)}\n",
    )
  }
}

///|
/// Parse the corpus file, or the directory of corpus files, at `path`.
pub async fn parse_tests(path : String) -> TestEntry {
  let name = file_stem(path)
  if is_dir(path) {
    let children = []
    for entry in @fs.readdir(path) {
      let hidden = entry.has_prefix(".")
      if !hidden {
        children.push(entry)
      }
    }
    children.sort_by(compare_bytes)
    let children = [ for child in children => parse_tests("\{path}/\{child}") ]
    Group(name~, children~, file_path=None)
  } else {
    let content = @support.read_to_string(path)
    parse_test_content(name, content, Some(path))
  }
}

///|
/// Replace ` word: (` with ` (` throughout the string.
/// Intended to operate on `to_sexp()` output where elements are separated by
/// single spaces.
pub fn strip_sexp_fields(sexp : String) -> String {
  let result = StringBuilder()
  let mut remaining = sexp[:]
  while remaining.find(": (") is Some(pos) {
    // Walk backwards from the `:` to find the field name and preceding space.
    if remaining[:pos].rev_find(" ") is Some(space_pos) {
      let word = remaining[space_pos + 1:pos]
      if !word.is_empty() &&
        word
        .iter()
        .all(b => b.is_ascii_alphabetic() || b.is_ascii_digit() || b == '_') {
        // Emit everything up to and including the space, then `(`
        result.write_view(remaining[:space_pos + 1])
        result.write_char('(')
        remaining = remaining[pos + 3:]
        continue
      }
    }
    // Not a field pattern — emit through `: (` and keep going
    result.write_view(remaining[:pos + 3])
    remaining = remaining[pos + 3:]
  }
  result.write_view(remaining)
  result.to_string()
}

///|
/// Remove `[row, col]` point annotations from sexp strings, including
/// surrounding whitespace.
/// Matches the pattern: `\s* [ \s* digits \s* , \s* digits \s* ] \s*`
pub fn strip_points(sexp : String) -> String {
  let result = StringBuilder()
  let mut skip_until = 0
  for i = 0; i < sexp.length(); i = i + 1 {
    if i < skip_until {
      continue
    }
    if try_match_point(sexp[i:]) is Some(point_len) {
      skip_until = i + point_len
    } else {
      result.write_char(Int32::unsafe_to_char(sexp[i].to_int()))
    }
  }
  result.to_string()
}

///|
/// Try to match `\s*[\s*\d+\s*,\s*\d+\s*]\s*` from the start of `text`.
/// Returns the length of the match, or `None` if no match.
fn try_match_point(text : StringView) -> Int32? {
  let mut j = count_whitespace(text)
  guard expect_char(text[j:], '[') is Some(n) else { return None }
  j += n
  j += count_whitespace(text[j:])
  guard expect_digits(text[j:]) is Some(n) else { return None }
  j += n
  j += count_whitespace(text[j:])
  guard expect_char(text[j:], ',') is Some(n) else { return None }
  j += n
  j += count_whitespace(text[j:])
  guard expect_digits(text[j:]) is Some(n) else { return None }
  j += n
  j += count_whitespace(text[j:])
  guard expect_char(text[j:], ']') is Some(n) else { return None }
  j += n
  Some(j + count_whitespace(text[j:]))
}

///|
fn count_whitespace(text : StringView) -> Int32 {
  let mut i = 0
  while i < text.length() && is_ws_unit(text[i]) {
    i += 1
  }
  i
}

///|
fn expect_char(text : StringView, expected : Char) -> Int32? {
  if text.length() > 0 && text[0].to_int() == expected.to_int() {
    Some(1)
  } else {
    None
  }
}

///|
fn expect_digits(text : StringView) -> Int32? {
  let mut i = 0
  while i < text.length() && text[i] >= '0' && text[i] <= '9' {
    i += 1
  }
  if i == 0 {
    None
  } else {
    Some(i)
  }
}

///|
/// Check if a delimiter line's suffix matches the file's first suffix.
fn suffix_matches(first_suffix : String?, suffix : StringView) -> Bool {
  match (first_suffix, suffix.is_empty()) {
    (None, true) => true
    (Some(fs), false) => fs == suffix.to_owned()
    _ => false
  }
}

///|
/// Parsed header info stored between iterations while we wait to discover the
/// body boundaries.
priv struct PendingTest {
  name : String
  attributes_str : String
  header_delim_len : Int32
  attributes : TestAttributes
  body_start_line : Int32
}

///|
/// If `token` matches the shape of one of the known test attributes,
/// then return the prefix
fn known_attribute(token : StringView) -> StringView? {
  let head = split_first(token, '(')
  match head {
    ":skip" | ":error" | ":fail-fast" | ":cst" | ":platform" | ":language" =>
      Some(head)
    _ => None
  }
}

///|
/// Try to parse a header block (opening `===`, name/markers, closing `===`)
/// starting at `lines[start_line]`. Returns the parsed header and the line
/// index after the closing `===`, or `None` if `lines[start_line]` isn't a
/// matching `===` delimiter.
fn parse_header(
  lines : Array[StringView],
  first_suffix : String?,
  start_line : Int32,
) -> (PendingTest, Int32)? {
  guard parse_delimiter_line(lines[start_line], '=')
    is Some((header_delim_len, suffix)) else {
    return None
  }
  if !suffix_matches(first_suffix, suffix) {
    return None
  }

  // Collect name and attribute lines until the closing `===` line.
  let test_name = StringBuilder()
  let mut seen_marker = false
  let mut seen_skip = false
  let mut seen_error = false
  let mut platform : Bool? = None
  let mut fail_fast = false
  let mut cst = false
  let languages : Array[String] = []
  let mut line_num = start_line + 1 // start past opening === line
  while line_num < lines.length() {
    if parse_delimiter_line(lines[line_num], '=') is Some((_, closing_suffix)) &&
      suffix_matches(first_suffix, closing_suffix) {
      break
    }
    let trimmed = trim_ws(lines[line_num])
    // Reject a blank line in the name region so a literal `===` inside a
    // test body can't be mistaken for an opening delimiter. Blank lines
    // between markers are allowed as visual separators.
    if trimmed.is_empty() && !seen_marker {
      return None
    }
    match split_first(trimmed, '(') {
      ":skip" => {
        seen_marker = true
        seen_skip = true
      }
      ":platform" =>
        if strip_wrapped(trimmed, ":platform(", ")") is Some(platforms) {
          seen_marker = true
          platform = Some(
            platform.unwrap_or(false) || trim_ws(platforms) == current_os,
          )
        }
      ":fail-fast" => {
        seen_marker = true
        fail_fast = true
      }
      ":error" => {
        seen_marker = true
        seen_error = true
      }
      ":language" =>
        if strip_wrapped(trimmed, ":language(", ")") is Some(lang) {
          seen_marker = true
          languages.push(lang.to_owned())
        }
      ":cst" => {
        seen_marker = true
        cst = true
      }
      _ if !seen_marker => {
        // This line is part of the test name. If it contains a token that
        // looks like an attribute marker, warn the user.
        let mut warned = false
        for token in split_whitespace(trimmed) {
          if known_attribute(token) is Some(attr) {
            warn(
              "Test header line `\{trimmed}` contains `\{attr}`, which looks like a test attribute but won't be recognized as one. Attributes must appear on their own line(s) below the test name.",
            )
            warned = true
          }
        }
        // A line that is itself a single `:` prefixed token and didn't
        // match any known marker is most likely a typo'd attribute.
        if !warned &&
          trimmed.has_prefix(":") &&
          !trimmed.iter().any(c => c.is_whitespace()) {
          warn(
            "Test header line `\{trimmed}` looks like a test attribute but isn't.",
          )
        }
        test_name.write_view(lines[line_num])
      }
      _ =>
        // In the marker region, lines that start with `:` but don't
        // match any known marker are most likely a typo.
        if trimmed.has_prefix(":") {
          warn(
            "Test header line `\{trimmed}` looks like a test attribute but isn't.",
          )
        }
    }
    line_num += 1
  }
  let test_name = test_name.to_string()
  if line_num >= lines.length() {
    warn("No closing `===` line found for \{trim_ws_end(test_name)}")
    return None // No closing `===` line found.
  }
  let expectation : TestExpectation = match (seen_skip, seen_error) {
    (true, true) => {
      warn(
        "Test '\{trim_ws_end(test_name)}' specifies both `:skip` and `:error`. The `:error` attribute will be dropped.",
      )
      Skip
    }
    (false, false) => Pass
    (true, false) => Skip
    (false, true) => Error
  }

  // Build attributes string from the content between test name and closing
  // delimiter.
  let name_and_markers = StringBuilder()
  for i in (start_line + 1)..<line_num {
    name_and_markers.write_view(lines[i])
  }
  let name_and_markers = name_and_markers.to_string()
  let attributes_str = if name_and_markers.has_prefix(test_name) {
    trim_ws_end(name_and_markers[test_name.length():]).to_owned()
  } else {
    ""
  }
  if languages.is_empty() {
    languages.push("")
  }
  let pending = {
    name: trim_ws_end(test_name).to_owned(),
    attributes_str,
    header_delim_len,
    attributes: {
      platform: platform.unwrap_or(true),
      fail_fast,
      expectation,
      cst,
      languages,
    },
    body_start_line: line_num + 1,
  }
  Some((pending, line_num + 1)) // +1 to consume the closing `===` line
}

///|
fn parse_test_content(
  name : String,
  content : String,
  file_path : String?,
) -> TestEntry {
  let children = []
  let lines = split_inclusive_newline(content)

  // Determine the suffix from the first `===` line in the file.
  let mut first_suffix : String? = None
  for line in lines {
    if parse_delimiter_line(line, '=') is Some((_, suffix)) &&
      !suffix.is_empty() {
      first_suffix = Some(suffix.to_owned())
      break
    }
  }

  // Scan for header blocks and build test entries from the bodies between
  // them.
  let mut line_num = 0
  let mut prev_test : PendingTest? = None
  while line_num < lines.length() {
    guard parse_header(lines, first_suffix, line_num)
      is Some((pending, body_start_line)) else {
      line_num += 1
      continue
    }
    let opening_line = line_num
    line_num = body_start_line

    // Process the PREVIOUS test's body now that we know where it ends.
    if prev_test is Some(prev) &&
      build_test_entry(
        lines[prev.body_start_line:opening_line],
        first_suffix,
        prev,
        file_path,
      )
      is Some(entry) {
      children.push(entry)
    }
    prev_test = Some(pending)
  }

  // Process the last test's body (terminated by end of content).
  if prev_test is Some(prev) &&
    build_test_entry(
      lines[prev.body_start_line:],
      first_suffix,
      prev,
      file_path,
    )
    is Some(entry) {
    children.push(entry)
  }
  Group(name~, children~, file_path~)
}

///|
/// Build a single test entry from the body lines between a header and the
/// next header. Finds the longest matching `---` divider to separate input
/// from expected output.
fn build_test_entry(
  body_lines : ArrayView[StringView],
  first_suffix : String?,
  pending : PendingTest,
  file_path : String?,
) -> TestEntry? {
  // Find the longest `---` divider line in the body whose suffix matches.
  let mut best_divider : (Int32, Int32)? = None // (delim_len, line_index)
  let mut best_total_len = 0
  for j, line in body_lines {
    if parse_delimiter_line(line, '-') is Some((delim_len, suffix)) &&
      suffix_matches(first_suffix, suffix) {
      let total_len = delim_len + utf8_len(suffix)
      // For ties prefer the later candidate, as an earlier same-length
      // `---` is a literal in the input.
      if total_len >= best_total_len {
        best_divider = Some((delim_len, j))
        best_total_len = total_len
      }
    }
  }
  guard best_divider is Some((divider_delim_len, divider_line)) else {
    return None
  }

  // Input: lines before the divider (as bytes), with trailing newline
  // stripped.
  let input_text = StringBuilder()
  for line in body_lines[:divider_line] {
    input_text.write_view(line)
  }
  let input = @utf8.encode(input_text.to_string()).to_array()
  // Remove trailing newline.
  if input.last() == Some(b'\n') {
    ignore(input.pop())
  }
  if input.last() == Some(b'\r') {
    ignore(input.pop())
  }

  // Output: lines after the divider.
  let output_str = StringBuilder()
  for line in body_lines[divider_line + 1:] {
    output_str.write_view(line)
  }
  let output_str = output_str.to_string()
  let (output, has_fields) = if pending.attributes.cst {
    (trim_ws(output_str).to_owned(), false)
  } else {
    normalize_sexp_output(output_str)
  }
  let file_name = match file_path {
    Some(p) => Some(file_name_of(p))
    None => None
  }
  Some(
    Example(
      name=pending.name,
      input=Bytes::from_array(input),
      output~,
      header_delim_len=pending.header_delim_len,
      divider_delim_len~,
      has_fields~,
      attributes_str=pending.attributes_str,
      attributes=pending.attributes,
      file_name~,
    ),
  )
}

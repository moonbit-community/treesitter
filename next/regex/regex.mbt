// A byte-oriented regular expression matcher equivalent to the `is_match`
// method of the Rust `regex` crate's `regex::bytes::Regex`, which is what
// Tree-sitter's Rust binding uses for `#match?` query predicates.
//
// Patterns are parsed and translated with `next/regex_syntax` using the same
// settings as `regex::bytes::Regex::new` (regex 1.13): Unicode mode enabled,
// UTF-8 mode *disabled* (so `(?-u:\xFF)` is accepted and matches the raw
// byte), octal escapes disabled, a nesting limit of 250, `\n` as the line
// terminator and every other flag off unless enabled inline. The resulting
// HIR is compiled to a Thompson NFA over bytes in which Unicode classes are
// single states that decode one UTF-8 encoded scalar value; the NFA is
// simulated breadth-first (a Pike VM without capture slots), which yields
// unanchored `is_match` semantics.

///|
/// An error building a [`Regex`].
pub(all) suberror RegexError {
  /// The pattern failed to parse or translate; the payload is the
  /// regex-syntax error.
  Syntax(String)
  /// The compiled program exceeded the size limit (`regex` uses an NFA size
  /// limit of 10 MiB by default).
  CompiledTooBig(Int32)
} derive(Eq, Debug)

///|
pub impl Show for RegexError with fn output(self, logger) {
  match self {
    Syntax(message) => logger.write_string(message)
    CompiledTooBig(limit) =>
      logger.write_string(
        "Compiled regex exceeds size limit of \{limit} bytes.",
      )
  }
}

///|
/// A compiled regular expression that can be searched against byte strings.
pub struct Regex {
  priv pattern : String
  priv program : Program
}

///|
/// Compile `pattern` with the default configuration of
/// `regex::bytes::Regex::new`.
pub fn Regex::new(pattern : String) -> Regex raise RegexError {
  let parser = @ast.ParserBuilder::new()
    .nest_limit(250)
    .octal(false)
    .ignore_whitespace(false)
    .build()
  let ast = parser.parse(pattern) catch {
    err => raise Syntax(err.kind().to_string())
  }
  let translator = @hir.TranslatorBuilder::new()
    .utf8(false)
    .unicode(true)
    .case_insensitive(false)
    .multi_line(false)
    .dot_matches_new_line(false)
    .crlf(false)
    .swap_greed(false)
    .line_terminator(b'\n')
    .build()
  let hir = translator.translate(pattern, ast) catch {
    err => raise Syntax(err.kind().to_string())
  }
  if estimate_size(hir) > nfa_size_limit {
    raise CompiledTooBig(nfa_size_limit)
  }
  { pattern, program: compile(hir), }
}

///|
/// The source pattern of this regex.
pub fn Regex::as_str(self : Regex) -> String {
  self.pattern
}

///|
pub impl Show for Regex with fn output(self, logger) {
  logger.write_string(self.pattern)
}

///|
/// Returns true if and only if there is a match for the regex anywhere in
/// `haystack`.
pub fn Regex::is_match(self : Regex, haystack : BytesView) -> Bool {
  self.program.is_match(haystack)
}

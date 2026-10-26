// A byte-oriented regular expression matcher equivalent to the `is_match`
// method of the Rust `regex` crate's `regex::bytes::Regex`, which is what
// Tree-sitter's Rust binding uses for `#match?` query predicates.
//
// Patterns are parsed and translated with `regex_syntax` using the same
// settings as `regex::bytes::Regex::new` (regex 1.13): Unicode mode enabled,
// UTF-8 mode *disabled* (so `(?-u:\xFF)` is accepted and matches the raw
// byte), octal escapes disabled, a nesting limit of 250, `\n` as the line
// terminator and every other flag off unless enabled inline. The resulting
// HIR is compiled to a Thompson NFA over bytes in which Unicode classes are
// single states that decode one UTF-8 encoded scalar value; the NFA is
// simulated breadth-first (a Pike VM without capture slots), which yields
// unanchored `is_match` semantics. `find` uses a second NFA (find.mbt), and
// a large alternation of literals is searched with Aho-Corasick instead, as
// the meta engine does (aho_corasick.mbt).

///|
/// An error building a [`Regex`].
pub(all) suberror RegexError {
  /// The pattern failed to parse or translate; the payload is the
  /// `Display` text of the regex-syntax error (as in `regex::Error::Syntax`).
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
  priv hir : @hir.Hir
  /// UTF-8 mode (`regex::Regex` rather than `regex::bytes::Regex`).
  priv utf8 : Bool
  /// The Aho-Corasick automaton that answers every search when the meta
  /// engine uses its literal-alternation strategy (aho_corasick.mbt).
  priv literals : AhoCorasick?
  /// The NFA used by `is_match`, compiled on first use.
  priv mut program : Program?
  /// The NFA used by `find`, compiled on first use (find.mbt).
  priv mut find_program : FindProgram?
}

///|
/// Compile `pattern` with the default configuration of
/// `regex::bytes::Regex::new`, or of `regex::Regex::new` when `utf8` is true
/// (UTF-8 mode: the pattern must only match valid UTF-8, and empty matches
/// never split a code point).
pub fn Regex::new(
  pattern : String,
  utf8~ : Bool = false,
) -> Regex raise RegexError {
  let parser = @ast.ParserBuilder::new()
    .nest_limit(250)
    .octal(false)
    .ignore_whitespace(false)
    .build()
  let ast = parser.parse(pattern) catch {
    err => raise Syntax(format_ast_error(err))
  }
  let translator = @hir.TranslatorBuilder::new()
    .utf8(utf8)
    .unicode(true)
    .case_insensitive(false)
    .multi_line(false)
    .dot_matches_new_line(false)
    .crlf(false)
    .swap_greed(false)
    .line_terminator(b'\n')
    .build()
  let hir = translator.translate(pattern, ast) catch {
    err => raise Syntax(format_hir_error(err))
  }
  let literals = alternation_literals(hir).map(AhoCorasick::new)
  if literals is None && exceeds_size_limit(hir) {
    raise CompiledTooBig(nfa_size_limit)
  }
  { pattern, hir, utf8, literals, program: None, find_program: None, }
}

///|
fn Regex::program(self : Regex) -> Program {
  match self.program {
    Some(program) => program
    None => {
      let program = compile(self.hir)
      self.program = Some(program)
      program
    }
  }
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
///
/// In UTF-8 mode, when the regex can match the empty string, the result
/// depends on the meta engine's choice of engine; see `utf8_empty_is_match`.
pub fn Regex::is_match(self : Regex, haystack : BytesView) -> Bool {
  if self.literals is Some(literals) {
    return literals.find(haystack, 0) is Some(_)
  }
  let program = self.program()
  if self.utf8 && program.has_empty {
    self.utf8_empty_is_match(program, haystack)
  } else {
    program.earliest_end(haystack, 0, any=true) >= 0
  }
}

///|
/// `is_match` in UTF-8 mode for a regex that can match the empty string.
///
/// The meta engine runs an earliest search with regex-automata's
/// `skip_splits_fwd`: while the match it finds ends inside a code point
/// (which only an empty match can), the search is repeated one byte further.
/// The lazy DFA and the PikeVM report the smallest match end; so a regex like
/// `x☃|(?-u:\B)` does not match `"x☃y"` (the empty matches inside `☃` end
/// first), although `find` finds `x☃`.
///
/// When the regex has a Unicode word boundary, the lazy DFA gives up on the
/// first non-ASCII byte it reads (including the byte before the search
/// start), and the meta engine redoes the whole search with another engine:
/// for haystacks of at most 128 bytes the bounded backtracker, which reports
/// the end of the leftmost-first match, otherwise the PikeVM. (The
/// backtracker's own limit, 256 KiB of visited bits, is not modelled: it only
/// excludes NFAs of more than 16,000 states here. Regexes anchored at the
/// start cannot differ: their matches start at 0, so a non-empty one ends on
/// a code point boundary.)
fn Regex::utf8_empty_is_match(
  self : Regex,
  program : Program,
  haystack : BytesView,
) -> Bool {
  let len = haystack.length()
  // Only a fallback to the backtracker changes the result.
  let may_quit = len <= 128 && has_unicode_word_boundary(self.hir)
  for from = 0; from <= len; from = from + 1 {
    let end = program.earliest_end(haystack, from, any=false)
    if may_quit && reads_non_ascii(haystack, from, end) {
      return self.backtrack_utf8_empty_is_match(haystack)
    }
    if end < 0 {
      return false
    }
    if is_char_boundary(haystack, end) {
      return true
    }
  }
  false
}

///|
/// The bounded backtracker's `is_match` with `skip_splits_fwd` (see
/// `utf8_empty_is_match`): the end of the leftmost-first match.
fn Regex::backtrack_utf8_empty_is_match(
  self : Regex,
  haystack : BytesView,
) -> Bool {
  let program = self.find_program()
  for from = 0; from <= haystack.length(); from = from + 1 {
    match program.search(haystack, from) {
      None => return false
      Some((_, end)) => if is_char_boundary(haystack, end) { return true }
    }
  }
  false
}

///|
/// Whether the lazy DFA quits on a non-ASCII byte (`quit_set_from_nfa`).
fn has_unicode_word_boundary(hir : @hir.Hir) -> Bool {
  let looks = hir.properties().look_set()
  [
    @hir.Look::WordUnicode,
    WordUnicodeNegate,
    WordStartUnicode,
    WordEndUnicode,
    WordStartHalfUnicode,
    WordEndHalfUnicode,
  ]
  .iter()
  .any(look => looks.contains(look))
}

///|
/// Whether a forward lazy DFA search starting at `from` that stops at the
/// match ending at `end` (-1 for none) reads a non-ASCII byte: the
/// look-behind byte, and every byte up to the one after the match (the DFA
/// recognizes a match one byte late) or up to the end of the haystack.
fn reads_non_ascii(haystack : BytesView, from : Int32, end : Int32) -> Bool {
  let len = haystack.length()
  let stop = if end >= 0 && end < len { end + 1 } else { len }
  let start = if from > 0 { from - 1 } else { 0 }
  for i in start..<stop {
    if haystack[i] >= b'\x80' {
      return true
    }
  }
  false
}

// Port of tree-sitter crates/generate/src/prepare_grammar/pattern.rs.
//
// Parsing of token patterns.
//
// Unicode simple case folding maps two non-ASCII code points onto ASCII letters:
//     - the long s `ſ` onto `s`
//     - the Kelvin sign `K` onto `k`
//
// Taken as is, every case-insensitive ASCII token picks both up, which is virtually
// never intended and stops the token from being extracted as a keyword. To
// fix this, we expand the `i` flag ourselves.
//
// The `regex_syntax` crate parses a pattern into an `ast::Ast`, then lowers
// it to an `hir::Hir` via a `hir::translate::Translator`. The translator is
// what applies `i`, and it folds each leaf of a class expression before applying
// that leaf's negation and the set algebra above it. This order is what makes
// `(?i)[^x]` exclude `X` rather than re-admit it, so we keep that order and only
// change the fold:
//     - Walk the AST
//     - Fold each leaf as if `ſ` and `K` were their own equivalence classes
//     - Hand the result to the translator with its own folding turned off
//
// Folding at the leaves is sufficient for correctness, as case folding sorts every
// character into a group of case variants (`{a, A}`, `{s, S, ſ}`, etc.), with
// each character in exactly one group. Folding a set adds (for each character
// in it) the rest of that character's group, so the result is always built out
// of whole groups. Negation and set algebra preserve that, because they treat
// every character in a group alike: a group ends up either wholly inside or wholly
// outside the result. Folding a set that is already whole groups adds nothing,
// so once leaves are folded, every fold the translator would still apply does
// nothing and it compiles exactly what is would have with our fold in place of
// its own.
//
// Upstream mutates the AST in place (`*ast = ...`); here the walk returns the
// (possibly replaced) node and the parent stores it.

///|
/// The flags that decide whether we fold a scope's leaves.
priv struct FoldMode {
  case_insensitive : Bool
  unicode : Bool
}

///|
/// Whether we fold this scope's leaves ourselves.
///
/// Inside `(?-u:...)` the translator works on bytes and folds ASCII only, which
/// can never pull in `ſ` or `K`, so those scopes keep its folding.
fn FoldMode::folds_here(self : FoldMode) -> Bool {
  self.case_insensitive && self.unicode
}

///|
/// The state of the walk: The flags in effect, and one translator to resolve
/// `\p{...}` and friends without rebuilding it per leaf.
priv struct PatternExpander {
  translator : @hir.Translator
  pattern : String
  mut mode : FoldMode
}

///|
/// `pattern::parse`: parse a token pattern into an `Hir`, folding any `i`
/// flag manually.
pub fn pattern_parse(
  pattern : String,
  case_insensitive : Bool,
) -> @hir.Hir raise RegexError {
  let ast = @ast.ParserBuilder::new().build().parse(pattern) catch {
      e => raise RegexError::new(@regex_syntax.SyntaxError::from_ast(e))
    }
  let expander = {
    translator: @hir.TranslatorBuilder::new()
    .case_insensitive(false)
    .unicode(true)
    .utf8(false)
    .build(),
    pattern,
    mode: { case_insensitive, unicode: true, },
  }
  let ast = expander.expand(ast) catch {
    e => raise RegexError::new(@regex_syntax.SyntaxError::from_hir(e))
  }
  expander.translator.translate(pattern, ast) catch {
    e => raise RegexError::new(@regex_syntax.SyntaxError::from_hir(e))
  }
}

///|
fn PatternExpander::expand(
  self : PatternExpander,
  ast : @ast.Ast,
) -> @ast.Ast raise @hir.HirError {
  match ast {
    Flags(f) => self.set_flags(f.flags)
    Repetition(r) => r.ast = self.expand(r.ast)
    Group(g) => {
      let outer = self.mode
      if g.kind is NonCapturing(flags) {
        self.set_flags(flags)
      }
      g.ast = self.expand(g.ast)
      self.mode = outer
    }
    // Flags set in one branch carry into the next, as they do in the translator,
    // which scopes flags to groups but not to these.
    Alternation(a) =>
      for i in 0..<a.asts.length() {
        a.asts[i] = self.expand(a.asts[i])
      }
    Concat(c) =>
      for i in 0..<c.asts.length() {
        c.asts[i] = self.expand(c.asts[i])
      }
    ClassBracketed(b) if self.mode.folds_here() =>
      b.kind = self.expand_class_set(b.kind)
    // The remaining class-valued nodes are the same leaves as a bracket holds,
    // so they fold through the same path.
    _ if self.mode.folds_here() => {
      let item : @ast.ClassSetItem = match ast {
        Literal(l) => Literal(l)
        ClassUnicode(u) => Unicode(u)
        ClassPerl(p) => Perl(p)
        // `.` is fold-closed, nothing else matches a character
        _ => return ast
      }
      let item = self.expand_class_item(item)
      if item is Bracketed(class) {
        return ClassBracketed(class)
      }
    }
    // Left to the translator: either no `i` is in effect, or this is a
    // `(?-u:...)` scope, where its own folding is ASCII-only and cannot
    // pull in `ſ` or `K`.
    Empty(_)
    | Dot(_)
    | Assertion(_)
    | Literal(_)
    | ClassUnicode(_)
    | ClassPerl(_)
    | ClassBracketed(_) => ()
  }
  ast
}

///|
/// Apply a flag directive to the mode, then rewrite the directive to say what
/// the translator should still do about `i` in the scope it opens.
///
/// `i` comes out everywhere, since folding a leaf we already folded would put
/// `ſ`/`K` straight back. It goes back in wherever [`FoldMode::folds_here`]
/// says we left the folding alone, which would otherwise lose case-insensitivity
/// in that scope entirely.
fn PatternExpander::set_flags(self : PatternExpander, flags : @ast.Flags) -> Unit {
  let mut negated = false
  for item in flags.items {
    match item.kind {
      Negation => negated = true
      Flag(CaseInsensitive) =>
        self.mode = { ..self.mode, case_insensitive: !negated, }
      Flag(Unicode) => self.mode = { ..self.mode, unicode: !negated, }
      Flag(_) => ()
    }
  }
  let item = (kind : @ast.FlagsItemKind) => @ast.FlagsItem::{
    span: flags.span,
    kind,
  }
  flags.items.retain(it => !(it.kind is Flag(CaseInsensitive)))
  if self.mode.folds_here() {
    flags.items.push(item(Negation))
    flags.items.push(item(Flag(CaseInsensitive)))
  } else if self.mode.case_insensitive {
    flags.items.insert(0, item(Flag(CaseInsensitive)))
  }
}

///|
/// Fold the leaves of a class expression, leaving its structure alone. The
/// translator still performs the negations and the `&&`/`--`/`~~` itself, on
/// operands that are already folded.
fn PatternExpander::expand_class_set(
  self : PatternExpander,
  set : @ast.ClassSet,
) -> @ast.ClassSet raise @hir.HirError {
  match set {
    Item(item) => Item(self.expand_class_item(item))
    BinaryOp(op) => {
      op.lhs = self.expand_class_set(op.lhs)
      op.rhs = self.expand_class_set(op.rhs)
      set
    }
  }
}

///|
fn PatternExpander::expand_class_item(
  self : PatternExpander,
  item : @ast.ClassSetItem,
) -> @ast.ClassSetItem raise @hir.HirError {
  // Whether the leaf carries its own negation (`\P{L}, `[:^alpha:]`, `\D`, etc.).
  let (span, negated) = match item {
    Bracketed(b) => {
      b.kind = self.expand_class_set(b.kind)
      return item
    }
    Union(u) => {
      for i in 0..<u.items.length() {
        u.items[i] = self.expand_class_item(u.items[i])
      }
      return item
    }
    Empty(_) => return item
    Literal(l) => (l.span, false)
    Range(r) => (r.span, false)
    Ascii(a) => (a.span, a.negated)
    Perl(p) => (p.span, p.negated)
    Unicode(u) => (u.span, u.is_negated())
  }

  // `leaf_set` applies the leaf's own negation, so undo it to recover the
  // operand the translator would have folded, and hand the negation back
  // to the replacement so it is reapplied after the fold.
  let operand = self.leaf_set(item)
  if negated {
    operand.negate()
  }
  let folded = operand.copy()
  PatternExpander::fold_ascii_safe(folded)
  // A leaf that is already fold-closed stays as written, which keeps most
  // unicode properties out of the expansion.
  if folded.ranges() != operand.ranges() {
    return Bracketed({
      span,
      negated,
      kind: Item(PatternExpander::class_to_item(span, folded)),
    })
  }
  item
}

///|
/// The set a leaf denotes, with any negation of its own already applied.
///
/// Literals and ranges are read directly from the AST. Everything else goes
/// back through the translator, which own the property and POSIX tables.
fn PatternExpander::leaf_set(
  self : PatternExpander,
  item : @ast.ClassSetItem,
) -> @hir.ClassUnicode raise @hir.HirError {
  let range = match item {
    Literal(l) => @hir.ClassUnicodeRange::new(l.c.to_int(), l.c.to_int())
    Range(r) =>
      @hir.ClassUnicodeRange::new(r.start.c.to_int(), r.end.c.to_int())
    _ => {
      let ast = @ast.Ast::ClassBracketed({
        span: item.span(),
        negated: false,
        kind: Item(item),
      })
      return PatternExpander::class_of(self.translator.translate(self.pattern, ast))
    }
  }
  @hir.ClassUnicode::new([range])
}

///|
/// The class a single-class `Hir` denotes.
///
/// We only ever translate one `Ast::ClassBracketed`, so `Hir::class` built
/// the result: A class, or one of the two shapes it collapses to. The structural
/// kinds (`Empty`, `Look`, `Repetition`, `Capture`, `Concat`, `Alternation`)
/// need AST nodes we never construct in `Self::leaf_set`.
fn PatternExpander::class_of(hir : @hir.Hir) -> @hir.ClassUnicode {
  match hir.into_kind() {
    Class(Unicode(class)) => class
    Literal(literal) => {
      // A one character class, translated in unicode mode, so this must
      // be that character's UTF-8.
      let @hir.Literal(bytes) = literal
      let literal = try! @hir.from_utf8(bytes[:])
      @hir.ClassUnicode::new(
        literal.map(c => @hir.ClassUnicodeRange::new(c.to_int(), c.to_int())),
      )
    }
    // An empty class collapses to `Hir::fail` (an empty byte class).
    _ => @hir.ClassUnicode::empty()
  }
}

///|
/// Re-encode a class of the AST nodes the tranlator will read back, the inverse
/// of `Self::leaf_set`.
///
/// Every node reuses the leaf's own span to preserve error spans. The literal
/// kind is irrelevant, in unicode mode the translator only reads `c`.
fn PatternExpander::class_to_item(
  span : @ast.Span,
  class : @hir.ClassUnicode,
) -> @ast.ClassSetItem {
  let literal = (c : Int32) => @ast.Literal::{
    span,
    kind: Verbatim,
    c: c.unsafe_to_char(),
  }
  let union : @ast.ClassSetUnion = {
    span,
    items: class
    .ranges()
    .iter()
    .map(r => {
      @ast.ClassSetItem::Range({
        span,
        start: literal(r.start()),
        end: literal(r.end()),
      })
    })
    .collect(),
  }
  union.into_item()
}

///|
/// Fold `class` in place, with `ſ` and `K` each in a group of their own rather
/// than the the `s`/`S` and `k`/`K` groups.
///
/// Dropping them before the fold stops a `ſ` in the class from pulling in `s`/`S`.
/// Dropping them after removes the ones folding `s`/`S` introduced. The union
/// restores any the class genuinely held.
fn PatternExpander::fold_ascii_safe(class : @hir.ClassUnicode) -> Unit {
  // The code points that Unicode simple case folding maps onto ASCII letters:
  // the long s `ſ` folds with `s`/`S`, and the Kelvin sign `K` with `k`/`K`.
  let non_ascii_folds = [0x17f, 0x212a]
  let exotic = @hir.ClassUnicode::new(
    non_ascii_folds.map(c => @hir.ClassUnicodeRange::new(c, c)),
  )

  // The ones the pattern asked for itself, which folding  must not drop
  let asked_for = exotic.copy()
  asked_for.intersect(class)
  class.difference(exotic)
  class.case_fold_simple()
  class.difference(exotic)
  class.union(asked_for)
}

///|
/// Mirror of `regex_syntax::ast::ErrorKind` and `regex_syntax::hir::ErrorKind`.
pub(all) enum RegexErrorKind {
  CaptureLimitExceeded
  ClassEscapeInvalid
  ClassRangeInvalid
  ClassRangeLiteral
  ClassUnclosed
  DecimalEmpty
  DecimalInvalid
  EscapeHexEmpty
  EscapeHexInvalid
  EscapeHexInvalidDigit
  EscapeUnexpectedEof
  EscapeUnrecognized
  FlagDanglingNegation
  FlagUnexpectedEof
  FlagUnrecognized
  GroupNameEmpty
  GroupNameInvalid
  GroupNameUnexpectedEof
  GroupUnclosed
  GroupUnopened
  RepetitionCountInvalid
  RepetitionCountDecimalEmpty
  RepetitionCountUnclosed
  RepetitionMissing
  SpecialWordBoundaryUnclosed
  SpecialWordBoundaryUnrecognized
  SpecialWordOrRepetitionUnexpectedEof
  UnicodeClassInvalid
  UnsupportedBackreference
  UnsupportedLookAround
  UnicodeNotAllowed
  InvalidUtf8
  InvalidLineTerminator
  UnicodePropertyNotFound
  UnicodePropertyValueNotFound
  UnicodePerlClassNotFound
  UnicodeCaseUnavailable
  FlagDuplicate
  FlagRepeatedNegation
  GroupNameDuplicate
  NestLimitExceeded(UInt32)
  /// A kind `regex_syntax` added after this mirror was written.
  Other(String)
} derive(Eq, Debug)

///|
pub impl Show for RegexErrorKind with fn output(self, f) {
  let msg = match self {
    CaptureLimitExceeded =>
      "exceeded the maximum number of capturing groups (4294967295)"
    ClassEscapeInvalid => "invalid escape sequence found in character class"
    ClassRangeInvalid =>
      "invalid character class range, the start must be <= the end"
    ClassRangeLiteral => "invalid range boundary, must be a literal"
    ClassUnclosed => "unclosed character class"
    DecimalEmpty => "decimal literal empty"
    DecimalInvalid => "decimal literal invalid"
    EscapeHexEmpty => "hexadecimal literal empty"
    EscapeHexInvalid => "hexadecimal literal is not a Unicode scalar value"
    EscapeHexInvalidDigit => "invalid hexadecimal digit"
    EscapeUnexpectedEof =>
      "incomplete escape sequence, reached end of pattern prematurely"
    EscapeUnrecognized => "unrecognized escape sequence"
    FlagDanglingNegation => "dangling flag negation operator"
    FlagUnexpectedEof => "expected flag but got end of regex"
    FlagUnrecognized => "unrecognized flag"
    GroupNameEmpty => "empty capture group name"
    GroupNameInvalid => "invalid capture group character"
    GroupNameUnexpectedEof => "unclosed capture group name"
    GroupUnclosed => "unclosed group"
    GroupUnopened => "unopened group"
    RepetitionCountInvalid =>
      "invalid repetition count range, the start must be <= the end"
    RepetitionCountDecimalEmpty =>
      "repetition quantifier expects a valid decimal"
    RepetitionCountUnclosed => "unclosed counted repetition"
    RepetitionMissing => "repetition operator missing expression"
    SpecialWordBoundaryUnclosed =>
      "special word boundary assertion is either unclosed or contains an invalid character"
    SpecialWordBoundaryUnrecognized =>
      "unrecognized special word boundary assertion, valid choices are: start, end, start-half or end-half"
    SpecialWordOrRepetitionUnexpectedEof =>
      "found either the beginning of a special word boundary or a bounded repetition on a \\b with an opening brace, but no closing brace"
    UnicodeClassInvalid => "invalid Unicode character class"
    UnsupportedBackreference => "backreferences are not supported"
    UnsupportedLookAround =>
      "look-around, including look-ahead and look-behind, is not supported"
    UnicodeNotAllowed => "Unicode not allowed here"
    InvalidUtf8 => "pattern can match invalid UTF-8"
    InvalidLineTerminator => "invalid line terminator, must be ASCII"
    UnicodePropertyNotFound => "Unicode property not found"
    UnicodePropertyValueNotFound => "Unicode property value not found"
    UnicodePerlClassNotFound =>
      "Unicode-aware Perl class not found (make sure the unicode-perl feature is enabled)"
    UnicodeCaseUnavailable =>
      "Unicode-aware case insensitivity matching is not available (make sure the unicode-case feature is enabled)"
    FlagDuplicate => "duplicate flag"
    FlagRepeatedNegation => "flag negation operator repeated"
    GroupNameDuplicate => "duplicate capture group name"
    NestLimitExceeded(limit) =>
      "exceed the maximum number of nested parentheses/brackets (\{limit})"
    Other(message) => message
  }
  f.write_string(msg)
}

///|
/// `From<&ast::ErrorKind> for RegexErrorKind`.
fn RegexErrorKind::from_ast(kind : @ast.ErrorKind) -> RegexErrorKind {
  match kind {
    CaptureLimitExceeded => CaptureLimitExceeded
    ClassEscapeInvalid => ClassEscapeInvalid
    ClassRangeInvalid => ClassRangeInvalid
    ClassRangeLiteral => ClassRangeLiteral
    ClassUnclosed => ClassUnclosed
    DecimalEmpty => DecimalEmpty
    DecimalInvalid => DecimalInvalid
    EscapeHexEmpty => EscapeHexEmpty
    EscapeHexInvalid => EscapeHexInvalid
    EscapeHexInvalidDigit => EscapeHexInvalidDigit
    EscapeUnexpectedEof => EscapeUnexpectedEof
    EscapeUnrecognized => EscapeUnrecognized
    FlagDanglingNegation => FlagDanglingNegation
    FlagUnexpectedEof => FlagUnexpectedEof
    FlagUnrecognized => FlagUnrecognized
    GroupNameEmpty => GroupNameEmpty
    GroupNameInvalid => GroupNameInvalid
    GroupNameUnexpectedEof => GroupNameUnexpectedEof
    GroupUnclosed => GroupUnclosed
    GroupUnopened => GroupUnopened
    RepetitionCountInvalid => RepetitionCountInvalid
    RepetitionCountDecimalEmpty => RepetitionCountDecimalEmpty
    RepetitionCountUnclosed => RepetitionCountUnclosed
    RepetitionMissing => RepetitionMissing
    SpecialWordBoundaryUnclosed => SpecialWordBoundaryUnclosed
    SpecialWordBoundaryUnrecognized => SpecialWordBoundaryUnrecognized
    SpecialWordOrRepetitionUnexpectedEof => SpecialWordOrRepetitionUnexpectedEof
    UnicodeClassInvalid => UnicodeClassInvalid
    UnsupportedBackreference => UnsupportedBackreference
    UnsupportedLookAround => UnsupportedLookAround
    FlagDuplicate(..) => FlagDuplicate
    FlagRepeatedNegation(..) => FlagRepeatedNegation
    GroupNameDuplicate(..) => GroupNameDuplicate
    NestLimitExceeded(limit) => NestLimitExceeded(limit)
  }
}

///|
/// `From<&hir::ErrorKind> for RegexErrorKind`.
fn RegexErrorKind::from_hir(kind : @hir.ErrorKind) -> RegexErrorKind {
  match kind {
    UnicodeNotAllowed => UnicodeNotAllowed
    InvalidUtf8 => InvalidUtf8
    InvalidLineTerminator => InvalidLineTerminator
    UnicodePropertyNotFound => UnicodePropertyNotFound
    UnicodePropertyValueNotFound => UnicodePropertyValueNotFound
    UnicodePerlClassNotFound => UnicodePerlClassNotFound
    UnicodeCaseUnavailable => UnicodeCaseUnavailable
  }
}

///|
/// Byte range within a pattern string.
pub(all) struct PatternSpan {
  start : UInt32
  end : UInt32
} derive(Eq, Compare, Debug)

///|
fn PatternSpan::new(span : @ast.Span) -> PatternSpan {
  {
    start: span.start.offset.reinterpret_as_uint(),
    end: span.end.offset.reinterpret_as_uint(),
  }
}

///|
/// A pattern rejected by [`pattern_parse`], carrying the pattern and the
/// offending range inside it.
pub(all) suberror RegexError {
  RegexError(
    pattern~ : String,
    kind~ : RegexErrorKind,
    span~ : PatternSpan?,
    aux_span~ : PatternSpan?
  )
} derive(Eq, Debug)

///|
fn RegexError::new(error : @regex_syntax.SyntaxError) -> RegexError {
  let (pattern, kind, span, aux_span) = match error {
    Parse(e) =>
      (
        e.pattern(),
        RegexErrorKind::from_ast(e.kind()),
        Some(e.span()),
        e.auxiliary_span(),
      )
    Translate(e) =>
      (e.pattern(), RegexErrorKind::from_hir(e.kind()), Some(e.span()), None)
  }
  RegexError(
    pattern~,
    kind~,
    span=span.map(PatternSpan::new),
    aux_span=aux_span.map(PatternSpan::new),
  )
}

///|
/// The number of chars in the first `offset` UTF-8 bytes of the pattern.
fn RegexError::column(self : RegexError, offset : UInt32) -> Int32 {
  let RegexError(pattern~, ..) = self
  let offset = offset.reinterpret_as_int()
  let mut bytes = 0
  let mut count = 0
  for c in pattern {
    if bytes >= offset {
      break
    }
    bytes += @hir.len_utf8(c.to_int())
    count += 1
  }
  count
}

///|
pub impl Show for RegexError with fn output(self, f) {
  let RegexError(pattern~, kind~, span~, aux_span~) = self
  f.write_string("regex parse error:\n")
  f.write_string("    \{pattern}\n")
  if span is Some(_) {
    let spans = [span, aux_span]
    // `sort_unstable_by_key(|span| span.map(|s| (s.start, s.end)))`: `None`
    // first; equal keys are indistinguishable.
    spans.sort_by((a, b) => {
      match (a, b) {
        (None, None) => 0
        (None, Some(_)) => -1
        (Some(_), None) => 1
        (Some(x), Some(y)) => x.compare(y)
      }
    })
    f.write_string("    ")
    let mut column = 0
    for span in spans {
      guard span is Some(span) else { continue }
      let start = self.column(span.start)
      let end = self.column(span.end)
      let width = @cmp.maximum(if end > start { end - start } else { 0 }, 1)
      let pad = if start > column { start - column } else { 0 }
      f.write_string(" ".repeat(pad))
      f.write_string("^".repeat(width))
      column = @cmp.maximum(column, start) + width
    }
    f.write_string("\n")
  }
  f.write_string("error: \{kind}")
}

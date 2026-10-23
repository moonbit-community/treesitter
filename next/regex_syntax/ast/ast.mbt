// Port of regex-syntax 0.8.11 src/ast/mod.rs.
//
// Defines an abstract syntax for regular expressions. Spans count UTF-8 bytes
// of the pattern, exactly as upstream. `u32` quantities (capture indices,
// repetition counts, the nest limit) are `UInt`. The `Drop` impls and the
// `arbitrary` support of upstream are not needed and are omitted.

///|
/// An error that occurred while parsing a regular expression into an abstract
/// syntax tree (upstream `ast::Error`).
///
/// Note that not all ASTs represents a valid regular expression. For example,
/// an AST is constructed without error for `\p{Quux}`, but `Quux` is not a
/// valid Unicode property name. That particular error is reported when
/// translating an AST to the high-level intermediate representation (`HIR`).
pub(all) suberror AstError {
  AstError(kind~ : ErrorKind, pattern~ : String, span~ : Span)
} derive(Eq, Debug)

///|
/// Return the type of this error.
pub fn AstError::kind(self : AstError) -> ErrorKind {
  let AstError(kind~, ..) = self
  kind
}

///|
/// The original pattern string in which this error occurred.
pub fn AstError::pattern(self : AstError) -> String {
  let AstError(pattern~, ..) = self
  pattern
}

///|
/// Return the span at which this error occurred.
pub fn AstError::span(self : AstError) -> Span {
  let AstError(span~, ..) = self
  span
}

///|
/// Return an auxiliary span. This span exists only for some errors that
/// benefit from being able to point to two locations in the original
/// regular expression. For example, "duplicate" errors will have the
/// main error position set to the duplicate occurrence while its
/// auxiliary span will be set to the initial occurrence.
pub fn AstError::auxiliary_span(self : AstError) -> Span? {
  match self.kind() {
    FlagDuplicate(original~) => Some(original)
    FlagRepeatedNegation(original~) => Some(original)
    GroupNameDuplicate(original~) => Some(original)
    _ => None
  }
}

///|
/// The type of an error that occurred while building an AST.
pub(all) enum ErrorKind {
  /// The capturing group limit was exceeded.
  CaptureLimitExceeded
  /// An invalid escape sequence was found in a character class set.
  ClassEscapeInvalid
  /// An invalid character class range was found. An invalid range is any
  /// range where the start is greater than the end.
  ClassRangeInvalid
  /// An invalid range boundary was found in a character class.
  ClassRangeLiteral
  /// An opening `[` was found with no corresponding closing `]`.
  ClassUnclosed
  /// Note that this error variant is no longer used.
  DecimalEmpty
  /// An invalid decimal number was given where one was expected.
  DecimalInvalid
  /// A bracketed hex literal was empty.
  EscapeHexEmpty
  /// A bracketed hex literal did not correspond to a Unicode scalar value.
  EscapeHexInvalid
  /// An invalid hexadecimal digit was found.
  EscapeHexInvalidDigit
  /// EOF was found before an escape sequence was completed.
  EscapeUnexpectedEof
  /// An unrecognized escape sequence.
  EscapeUnrecognized
  /// A dangling negation was used when setting flags, e.g., `i-`.
  FlagDanglingNegation
  /// A flag was used twice, e.g., `i-i`.
  FlagDuplicate(original~ : Span)
  /// The negation operator was used twice, e.g., `-i-s`.
  FlagRepeatedNegation(original~ : Span)
  /// Expected a flag but got EOF, e.g., `(?`.
  FlagUnexpectedEof
  /// Unrecognized flag, e.g., `a`.
  FlagUnrecognized
  /// A duplicate capture name was found.
  GroupNameDuplicate(original~ : Span)
  /// A capture group name is empty, e.g., `(?P<>abc)`.
  GroupNameEmpty
  /// An invalid character was seen for a capture group name.
  GroupNameInvalid
  /// A closing `>` could not be found for a capture group name.
  GroupNameUnexpectedEof
  /// An unclosed group, e.g., `(ab`.
  GroupUnclosed
  /// An unopened group, e.g., `ab)`.
  GroupUnopened
  /// The nest limit was exceeded. The limit stored here is the limit
  /// configured in the parser.
  NestLimitExceeded(UInt32)
  /// The range provided in a counted repetition operator is invalid.
  RepetitionCountInvalid
  /// An opening `{` was not followed by a valid decimal value.
  RepetitionCountDecimalEmpty
  /// An opening `{` was found with no corresponding closing `}`.
  RepetitionCountUnclosed
  /// A repetition operator was applied to a missing sub-expression.
  RepetitionMissing
  /// The special word boundary syntax, `\b{something}`, was used, but
  /// either EOF without `}` was seen, or an invalid character in the
  /// braces was seen.
  SpecialWordBoundaryUnclosed
  /// The special word boundary syntax, `\b{something}`, was used, but
  /// `something` was not recognized as a valid word boundary kind.
  SpecialWordBoundaryUnrecognized
  /// The syntax `\b{` was observed, but afterwards the end of the pattern
  /// was observed.
  SpecialWordOrRepetitionUnexpectedEof
  /// The Unicode class is not valid.
  UnicodeClassInvalid
  /// When octal support is disabled, this error is produced when an octal
  /// escape is used.
  UnsupportedBackreference
  /// When syntax similar to PCRE's look-around is used, this error is
  /// returned.
  UnsupportedLookAround
} derive(Eq, Debug)

///|
pub impl Show for ErrorKind with fn output(self, f) {
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
    FlagDuplicate(..) => "duplicate flag"
    FlagRepeatedNegation(..) => "flag negation operator repeated"
    FlagUnexpectedEof => "expected flag but got end of regex"
    FlagUnrecognized => "unrecognized flag"
    GroupNameDuplicate(..) => "duplicate capture group name"
    GroupNameEmpty => "empty capture group name"
    GroupNameInvalid => "invalid capture group character"
    GroupNameUnexpectedEof => "unclosed capture group name"
    GroupUnclosed => "unclosed group"
    GroupUnopened => "unopened group"
    NestLimitExceeded(limit) =>
      "exceed the maximum number of nested parentheses/brackets (\{limit})"
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
  }
  f.write_string(msg)
}

///|
/// Span represents the position information of a single AST item.
///
/// All span positions are absolute byte offsets that can be used on the
/// original regular expression that was parsed.
pub(all) struct Span {
  /// The start byte offset.
  start : Position
  /// The end byte offset.
  end : Position
} derive(Eq, Debug)

///|
/// A single position in a regular expression.
pub(all) struct Position {
  /// The absolute offset of this position, starting at `0` from the
  /// beginning of the regular expression pattern string.
  offset : Int32
  /// The line number, starting at `1`.
  line : Int32
  /// The approximate column number, starting at `1`.
  column : Int32
} derive(Eq, Debug)

///|
/// Spans are ordered by `(start, end)`; positions by offset.
pub impl Compare for Position with fn compare(self, other) {
  self.offset.compare(other.offset)
}

///|
pub impl Compare for Span with fn compare(self, other) {
  let c = self.start.compare(other.start)
  if c != 0 {
    c
  } else {
    self.end.compare(other.end)
  }
}

///|
/// Create a new span with the given positions.
pub fn Span::new(start : Position, end : Position) -> Span {
  { start, end, }
}

///|
/// Create a new span using the given position as the start and end.
pub fn Span::splat(pos : Position) -> Span {
  Span::new(pos, pos)
}

///|
/// Create a new span by replacing the starting the position with the one
/// given.
pub fn Span::with_start(self : Span, pos : Position) -> Span {
  { ..self, start: pos, }
}

///|
/// Create a new span by replacing the ending the position with the one
/// given.
pub fn Span::with_end(self : Span, pos : Position) -> Span {
  { ..self, end: pos, }
}

///|
/// Returns true if and only if this span occurs on a single line.
pub fn Span::is_one_line(self : Span) -> Bool {
  self.start.line == self.end.line
}

///|
/// Returns true if and only if this span is empty.
pub fn Span::is_empty(self : Span) -> Bool {
  self.start.offset == self.end.offset
}

///|
/// Create a new position with the given information.
pub fn Position::new(offset : Int32, line : Int32, column : Int32) -> Position {
  { offset, line, column, }
}

///|
/// An abstract syntax tree for a singular expression along with comments
/// found.
pub(all) struct WithComments {
  /// The actual ast.
  ast : Ast
  /// All comments found in the original regular expression.
  comments : Array[Comment]
} derive(Eq, Debug)

///|
/// A comment from a regular expression with an associated span.
pub(all) struct Comment {
  /// The span of this comment, including the beginning `#` and ending `\n`.
  span : Span
  /// The comment text.
  comment : String
} derive(Eq, Debug)

///|
/// An abstract syntax tree for a single regular expression.
pub(all) enum Ast {
  /// An empty regex that matches everything.
  Empty(Span)
  /// A set of flags, e.g., `(?is)`.
  Flags(SetFlags)
  /// A single character literal, which includes escape sequences.
  Literal(Literal)
  /// The "any character" class.
  Dot(Span)
  /// A single zero-width assertion.
  Assertion(Assertion)
  /// A single Unicode character class, e.g., `\pL` or `\p{Greek}`.
  ClassUnicode(ClassUnicode)
  /// A single perl character class, e.g., `\d` or `\W`.
  ClassPerl(ClassPerl)
  /// A single bracketed character class set, e.g., `[a-zA-Z\pL]`.
  ClassBracketed(ClassBracketed)
  /// A repetition operator applied to an arbitrary regular expression.
  Repetition(Repetition)
  /// A grouped regular expression.
  Group(Group)
  /// An alternation of regular expressions.
  Alternation(Alternation)
  /// A concatenation of regular expressions.
  Concat(Concat)
} derive(Eq, Debug)

///|
/// Return the span of this abstract syntax tree.
pub fn Ast::span(self : Ast) -> Span {
  match self {
    Empty(span) => span
    Flags(x) => x.span
    Literal(x) => x.span
    Dot(span) => span
    Assertion(x) => x.span
    ClassUnicode(x) => x.span
    ClassPerl(x) => x.span
    ClassBracketed(x) => x.span
    Repetition(x) => x.span
    Group(x) => x.span
    Alternation(x) => x.span
    Concat(x) => x.span
  }
}

///|
/// Return true if and only if this Ast is empty.
pub fn Ast::is_empty(self : Ast) -> Bool {
  self is Empty(_)
}

///|
/// An alternation of regular expressions.
pub(all) struct Alternation {
  /// The span of this alternation.
  mut span : Span
  /// The alternate regular expressions.
  asts : Array[Ast]
} derive(Eq, Debug)

///|
/// Return this alternation as an AST.
///
/// If this alternation contains zero ASTs, then `Ast::empty` is returned.
/// If this alternation contains exactly 1 AST, then the corresponding AST
/// is returned. Otherwise, `Ast::alternation` is returned.
pub fn Alternation::into_ast(self : Alternation) -> Ast {
  match self.asts.length() {
    0 => Empty(self.span)
    1 => self.asts.unsafe_pop()
    _ => Alternation(self)
  }
}

///|
/// A concatenation of regular expressions.
pub(all) struct Concat {
  /// The span of this concatenation.
  mut span : Span
  /// The concatenation regular expressions.
  asts : Array[Ast]
} derive(Eq, Debug)

///|
/// Return this concatenation as an AST.
pub fn Concat::into_ast(self : Concat) -> Ast {
  match self.asts.length() {
    0 => Empty(self.span)
    1 => self.asts.unsafe_pop()
    _ => Concat(self)
  }
}

///|
/// A single literal expression.
pub(all) struct Literal {
  /// The span of this literal.
  mut span : Span
  /// The kind of this literal.
  kind : LiteralKind
  /// The Unicode scalar value corresponding to this literal.
  c : Char
} derive(Eq, Debug)

///|
/// If this literal was written as a `\x` hex escape, then this returns
/// the corresponding byte value. Otherwise, this returns `None`.
pub fn Literal::byte(self : Literal) -> Byte? {
  match self.kind {
    HexFixed(X) if self.c.to_int() <= 0xFF => Some(self.c.to_int().to_byte())
    _ => None
  }
}

///|
/// The kind of a single literal expression.
pub(all) enum LiteralKind {
  /// The literal is written verbatim, e.g., `a` or `☃`.
  Verbatim
  /// The literal is written as an escape because it is otherwise a special
  /// regex meta character, e.g., `\*` or `\[`.
  Meta
  /// The literal is written as an escape despite the fact that the escape is
  /// unnecessary, e.g., `\%` or `\/`.
  Superfluous
  /// The literal is written as an octal escape, e.g., `\141`.
  Octal
  /// The literal is written as a hex code with a fixed number of digits
  /// depending on the type of the escape, e.g., `\x61` or `a` or
  /// `\U00000061`.
  HexFixed(HexLiteralKind)
  /// The literal is written as a hex code with a bracketed number of
  /// digits.
  HexBrace(HexLiteralKind)
  /// The literal is written as a specially recognized escape, e.g., `\f`
  /// or `\n`.
  Special(SpecialLiteralKind)
} derive(Eq, Debug)

///|
/// The type of a special literal.
pub(all) enum SpecialLiteralKind {
  /// Bell, spelled `\a` (`\x07`).
  Bell
  /// Form feed, spelled `\f` (`\x0C`).
  FormFeed
  /// Tab, spelled `\t` (`\x09`).
  Tab
  /// Line feed, spelled `\n` (`\x0A`).
  LineFeed
  /// Carriage return, spelled `\r` (`\x0D`).
  CarriageReturn
  /// Vertical tab, spelled `\v` (`\x0B`).
  VerticalTab
  /// Space, spelled `\ ` (`\x20`). Note that this can only appear when
  /// parsing in verbose mode.
  Space
} derive(Eq, Debug)

///|
/// The type of a Unicode hex literal.
pub(all) enum HexLiteralKind {
  /// A `\x` prefix. When used without brackets, this form is limited to
  /// two digits.
  X
  /// A `\u` prefix. When used without brackets, this form is limited to
  /// four digits.
  UnicodeShort
  /// A `\U` prefix. When used without brackets, this form is limited to
  /// eight digits.
  UnicodeLong
} derive(Eq, Debug)

///|
/// The number of digits that must be used with this literal form when
/// used without brackets.
pub fn HexLiteralKind::digits(self : HexLiteralKind) -> Int32 {
  match self {
    X => 2
    UnicodeShort => 4
    UnicodeLong => 8
  }
}

///|
/// A Perl character class.
pub(all) struct ClassPerl {
  /// The span of this class.
  mut span : Span
  /// The kind of Perl class.
  kind : ClassPerlKind
  /// Whether the class is negated or not. e.g., `\d` is not negated but
  /// `\D` is.
  negated : Bool
} derive(Eq, Debug)

///|
/// The available Perl character classes.
pub(all) enum ClassPerlKind {
  /// Decimal numbers.
  Digit
  /// Whitespace.
  Space
  /// Word characters.
  Word
} derive(Eq, Debug)

///|
/// An ASCII character class.
pub(all) struct ClassAscii {
  /// The span of this class.
  span : Span
  /// The kind of ASCII class.
  kind : ClassAsciiKind
  /// Whether the class is negated or not. e.g., `[[:alpha:]]` is not negated
  /// but `[[:^alpha:]]` is.
  negated : Bool
} derive(Eq, Debug)

///|
/// The available ASCII character classes.
pub(all) enum ClassAsciiKind {
  /// `[0-9A-Za-z]`
  Alnum
  /// `[A-Za-z]`
  Alpha
  /// `[\x00-\x7F]`
  Ascii
  /// `[ \t]`
  Blank
  /// `[\x00-\x1F\x7F]`
  Cntrl
  /// `[0-9]`
  Digit
  /// `[!-~]`
  Graph
  /// `[a-z]`
  Lower
  /// `[ -~]`
  Print
  /// ``[!-/:-@\[-`{-~]``
  Punct
  /// `[\t\n\v\f\r ]`
  Space
  /// `[A-Z]`
  Upper
  /// `[0-9A-Za-z_]`
  Word
  /// `[0-9A-Fa-f]`
  Xdigit
} derive(Eq, Debug)

///|
/// Return the corresponding ClassAsciiKind variant for the given name.
pub fn ClassAsciiKind::from_name(name : String) -> ClassAsciiKind? {
  match name {
    "alnum" => Some(Alnum)
    "alpha" => Some(Alpha)
    "ascii" => Some(Ascii)
    "blank" => Some(Blank)
    "cntrl" => Some(Cntrl)
    "digit" => Some(Digit)
    "graph" => Some(Graph)
    "lower" => Some(Lower)
    "print" => Some(Print)
    "punct" => Some(Punct)
    "space" => Some(Space)
    "upper" => Some(Upper)
    "word" => Some(Word)
    "xdigit" => Some(Xdigit)
    _ => None
  }
}

///|
/// A Unicode character class.
pub(all) struct ClassUnicode {
  /// The span of this class.
  mut span : Span
  /// Whether this class is negated or not (`\P` rather than `\p`). Use
  /// `is_negated` to take a `!=` operator into account.
  negated : Bool
  /// The kind of Unicode class.
  kind : ClassUnicodeKind
} derive(Eq, Debug)

///|
/// Returns true if this class has been negated.
///
/// Note that this takes the Unicode op into account, if it's present.
/// e.g., `is_negated` for `\P{scx!=Katakana}` will return `false`.
pub fn ClassUnicode::is_negated(self : ClassUnicode) -> Bool {
  match self.kind {
    NamedValue(op=NotEqual, ..) => !self.negated
    _ => self.negated
  }
}

///|
/// The available forms of Unicode character classes.
pub(all) enum ClassUnicodeKind {
  /// A one letter abbreviated class, e.g., `\pN`.
  OneLetter(Char)
  /// A binary property, general category or script. The string may be
  /// empty.
  Named(String)
  /// A property name and an associated value.
  NamedValue(op~ : ClassUnicodeOpKind, name~ : String, value~ : String)
} derive(Eq, Debug)

///|
/// The type of op used in a Unicode character class.
pub(all) enum ClassUnicodeOpKind {
  /// A property set to a specific value, e.g., `\p{scx=Katakana}`.
  Equal
  /// A property set to a specific value using a colon, e.g.,
  /// `\p{scx:Katakana}`.
  Colon
  /// A property that isn't a particular value, e.g., `\p{scx!=Katakana}`.
  NotEqual
} derive(Eq, Debug)

///|
/// Whether the op is an equality op or not.
pub fn ClassUnicodeOpKind::is_equal(self : ClassUnicodeOpKind) -> Bool {
  self is (Equal | Colon)
}

///|
/// A bracketed character class, e.g., `[a-z0-9]`.
pub(all) struct ClassBracketed {
  /// The span of this class.
  mut span : Span
  /// Whether this class is negated or not. e.g., `[a]` is not negated but
  /// `[^a]` is.
  negated : Bool
  /// The type of this set. A set is either a normal union of things, e.g.,
  /// `[abc]` or a result of applying set operations, e.g., `[\pL--c]`.
  mut kind : ClassSet
} derive(Eq, Debug)

///|
/// A character class set.
pub(all) enum ClassSet {
  /// An item, which can be a single literal, range, nested character class
  /// or a union of items.
  Item(ClassSetItem)
  /// A single binary operation (i.e., &&, -- or ~~).
  BinaryOp(ClassSetBinaryOp)
} derive(Eq, Debug)

///|
/// Build a set from a union.
pub fn ClassSet::union(ast : ClassSetUnion) -> ClassSet {
  Item(Union(ast))
}

///|
/// Return the span of this character class set.
pub fn ClassSet::span(self : ClassSet) -> Span {
  match self {
    Item(x) => x.span()
    BinaryOp(x) => x.span
  }
}

///|
/// A single component of a character class set.
pub(all) enum ClassSetItem {
  /// An empty item.
  Empty(Span)
  /// A single literal.
  Literal(Literal)
  /// A range between two literals.
  Range(ClassSetRange)
  /// An ASCII character class, e.g., `[:alnum:]` or `[:punct:]`.
  Ascii(ClassAscii)
  /// A Unicode character class, e.g., `\pL` or `\p{Greek}`.
  Unicode(ClassUnicode)
  /// A perl character class, e.g., `\d` or `\W`.
  Perl(ClassPerl)
  /// A bracketed character class set.
  Bracketed(ClassBracketed)
  /// A union of items.
  Union(ClassSetUnion)
} derive(Eq, Debug)

///|
/// Return the span of this character class set item.
pub fn ClassSetItem::span(self : ClassSetItem) -> Span {
  match self {
    Empty(span) => span
    Literal(x) => x.span
    Range(x) => x.span
    Ascii(x) => x.span
    Perl(x) => x.span
    Unicode(x) => x.span
    Bracketed(x) => x.span
    Union(x) => x.span
  }
}

///|
/// A single character class range in a set.
pub(all) struct ClassSetRange {
  /// The span of this range.
  span : Span
  /// The start of this range.
  start : Literal
  /// The end of this range.
  end : Literal
} derive(Eq, Debug)

///|
/// Returns true if and only if this character class range is valid.
pub fn ClassSetRange::is_valid(self : ClassSetRange) -> Bool {
  self.start.c <= self.end.c
}

///|
/// A union of items inside a character class set.
pub(all) struct ClassSetUnion {
  /// The span of the items in this operation.
  mut span : Span
  /// The sequence of items that make up this union.
  items : Array[ClassSetItem]
} derive(Eq, Debug)

///|
/// Push a new item in this union.
///
/// The ending position of this union's span is updated to the ending
/// position of the span of the item given. If the union is empty, then
/// the starting position of this union is set to the starting position
/// of this item.
pub fn ClassSetUnion::push(self : ClassSetUnion, item : ClassSetItem) -> Unit {
  if self.items.is_empty() {
    self.span = { ..self.span, start: item.span().start, }
  }
  self.span = { ..self.span, end: item.span().end, }
  self.items.push(item)
}

///|
/// Return this union as a character class set item.
pub fn ClassSetUnion::into_item(self : ClassSetUnion) -> ClassSetItem {
  match self.items.length() {
    0 => Empty(self.span)
    1 => self.items.unsafe_pop()
    _ => Union(self)
  }
}

///|
/// A Unicode character class set operation.
pub(all) struct ClassSetBinaryOp {
  /// The span of this operation.
  span : Span
  /// The type of this set operation.
  kind : ClassSetBinaryOpKind
  /// The left hand side of the operation.
  mut lhs : ClassSet
  /// The right hand side of the operation.
  mut rhs : ClassSet
} derive(Eq, Debug)

///|
/// The type of a Unicode character class set operation.
pub(all) enum ClassSetBinaryOpKind {
  /// The intersection of two sets, e.g., `\pN&&[a-z]`.
  Intersection
  /// The difference of two sets, e.g., `\pN--[0-9]`.
  Difference
  /// The symmetric difference of two sets.
  SymmetricDifference
} derive(Eq, Debug)

///|
/// A single zero-width assertion.
pub(all) struct Assertion {
  /// The span of this assertion.
  mut span : Span
  /// The assertion kind, e.g., `\b` or `^`.
  mut kind : AssertionKind
} derive(Eq, Debug)

///|
/// An assertion kind.
pub(all) enum AssertionKind {
  /// `^`
  StartLine
  /// `$`
  EndLine
  /// `\A`
  StartText
  /// `\z`
  EndText
  /// `\b`
  WordBoundary
  /// `\B`
  NotWordBoundary
  /// `\b{start}`
  WordBoundaryStart
  /// `\b{end}`
  WordBoundaryEnd
  /// `\<` (alias for `\b{start}`)
  WordBoundaryStartAngle
  /// `\>` (alias for `\b{end}`)
  WordBoundaryEndAngle
  /// `\b{start-half}`
  WordBoundaryStartHalf
  /// `\b{end-half}`
  WordBoundaryEndHalf
} derive(Eq, Debug)

///|
/// A repetition operation applied to a regular expression.
pub(all) struct Repetition {
  /// The span of this operation.
  span : Span
  /// The actual operation.
  op : RepetitionOp
  /// Whether this operation was applied greedily or not.
  greedy : Bool
  /// The regular expression under repetition.
  mut ast : Ast
} derive(Eq, Debug)

///|
/// The repetition operator itself.
pub(all) struct RepetitionOp {
  /// The span of this operator. This includes things like `+`, `*?` and
  /// `{m,n}`.
  span : Span
  /// The type of operation.
  kind : RepetitionKind
} derive(Eq, Debug)

///|
/// The kind of a repetition operator.
pub(all) enum RepetitionKind {
  /// `?`
  ZeroOrOne
  /// `*`
  ZeroOrMore
  /// `+`
  OneOrMore
  /// `{m,n}`
  Range(RepetitionRange)
} derive(Eq, Debug)

///|
/// A range repetition operator.
pub(all) enum RepetitionRange {
  /// `{m}`
  Exactly(UInt32)
  /// `{m,}`
  AtLeast(UInt32)
  /// `{m,n}`
  Bounded(UInt32, UInt32)
} derive(Eq, Debug)

///|
/// Returns true if and only if this repetition range is valid.
pub fn RepetitionRange::is_valid(self : RepetitionRange) -> Bool {
  match self {
    Bounded(s, e) if s > e => false
    _ => true
  }
}

///|
/// A grouped regular expression.
pub(all) struct Group {
  /// The span of this group.
  mut span : Span
  /// The kind of this group.
  kind : GroupKind
  /// The regular expression in this group.
  mut ast : Ast
} derive(Eq, Debug)

///|
/// If this group is non-capturing, then this returns the (possibly empty)
/// set of flags. Otherwise, `None` is returned.
pub fn Group::flags(self : Group) -> Flags? {
  match self.kind {
    NonCapturing(flags) => Some(flags)
    _ => None
  }
}

///|
/// Returns true if and only if this group is capturing.
pub fn Group::is_capturing(self : Group) -> Bool {
  self.kind is (CaptureIndex(_) | CaptureName(..))
}

///|
/// Returns the capture index of this group, if this is a capturing group.
pub fn Group::capture_index(self : Group) -> UInt32? {
  match self.kind {
    CaptureIndex(i) => Some(i)
    CaptureName(name~, ..) => Some(name.index)
    NonCapturing(_) => None
  }
}

///|
/// The kind of a group.
pub(all) enum GroupKind {
  /// `(a)`
  CaptureIndex(UInt32)
  /// `(?<name>a)` or `(?P<name>a)`
  CaptureName(starts_with_p~ : Bool, name~ : CaptureName)
  /// `(?:a)` and `(?i:a)`
  NonCapturing(Flags)
} derive(Eq, Debug)

///|
/// A capture name.
pub(all) struct CaptureName {
  /// The span of this capture name.
  span : Span
  /// The capture name.
  name : String
  /// The capture index.
  index : UInt32
} derive(Eq, Debug)

///|
/// A group of flags that is not applied to a particular regular expression.
pub(all) struct SetFlags {
  /// The span of these flags, including the grouping parentheses.
  span : Span
  /// The actual sequence of flags.
  flags : Flags
} derive(Eq, Debug)

///|
/// A group of flags.
pub(all) struct Flags {
  /// The span of this group of flags.
  mut span : Span
  /// A sequence of flag items. Each item is either a flag or a negation
  /// operator.
  items : Array[FlagsItem]
} derive(Eq, Debug)

///|
/// Add the given item to this sequence of flags.
///
/// If the item was added successfully, then `None` is returned. If the
/// given item is a duplicate, then `Some(i)` is returned, where
/// `items[i].kind == item.kind`.
pub fn Flags::add_item(self : Flags, item : FlagsItem) -> Int32? {
  for i, x in self.items {
    if x.kind == item.kind {
      return Some(i)
    }
  }
  self.items.push(item)
  None
}

///|
/// Returns the state of the given flag in this set.
pub fn Flags::flag_state(self : Flags, flag : Flag) -> Bool? {
  let mut negated = false
  for x in self.items {
    match x.kind {
      Negation => negated = true
      Flag(xflag) if xflag == flag => return Some(!negated)
      _ => ()
    }
  }
  None
}

///|
/// A single item in a group of flags.
pub(all) struct FlagsItem {
  /// The span of this item.
  span : Span
  /// The kind of this item.
  kind : FlagsItemKind
} derive(Eq, Debug)

///|
/// The kind of an item in a group of flags.
pub(all) enum FlagsItemKind {
  /// A negation operator applied to all subsequent flags in the enclosing
  /// group.
  Negation
  /// A single flag in a group.
  Flag(Flag)
} derive(Eq, Debug)

///|
/// Returns true if and only if this item is a negation operator.
pub fn FlagsItemKind::is_negation(self : FlagsItemKind) -> Bool {
  self is Negation
}

///|
/// A single flag.
pub(all) enum Flag {
  /// `i`
  CaseInsensitive
  /// `m`
  MultiLine
  /// `s`
  DotMatchesNewLine
  /// `U`
  SwapGreed
  /// `u`
  Unicode
  /// `R`
  CRLF
  /// `x`
  IgnoreWhitespace
} derive(Eq, Debug)

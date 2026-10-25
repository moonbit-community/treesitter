// Port of regex-syntax 0.8.11 src/ast/parse.rs.
//
// This module provides a regular expression parser. Positions are UTF-8 byte
// offsets like upstream; the parser additionally tracks the char index that
// corresponds to the current byte offset to read the UTF-16 MoonBit string.

///|
/// A primitive is an expression with no sub-expressions. This includes
/// literals, assertions and non-set character classes. This representation
/// is used as intermediate state in the parser.
///
/// This does not include ASCII character classes, since they can only appear
/// within a set character class.
priv enum Primitive {
  Literal(Literal)
  Assertion(Assertion)
  Dot(Span)
  Perl(ClassPerl)
  Unicode(ClassUnicode)
}

///|
/// Return the span of this primitive.
fn Primitive::span(self : Primitive) -> Span {
  match self {
    Literal(x) => x.span
    Assertion(x) => x.span
    Dot(span) => span
    Perl(x) => x.span
    Unicode(x) => x.span
  }
}

///|
/// Convert this primitive into a proper AST.
fn Primitive::into_ast(self : Primitive) -> Ast {
  match self {
    Literal(lit) => Ast::Literal(lit)
    Assertion(assert) => Ast::Assertion(assert)
    Dot(span) => Ast::Dot(span)
    Perl(cls) => Ast::ClassPerl(cls)
    Unicode(cls) => Ast::ClassUnicode(cls)
  }
}

///|
/// Convert this primitive into an item in a character class.
///
/// If this primitive is not a legal item (i.e., an assertion or a dot),
/// then return an error.
fn Primitive::into_class_set_item(
  self : Primitive,
  p : ParserI,
) -> ClassSetItem raise AstError {
  match self {
    Literal(lit) => ClassSetItem::Literal(lit)
    Perl(cls) => ClassSetItem::Perl(cls)
    Unicode(cls) => ClassSetItem::Unicode(cls)
    x => raise p.error(x.span(), ClassEscapeInvalid)
  }
}

///|
/// Convert this primitive into a literal in a character class. In
/// particular, literals are the only valid items that can appear in
/// ranges.
///
/// If this primitive is not a legal item (i.e., a class, assertion or a
/// dot), then return an error.
fn Primitive::into_class_literal(
  self : Primitive,
  p : ParserI,
) -> Literal raise AstError {
  match self {
    Literal(lit) => lit
    x => raise p.error(x.span(), ClassRangeLiteral)
  }
}

///|
/// Returns true if the given character is a hexadecimal digit.
fn is_hex(c : Char) -> Bool {
  ('0' <= c && c <= '9') || ('a' <= c && c <= 'f') || ('A' <= c && c <= 'F')
}

///|
/// Returns true if the given character is a valid in a capture group name.
///
/// If `first` is true, then `c` is treated as the first character in the
/// group name (which must be alphabetic or underscore).
fn is_capture_char(c : Char, first : Bool) -> Bool {
  if first {
    c == '_' || is_alphabetic(c)
  } else {
    c == '_' || c == '.' || c == '[' || c == ']' || is_alphanumeric(c)
  }
}

///|
/// A builder for a regular expression parser.
///
/// This builder permits modifying configuration options for the parser.
pub struct ParserBuilder {
  priv mut ignore_whitespace : Bool
  priv mut nest_limit : UInt32
  priv mut octal : Bool
  priv mut empty_min_range : Bool
}

///|
/// Create a new parser builder with a default configuration.
pub fn ParserBuilder::new() -> ParserBuilder {
  {
    ignore_whitespace: false,
    nest_limit: 250,
    octal: false,
    empty_min_range: false,
  }
}

///|
/// Build a parser from this configuration with the given pattern.
pub fn ParserBuilder::build(self : ParserBuilder) -> Parser {
  {
    pos: { offset: 0, line: 1, column: 1, },
    capture_index: 0,
    nest_limit: self.nest_limit,
    octal: self.octal,
    empty_min_range: self.empty_min_range,
    initial_ignore_whitespace: self.ignore_whitespace,
    ignore_whitespace: self.ignore_whitespace,
    comments: [],
    stack_group: [],
    stack_class: [],
    capture_names: [],
  }
}

///|
/// Set the nesting limit for this parser.
pub fn ParserBuilder::nest_limit(
  self : ParserBuilder,
  limit : UInt32,
) -> ParserBuilder {
  self.nest_limit = limit
  self
}

///|
/// Whether to support octal syntax or not.
pub fn ParserBuilder::octal(self : ParserBuilder, yes : Bool) -> ParserBuilder {
  self.octal = yes
  self
}

///|
/// Enable verbose mode in the regular expression.
pub fn ParserBuilder::ignore_whitespace(
  self : ParserBuilder,
  yes : Bool,
) -> ParserBuilder {
  self.ignore_whitespace = yes
  self
}

///|
/// Allow using `{,n}` as an equivalent to `{0,n}`.
pub fn ParserBuilder::empty_min_range(
  self : ParserBuilder,
  yes : Bool,
) -> ParserBuilder {
  self.empty_min_range = yes
  self
}

///|
/// A regular expression parser.
///
/// This parses a string representation of a regular expression into an
/// abstract syntax tree. The size of the tree is proportional to the length
/// of the regular expression pattern.
pub struct Parser {
  /// The current position of the parser.
  priv mut pos : Position
  /// The current capture index.
  priv mut capture_index : UInt32
  /// The maximum number of open parens/brackets allowed.
  priv nest_limit : UInt32
  /// Whether to support octal syntax or not.
  priv octal : Bool
  /// The initial setting for `ignore_whitespace` as provided by
  /// `ParserBuilder`. It is used when resetting the parser's state.
  priv initial_ignore_whitespace : Bool
  /// Whether the parser supports `{,n}` repetitions as an equivalent to
  /// `{0,n}.`
  priv empty_min_range : Bool
  /// Whether whitespace should be ignored. When enabled, comments are
  /// also permitted.
  priv mut ignore_whitespace : Bool
  /// A list of comments, in order of appearance.
  priv comments : Array[Comment]
  /// A stack of grouped sub-expressions, including alternations.
  priv stack_group : Array[GroupState]
  /// A stack of nested character classes. This is only non-empty when
  /// parsing a class.
  priv stack_class : Array[ClassState]
  /// A sorted sequence of capture names. This is used to detect duplicate
  /// capture names and report an error if one is detected.
  priv capture_names : Array[CaptureName]
}

///|
/// ParserI is the internal parser implementation.
///
/// We use this separate type so that we can carry the provided pattern string
/// along with us. In particular, a `Parser` internal state is not tied to any
/// one pattern, but `ParserI` is.
priv struct ParserI {
  /// The parser state/configuration.
  parser : Parser
  /// The full regular expression provided by the user.
  pattern : String
  /// The chars of `pattern`.
  chars : Array[Char]
  /// The UTF-8 byte offset of every char of `pattern`, followed by the total
  /// UTF-8 length.
  offsets : Array[Int32]
  /// For every UTF-8 byte offset that starts a char (or is the end), the
  /// index of that char; -1 elsewhere.
  index_at : FixedArray[Int32]
}

///|
/// GroupState represents a single stack frame while parsing nested groups
/// and alternations. Each frame records the state up to an opening parenthesis
/// or a alternating bracket `|`.
priv enum GroupState {
  /// This state is pushed whenever an opening group is found.
  Group(concat~ : Concat, group~ : Group, ignore_whitespace~ : Bool)
  /// This state is pushed whenever a new alternation branch is found. If
  /// an alternation branch is found and this state is at the top of the
  /// stack, then this state should be modified to include the new
  /// alternation.
  Alternation(Alternation)
}

///|
/// ClassState represents a single stack frame while parsing character classes.
/// Each frame records the state up to an intersection, difference, symmetric
/// difference or nested class.
///
/// Note that a parser's character class stack is only non-empty when parsing
/// a character class. In all other cases, it is empty.
priv enum ClassState {
  /// This state is pushed whenever an opening bracket is found.
  Open(union~ : ClassSetUnion, set~ : ClassBracketed)
  /// This state is pushed when a operator is seen. When popped, the stored
  /// set becomes the left hand side of the operator.
  Op(kind~ : ClassSetBinaryOpKind, lhs~ : ClassSet)
}

///|
/// Create a new parser with a default configuration.
pub fn Parser::new() -> Parser {
  ParserBuilder::new().build()
}

///|
/// Parse the regular expression into an abstract syntax tree.
pub fn Parser::parse(self : Parser, pattern : String) -> Ast raise AstError {
  ParserI::new(self, pattern).parse()
}

///|
/// Parse the regular expression and return an abstract syntax tree with
/// all of the comments found in the pattern.
pub fn Parser::parse_with_comments(
  self : Parser,
  pattern : String,
) -> WithComments raise AstError {
  ParserI::new(self, pattern).parse_with_comments()
}

///|
/// Reset the internal state of a parser.
///
/// This is called at the beginning of every parse. This prevents the
/// parser from running with inconsistent state (say, if a previous
/// invocation returned an error and the parser is reused).
fn Parser::reset(self : Parser) -> Unit {
  // These settings should be in line with the construction
  // in `ParserBuilder::build`.
  self.pos = { offset: 0, line: 1, column: 1, }
  self.ignore_whitespace = self.initial_ignore_whitespace
  self.comments.clear()
  self.stack_group.clear()
  self.stack_class.clear()
}

///|
/// Build an internal parser from a parser configuration and a pattern.
fn ParserI::new(parser : Parser, pattern : String) -> ParserI {
  let chars = []
  let offsets = []
  let mut offset = 0
  for c in pattern {
    chars.push(c)
    offsets.push(offset)
    offset += len_utf8(c)
  }
  offsets.push(offset)
  let index_at = FixedArray::make(offset + 1, -1)
  for i, o in offsets {
    index_at[o] = i
  }
  { parser, pattern, chars, offsets, index_at, }
}

///|
/// Return a reference to the pattern being parsed.
fn ParserI::pattern(self : ParserI) -> String {
  self.pattern
}

///|
/// Create a new error with the given span and error type.
fn ParserI::error(self : ParserI, span : Span, kind : ErrorKind) -> AstError {
  AstError(kind~, pattern=self.pattern(), span~)
}

///|
/// Return the current offset of the parser.
///
/// The offset starts at `0` from the beginning of the regular expression
/// pattern string.
fn ParserI::offset(self : ParserI) -> Int32 {
  self.parser.pos.offset
}

///|
/// Return the current line number of the parser.
fn ParserI::line(self : ParserI) -> Int32 {
  self.parser.pos.line
}

///|
/// Return the current column of the parser.
fn ParserI::column(self : ParserI) -> Int32 {
  self.parser.pos.column
}

///|
/// The char index of the given byte offset.
fn ParserI::index_of(self : ParserI, offset : Int32) -> Int32 {
  let i = self.index_at[offset]
  guard i >= 0 else { abort("offset \{offset} is not a char boundary") }
  i
}

///|
/// The text between two byte offsets.
fn ParserI::slice(self : ParserI, start : Int32, end : Int32) -> String {
  String::from_array(self.chars[self.index_of(start):self.index_of(end)])
}

///|
/// Return the next capturing index. Each subsequent call increments the
/// internal index.
///
/// The span given should correspond to the location of the opening
/// parenthesis.
///
/// If the capture limit is exceeded, then an error is returned.
fn ParserI::next_capture_index(
  self : ParserI,
  span : Span,
) -> UInt32 raise AstError {
  let current = self.parser.capture_index
  if current == 4294967295U {
    raise self.error(span, CaptureLimitExceeded)
  }
  let i = current + 1
  self.parser.capture_index = i
  i
}

///|
/// Adds the given capture name to this parser. If this capture name has
/// already been used, then an error is returned.
fn ParserI::add_capture_name(
  self : ParserI,
  cap : CaptureName,
) -> Unit raise AstError {
  let names = self.parser.capture_names
  // `binary_search_by_key` on the names (byte-wise order).
  let mut lo = 0
  let mut hi = names.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let cmp = compare_utf8(names[mid].name, cap.name)
    if cmp == 0 {
      raise self.error(cap.span, GroupNameDuplicate(original=names[mid].span))
    } else if cmp < 0 {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  names.insert(lo, cap)
}

///|
/// Rust `str` ordering: byte-wise on UTF-8, which equals code point order.
fn compare_utf8(a : String, b : String) -> Int32 {
  let xs = a.iter().collect()
  let ys = b.iter().collect()
  let n = if xs.length() < ys.length() { xs.length() } else { ys.length() }
  for i in 0..<n {
    let c = xs[i].compare(ys[i])
    if c != 0 {
      return c
    }
  }
  xs.length().compare(ys.length())
}

///|
/// Return whether the parser should ignore whitespace or not.
fn ParserI::ignore_whitespace(self : ParserI) -> Bool {
  self.parser.ignore_whitespace
}

///|
/// Return the character at the current position of the parser.
///
/// This panics if the current position does not point to a valid char.
fn ParserI::char(self : ParserI) -> Char {
  self.char_at(self.offset())
}

///|
/// Return the character at the given position.
///
/// This panics if the given position does not point to a valid char.
fn ParserI::char_at(self : ParserI, i : Int32) -> Char {
  match self.chars.get(self.index_of(i)) {
    Some(c) => c
    None => abort("expected char at offset \{i}")
  }
}

///|
/// Bump the parser to the next Unicode scalar value.
///
/// If the end of the input has been reached, then `false` is returned.
fn ParserI::bump(self : ParserI) -> Bool {
  if self.is_eof() {
    return false
  }
  let { offset, line, column, } = self.pos()
  let (line, column) = if self.char() == '\n' {
    (line + 1, 1)
  } else {
    (line, column + 1)
  }
  let offset = offset + len_utf8(self.char())
  self.parser.pos = { offset, line, column, }
  !self.is_eof()
}

///|
/// If the substring starting at the current position of the parser has
/// the given prefix, then bump the parser to the character immediately
/// following the prefix and return true. Otherwise, don't bump the parser
/// and return false.
fn ParserI::bump_if(self : ParserI, prefix : String) -> Bool {
  let start = self.index_of(self.offset())
  let prefix_chars : Array[Char] = prefix.iter().collect()
  if start + prefix_chars.length() > self.chars.length() {
    return false
  }
  for i, c in prefix_chars {
    if self.chars[start + i] != c {
      return false
    }
  }
  for _ in 0..<prefix_chars.length() {
    ignore(self.bump())
  }
  true
}

///|
/// Returns true if and only if the parser is positioned at a look-around
/// prefix. The conditions under which this returns true must always
/// correspond to a regular expression that would otherwise be consider
/// invalid.
///
/// This should only be called immediately after parsing the opening of
/// a group or a set of flags.
fn ParserI::is_lookaround_prefix(self : ParserI) -> Bool {
  self.bump_if("?=") ||
  self.bump_if("?!") ||
  self.bump_if("?<=") ||
  self.bump_if("?<!")
}

///|
/// Bump the parser, and if the `x` flag is enabled, bump through any
/// subsequent spaces. Return true if and only if the parser is not at
/// EOF.
fn ParserI::bump_and_bump_space(self : ParserI) -> Bool {
  if !self.bump() {
    return false
  }
  self.bump_space()
  !self.is_eof()
}

///|
/// If the `x` flag is enabled (i.e., whitespace insensitivity with
/// comments), then this will advance the parser through all whitespace
/// and comments to the next non-whitespace non-comment byte.
///
/// If the `x` flag is disabled, then this is a no-op.
fn ParserI::bump_space(self : ParserI) -> Unit {
  if !self.ignore_whitespace() {
    return
  }
  while !self.is_eof() {
    if is_whitespace(self.char()) {
      ignore(self.bump())
    } else if self.char() == '#' {
      let start = self.pos()
      let comment_text = StringBuilder()
      ignore(self.bump())
      while !self.is_eof() {
        let c = self.char()
        ignore(self.bump())
        if c == '\n' {
          break
        }
        comment_text.write_char(c)
      }
      let comment = {
        span: Span::new(start, self.pos()),
        comment: comment_text.to_string(),
      }
      self.parser.comments.push(comment)
    } else {
      break
    }
  }
}

///|
/// Peek at the next character in the input without advancing the parser.
///
/// If the input has been exhausted, then this returns `None`.
fn ParserI::peek(self : ParserI) -> Char? {
  if self.is_eof() {
    return None
  }
  self.chars.get(self.index_of(self.offset()) + 1)
}

///|
/// Like peek, but will ignore spaces when the parser is in whitespace
/// insensitive mode.
fn ParserI::peek_space(self : ParserI) -> Char? {
  if !self.ignore_whitespace() {
    return self.peek()
  }
  if self.is_eof() {
    return None
  }
  let mut start = self.index_of(self.offset()) + 1
  let mut in_comment = false
  for i in start..<self.chars.length() {
    let c = self.chars[i]
    if is_whitespace(c) {
      continue
    } else if !in_comment && c == '#' {
      in_comment = true
    } else if in_comment && c == '\n' {
      in_comment = false
    } else {
      start = i
      break
    }
  }
  self.chars.get(start)
}

///|
/// Returns true if the next call to `bump` would return false.
fn ParserI::is_eof(self : ParserI) -> Bool {
  self.offset() == self.offsets[self.offsets.length() - 1]
}

///|
/// Return the current position of the parser, which includes the offset,
/// line and column.
fn ParserI::pos(self : ParserI) -> Position {
  self.parser.pos
}

///|
/// Create a span at the current position of the parser. Both the start
/// and end of the span are set.
fn ParserI::span(self : ParserI) -> Span {
  Span::splat(self.pos())
}

///|
/// Create a span that covers the current character.
fn ParserI::span_char(self : ParserI) -> Span {
  let mut next = Position::new(
    self.offset() + len_utf8(self.char()),
    self.line(),
    self.column() + 1,
  )
  if self.char() == '\n' {
    next = { ..next, line: next.line + 1, column: 1, }
  }
  Span::new(self.pos(), next)
}

///|
/// Parse and push a single alternation on to the parser's internal stack.
/// If the top of the stack already has an alternation, then add to that
/// instead of pushing a new one.
///
/// The concatenation given corresponds to a single alternation branch.
/// The concatenation returned starts the next branch and is empty.
///
/// This assumes the parser is currently positioned at `|` and will advance
/// the parser to the character following `|`.
fn ParserI::push_alternate(self : ParserI, concat : Concat) -> Concat {
  guard! self.char() == '|'
  concat.span = { ..concat.span, end: self.pos(), }
  self.push_or_add_alternation(concat)
  ignore(self.bump())
  { span: self.span(), asts: [], }
}

///|
/// Pushes or adds the given branch of an alternation to the parser's
/// internal stack of state.
fn ParserI::push_or_add_alternation(self : ParserI, concat : Concat) -> Unit {
  let stack = self.parser.stack_group
  if stack.last() is Some(Alternation(alts)) {
    alts.asts.push(concat.into_ast())
    return
  }
  stack.push(
    Alternation({
      span: Span::new(concat.span.start, self.pos()),
      asts: [concat.into_ast()],
    }),
  )
}

///|
/// Parse and push a group AST (and its parent concatenation) on to the
/// parser's internal stack. Return a fresh concatenation corresponding
/// to the group's sub-AST.
///
/// If a set of flags was found (with no group), then the concatenation
/// is returned with that set of flags added.
///
/// This assumes that the parser is currently positioned on the opening
/// parenthesis. It advances the parser to the character at the start
/// of the sub-expression (or adjoining expression).
///
/// If there was a problem parsing the start of the group, then an error
/// is returned.
fn ParserI::push_group(
  self : ParserI,
  concat : Concat,
) -> Concat raise AstError {
  guard! self.char() == '('
  match self.parse_group() {
    Left(set) => {
      let ignore = set.flags.flag_state(IgnoreWhitespace)
      if ignore is Some(v) {
        self.parser.ignore_whitespace = v
      }
      concat.asts.push(Flags(set))
      concat
    }
    Right(group) => {
      let old_ignore_whitespace = self.ignore_whitespace()
      let new_ignore_whitespace = (match group.flags() {
        Some(f) => f.flag_state(IgnoreWhitespace)
        None => None
      }).unwrap_or(old_ignore_whitespace)
      self.parser.stack_group.push(
        Group(concat~, group~, ignore_whitespace=old_ignore_whitespace),
      )
      self.parser.ignore_whitespace = new_ignore_whitespace
      { span: self.span(), asts: [], }
    }
  }
}

///|
/// Pop a group AST from the parser's internal stack and set the group's
/// AST to the given concatenation. Return the concatenation containing
/// the group.
///
/// This assumes that the parser is currently positioned on the closing
/// parenthesis and advances the parser to the character following the `)`.
///
/// If no such group could be popped, then an unopened group error is
/// returned.
fn ParserI::pop_group(
  self : ParserI,
  group_concat : Concat,
) -> Concat raise AstError {
  guard! self.char() == ')'
  let stack = self.parser.stack_group
  let (prior_concat, group, ignore_whitespace, alt) = match stack.pop() {
    Some(Group(concat~, group~, ignore_whitespace~)) =>
      (concat, group, ignore_whitespace, None)
    Some(Alternation(alt)) =>
      match stack.pop() {
        Some(Group(concat~, group~, ignore_whitespace~)) =>
          (concat, group, ignore_whitespace, Some(alt))
        None | Some(Alternation(_)) =>
          raise self.error(self.span_char(), GroupUnopened)
      }
    None => raise self.error(self.span_char(), GroupUnopened)
  }
  self.parser.ignore_whitespace = ignore_whitespace
  group_concat.span = { ..group_concat.span, end: self.pos(), }
  ignore(self.bump())
  group.span = { ..group.span, end: self.pos(), }
  match alt {
    Some(alt) => {
      alt.span = { ..alt.span, end: group_concat.span.end, }
      alt.asts.push(group_concat.into_ast())
      group.ast = alt.into_ast()
    }
    None => group.ast = group_concat.into_ast()
  }
  prior_concat.asts.push(Group(group))
  prior_concat
}

///|
/// Pop the last state from the parser's internal stack, if it exists, and
/// add the given concatenation to it. There either must be no state or a
/// single alternation item on the stack. Any other scenario produces an
/// error.
///
/// This assumes that the parser has advanced to the end.
fn ParserI::pop_group_end(
  self : ParserI,
  concat : Concat,
) -> Ast raise AstError {
  concat.span = { ..concat.span, end: self.pos(), }
  let stack = self.parser.stack_group
  let ast = match stack.pop() {
    None => concat.into_ast()
    Some(Alternation(alt)) => {
      alt.span = { ..alt.span, end: self.pos(), }
      alt.asts.push(concat.into_ast())
      Ast::Alternation(alt)
    }
    Some(Group(group~, ..)) => raise self.error(group.span, GroupUnclosed)
  }
  // If we try to pop again, there should be nothing.
  match stack.pop() {
    None => ast
    Some(Alternation(_)) =>
      // This unreachable is unfortunate. This case can't happen
      // because the only way we can be here is if there were two
      // `GroupState::Alternation`s adjacent in the parser's stack,
      // which we guarantee to never happen because we never push a
      // `GroupState::Alternation` if one is already at the top of
      // the stack.
      abort("unreachable")
    Some(Group(group~, ..)) => raise self.error(group.span, GroupUnclosed)
  }
}

///|
/// Parse the opening of a character class and push the current class
/// parsing context onto the parser's stack. This assumes that the parser
/// is positioned at an opening `[`. The given union should correspond to
/// the union of set items built up before seeing the `[`.
///
/// If there was a problem parsing the opening of the class, then an error
/// is returned. Otherwise, a new union of set items for the class is
/// returned (which may be populated with either a `]` or a `-`).
fn ParserI::push_class_open(
  self : ParserI,
  parent_union : ClassSetUnion,
) -> ClassSetUnion raise AstError {
  guard! self.char() == '['
  let (nested_set, nested_union) = self.parse_set_class_open()
  self.parser.stack_class.push(Open(union=parent_union, set=nested_set))
  nested_union
}

///|
/// Parse the end of a character class set and pop the character class
/// parser stack. The union given corresponds to the last union built
/// before seeing the closing `]`. The union returned corresponds to the
/// parent character class set with the nested class added to it.
///
/// This assumes that the parser is positioned at a `]` and will advance
/// the parser to the byte immediately following the `]`.
///
/// If the stack is empty after popping, then this returns the final
/// "top-level" character class AST (where a "top-level" character class
/// is one that is not nested inside any other character class).
///
/// If there is no corresponding opening bracket on the parser's stack,
/// then an error is returned.
fn ParserI::pop_class(
  self : ParserI,
  nested_union : ClassSetUnion,
) -> Either[ClassSetUnion, ClassBracketed] {
  guard! self.char() == ']'
  let item = ClassSet::Item(nested_union.into_item())
  let prevset = self.pop_class_op(item)
  let stack = self.parser.stack_class
  match stack.pop() {
    None =>
      // We can never observe an empty stack:
      //
      // 1) We are guaranteed to start with a non-empty stack since
      //    the character class parser is only initiated when it sees
      //    a `[`.
      // 2) If we ever observe an empty stack while popping after
      //    seeing a `]`, then we signal the character class parser
      //    to terminate.
      abort("unexpected empty character class stack")
    Some(Op(..)) =>
      // This panic is unfortunate, but this case is impossible
      // since we already popped the Op state if one exists above.
      // Namely, every push to the class parser stack is guarded by
      // whether an existing Op is already on the top of the stack.
      // If it is, the existing Op is modified. That is, the stack
      // can never have consecutive Op states.
      abort("unexpected ClassState::Op")
    Some(Open(union~, set~)) => {
      ignore(self.bump())
      set.span = { ..set.span, end: self.pos(), }
      set.kind = prevset
      if stack.is_empty() {
        Right(set)
      } else {
        union.push(Bracketed(set))
        Left(union)
      }
    }
  }
}

///|
/// Return an "unclosed class" error whose span points to the most
/// recently opened class.
///
/// This should only be called while parsing a character class.
fn ParserI::unclosed_class_error(self : ParserI) -> AstError {
  for state in self.parser.stack_class.rev_iter() {
    if state is Open(set~, ..) {
      return self.error(set.span, ClassUnclosed)
    }
  }
  // We are guaranteed to have a non-empty stack with at least
  // one open bracket, so we should never get here.
  abort("no open character class found")
}

///|
/// Push the current set of class items on to the class parser's stack as
/// the left hand side of the given operator.
///
/// A fresh set union is returned, which should be used to build the right
/// hand side of this operator.
fn ParserI::push_class_op(
  self : ParserI,
  next_kind : ClassSetBinaryOpKind,
  next_union : ClassSetUnion,
) -> ClassSetUnion {
  let item = ClassSet::Item(next_union.into_item())
  let new_lhs = self.pop_class_op(item)
  self.parser.stack_class.push(Op(kind=next_kind, lhs=new_lhs))
  { span: self.span(), items: [], }
}

///|
/// Pop a character class set from the character class parser stack. If the
/// top of the stack is just an item (not an operation), then return the
/// given set unchanged. If the top of the stack is an operation, then the
/// given set will be used as the rhs of the operation on the top of the
/// stack. In that case, the binary operation is returned as a set.
fn ParserI::pop_class_op(self : ParserI, rhs : ClassSet) -> ClassSet {
  let stack = self.parser.stack_class
  let (kind, lhs) = match stack.pop() {
    Some(Op(kind~, lhs~)) => (kind, lhs)
    Some(Open(..) as state) => {
      stack.push(state)
      return rhs
    }
    None => abort("unreachable")
  }
  let span = Span::new(lhs.span().start, rhs.span().end)
  BinaryOp({ span, kind, lhs, rhs, })
}

///|
/// Upstream's `either::Either`.
priv enum Either[L, R] {
  Left(L)
  Right(R)
}

///|
/// Parse the regular expression into an abstract syntax tree.
fn ParserI::parse(self : ParserI) -> Ast raise AstError {
  self.parse_with_comments().ast
}

///|
/// Parse the regular expression and return an abstract syntax tree with
/// all of the comments found in the pattern.
fn ParserI::parse_with_comments(self : ParserI) -> WithComments raise AstError {
  guard self.offset() == 0 else { abort("parser can only be used once") }
  self.parser.reset()
  let mut concat : Concat = { span: self.span(), asts: [], }
  while true {
    self.bump_space()
    if self.is_eof() {
      break
    }
    match self.char() {
      '(' => concat = self.push_group(concat)
      ')' => concat = self.pop_group(concat)
      '|' => concat = self.push_alternate(concat)
      '[' => {
        let class = self.parse_set_class()
        concat.asts.push(ClassBracketed(class))
      }
      '?' => concat = self.parse_uncounted_repetition(concat, ZeroOrOne)
      '*' => concat = self.parse_uncounted_repetition(concat, ZeroOrMore)
      '+' => concat = self.parse_uncounted_repetition(concat, OneOrMore)
      '{' => concat = self.parse_counted_repetition(concat)
      _ => concat.asts.push(self.parse_primitive().into_ast())
    }
  }
  let ast = self.pop_group_end(concat)
  NestLimiter::new(self).check(ast)
  let comments = self.parser.comments.copy()
  self.parser.comments.clear()
  { ast, comments, }
}

///|
/// Parses an uncounted repetition operation. An uncounted repetition
/// operator includes ?, * and +, but does not include the {m,n} syntax.
/// The given `kind` should correspond to the operator observed by the
/// caller.
///
/// This assumes that the parser is currently positioned at the repetition
/// operator and advances the parser to the first character after the
/// operator. (Note that the operator may include a single additional `?`,
/// which makes the operator ungreedy.)
///
/// The caller should include the concatenation that is being built. The
/// concatenation returned includes the repetition operator applied to the
/// last expression in the given concatenation.
fn ParserI::parse_uncounted_repetition(
  self : ParserI,
  concat : Concat,
  kind : RepetitionKind,
) -> Concat raise AstError {
  guard! self.char() == '?' || self.char() == '*' || self.char() == '+'
  let op_start = self.pos()
  let ast = match concat.asts.pop() {
    Some(ast) => ast
    None => raise self.error(self.span(), RepetitionMissing)
  }
  match ast {
    Empty(_) | Flags(_) => raise self.error(self.span(), RepetitionMissing)
    _ => ()
  }
  let mut greedy = true
  if self.bump() && self.char() == '?' {
    greedy = false
    ignore(self.bump())
  }
  concat.asts.push(
    Repetition({
      span: ast.span().with_end(self.pos()),
      op: { span: Span::new(op_start, self.pos()), kind, },
      greedy,
      ast,
    }),
  )
  concat
}

///|
/// Parses a counted repetition operation. A counted repetition operator
/// corresponds to the {m,n} syntax, and does not include the ?, * or +
/// operators.
///
/// This assumes that the parser is currently positioned at the opening `{`
/// and advances the parser to the first character after the operator.
/// (Note that the operator may include a single additional `?`, which
/// makes the operator ungreedy.)
///
/// The caller should include the concatenation that is being built. The
/// concatenation returned includes the repetition operator applied to the
/// last expression in the given concatenation.
fn ParserI::parse_counted_repetition(
  self : ParserI,
  concat : Concat,
) -> Concat raise AstError {
  guard! self.char() == '{'
  let start = self.pos()
  let ast = match concat.asts.pop() {
    Some(ast) => ast
    None => raise self.error(self.span(), RepetitionMissing)
  }
  match ast {
    Empty(_) | Flags(_) => raise self.error(self.span(), RepetitionMissing)
    _ => ()
  }
  if !self.bump_and_bump_space() {
    raise self.error(Span::new(start, self.pos()), RepetitionCountUnclosed)
  }
  let count_start = specialize_err(
    Ok(self.parse_decimal()) catch {
      e => Err(e)
    },
    DecimalEmpty,
    RepetitionCountDecimalEmpty,
  )
  if self.is_eof() {
    raise self.error(Span::new(start, self.pos()), RepetitionCountUnclosed)
  }
  let range = if self.char() == ',' {
    if !self.bump_and_bump_space() {
      raise self.error(Span::new(start, self.pos()), RepetitionCountUnclosed)
    }
    if self.char() != '}' {
      let count_start = match count_start {
        Ok(c) => c
        Err(err) if err.kind() == RepetitionCountDecimalEmpty =>
          if self.parser.empty_min_range {
            0U
          } else {
            raise err
          }
        Err(err) => raise err
      }
      let count_end = specialize_err(
        Ok(self.parse_decimal()) catch {
          e => Err(e)
        },
        DecimalEmpty,
        RepetitionCountDecimalEmpty,
      ).unwrap_or_error()
      RepetitionRange::Bounded(count_start, count_end)
    } else {
      RepetitionRange::AtLeast(count_start.unwrap_or_error())
    }
  } else {
    RepetitionRange::Exactly(count_start.unwrap_or_error())
  }
  if self.is_eof() || self.char() != '}' {
    raise self.error(Span::new(start, self.pos()), RepetitionCountUnclosed)
  }
  let mut greedy = true
  if self.bump_and_bump_space() && self.char() == '?' {
    greedy = false
    ignore(self.bump())
  }
  let op_span = Span::new(start, self.pos())
  if !range.is_valid() {
    raise self.error(op_span, RepetitionCountInvalid)
  }
  concat.asts.push(
    Repetition({
      span: ast.span().with_end(self.pos()),
      op: { span: op_span, kind: Range(range), },
      greedy,
      ast,
    }),
  )
  concat
}

///|
/// Parse a group (which contains a sub-expression) or a set of flags.
///
/// If a group was found, then it is returned with an empty AST. If a set
/// of flags is found, then that set is returned.
///
/// The parser should be positioned at the opening parenthesis.
///
/// This advances the parser to the character before the start of the
/// sub-expression (in the case of a group) or to the closing parenthesis
/// immediately following the set of flags.
///
/// # Errors
///
/// If flags are given and incorrectly specified, then a corresponding
/// error is returned.
///
/// If a capture name is given and it is incorrectly specified, then a
/// corresponding error is returned.
fn ParserI::parse_group(
  self : ParserI,
) -> Either[SetFlags, Group] raise AstError {
  guard! self.char() == '('
  let open_span = self.span_char()
  ignore(self.bump())
  self.bump_space()
  if self.is_lookaround_prefix() {
    raise self.error(
      Span::new(open_span.start, self.span().end),
      UnsupportedLookAround,
    )
  }
  let inner_span = self.span()
  let mut starts_with_p = true
  if self.bump_if("?P<") ||
    ({
      starts_with_p = false
      self.bump_if("?<")
    }) {
    let capture_index = self.next_capture_index(open_span)
    let name = self.parse_capture_name(capture_index)
    Right({
      span: open_span,
      kind: CaptureName(starts_with_p~, name~),
      ast: Empty(self.span()),
    })
  } else if self.bump_if("?") {
    if self.is_eof() {
      raise self.error(open_span, GroupUnclosed)
    }
    let flags = self.parse_flags()
    let char_end = self.char()
    ignore(self.bump())
    if char_end == ')' {
      // We don't allow empty flags, e.g., `(?)`. We instead
      // interpret it as a repetition operator missing its argument.
      if flags.items.is_empty() {
        raise self.error(inner_span, RepetitionMissing)
      }
      Left({ span: { ..open_span, end: self.pos(), }, flags, })
    } else {
      guard! char_end == ':'
      Right({
        span: open_span,
        kind: NonCapturing(flags),
        ast: Empty(self.span()),
      })
    }
  } else {
    let capture_index = self.next_capture_index(open_span)
    Right({
      span: open_span,
      kind: CaptureIndex(capture_index),
      ast: Empty(self.span()),
    })
  }
}

///|
/// Parses a capture group name. Assumes that the parser is positioned at
/// the first character in the name following the opening `<` (and may
/// possibly be EOF). This advances the parser to the first character
/// following the closing `>`.
///
/// The caller must provide the capture index of the group for this name.
fn ParserI::parse_capture_name(
  self : ParserI,
  capture_index : UInt32,
) -> CaptureName raise AstError {
  if self.is_eof() {
    raise self.error(self.span(), GroupNameUnexpectedEof)
  }
  let start = self.pos()
  while true {
    if self.char() == '>' {
      break
    }
    if !is_capture_char(self.char(), self.pos() == start) {
      raise self.error(self.span_char(), GroupNameInvalid)
    }
    if !self.bump() {
      break
    }
  }
  let end = self.pos()
  if self.is_eof() {
    raise self.error(self.span(), GroupNameUnexpectedEof)
  }
  guard! self.char() == '>'
  ignore(self.bump())
  let name = self.slice(start.offset, end.offset)
  if name.is_empty() {
    raise self.error(Span::new(start, start), GroupNameEmpty)
  }
  let capname = { span: Span::new(start, end), name, index: capture_index, }
  self.add_capture_name(capname)
  capname
}

///|
/// Parse a sequence of flags starting at the current character.
///
/// This advances the parser to the character immediately following the
/// flags, which is guaranteed to be either `:` or `)`.
///
/// # Errors
///
/// If any flags are duplicated, then an error is returned.
///
/// If the negation operator is used more than once, then an error is
/// returned.
///
/// If no flags could be found or if the negation operation is not followed
/// by any flags, then an error is returned.
fn ParserI::parse_flags(self : ParserI) -> Flags raise AstError {
  let flags : Flags = { span: self.span(), items: [], }
  let mut last_was_negation = None
  while self.char() != ':' && self.char() != ')' {
    if self.char() == '-' {
      last_was_negation = Some(self.span_char())
      let item : FlagsItem = { span: self.span_char(), kind: Negation, }
      if flags.add_item(item) is Some(i) {
        raise self.error(
          self.span_char(),
          FlagRepeatedNegation(original=flags.items[i].span),
        )
      }
    } else {
      last_was_negation = None
      let item : FlagsItem = {
        span: self.span_char(),
        kind: Flag(self.parse_flag()),
      }
      if flags.add_item(item) is Some(i) {
        raise self.error(
          self.span_char(),
          FlagDuplicate(original=flags.items[i].span),
        )
      }
    }
    if !self.bump() {
      raise self.error(self.span(), FlagUnexpectedEof)
    }
  }
  if last_was_negation is Some(span) {
    raise self.error(span, FlagDanglingNegation)
  }
  flags.span = { ..flags.span, end: self.pos(), }
  flags
}

///|
/// Parse the current character as a flag. Do not advance the parser.
///
/// # Errors
///
/// If the flag is not recognized, then an error is returned.
fn ParserI::parse_flag(self : ParserI) -> Flag raise AstError {
  match self.char() {
    'i' => CaseInsensitive
    'm' => MultiLine
    's' => DotMatchesNewLine
    'U' => SwapGreed
    'u' => Unicode
    'R' => CRLF
    'x' => IgnoreWhitespace
    _ => raise self.error(self.span_char(), FlagUnrecognized)
  }
}

///|
/// Parse a primitive AST. e.g., A literal, non-set character class or
/// assertion.
///
/// This assumes that the parser expects a primitive at the current
/// location. i.e., All other non-primitive cases have been handled.
/// For example, if the parser's position is at `|`, then `|` will be
/// treated as a literal (e.g., inside a character class).
///
/// This advances the parser to the first character immediately following
/// the primitive.
fn ParserI::parse_primitive(self : ParserI) -> Primitive raise AstError {
  match self.char() {
    '\\' => self.parse_escape()
    '.' => {
      let ast = Primitive::Dot(self.span_char())
      ignore(self.bump())
      ast
    }
    '^' => {
      let ast = Primitive::Assertion({
        span: self.span_char(),
        kind: StartLine,
      })
      ignore(self.bump())
      ast
    }
    '$' => {
      let ast = Primitive::Assertion({ span: self.span_char(), kind: EndLine, })
      ignore(self.bump())
      ast
    }
    c => {
      let ast = Primitive::Literal({
        span: self.span_char(),
        kind: Verbatim,
        c,
      })
      ignore(self.bump())
      ast
    }
  }
}

///|
/// Parse an escape sequence as a primitive AST.
///
/// This assumes the parser is positioned at the start of the escape
/// sequence, i.e., `\`. It advances the parser to the first position
/// immediately following the escape sequence.
fn ParserI::parse_escape(self : ParserI) -> Primitive raise AstError {
  guard! self.char() == '\\'
  let start = self.pos()
  if !self.bump() {
    raise self.error(Span::new(start, self.pos()), EscapeUnexpectedEof)
  }
  let c = self.char()
  // Put some of the more complicated routines into helpers.
  match c {
    '0'..<='7' => {
      if !self.parser.octal {
        raise self.error(
          Span::new(start, self.span_char().end),
          UnsupportedBackreference,
        )
      }
      let lit = self.parse_octal()
      lit.span = { ..lit.span, start, }
      return Primitive::Literal(lit)
    }
    '8'..<='9' if !self.parser.octal =>
      raise self.error(
        Span::new(start, self.span_char().end),
        UnsupportedBackreference,
      )
    'x' | 'u' | 'U' => {
      let lit = self.parse_hex()
      lit.span = { ..lit.span, start, }
      return Primitive::Literal(lit)
    }
    'p' | 'P' => {
      let cls = self.parse_unicode_class()
      cls.span = { ..cls.span, start, }
      return Primitive::Unicode(cls)
    }
    'd' | 's' | 'w' | 'D' | 'S' | 'W' => {
      let cls = self.parse_perl_class()
      cls.span = { ..cls.span, start, }
      return Primitive::Perl(cls)
    }
    _ => ()
  }

  // Handle all of the one letter sequences inline.
  ignore(self.bump())
  let span = Span::new(start, self.pos())
  if is_meta_character(c) {
    return Primitive::Literal({ span, kind: Meta, c, })
  }
  if is_escapeable_character(c) {
    return Primitive::Literal({ span, kind: Superfluous, c, })
  }
  let special = (kind, c) => {
    Primitive::Literal({ span, kind: Special(kind), c, })
  }
  match c {
    'a' => special(Bell, '\u{07}')
    'f' => special(FormFeed, '\u{0C}')
    't' => special(Tab, '\t')
    'n' => special(LineFeed, '\n')
    'r' => special(CarriageReturn, '\r')
    'v' => special(VerticalTab, '\u{0B}')
    'A' => Primitive::Assertion({ span, kind: StartText, })
    'z' => Primitive::Assertion({ span, kind: EndText, })
    'b' => {
      let wb : Assertion = { span, kind: WordBoundary, }
      // After a \b, we "try" to parse things like \b{start} for
      // special word boundary assertions.
      if !self.is_eof() && self.char() == '{' {
        if self.maybe_parse_special_word_boundary(start) is Some(kind) {
          wb.kind = kind
          wb.span = { ..wb.span, end: self.pos(), }
        }
      }
      Primitive::Assertion(wb)
    }
    'B' => Primitive::Assertion({ span, kind: NotWordBoundary, })
    '<' => Primitive::Assertion({ span, kind: WordBoundaryStartAngle, })
    '>' => Primitive::Assertion({ span, kind: WordBoundaryEndAngle, })
    _ => raise self.error(span, EscapeUnrecognized)
  }
}

///|
/// Attempt to parse a specialty word boundary. That is, `\b{start}`,
/// `\b{end}`, `\b{start-half}` or `\b{end-half}`.
///
/// This is similar to `maybe_parse_ascii_class` in that, in most cases,
/// if it fails it will just return `None` with no error. This is done
/// because `\b{5}` is a valid expression and we want to let that be parsed
/// by the existing counted repetition parsing code.
///
/// Unlike `maybe_parse_ascii_class` though, this can return an error.
/// Namely, if we definitely know it isn't a counted repetition, then we
/// return an error specific to the specialty word boundaries.
///
/// This assumes the parser is positioned at a `{` immediately following
/// a `\b`. When `None` is returned, the parser is returned to the position
/// at which it started: pointing at a `{`.
///
/// The position given should correspond to the start of the `\b`.
fn ParserI::maybe_parse_special_word_boundary(
  self : ParserI,
  wb_start : Position,
) -> AssertionKind? raise AstError {
  guard! self.char() == '{'
  let is_valid_char = (c : Char) => c is ('A'..<='Z' | 'a'..<='z' | '-')
  let start = self.pos()
  if !self.bump_and_bump_space() {
    raise self.error(
      Span::new(wb_start, self.pos()),
      SpecialWordOrRepetitionUnexpectedEof,
    )
  }
  let start_contents = self.pos()
  // This is one of the critical bits: if the first non-whitespace
  // character isn't in [-A-Za-z] (i.e., this can't be a special word
  // boundary), then we bail and let the counted repetition parser deal
  // with this.
  if !is_valid_char(self.char()) {
    self.parser.pos = start
    return None
  }

  // Now collect up our chars until we see a '}'.
  let scratch = StringBuilder()
  while !self.is_eof() && is_valid_char(self.char()) {
    scratch.write_char(self.char())
    ignore(self.bump_and_bump_space())
  }
  if self.is_eof() || self.char() != '}' {
    raise self.error(Span::new(start, self.pos()), SpecialWordBoundaryUnclosed)
  }
  let end = self.pos()
  ignore(self.bump())
  let kind : AssertionKind = match scratch.to_string() {
    "start" => WordBoundaryStart
    "end" => WordBoundaryEnd
    "start-half" => WordBoundaryStartHalf
    "end-half" => WordBoundaryEndHalf
    _ =>
      raise self.error(
        Span::new(start_contents, end),
        SpecialWordBoundaryUnrecognized,
      )
  }
  Some(kind)
}

///|
/// Parse an octal representation of a Unicode codepoint up to 3 digits
/// long. This expects the parser to be positioned at the first octal
/// digit and advances the parser to the first character immediately
/// following the octal number. This also assumes that parsing octal
/// escapes is enabled.
///
/// Assuming the preconditions are met, this routine can never fail.
fn ParserI::parse_octal(self : ParserI) -> Literal {
  guard! self.parser.octal
  guard! '0' <= self.char() && self.char() <= '7'
  let start = self.pos()
  // Parse up to two more digits.
  while self.bump() &&
        '0' <= self.char() &&
        self.char() <= '7' &&
        self.pos().offset - start.offset <= 2 {

  }
  let end = self.pos()
  let octal = self.slice(start.offset, end.offset)
  // Parsing the octal should never fail since the above guarantees a
  // valid number.
  let mut codepoint = 0
  for d in octal {
    codepoint = codepoint * 8 + (d.to_int() - '0'.to_int())
  }
  // The max value for 3 digit octal is 0777 = 511 and [0, 511] has no
  // invalid Unicode scalar values.
  let c = codepoint.to_char().unwrap()
  { span: Span::new(start, end), kind: Octal, c, }
}

///|
/// Parse a hex representation of a Unicode codepoint. This handles both
/// hex notations, i.e., `\xFF` and `\x{FFFF}`. This expects the parser to
/// be positioned at the `x`, `u` or `U` prefix. The parser is advanced to
/// the first character immediately following the hexadecimal literal.
fn ParserI::parse_hex(self : ParserI) -> Literal raise AstError {
  guard! self.char() == 'x' || self.char() == 'u' || self.char() == 'U'
  let hex_kind : HexLiteralKind = match self.char() {
    'x' => X
    'u' => UnicodeShort
    _ => UnicodeLong
  }
  if !self.bump_and_bump_space() {
    raise self.error(self.span(), EscapeUnexpectedEof)
  }
  if self.char() == '{' {
    self.parse_hex_brace(hex_kind)
  } else {
    self.parse_hex_digits(hex_kind)
  }
}

///|
/// `u32::from_str_radix(hex, 16).ok().and_then(char::from_u32)`.
fn hex_to_char(hex : String) -> Char? {
  let mut value = 0L
  for c in hex {
    let d = if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 'a'.to_int() + 10
    } else {
      c.to_int() - 'A'.to_int() + 10
    }
    value = value * 16L + d.to_int64()
    if value > 0xFFFFFFFFL {
      return None
    }
  }
  if value > 0x10FFFFL {
    return None
  }
  value.to_int().to_char()
}

///|
/// Parse an N-digit hex representation of a Unicode codepoint. This
/// expects the parser to be positioned at the first digit and will advance
/// the parser to the first character immediately following the escape
/// sequence.
///
/// The number of digits given must be 2 (for `\xNN`), 4 (for `\uNNNN`)
/// or 8 (for `\UNNNNNNNN`).
fn ParserI::parse_hex_digits(
  self : ParserI,
  kind : HexLiteralKind,
) -> Literal raise AstError {
  let scratch = StringBuilder()
  let start = self.pos()
  for i in 0..<kind.digits() {
    if i > 0 && !self.bump_and_bump_space() {
      raise self.error(self.span(), EscapeUnexpectedEof)
    }
    if !is_hex(self.char()) {
      raise self.error(self.span_char(), EscapeHexInvalidDigit)
    }
    scratch.write_char(self.char())
  }
  // The final bump just moves the parser past the literal, which may
  // be EOF.
  ignore(self.bump_and_bump_space())
  let end = self.pos()
  match hex_to_char(scratch.to_string()) {
    None => raise self.error(Span::new(start, end), EscapeHexInvalid)
    Some(c) => { span: Span::new(start, end), kind: HexFixed(kind), c, }
  }
}

///|
/// Parse a hex representation of any Unicode scalar value. This expects
/// the parser to be positioned at the opening brace `{` and will advance
/// the parser to the first character following the closing brace `}`.
fn ParserI::parse_hex_brace(
  self : ParserI,
  kind : HexLiteralKind,
) -> Literal raise AstError {
  let scratch = StringBuilder()
  let brace_pos = self.pos()
  let start = self.span_char().end
  while self.bump_and_bump_space() && self.char() != '}' {
    if !is_hex(self.char()) {
      raise self.error(self.span_char(), EscapeHexInvalidDigit)
    }
    scratch.write_char(self.char())
  }
  if self.is_eof() {
    raise self.error(Span::new(brace_pos, self.pos()), EscapeUnexpectedEof)
  }
  let end = self.pos()
  let hex = scratch.to_string()
  guard! self.char() == '}'
  ignore(self.bump_and_bump_space())
  if hex.is_empty() {
    raise self.error(Span::new(brace_pos, self.pos()), EscapeHexEmpty)
  }
  match hex_to_char(hex) {
    None => raise self.error(Span::new(start, end), EscapeHexInvalid)
    Some(c) => { span: Span::new(start, self.pos()), kind: HexBrace(kind), c, }
  }
}

///|
/// Parse a decimal number into a u32 while trimming leading and trailing
/// whitespace.
///
/// This expects the parser to be positioned at the first position where
/// a decimal digit could occur. This will advance the parser to the byte
/// immediately following the last contiguous decimal digit.
///
/// If no decimal digit could be found or if there was a problem parsing
/// the complete set of digits into a u32, then an error is returned.
fn ParserI::parse_decimal(self : ParserI) -> UInt32 raise AstError {
  let scratch = StringBuilder()
  while !self.is_eof() && is_whitespace(self.char()) {
    ignore(self.bump())
  }
  let start = self.pos()
  while !self.is_eof() && '0' <= self.char() && self.char() <= '9' {
    scratch.write_char(self.char())
    ignore(self.bump_and_bump_space())
  }
  let span = Span::new(start, self.pos())
  while !self.is_eof() && is_whitespace(self.char()) {
    ignore(self.bump_and_bump_space())
  }
  let digits = scratch.to_string()
  if digits.is_empty() {
    raise self.error(span, DecimalEmpty)
  }
  let mut value = 0L
  for d in digits {
    value = value * 10L + (d.to_int() - '0'.to_int()).to_int64()
    if value > 0xFFFFFFFFL {
      raise self.error(span, DecimalInvalid)
    }
  }
  value.to_int().reinterpret_as_uint()
}

///|
/// Parse a standard character class consisting primarily of characters or
/// character ranges, but can also contain nested character classes of
/// any type (sans `.`).
///
/// This assumes the parser is positioned at the opening `[`. If parsing
/// is successful, then the parser is advanced to the position immediately
/// following the closing `]`.
fn ParserI::parse_set_class(self : ParserI) -> ClassBracketed raise AstError {
  guard! self.char() == '['
  let mut union : ClassSetUnion = { span: self.span(), items: [], }
  while true {
    self.bump_space()
    if self.is_eof() {
      raise self.unclosed_class_error()
    }
    match self.char() {
      '[' => {
        // If we've already parsed the opening bracket, then
        // attempt to treat this as the beginning of an ASCII
        // class. If ASCII class parsing fails, then the parser
        // backs up to `[`.
        if !self.parser.stack_class.is_empty() {
          if self.maybe_parse_ascii_class() is Some(cls) {
            union.push(Ascii(cls))
            continue
          }
        }
        union = self.push_class_open(union)
      }
      ']' =>
        match self.pop_class(union) {
          Left(nested_union) => union = nested_union
          Right(class) => return class
        }
      '&' if self.peek() == Some('&') => {
        guard! self.bump_if("&&")
        union = self.push_class_op(Intersection, union)
      }
      '-' if self.peek() == Some('-') => {
        guard! self.bump_if("--")
        union = self.push_class_op(Difference, union)
      }
      '~' if self.peek() == Some('~') => {
        guard! self.bump_if("~~")
        union = self.push_class_op(SymmetricDifference, union)
      }
      _ => union.push(self.parse_set_class_range())
    }
  }
  abort("unreachable")
}

///|
/// Parse a single primitive item in a character class set. The item to
/// be parsed can either be one of a simple literal character, a range
/// between two simple literal characters or a "primitive" character
/// class like \w or \p{Greek}.
///
/// If an invalid escape is found, or if a character class is found where
/// a simple literal is expected (e.g., in a range), then an error is
/// returned.
fn ParserI::parse_set_class_range(
  self : ParserI,
) -> ClassSetItem raise AstError {
  let prim1 = self.parse_set_class_item()
  self.bump_space()
  if self.is_eof() {
    raise self.unclosed_class_error()
  }
  // If the next char isn't a `-`, then we don't have a range.
  // There are two exceptions. If the char after a `-` is a `]`, then
  // `-` is interpreted as a literal `-`. Alternatively, if the char
  // after a `-` is a `-`, then `--` corresponds to a "difference"
  // operation.
  if self.char() != '-' ||
    self.peek_space() == Some(']') ||
    self.peek_space() == Some('-') {
    return prim1.into_class_set_item(self)
  }
  // OK, now we're parsing a range, so bump past the `-` and parse the
  // second half of the range.
  if !self.bump_and_bump_space() {
    raise self.unclosed_class_error()
  }
  let prim2 = self.parse_set_class_item()
  let range : ClassSetRange = {
    span: Span::new(prim1.span().start, prim2.span().end),
    start: prim1.into_class_literal(self),
    end: prim2.into_class_literal(self),
  }
  if !range.is_valid() {
    raise self.error(range.span, ClassRangeInvalid)
  }
  Range(range)
}

///|
/// Parse a single item in a character class as a primitive, where the
/// primitive either consists of a verbatim literal or a single escape
/// sequence.
///
/// This assumes the parser is positioned at the beginning of a primitive,
/// and advances the parser to the first position after the primitive if
/// successful.
///
/// Note that it is the caller's responsibility to report an error if an
/// illegal primitive was parsed.
fn ParserI::parse_set_class_item(self : ParserI) -> Primitive raise AstError {
  if self.char() == '\\' {
    self.parse_escape()
  } else {
    let x = Primitive::Literal({
      span: self.span_char(),
      kind: Verbatim,
      c: self.char(),
    })
    ignore(self.bump())
    x
  }
}

///|
/// Parses the opening of a character class set. This includes the opening
/// bracket along with `^` if present to indicate negation. This also
/// starts parsing the opening set of unioned items if applicable, since
/// there are special rules applied to certain characters in the opening
/// of a character class. For example, `[^]]` is the class of all
/// characters not equal to `]`. (`]` would need to be escaped in any other
/// position.) Similarly for `-`.
///
/// In all cases, the op inside the returned `ast::ClassBracketed` is an
/// empty union. This empty union should be replaced with the actual item
/// when it is popped from the parser's stack.
///
/// This assumes the parser is positioned at the opening `[` and advances
/// the parser to the first non-special byte of the character class.
///
/// An error is returned if EOF is found.
fn ParserI::parse_set_class_open(
  self : ParserI,
) -> (ClassBracketed, ClassSetUnion) raise AstError {
  guard! self.char() == '['
  let start = self.pos()
  if !self.bump_and_bump_space() {
    raise self.error(Span::new(start, self.pos()), ClassUnclosed)
  }
  let negated = if self.char() != '^' {
    false
  } else {
    if !self.bump_and_bump_space() {
      raise self.error(Span::new(start, self.pos()), ClassUnclosed)
    }
    true
  }
  // Accept any number of `-` as literal `-`.
  let union : ClassSetUnion = { span: self.span(), items: [], }
  while self.char() == '-' {
    union.push(Literal({ span: self.span_char(), kind: Verbatim, c: '-', }))
    if !self.bump_and_bump_space() {
      raise self.error(Span::new(start, start), ClassUnclosed)
    }
  }
  // If `]` is the *first* char in a set, then interpret it as a literal
  // `]`. That is, an empty class is impossible to write.
  if union.items.is_empty() && self.char() == ']' {
    union.push(Literal({ span: self.span_char(), kind: Verbatim, c: ']', }))
    if !self.bump_and_bump_space() {
      raise self.error(Span::new(start, self.pos()), ClassUnclosed)
    }
  }
  let set : ClassBracketed = {
    span: Span::new(start, self.pos()),
    negated,
    kind: ClassSet::union({
      span: Span::new(union.span.start, union.span.start),
      items: [],
    }),
  }
  (set, union)
}

///|
/// Attempt to parse an ASCII character class, e.g., `[:alnum:]`.
///
/// This assumes the parser is positioned at the opening `[`.
///
/// If no valid ASCII character class could be found, then this does not
/// advance the parser and `None` is returned. Otherwise, the parser is
/// advanced to the first byte following the closing `]` and the
/// corresponding ASCII class is returned.
fn ParserI::maybe_parse_ascii_class(self : ParserI) -> ClassAscii? {
  // ASCII character classes are interesting from a parsing perspective
  // because parsing cannot fail with any interesting error. For example,
  // in order to use an ASCII character class, it must be enclosed in
  // double brackets, e.g., `[[:alnum:]]`. Alternatively, you might think
  // of it as "ASCII character classes have the syntax `[:NAME:]` which
  // can only appear within character brackets." This means that things
  // like `[[:lower:]A]` are legal constructs.
  //
  // However, if one types an incorrect ASCII character class, e.g.,
  // `[[:loower:]]`, then we treat that as a normal nested character
  // class containing the characters `:elorw`. One might argue that we
  // should return an error instead since the repeated colons give away
  // the intent to write an ASCII class. But what if the user typed
  // `[[:lower]]` instead? How can we tell that was intended to be an
  // ASCII class and not just a normal nested class?
  //
  // Reasonable people can probably disagree over this, but for better
  // or worse, we implement semantics that never fails at the expense
  // of better failure modes.
  guard! self.char() == '['
  // If parsing fails, then we back up the parser to this starting point.
  let start = self.pos()
  let mut negated = false
  if !self.bump() || self.char() != ':' {
    self.parser.pos = start
    return None
  }
  if !self.bump() {
    self.parser.pos = start
    return None
  }
  if self.char() == '^' {
    negated = true
    if !self.bump() {
      self.parser.pos = start
      return None
    }
  }
  let name_start = self.offset()
  while self.char() != ':' && self.bump() {

  }
  if self.is_eof() {
    self.parser.pos = start
    return None
  }
  let name = self.slice(name_start, self.offset())
  if !self.bump_if(":]") {
    self.parser.pos = start
    return None
  }
  let kind = match ClassAsciiKind::from_name(name) {
    Some(kind) => kind
    None => {
      self.parser.pos = start
      return None
    }
  }
  Some({ span: Span::new(start, self.pos()), kind, negated, })
}

///|
/// Parse a Unicode class in either the single character notation, `\pN`
/// or the multi-character bracketed notation, `\p{Greek}`. This assumes
/// the parser is positioned at the `p` (or `P` for negation) and will
/// advance the parser to the character immediately following the class.
///
/// Note that this does not check whether the class name is valid or not.
fn ParserI::parse_unicode_class(self : ParserI) -> ClassUnicode raise AstError {
  guard! self.char() == 'p' || self.char() == 'P'
  let scratch = StringBuilder()
  let negated = self.char() == 'P'
  if !self.bump_and_bump_space() {
    raise self.error(self.span(), EscapeUnexpectedEof)
  }
  let (start, kind) = if self.char() == '{' {
    let start = self.span_char().end
    while self.bump_and_bump_space() && self.char() != '}' {
      scratch.write_char(self.char())
    }
    if self.is_eof() {
      raise self.error(self.span(), EscapeUnexpectedEof)
    }
    guard! self.char() == '}'
    ignore(self.bump())
    let name = scratch.to_string()
    if name.find("!=") is Some(i) {
      (
        start,
        ClassUnicodeKind::NamedValue(
          op=NotEqual,
          name=name.view(end_offset=i).to_owned(),
          value=name.view(start_offset=i + 2).to_owned(),
        ),
      )
    } else if name.find(":") is Some(i) {
      (
        start,
        ClassUnicodeKind::NamedValue(
          op=Colon,
          name=name.view(end_offset=i).to_owned(),
          value=name.view(start_offset=i + 1).to_owned(),
        ),
      )
    } else if name.find("=") is Some(i) {
      (
        start,
        ClassUnicodeKind::NamedValue(
          op=Equal,
          name=name.view(end_offset=i).to_owned(),
          value=name.view(start_offset=i + 1).to_owned(),
        ),
      )
    } else {
      (start, ClassUnicodeKind::Named(name))
    }
  } else {
    let start = self.pos()
    let c = self.char()
    if c == '\\' {
      raise self.error(self.span_char(), UnicodeClassInvalid)
    }
    ignore(self.bump_and_bump_space())
    let kind = ClassUnicodeKind::OneLetter(c)
    (start, kind)
  }
  { span: Span::new(start, self.pos()), negated, kind, }
}

///|
/// Parse a Perl character class, e.g., `\d` or `\W`. This assumes the
/// parser is currently at a valid character class name and will be
/// advanced to the character immediately following the class.
fn ParserI::parse_perl_class(self : ParserI) -> ClassPerl {
  let c = self.char()
  let span = self.span_char()
  ignore(self.bump())
  let (negated, kind) : (Bool, ClassPerlKind) = match c {
    'd' => (false, Digit)
    'D' => (true, Digit)
    's' => (false, Space)
    'S' => (true, Space)
    'w' => (false, Word)
    'W' => (true, Word)
    c => abort("expected valid Perl class but got '\{c}'")
  }
  { span, kind, negated, }
}

///|
/// A type that traverses a fully parsed Ast and checks whether its depth
/// exceeds the specified nesting limit. If it does, then an error is returned.
priv struct NestLimiter {
  /// The parser that is checking the nest limit.
  p : ParserI
  /// The current depth while walking an Ast.
  mut depth : UInt32
}

///|
fn NestLimiter::new(p : ParserI) -> NestLimiter {
  { p, depth: 0, }
}

///|
fn NestLimiter::check(self : NestLimiter, ast : Ast) -> Unit raise AstError {
  visit(ast, self) catch {
    AstError(_) as e => raise e
    _ => abort("unreachable")
  }
}

///|
fn NestLimiter::increment_depth(
  self : NestLimiter,
  span : Span,
) -> Unit raise AstError {
  if self.depth == 4294967295U {
    raise self.p.error(span, NestLimitExceeded(4294967295U))
  }
  let new = self.depth + 1
  let limit = self.p.parser.nest_limit
  if new > limit {
    raise self.p.error(span, NestLimitExceeded(limit))
  }
  self.depth = new
}

///|
fn NestLimiter::decrement_depth(self : NestLimiter) -> Unit {
  // Assuming the correctness of the visitor, this should never drop
  // below 0.
  guard! self.depth > 0
  self.depth = self.depth - 1
}

///|
impl Visitor for NestLimiter with fn visit_pre(self, ast) {
  let span = match ast {
    Empty(_)
    | Flags(_)
    | Literal(_)
    | Dot(_)
    | Assertion(_)
    | ClassUnicode(_)
    | ClassPerl(_) =>
      // These are all base cases, so we don't increment depth.
      return
    ClassBracketed(x) => x.span
    Repetition(x) => x.span
    Group(x) => x.span
    Alternation(x) => x.span
    Concat(x) => x.span
  }
  self.increment_depth(span)
}

///|
impl Visitor for NestLimiter with fn visit_post(self, ast) {
  match ast {
    Empty(_)
    | Flags(_)
    | Literal(_)
    | Dot(_)
    | Assertion(_)
    | ClassUnicode(_)
    | ClassPerl(_) =>
      // These are all base cases, so we don't decrement depth.
      ()
    ClassBracketed(_) | Repetition(_) | Group(_) | Alternation(_) | Concat(_) =>
      self.decrement_depth()
  }
}

///|
impl Visitor for NestLimiter with fn visit_class_set_item_pre(self, ast) {
  let span = match ast {
    Empty(_) | Literal(_) | Range(_) | Ascii(_) | Unicode(_) | Perl(_) =>
      // These are all base cases, so we don't increment depth.
      return
    Bracketed(x) => x.span
    Union(x) => x.span
  }
  self.increment_depth(span)
}

///|
impl Visitor for NestLimiter with fn visit_class_set_item_post(self, ast) {
  match ast {
    Empty(_) | Literal(_) | Range(_) | Ascii(_) | Unicode(_) | Perl(_) =>
      // These are all base cases, so we don't decrement depth.
      ()
    Bracketed(_) | Union(_) => self.decrement_depth()
  }
}

///|
impl Visitor for NestLimiter with fn visit_class_set_binary_op_pre(self, ast) {
  self.increment_depth(ast.span)
}

///|
impl Visitor for NestLimiter with fn visit_class_set_binary_op_post(self, _ast) {
  self.decrement_depth()
}

///|
/// When the result is an error, transforms the ast::ErrorKind from the source
/// Result into another one. This function is used to return clearer error
/// messages when possible.
#warnings("-result_error_return")
fn[T] specialize_err(
  result : Result[T, AstError],
  from : ErrorKind,
  to : ErrorKind,
) -> Result[T, AstError] {
  match result {
    Err(e) =>
      if e.kind() == from {
        Err(AstError(kind=to, pattern=e.pattern(), span=e.span()))
      } else {
        Err(e)
      }
    Ok(_) => result
  }
}

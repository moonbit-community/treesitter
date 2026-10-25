// Port of regex-syntax 0.8.11 src/hir/translate.rs.
//
// Defines a translator that converts an `Ast` to an `Hir`.

///|
/// A builder for constructing an AST->HIR translator.
pub struct TranslatorBuilder {
  priv mut utf8 : Bool
  priv mut line_terminator : Byte
  priv mut flags : Flags
}

///|
/// Create a new translator builder with a default configuration.
pub fn TranslatorBuilder::new() -> TranslatorBuilder {
  { utf8: true, line_terminator: b'\n', flags: Flags::default(), }
}

///|
/// Build a translator using the current configuration.
pub fn TranslatorBuilder::build(self : TranslatorBuilder) -> Translator {
  {
    stack: [],
    flags: self.flags,
    utf8: self.utf8,
    line_terminator: self.line_terminator,
  }
}

///|
/// When disabled, translation will permit the construction of a regular
/// expression that may match invalid UTF-8.
///
/// When enabled (the default), the translator is guaranteed to produce an
/// expression that, for non-empty matches, will only ever produce spans
/// that are entirely valid UTF-8 (otherwise, the translator will return an
/// error).
pub fn TranslatorBuilder::utf8(
  self : TranslatorBuilder,
  yes : Bool,
) -> TranslatorBuilder {
  self.utf8 = yes
  self
}

///|
/// Sets the line terminator for use with `(?u-s:.)` and `(?-us:.)`.
pub fn TranslatorBuilder::line_terminator(
  self : TranslatorBuilder,
  byte : Byte,
) -> TranslatorBuilder {
  self.line_terminator = byte
  self
}

///|
/// Enable or disable the case insensitive flag (`i`) by default.
pub fn TranslatorBuilder::case_insensitive(
  self : TranslatorBuilder,
  yes : Bool,
) -> TranslatorBuilder {
  self.flags = {
    ..self.flags,
    case_insensitive: if yes {
      Some(true)
    } else {
      None
    },
  }
  self
}

///|
/// Enable or disable the multi-line matching flag (`m`) by default.
pub fn TranslatorBuilder::multi_line(
  self : TranslatorBuilder,
  yes : Bool,
) -> TranslatorBuilder {
  self.flags = {
    ..self.flags,
    multi_line: if yes {
      Some(true)
    } else {
      None
    },
  }
  self
}

///|
/// Enable or disable the "dot matches any character" flag (`s`) by
/// default.
pub fn TranslatorBuilder::dot_matches_new_line(
  self : TranslatorBuilder,
  yes : Bool,
) -> TranslatorBuilder {
  self.flags = {
    ..self.flags,
    dot_matches_new_line: if yes {
      Some(true)
    } else {
      None
    },
  }
  self
}

///|
/// Enable or disable the CRLF mode flag (`R`) by default.
pub fn TranslatorBuilder::crlf(
  self : TranslatorBuilder,
  yes : Bool,
) -> TranslatorBuilder {
  self.flags = { ..self.flags, crlf: if yes { Some(true) } else { None }, }
  self
}

///|
/// Enable or disable the "swap greed" flag (`U`) by default.
pub fn TranslatorBuilder::swap_greed(
  self : TranslatorBuilder,
  yes : Bool,
) -> TranslatorBuilder {
  self.flags = {
    ..self.flags,
    swap_greed: if yes {
      Some(true)
    } else {
      None
    },
  }
  self
}

///|
/// Enable or disable the Unicode flag (`u`) by default.
pub fn TranslatorBuilder::unicode(
  self : TranslatorBuilder,
  yes : Bool,
) -> TranslatorBuilder {
  self.flags = { ..self.flags, unicode: if yes { None } else { Some(false) }, }
  self
}

///|
/// A translator maps abstract syntax to a high level intermediate
/// representation.
///
/// A translator may be benefit from reuse. That is, a translator can translate
/// many abstract syntax trees. Like upstream, its stack and active flags
/// persist across calls to `translate`.
pub struct Translator {
  /// Our call stack, but on the heap.
  priv stack : Array[HirFrame]
  /// The current flag settings.
  priv mut flags : Flags
  /// Whether we're allowed to produce HIR that can match arbitrary bytes.
  priv utf8 : Bool
  /// The line terminator to use for `.`.
  priv line_terminator : Byte
}

///|
/// Create a new translator using the default configuration.
pub fn Translator::new() -> Translator {
  TranslatorBuilder::new().build()
}

///|
/// Translate the given abstract syntax tree (AST) into a high level
/// intermediate representation (HIR).
///
/// If there was a problem doing the translation, then an HIR-specific
/// error is returned.
///
/// The original pattern string used to produce the `Ast` *must* also be
/// provided. The translator does not use the pattern string during any
/// correct translation, but is used for error reporting.
pub fn Translator::translate(
  self : Translator,
  pattern : String,
  ast : @ast.Ast,
) -> Hir raise HirError {
  let visitor = TranslatorI::new(self, pattern)
  @ast.visit(ast, visitor) catch {
    HirError(_) as e => raise e
    e => abort("unexpected error: \{e}")
  }
  visitor.finish()
}

///|
/// An HirFrame is a single stack frame, represented explicitly, which is
/// created for each item in the Ast that we traverse.
///
/// Note that technically, this type doesn't represent our entire stack
/// frame. In particular, the Ast visitor represents any state associated with
/// traversing the Ast itself.
priv enum HirFrame {
  /// An arbitrary HIR expression. These get pushed whenever we hit a base
  /// case in the Ast. They get popped after an inductive (i.e., recursive)
  /// step is complete.
  Expr(Hir)
  /// A literal that is being constructed, character by character, from the
  /// AST. We need this because the AST gives each individual character its
  /// own node. So as we see characters, we peek at the top-most HirFrame.
  /// If it's a literal, then we add to it. Otherwise, we push a new literal.
  /// When it comes time to pop it, we convert it to an Hir via Hir::literal.
  Literal(Array[Byte])
  /// A Unicode character class. This frame is mutated as we descend into
  /// the Ast of a character class (which is itself its own mini recursive
  /// structure).
  ClassUnicode(ClassUnicode)
  /// A byte-oriented character class. This frame is mutated as we descend
  /// into the Ast of a character class (which is itself its own mini
  /// recursive structure).
  ///
  /// Byte character classes are created when Unicode mode (`u`) is disabled.
  /// If `utf8` is enabled (the default), then a byte character is only
  /// permitted to match ASCII text.
  ClassBytes(ClassBytes)
  /// This is pushed whenever a repetition is observed. After visiting every
  /// sub-expression in the repetition, the translator's stack is expected to
  /// have this sentinel at the top.
  ///
  /// This sentinel only exists to stop other things (like flattening
  /// literals) from reaching across repetition operators.
  Repetition
  /// This is pushed on to the stack upon first seeing any kind of capture,
  /// indicated by parentheses (including non-capturing groups). It is popped
  /// upon leaving a group.
  ///
  /// The old active flags when this group was opened.
  ///
  /// If this group sets flags, then the new active flags are set to the
  /// result of merging the old flags with the flags introduced by this
  /// group. If the group doesn't set any flags, then this is simply
  /// equivalent to whatever flags were set when the group was opened.
  ///
  /// When this group is popped, the active flags should be restored to
  /// the flags set here.
  ///
  /// The "active" flags correspond to whatever flags are set in the
  /// Translator.
  Group(old_flags~ : Flags)
  /// This is pushed whenever a concatenation is observed. After visiting
  /// every sub-expression in the concatenation, the translator's stack is
  /// popped until it sees a Concat frame.
  Concat
  /// This is pushed whenever an alternation is observed. After visiting
  /// every sub-expression in the alternation, the translator's stack is
  /// popped until it sees an Alternation frame.
  Alternation
  /// This is pushed immediately before each sub-expression in an
  /// alternation. This separates the branches of an alternation on the
  /// stack and prevents literal flattening from reaching across alternation
  /// branches.
  ///
  /// It is popped after each expression in a branch until an 'Alternation'
  /// frame is observed when doing a post visit on an alternation.
  AlternationBranch
}

///|
/// Assert that the current stack frame is an Hir expression and return it.
fn HirFrame::unwrap_expr(self : HirFrame) -> Hir {
  match self {
    Expr(expr) => expr
    Literal(lit) => Hir::literal(Bytes::from_array(lit))
    _ => abort("tried to unwrap expr from HirFrame")
  }
}

///|
/// Assert that the current stack frame is a Unicode class expression and
/// return it.
fn HirFrame::unwrap_class_unicode(self : HirFrame) -> ClassUnicode {
  match self {
    ClassUnicode(cls) => cls
    _ => abort("tried to unwrap Unicode class from HirFrame")
  }
}

///|
/// Assert that the current stack frame is a byte class expression and
/// return it.
fn HirFrame::unwrap_class_bytes(self : HirFrame) -> ClassBytes {
  match self {
    ClassBytes(cls) => cls
    _ => abort("tried to unwrap byte class from HirFrame")
  }
}

///|
/// Assert that the current stack frame is a repetition sentinel. If it
/// isn't, then panic.
fn HirFrame::unwrap_repetition(self : HirFrame) -> Unit {
  match self {
    Repetition => ()
    _ => abort("tried to unwrap repetition from HirFrame")
  }
}

///|
/// Assert that the current stack frame is a group indicator and return
/// its corresponding flags (the flags that were active at the time the
/// group was entered).
fn HirFrame::unwrap_group(self : HirFrame) -> Flags {
  match self {
    Group(old_flags~) => old_flags
    _ => abort("tried to unwrap group from HirFrame")
  }
}

///|
/// Assert that the current stack frame is an alternation pipe sentinel. If
/// it isn't, then panic.
fn HirFrame::unwrap_alternation_pipe(self : HirFrame) -> Unit {
  match self {
    AlternationBranch => ()
    _ => abort("tried to unwrap alt pipe from HirFrame")
  }
}

///|
/// `Visitor::finish`.
fn TranslatorI::finish(self : TranslatorI) -> Hir {
  // ... otherwise, we should have exactly one HIR on the stack.
  guard self.trans().stack.length() == 1 else { abort("assertion failed") }
  self.pop().unwrap().unwrap_expr()
}

///|
impl @ast.Visitor for TranslatorI with fn visit_pre(self, ast) {
  match ast {
    ClassBracketed(_) =>
      if self.flags().unicode() {
        let cls = ClassUnicode::empty()
        self.push(ClassUnicode(cls))
      } else {
        let cls = ClassBytes::empty()
        self.push(ClassBytes(cls))
      }
    Repetition(_) => self.push(Repetition)
    Group(x) => {
      let old_flags = match x.flags() {
        Some(ast) => self.set_flags(ast)
        None => self.flags()
      }
      self.push(Group(old_flags~))
    }
    Concat(_) => self.push(Concat)
    Alternation(x) => {
      self.push(Alternation)
      if !x.asts.is_empty() {
        self.push(AlternationBranch)
      }
    }
    _ => ()
  }
}

///|
impl @ast.Visitor for TranslatorI with fn visit_post(self, ast) {
  match ast {
    Empty(_) => self.push(Expr(Hir::empty()))
    Flags(x) => {
      ignore(self.set_flags(x.flags))
      // Flags in the AST are generally considered directives and
      // not actual sub-expressions. However, they can be used in
      // the concrete syntax like `((?i))`, and we need some kind of
      // indication of an expression there, and Empty is the correct
      // choice.
      //
      // There can also be things like `(?i)+`, but we rule those out
      // in the parser. In the future, we might allow them for
      // consistency sake.
      self.push(Expr(Hir::empty()))
    }
    Literal(x) =>
      match self.ast_literal_to_scalar(x) {
        Right(byte) => self.push_byte(byte)
        Left(ch) =>
          match self.case_fold_char(x.span, ch) {
            None => self.push_char(ch)
            Some(expr) => self.push(Expr(expr))
          }
      }
    Dot(span) => self.push(Expr(self.hir_dot(span)))
    Assertion(x) => self.push(Expr(self.hir_assertion(x)))
    ClassPerl(x) =>
      if self.flags().unicode() {
        let cls = self.hir_perl_unicode_class(x)
        let hcls = Class::Unicode(cls)
        self.push(Expr(Hir::class(hcls)))
      } else {
        let cls = self.hir_perl_byte_class(x)
        let hcls = Class::Bytes(cls)
        self.push(Expr(Hir::class(hcls)))
      }
    ClassUnicode(x) => {
      let cls = Class::Unicode(self.hir_unicode_class(x))
      self.push(Expr(Hir::class(cls)))
    }
    ClassBracketed(ast) =>
      if self.flags().unicode() {
        let cls = self.pop().unwrap().unwrap_class_unicode()
        self.unicode_fold_and_negate(ast.span, ast.negated, cls)
        let expr = Hir::class(Unicode(cls))
        self.push(Expr(expr))
      } else {
        let cls = self.pop().unwrap().unwrap_class_bytes()
        self.bytes_fold_and_negate(ast.span, ast.negated, cls)
        let expr = Hir::class(Bytes(cls))
        self.push(Expr(expr))
      }
    Repetition(x) => {
      let expr = self.pop().unwrap().unwrap_expr()
      self.pop().unwrap().unwrap_repetition()
      self.push(Expr(self.hir_repetition(x, expr)))
    }
    Group(x) => {
      let expr = self.pop().unwrap().unwrap_expr()
      let old_flags = self.pop().unwrap().unwrap_group()
      self.trans().flags = old_flags
      self.push(Expr(self.hir_capture(x, expr)))
    }
    Concat(_) => {
      let exprs = []
      while self.pop_concat_expr() is Some(expr) {
        if !(expr.kind() is Empty) {
          exprs.push(expr)
        }
      }
      exprs.rev_in_place()
      self.push(Expr(Hir::concat(exprs)))
    }
    Alternation(_) => {
      let exprs = []
      while self.pop_alt_expr() is Some(expr) {
        self.pop().unwrap().unwrap_alternation_pipe()
        exprs.push(expr)
      }
      exprs.rev_in_place()
      self.push(Expr(Hir::alternation(exprs)))
    }
  }
}

///|
impl @ast.Visitor for TranslatorI with fn visit_alternation_in(self) {
  self.push(AlternationBranch)
}

///|
impl @ast.Visitor for TranslatorI with fn visit_class_set_item_pre(self, ast) {
  match ast {
    Bracketed(_) =>
      if self.flags().unicode() {
        let cls = ClassUnicode::empty()
        self.push(ClassUnicode(cls))
      } else {
        let cls = ClassBytes::empty()
        self.push(ClassBytes(cls))
      }
    // We needn't handle the Union case here since the visitor will
    // do it for us.
    _ => ()
  }
}

///|
impl @ast.Visitor for TranslatorI with fn visit_class_set_item_post(self, ast) {
  match ast {
    Empty(_) => ()
    Literal(x) =>
      if self.flags().unicode() {
        let cls = self.pop().unwrap().unwrap_class_unicode()
        cls.push(ClassUnicodeRange::new(x.c.to_int(), x.c.to_int()))
        self.push(ClassUnicode(cls))
      } else {
        let cls = self.pop().unwrap().unwrap_class_bytes()
        let byte = self.class_literal_byte(x)
        cls.push(ClassBytesRange::new(byte, byte))
        self.push(ClassBytes(cls))
      }
    Range(x) =>
      if self.flags().unicode() {
        let cls = self.pop().unwrap().unwrap_class_unicode()
        cls.push(ClassUnicodeRange::new(x.start.c.to_int(), x.end.c.to_int()))
        self.push(ClassUnicode(cls))
      } else {
        let cls = self.pop().unwrap().unwrap_class_bytes()
        let start = self.class_literal_byte(x.start)
        let end = self.class_literal_byte(x.end)
        cls.push(ClassBytesRange::new(start, end))
        self.push(ClassBytes(cls))
      }
    Ascii(x) =>
      if self.flags().unicode() {
        let xcls = self.hir_ascii_unicode_class(x)
        let cls = self.pop().unwrap().unwrap_class_unicode()
        cls.union(xcls)
        self.push(ClassUnicode(cls))
      } else {
        let xcls = self.hir_ascii_byte_class(x)
        let cls = self.pop().unwrap().unwrap_class_bytes()
        cls.union(xcls)
        self.push(ClassBytes(cls))
      }
    Unicode(x) => {
      let xcls = self.hir_unicode_class(x)
      let cls = self.pop().unwrap().unwrap_class_unicode()
      cls.union(xcls)
      self.push(ClassUnicode(cls))
    }
    Perl(x) =>
      if self.flags().unicode() {
        let xcls = self.hir_perl_unicode_class(x)
        let cls = self.pop().unwrap().unwrap_class_unicode()
        cls.union(xcls)
        self.push(ClassUnicode(cls))
      } else {
        let xcls = self.hir_perl_byte_class(x)
        let cls = self.pop().unwrap().unwrap_class_bytes()
        cls.union(xcls)
        self.push(ClassBytes(cls))
      }
    Bracketed(ast) =>
      if self.flags().unicode() {
        let cls1 = self.pop().unwrap().unwrap_class_unicode()
        self.unicode_fold_and_negate(ast.span, ast.negated, cls1)
        let cls2 = self.pop().unwrap().unwrap_class_unicode()
        cls2.union(cls1)
        self.push(ClassUnicode(cls2))
      } else {
        let cls1 = self.pop().unwrap().unwrap_class_bytes()
        self.bytes_fold_and_negate(ast.span, ast.negated, cls1)
        let cls2 = self.pop().unwrap().unwrap_class_bytes()
        cls2.union(cls1)
        self.push(ClassBytes(cls2))
      }
    // This is handled automatically by the visitor.
    Union(_) => ()
  }
}

///|
impl @ast.Visitor for TranslatorI with fn visit_class_set_binary_op_pre(
  self,
  _op,
) {
  if self.flags().unicode() {
    let cls = ClassUnicode::empty()
    self.push(ClassUnicode(cls))
  } else {
    let cls = ClassBytes::empty()
    self.push(ClassBytes(cls))
  }
}

///|
impl @ast.Visitor for TranslatorI with fn visit_class_set_binary_op_in(
  self,
  _op,
) {
  if self.flags().unicode() {
    let cls = ClassUnicode::empty()
    self.push(ClassUnicode(cls))
  } else {
    let cls = ClassBytes::empty()
    self.push(ClassBytes(cls))
  }
}

///|
impl @ast.Visitor for TranslatorI with fn visit_class_set_binary_op_post(
  self,
  op,
) {
  if self.flags().unicode() {
    let rhs = self.pop().unwrap().unwrap_class_unicode()
    let lhs = self.pop().unwrap().unwrap_class_unicode()
    let cls = self.pop().unwrap().unwrap_class_unicode()
    if self.flags().case_insensitive() {
      rhs.try_case_fold_simple() catch {
        _ => raise self.error(op.rhs.span(), UnicodeCaseUnavailable)
      }
      lhs.try_case_fold_simple() catch {
        _ => raise self.error(op.lhs.span(), UnicodeCaseUnavailable)
      }
    }
    match op.kind {
      Intersection => lhs.intersect(rhs)
      Difference => lhs.difference(rhs)
      SymmetricDifference => lhs.symmetric_difference(rhs)
    }
    cls.union(lhs)
    self.push(ClassUnicode(cls))
  } else {
    let rhs = self.pop().unwrap().unwrap_class_bytes()
    let lhs = self.pop().unwrap().unwrap_class_bytes()
    let cls = self.pop().unwrap().unwrap_class_bytes()
    if self.flags().case_insensitive() {
      rhs.case_fold_simple()
      lhs.case_fold_simple()
    }
    match op.kind {
      Intersection => lhs.intersect(rhs)
      Difference => lhs.difference(rhs)
      SymmetricDifference => lhs.symmetric_difference(rhs)
    }
    cls.union(lhs)
    self.push(ClassBytes(cls))
  }
}

///|
/// The internal implementation of a translator.
///
/// This type is responsible for carrying around the original pattern string,
/// which is not tied to the internal state of a translator.
///
/// A TranslatorI exists for the time it takes to translate a single Ast.
priv struct TranslatorI {
  trans : Translator
  pattern : String
}

///|
/// Upstream's `either::Either`.
priv enum Either[L, R] {
  Left(L)
  Right(R)
}

///|
/// Build a new internal translator.
fn TranslatorI::new(trans : Translator, pattern : String) -> TranslatorI {
  { trans, pattern, }
}

///|
/// Return a reference to the underlying translator.
fn TranslatorI::trans(self : TranslatorI) -> Translator {
  self.trans
}

///|
/// Push the given frame on to the call stack.
fn TranslatorI::push(self : TranslatorI, frame : HirFrame) -> Unit {
  self.trans().stack.push(frame)
}

///|
/// Push the given literal char on to the call stack.
///
/// If the top-most element of the stack is a literal, then the char
/// is appended to the end of that literal. Otherwise, a new literal
/// containing just the given char is pushed to the top of the stack.
fn TranslatorI::push_char(self : TranslatorI, ch : Char) -> Unit {
  let bytes = []
  encode_utf8_into(ch.to_int(), bytes)
  let stack = self.trans().stack
  if stack.last() is Some(Literal(literal)) {
    for b in bytes {
      literal.push(b)
    }
  } else {
    stack.push(Literal(bytes))
  }
}

///|
/// Push the given literal byte on to the call stack.
///
/// If the top-most element of the stack is a literal, then the byte
/// is appended to the end of that literal. Otherwise, a new literal
/// containing just the given byte is pushed to the top of the stack.
fn TranslatorI::push_byte(self : TranslatorI, byte : Byte) -> Unit {
  let stack = self.trans().stack
  if stack.last() is Some(Literal(literal)) {
    literal.push(byte)
  } else {
    stack.push(Literal([byte]))
  }
}

///|
/// Pop the top of the call stack. If the call stack is empty, return None.
fn TranslatorI::pop(self : TranslatorI) -> HirFrame? {
  self.trans().stack.pop()
}

///|
/// Pop an HIR expression from the top of the stack for a concatenation.
///
/// This returns None if the stack is empty or when a concat frame is seen.
/// Otherwise, it panics if it could not find an HIR expression.
fn TranslatorI::pop_concat_expr(self : TranslatorI) -> Hir? {
  guard self.pop() is Some(frame) else { return None }
  match frame {
    Concat => None
    Expr(expr) => Some(expr)
    Literal(lit) => Some(Hir::literal(Bytes::from_array(lit)))
    ClassUnicode(_) => abort("expected expr or concat, got Unicode class")
    ClassBytes(_) => abort("expected expr or concat, got byte class")
    Repetition => abort("expected expr or concat, got repetition")
    Group(..) => abort("expected expr or concat, got group")
    Alternation => abort("expected expr or concat, got alt marker")
    AlternationBranch => abort("expected expr or concat, got alt branch marker")
  }
}

///|
/// Pop an HIR expression from the top of the stack for an alternation.
///
/// This returns None if the stack is empty or when an alternation frame is
/// seen. Otherwise, it panics if it could not find an HIR expression.
fn TranslatorI::pop_alt_expr(self : TranslatorI) -> Hir? {
  guard self.pop() is Some(frame) else { return None }
  match frame {
    Alternation => None
    Expr(expr) => Some(expr)
    Literal(lit) => Some(Hir::literal(Bytes::from_array(lit)))
    ClassUnicode(_) => abort("expected expr or alt, got Unicode class")
    ClassBytes(_) => abort("expected expr or alt, got byte class")
    Repetition => abort("expected expr or alt, got repetition")
    Group(..) => abort("expected expr or alt, got group")
    Concat => abort("expected expr or alt, got concat marker")
    AlternationBranch => abort("expected expr or alt, got alt branch marker")
  }
}

///|
/// Create a new error with the given span and error type.
fn TranslatorI::error(
  self : TranslatorI,
  span : @ast.Span,
  kind : ErrorKind,
) -> HirError {
  HirError(kind~, pattern=self.pattern, span~)
}

///|
/// Return a copy of the active flags.
fn TranslatorI::flags(self : TranslatorI) -> Flags {
  self.trans().flags
}

///|
/// Set the flags of this translator from the flags set in the given AST.
/// Then, return the old flags.
fn TranslatorI::set_flags(self : TranslatorI, ast_flags : @ast.Flags) -> Flags {
  let old_flags = self.flags()
  let new_flags = Flags::from_ast(ast_flags).merge(old_flags)
  self.trans().flags = new_flags
  old_flags
}

///|
/// Convert an Ast literal to its scalar representation.
///
/// When Unicode mode is enabled, then this always succeeds and returns a
/// `char` (Unicode scalar value).
///
/// When Unicode mode is disabled, then a `char` will still be returned
/// whenever possible. A byte is returned only when invalid UTF-8 is
/// allowed and when the byte is not ASCII. Otherwise, a non-ASCII byte
/// will result in an error when invalid UTF-8 is not allowed.
fn TranslatorI::ast_literal_to_scalar(
  self : TranslatorI,
  lit : @ast.Literal,
) -> Either[Char, Byte] raise HirError {
  if self.flags().unicode() {
    return Left(lit.c)
  }
  let byte = match lit.byte() {
    None => return Left(lit.c)
    Some(byte) => byte
  }
  if byte <= 0x7F {
    return Left(byte.to_int().unsafe_to_char())
  }
  if self.trans().utf8 {
    raise self.error(lit.span, InvalidUtf8)
  }
  Right(byte)
}

///|
fn TranslatorI::case_fold_char(
  self : TranslatorI,
  span : @ast.Span,
  c : Char,
) -> Hir? raise HirError {
  if !self.flags().case_insensitive() {
    return None
  }
  if self.flags().unicode() {
    // If case folding won't do anything, then don't bother trying.
    let map = (SimpleCaseFolder::new() catch {
      _ => raise self.error(span, UnicodeCaseUnavailable)
    }).overlaps(c.to_int(), c.to_int())
    if !map {
      return None
    }
    let cls = ClassUnicode::new([ClassUnicodeRange::new(c.to_int(), c.to_int())])
    cls.try_case_fold_simple() catch {
      _ => raise self.error(span, UnicodeCaseUnavailable)
    }
    Some(Hir::class(Unicode(cls)))
  } else {
    if c.to_int() > 0x7F {
      return None
    }
    // If case folding won't do anything, then don't bother trying.
    match c {
      'A'..<='Z' | 'a'..<='z' => ()
      _ => return None
    }
    let cls = ClassBytes::new([
      // OK because 'c.len_utf8() == 1' which in turn implies
      // that 'c' is ASCII.
      ClassBytesRange::new(c.to_int().to_byte(), c.to_int().to_byte()),
    ])
    cls.case_fold_simple()
    Some(Hir::class(Bytes(cls)))
  }
}

///|
fn TranslatorI::hir_dot(
  self : TranslatorI,
  span : @ast.Span,
) -> Hir raise HirError {
  let (utf8, lineterm, flags) = (
    self.trans().utf8,
    self.trans().line_terminator,
    self.flags(),
  )
  if utf8 && (!flags.unicode() || lineterm > 0x7F) {
    raise self.error(span, InvalidUtf8)
  }
  let dot = if flags.dot_matches_new_line() {
    if flags.unicode() {
      Dot::AnyChar
    } else {
      Dot::AnyByte
    }
  } else if flags.unicode() {
    if flags.crlf() {
      Dot::AnyCharExceptCRLF
    } else {
      if lineterm > 0x7F {
        raise self.error(span, InvalidLineTerminator)
      }
      Dot::AnyCharExcept(lineterm.to_int())
    }
  } else if flags.crlf() {
    Dot::AnyByteExceptCRLF
  } else {
    Dot::AnyByteExcept(lineterm)
  }
  Hir::dot(dot)
}

///|
fn TranslatorI::hir_assertion(
  self : TranslatorI,
  asst : @ast.Assertion,
) -> Hir raise HirError {
  let unicode = self.flags().unicode()
  let multi_line = self.flags().multi_line()
  let crlf = self.flags().crlf()
  match asst.kind {
    StartLine =>
      Hir::look(
        if multi_line {
          if crlf {
            StartCRLF
          } else {
            StartLF
          }
        } else {
          Start
        },
      )
    EndLine =>
      Hir::look(
        if multi_line {
          if crlf {
            EndCRLF
          } else {
            EndLF
          }
        } else {
          End
        },
      )
    StartText => Hir::look(Start)
    EndText => Hir::look(End)
    WordBoundary => Hir::look(if unicode { WordUnicode } else { WordAscii })
    NotWordBoundary =>
      Hir::look(if unicode { WordUnicodeNegate } else { WordAsciiNegate })
    WordBoundaryStart | WordBoundaryStartAngle =>
      Hir::look(if unicode { WordStartUnicode } else { WordStartAscii })
    WordBoundaryEnd | WordBoundaryEndAngle =>
      Hir::look(if unicode { WordEndUnicode } else { WordEndAscii })
    WordBoundaryStartHalf =>
      Hir::look(if unicode { WordStartHalfUnicode } else { WordStartHalfAscii })
    WordBoundaryEndHalf =>
      Hir::look(if unicode { WordEndHalfUnicode } else { WordEndHalfAscii })
  }
}

///|
fn TranslatorI::hir_capture(
  _self : TranslatorI,
  group : @ast.Group,
  expr : Hir,
) -> Hir {
  let (index, name) = match group.kind {
    CaptureIndex(index) => (index, None)
    CaptureName(name~, ..) => (name.index, Some(name.name))
    // The HIR doesn't need to use non-capturing groups, since the way
    // in which the data type is defined handles this automatically.
    NonCapturing(_) => return expr
  }
  Hir::capture({ index, name, sub: expr, })
}

///|
fn TranslatorI::hir_repetition(
  self : TranslatorI,
  rep : @ast.Repetition,
  expr : Hir,
) -> Hir {
  let (min, max) : (UInt32, UInt32?) = match rep.op.kind {
    ZeroOrOne => (0, Some(1))
    ZeroOrMore => (0, None)
    OneOrMore => (1, None)
    Range(Exactly(m)) => (m, Some(m))
    Range(AtLeast(m)) => (m, None)
    Range(Bounded(m, n)) => (m, Some(n))
  }
  let greedy = if self.flags().swap_greed() { !rep.greedy } else { rep.greedy }
  Hir::repetition({ min, max, greedy, sub: expr, })
}

///|
fn TranslatorI::hir_unicode_class(
  self : TranslatorI,
  ast_class : @ast.ClassUnicode,
) -> ClassUnicode raise HirError {
  if !self.flags().unicode() {
    raise self.error(ast_class.span, UnicodeNotAllowed)
  }
  let query = match ast_class.kind {
    OneLetter(name) => ClassQuery::OneLetter(name)
    Named(name) => ClassQuery::Binary(name)
    NamedValue(name~, value~, ..) =>
      ClassQuery::ByValue(property_name=name, property_value=value)
  }
  let class = self.convert_unicode_class_error(ast_class.span, () => {
    class(query)
  })
  self.unicode_fold_and_negate(ast_class.span, ast_class.is_negated(), class)
  class
}

///|
fn TranslatorI::hir_ascii_unicode_class(
  self : TranslatorI,
  ast : @ast.ClassAscii,
) -> ClassUnicode raise HirError {
  let cls = ClassUnicode::new(
    ascii_class_as_chars(ast.kind).map(r => ClassUnicodeRange::new(r.0, r.1)),
  )
  self.unicode_fold_and_negate(ast.span, ast.negated, cls)
  cls
}

///|
fn TranslatorI::hir_ascii_byte_class(
  self : TranslatorI,
  ast : @ast.ClassAscii,
) -> ClassBytes raise HirError {
  let cls = ClassBytes::new(
    ascii_class(ast.kind).map(r => ClassBytesRange::new(r.0, r.1)),
  )
  self.bytes_fold_and_negate(ast.span, ast.negated, cls)
  cls
}

///|
fn TranslatorI::hir_perl_unicode_class(
  self : TranslatorI,
  ast_class : @ast.ClassPerl,
) -> ClassUnicode raise HirError {
  guard self.flags().unicode() else { abort("assertion failed") }
  let class = self.convert_unicode_class_error(ast_class.span, () => {
    match ast_class.kind {
      Digit => perl_digit()
      Space => perl_space()
      Word => perl_word()
    }
  })
  // We needn't apply case folding here because the Perl Unicode classes
  // are already closed under Unicode simple case folding.
  if ast_class.negated {
    class.negate()
  }
  class
}

///|
fn TranslatorI::hir_perl_byte_class(
  self : TranslatorI,
  ast_class : @ast.ClassPerl,
) -> ClassBytes raise HirError {
  guard !self.flags().unicode() else { abort("assertion failed") }
  let class = match ast_class.kind {
    Digit => hir_ascii_class_bytes(Digit)
    Space => hir_ascii_class_bytes(Space)
    Word => hir_ascii_class_bytes(Word)
  }
  // We needn't apply case folding here because the Perl ASCII classes
  // are already closed (under ASCII case folding).
  if ast_class.negated {
    class.negate()
  }
  // Negating a Perl byte class is likely to cause it to match invalid
  // UTF-8. That's only OK if the translator is configured to allow such
  // things.
  if self.trans().utf8 && !class.is_ascii() {
    raise self.error(ast_class.span, InvalidUtf8)
  }
  class
}

///|
/// Converts the given Unicode specific error to an HIR translation error.
///
/// The span given should approximate the position at which an error would
/// occur.
fn TranslatorI::convert_unicode_class_error(
  self : TranslatorI,
  span : @ast.Span,
  result : () -> ClassUnicode raise UnicodeError,
) -> ClassUnicode raise HirError {
  result() catch {
    PropertyNotFound => raise self.error(span, UnicodePropertyNotFound)
    PropertyValueNotFound =>
      raise self.error(span, UnicodePropertyValueNotFound)
    PerlClassNotFound => raise self.error(span, UnicodePerlClassNotFound)
  }
}

///|
fn TranslatorI::unicode_fold_and_negate(
  self : TranslatorI,
  span : @ast.Span,
  negated : Bool,
  class : ClassUnicode,
) -> Unit raise HirError {
  // Note that we must apply case folding before negation!
  // Consider `(?i)[^x]`. If we applied negation first, then
  // the result would be the character class that matched any
  // Unicode scalar value.
  if self.flags().case_insensitive() {
    class.try_case_fold_simple() catch {
      _ => raise self.error(span, UnicodeCaseUnavailable)
    }
  }
  if negated {
    class.negate()
  }
}

///|
fn TranslatorI::bytes_fold_and_negate(
  self : TranslatorI,
  span : @ast.Span,
  negated : Bool,
  class : ClassBytes,
) -> Unit raise HirError {
  // Note that we must apply case folding before negation!
  // Consider `(?i)[^x]`. If we applied negation first, then
  // the result would be the character class that matched any
  // Unicode scalar value.
  if self.flags().case_insensitive() {
    class.case_fold_simple()
  }
  if negated {
    class.negate()
  }
  if self.trans().utf8 && !class.is_ascii() {
    raise self.error(span, InvalidUtf8)
  }
}

///|
/// Return a scalar byte value suitable for use as a literal in a byte
/// character class.
fn TranslatorI::class_literal_byte(
  self : TranslatorI,
  ast : @ast.Literal,
) -> Byte raise HirError {
  match self.ast_literal_to_scalar(ast) {
    Right(byte) => byte
    Left(ch) =>
      if ch.to_int() <= 0x7F {
        ch.to_int().to_byte()
      } else {
        // We can't feasibly support Unicode in
        // byte oriented classes. Byte classes don't
        // do Unicode case folding.
        raise self.error(ast.span, UnicodeNotAllowed)
      }
  }
}

///|
/// A translator's representation of a regular expression's flags at any given
/// moment in time.
///
/// Each flag can be in one of three states: absent, present but disabled or
/// present but enabled.
priv struct Flags {
  case_insensitive : Bool?
  multi_line : Bool?
  dot_matches_new_line : Bool?
  swap_greed : Bool?
  unicode : Bool?
  crlf : Bool?
  // Note that `ignore_whitespace` is omitted here because it is handled
  // entirely in the parser.
}

///|
fn Flags::default() -> Flags {
  {
    case_insensitive: None,
    multi_line: None,
    dot_matches_new_line: None,
    swap_greed: None,
    unicode: None,
    crlf: None,
  }
}

///|
fn Flags::from_ast(ast : @ast.Flags) -> Flags {
  let mut flags = Flags::default()
  let mut enable = true
  for item in ast.items {
    match item.kind {
      Negation => enable = false
      Flag(CaseInsensitive) =>
        flags = { ..flags, case_insensitive: Some(enable), }
      Flag(MultiLine) => flags = { ..flags, multi_line: Some(enable), }
      Flag(DotMatchesNewLine) =>
        flags = { ..flags, dot_matches_new_line: Some(enable), }
      Flag(SwapGreed) => flags = { ..flags, swap_greed: Some(enable), }
      Flag(Unicode) => flags = { ..flags, unicode: Some(enable), }
      Flag(CRLF) => flags = { ..flags, crlf: Some(enable), }
      Flag(IgnoreWhitespace) => ()
    }
  }
  flags
}

///|
/// Upstream mutates `self` in place; this returns the merged flags.
fn Flags::merge(self : Flags, previous : Flags) -> Flags {
  {
    case_insensitive: opt_or(self.case_insensitive, previous.case_insensitive),
    multi_line: opt_or(self.multi_line, previous.multi_line),
    dot_matches_new_line: opt_or(
      self.dot_matches_new_line,
      previous.dot_matches_new_line,
    ),
    swap_greed: opt_or(self.swap_greed, previous.swap_greed),
    unicode: opt_or(self.unicode, previous.unicode),
    crlf: opt_or(self.crlf, previous.crlf),
  }
}

///|
fn Flags::case_insensitive(self : Flags) -> Bool {
  self.case_insensitive.unwrap_or(false)
}

///|
fn Flags::multi_line(self : Flags) -> Bool {
  self.multi_line.unwrap_or(false)
}

///|
fn Flags::dot_matches_new_line(self : Flags) -> Bool {
  self.dot_matches_new_line.unwrap_or(false)
}

///|
fn Flags::swap_greed(self : Flags) -> Bool {
  self.swap_greed.unwrap_or(false)
}

///|
fn Flags::unicode(self : Flags) -> Bool {
  self.unicode.unwrap_or(true)
}

///|
fn Flags::crlf(self : Flags) -> Bool {
  self.crlf.unwrap_or(false)
}

///|
fn hir_ascii_class_bytes(kind : @ast.ClassAsciiKind) -> ClassBytes {
  let ranges = ascii_class(kind).map(r => ClassBytesRange::new(r.0, r.1))
  ClassBytes::new(ranges)
}

///|
fn ascii_class(kind : @ast.ClassAsciiKind) -> Array[(Byte, Byte)] {
  match kind {
    Alnum => [(b'0', b'9'), (b'A', b'Z'), (b'a', b'z')]
    Alpha => [(b'A', b'Z'), (b'a', b'z')]
    Ascii => [(b'\x00', b'\x7F')]
    Blank => [(b'\t', b'\t'), (b' ', b' ')]
    Cntrl => [(b'\x00', b'\x1F'), (b'\x7F', b'\x7F')]
    Digit => [(b'0', b'9')]
    Graph => [(b'!', b'~')]
    Lower => [(b'a', b'z')]
    Print => [(b' ', b'~')]
    Punct => [(b'!', b'/'), (b':', b'@'), (b'[', b'`'), (b'{', b'~')]
    Space =>
      [
        (b'\t', b'\t'),
        (b'\n', b'\n'),
        (b'\x0B', b'\x0B'),
        (b'\x0C', b'\x0C'),
        (b'\r', b'\r'),
        (b' ', b' '),
      ]
    Upper => [(b'A', b'Z')]
    Word => [(b'0', b'9'), (b'A', b'Z'), (b'_', b'_'), (b'a', b'z')]
    Xdigit => [(b'0', b'9'), (b'A', b'F'), (b'a', b'f')]
  }
}

///|
fn ascii_class_as_chars(kind : @ast.ClassAsciiKind) -> Array[(Int32, Int32)] {
  ascii_class(kind).map(r => (r.0.to_int(), r.1.to_int()))
}

///|
/// Rust `Option::is_none` + assignment in `Flags::merge`.
fn opt_or(value : Bool?, previous : Bool?) -> Bool? {
  match value {
    None => previous
    value => value
  }
}

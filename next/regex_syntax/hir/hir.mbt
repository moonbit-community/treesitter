// Port of regex-syntax 0.8.11 src/hir/mod.rs (and the `utf8_decode` helper
// of src/debug.rs).
//
// Defines a high-level intermediate (HIR) representation for regular
// expressions. The smart constructors (`Hir::concat`, `Hir::alternation`,
// `Hir::repetition`, `Hir::class`, ...) simplify exactly like upstream, since
// the shape of the HIR determines the NFA built from it. `usize` lengths are
// `UInt64`, `u32` counts are `UInt`, `char` bounds are `Int` code points. The
// `Drop` impl and `memory_usage` are not needed.

///|
/// An error that can occur while translating an `Ast` to a `Hir`
/// (upstream `hir::Error`).
pub(all) suberror HirError {
  HirError(kind~ : ErrorKind, pattern~ : String, span~ : @ast.Span)
} derive(Eq, Debug)

///|
/// Return the type of this error.
pub fn HirError::kind(self : HirError) -> ErrorKind {
  let HirError(kind~, ..) = self
  kind
}

///|
/// The original pattern string in which this error occurred.
pub fn HirError::pattern(self : HirError) -> String {
  let HirError(pattern~, ..) = self
  pattern
}

///|
/// Return the span at which this error occurred.
pub fn HirError::span(self : HirError) -> @ast.Span {
  let HirError(span~, ..) = self
  span
}

///|
/// The type of an error that occurred while building an `Hir`.
pub(all) enum ErrorKind {
  /// This error occurs when a Unicode feature is used when Unicode
  /// support is disabled. For example `(?-u:\pL)` would trigger this error.
  UnicodeNotAllowed
  /// This error occurs when translating a pattern that could match a byte
  /// sequence that isn't UTF-8 and `utf8` was enabled.
  InvalidUtf8
  /// This error occurs when one uses a non-ASCII byte for a line terminator,
  /// but where Unicode mode is enabled and UTF-8 mode is disabled.
  InvalidLineTerminator
  /// This occurs when an unrecognized Unicode property name could not
  /// be found.
  UnicodePropertyNotFound
  /// This occurs when an unrecognized Unicode property value could not
  /// be found.
  UnicodePropertyValueNotFound
  /// This occurs when a Unicode-aware Perl character class (`\w`, `\s` or
  /// `\d`) could not be found.
  UnicodePerlClassNotFound
  /// This occurs when the Unicode simple case mapping tables are not
  /// available, and the regular expression required Unicode aware case
  /// insensitivity.
  UnicodeCaseUnavailable
} derive(Eq, Debug)

///|
pub impl Show for ErrorKind with fn output(self, f) {
  let msg = match self {
    UnicodeNotAllowed => "Unicode not allowed here"
    InvalidUtf8 => "pattern can match invalid UTF-8"
    InvalidLineTerminator => "invalid line terminator, must be ASCII"
    UnicodePropertyNotFound => "Unicode property not found"
    UnicodePropertyValueNotFound => "Unicode property value not found"
    UnicodePerlClassNotFound =>
      "Unicode-aware Perl class not found (make sure the unicode-perl feature is enabled)"
    UnicodeCaseUnavailable =>
      "Unicode-aware case insensitivity matching is not available (make sure the unicode-case feature is enabled)"
  }
  f.write_string(msg)
}

///|
/// A high-level intermediate representation (HIR) for a regular expression.
///
/// An HIR value is a combination of a [`HirKind`] and a set of [`Properties`].
/// An `HirKind` indicates what kind of regular expression it is (a literal,
/// a repetition, a look-around assertion, etc.), where as a `Properties`
/// describes various facts about the regular expression.
pub struct Hir {
  /// The underlying HIR kind.
  priv kind : HirKind
  /// Analysis info about this HIR, computed bottom-up.
  priv props : Properties
} derive(Eq, Debug)

///|
/// Returns a reference to the underlying HIR kind.
pub fn Hir::kind(self : Hir) -> HirKind {
  self.kind
}

///|
/// Consumes ownership of this HIR expression and returns its underlying
/// `HirKind`.
pub fn Hir::into_kind(self : Hir) -> HirKind {
  self.kind
}

///|
/// Returns the properties computed for this `Hir`.
pub fn Hir::properties(self : Hir) -> Properties {
  self.props
}

///|
/// Splits this HIR into its constituent parts.
fn Hir::into_parts(self : Hir) -> (HirKind, Properties) {
  (self.kind, self.props)
}

///|
/// Returns an empty HIR expression.
///
/// An empty HIR expression always matches, including the empty string.
pub fn Hir::empty() -> Hir {
  let props = Properties::empty()
  { kind: Empty, props, }
}

///|
/// Returns an HIR expression that can never match anything. That is,
/// the size of the set of strings in the language described by the HIR
/// returned is `0`.
pub fn Hir::fail() -> Hir {
  let class = Class::Bytes(ClassBytes::empty())
  let props = Properties::class(class)
  // We can't just call Hir::class here because it defers to Hir::fail
  // in order to canonicalize the Hir value used to represent "cannot
  // match."
  { kind: Class(class), props, }
}

///|
/// Creates a literal HIR expression.
///
/// This accepts anything that can be converted into a `Box<[u8]>`.
///
/// Note that there is no mechanism for storing a `char` or a `Box<str>`
/// in an HIR. Everything is "just bytes." Whether a `Literal` (or
/// any HIR node) matches valid UTF-8 exclusively can be queried via
/// [`Properties::is_utf8`].
pub fn Hir::literal(lit : Bytes) -> Hir {
  let bytes = lit
  if bytes.is_empty() {
    return Hir::empty()
  }
  let lit = Literal::Literal(bytes)
  let props = Properties::literal(lit)
  { kind: Literal(lit), props, }
}

///|
/// Creates a class HIR expression. The class may either be defined over
/// ranges of Unicode codepoints or ranges of raw byte values.
///
/// Note that an empty class is permitted. An empty class is equivalent to
/// `Hir::fail()`.
pub fn Hir::class(class : Class) -> Hir {
  if class.is_empty() {
    return Hir::fail()
  } else if class.literal() is Some(bytes) {
    return Hir::literal(bytes)
  }
  let props = Properties::class(class)
  { kind: Class(class), props, }
}

///|
/// Creates a look-around assertion HIR expression.
pub fn Hir::look(look : Look) -> Hir {
  let props = Properties::look(look)
  { kind: Look(look), props, }
}

///|
/// Creates a repetition HIR expression.
pub fn Hir::repetition(rep : Repetition) -> Hir {
  let mut rep = rep
  // If the sub-expression of a repetition can only match the empty
  // string, then we force its maximum to be at most 1.
  if rep.sub.properties().maximum_len() == Some(0) {
    rep = {
      ..rep,
      min: @cmp.minimum(rep.min, 1),
      max: Some(
        match rep.max {
          Some(n) => @cmp.minimum(n, 1)
          None => 1
        },
      ),
    }
  }
  // The regex 'a{0}' is always equivalent to the empty regex. This is
  // true even when 'a' is an expression that never matches anything
  // (like '\P{any}').
  //
  // Additionally, the regex 'a{1}' is always equivalent to 'a'.
  if rep.min == 0 && rep.max == Some(0) {
    return Hir::empty()
  } else if rep.min == 1 && rep.max == Some(1) {
    return rep.sub
  }
  let props = Properties::repetition(rep)
  { kind: Repetition(rep), props, }
}

///|
/// Creates a capture HIR expression.
///
/// Note that there is no explicit HIR value for a non-capturing group.
/// Since a non-capturing group only exists to override precedence in the
/// concrete syntax and since an HIR already does its own grouping based on
/// what is parsed, there is no need to explicitly represent non-capturing
/// groups in the HIR.
pub fn Hir::capture(capture : Capture) -> Hir {
  let props = Properties::capture(capture)
  { kind: Capture(capture), props, }
}

///|
/// Returns the concatenation of the given expressions.
///
/// This attempts to flatten and simplify the concatenation as appropriate.
pub fn Hir::concat(subs : Array[Hir]) -> Hir {
  // We rebuild the concatenation by simplifying it. Would be nice to do
  // it in place, but that seems a little tricky?
  let new = []
  // This gobbles up any adjacent literals in a concatenation and smushes
  // them together. Basically, when we see a literal, we add its bytes
  // to 'prior_lit', and whenever we see anything else, we first take
  // any bytes in 'prior_lit' and add it to the 'new' concatenation.
  let mut prior_lit : Array[Byte]? = None
  for sub in subs {
    let (kind, props) = sub.into_parts()
    match kind {
      Literal(Literal(bytes)) =>
        match prior_lit {
          Some(prior_bytes) =>
            for b in bytes {
              prior_bytes.push(b)
            }
          None => prior_lit = Some(bytes.to_array())
        }
      // We also flatten concats that are direct children of another
      // concat. We only need to do this one level deep since
      // Hir::concat is the only way to build concatenations, and so
      // flattening happens inductively.
      Concat(subs2) =>
        for sub2 in subs2 {
          let (kind2, props2) = sub2.into_parts()
          match kind2 {
            Literal(Literal(bytes)) =>
              match prior_lit {
                Some(prior_bytes) =>
                  for b in bytes {
                    prior_bytes.push(b)
                  }
                None => prior_lit = Some(bytes.to_array())
              }
            kind2 => {
              if prior_lit is Some(prior_bytes) {
                prior_lit = None
                new.push(Hir::literal(Bytes::from_array(prior_bytes)))
              }
              new.push({ kind: kind2, props: props2, })
            }
          }
        }
      // We can just skip empty HIRs.
      Empty => ()
      kind => {
        if prior_lit is Some(prior_bytes) {
          prior_lit = None
          new.push(Hir::literal(Bytes::from_array(prior_bytes)))
        }
        new.push({ kind, props, })
      }
    }
  }
  if prior_lit is Some(prior_bytes) {
    new.push(Hir::literal(Bytes::from_array(prior_bytes)))
  }
  if new.is_empty() {
    return Hir::empty()
  } else if new.length() == 1 {
    return new.unsafe_pop()
  }
  let props = Properties::concat(new)
  { kind: Concat(new), props, }
}

///|
/// Returns the alternation of the given expressions.
///
/// This flattens and simplifies the alternation as appropriate. This may
/// include factoring out common prefixes or even rewriting the alternation
/// as a character class.
///
/// Note that an empty alternation is equivalent to `Hir::fail()`. (It
/// is not possible for one to write an empty alternation, or even an
/// alternation with a single sub-expression, in the concrete syntax of a
/// regex.)
pub fn Hir::alternation(subs : Array[Hir]) -> Hir {
  // We rebuild the alternation by simplifying it. We proceed similarly
  // as the concatenation case. But in this case, there's no literal
  // simplification happening. We're just flattening alternations.
  let mut new = []
  for sub in subs {
    let (kind, props) = sub.into_parts()
    match kind {
      Alternation(subs2) =>
        for s in subs2 {
          new.push(s)
        }
      kind => new.push({ kind, props, })
    }
  }
  if new.is_empty() {
    return Hir::fail()
  } else if new.length() == 1 {
    return new.unsafe_pop()
  }
  // Now that it's completely flattened, look for the special case of
  // 'char1|char2|...|charN' and collapse that into a class. Note that
  // we look for 'char' first and then bytes. The issue here is that if
  // we find both non-ASCII codepoints and non-ASCII singleton bytes,
  // then it isn't actually possible to smush them into a single class.
  // (Because classes are either "all codepoints" or "all bytes." You
  // can have a class that both matches non-ASCII but valid UTF-8 and
  // invalid UTF-8.) So we look for all chars and then all bytes, and
  // don't handle anything else.
  if singleton_chars(new) is Some(singletons) {
    let it = singletons.map(ch => ClassUnicodeRange::{ start: ch, end: ch, })
    return Hir::class(Unicode(ClassUnicode::new(it)))
  }
  if singleton_bytes(new) is Some(singletons) {
    let it = singletons.map(b => ClassBytesRange::{ start: b, end: b, })
    return Hir::class(Bytes(ClassBytes::new(it)))
  }
  // Similar to singleton chars, we can also look for alternations of
  // classes. Those can be smushed into a single class.
  if class_chars(new) is Some(cls) {
    return Hir::class(cls)
  }
  if class_bytes(new) is Some(cls) {
    return Hir::class(cls)
  }
  // Factor out a common prefix if we can, which might potentially
  // simplify the expression and unlock other optimizations downstream.
  // It also might generally make NFA matching and DFA construction
  // faster by reducing the scope of branching in the regex.
  new = match lift_common_prefix(new) {
    Ok(hir) => return hir
    Err(unchanged) => unchanged
  }
  let props = Properties::alternation(new)
  { kind: Alternation(new), props, }
}

///|
/// Returns an HIR expression for `.`.
pub fn Hir::dot(dot : Dot) -> Hir {
  match dot {
    AnyChar =>
      Hir::class(
        Unicode(ClassUnicode::new([ClassUnicodeRange::new(0, 0x10FFFF)])),
      )
    AnyByte =>
      Hir::class(
        Bytes(ClassBytes::new([ClassBytesRange::new(b'\x00', b'\xFF')])),
      )
    AnyCharExcept(ch) => {
      let cls = ClassUnicode::new([ClassUnicodeRange::new(ch, ch)])
      cls.negate()
      Hir::class(Unicode(cls))
    }
    AnyCharExceptLF =>
      Hir::class(
        Unicode(
          ClassUnicode::new([
            ClassUnicodeRange::new(0, 0x09),
            ClassUnicodeRange::new(0x0B, 0x10FFFF),
          ]),
        ),
      )
    AnyCharExceptCRLF =>
      Hir::class(
        Unicode(
          ClassUnicode::new([
            ClassUnicodeRange::new(0, 0x09),
            ClassUnicodeRange::new(0x0B, 0x0C),
            ClassUnicodeRange::new(0x0E, 0x10FFFF),
          ]),
        ),
      )
    AnyByteExcept(byte) => {
      let cls = ClassBytes::new([ClassBytesRange::new(byte, byte)])
      cls.negate()
      Hir::class(Bytes(cls))
    }
    AnyByteExceptLF =>
      Hir::class(
        Bytes(
          ClassBytes::new([
            ClassBytesRange::new(b'\x00', b'\x09'),
            ClassBytesRange::new(b'\x0B', b'\xFF'),
          ]),
        ),
      )
    AnyByteExceptCRLF =>
      Hir::class(
        Bytes(
          ClassBytes::new([
            ClassBytesRange::new(b'\x00', b'\x09'),
            ClassBytesRange::new(b'\x0B', b'\x0C'),
            ClassBytesRange::new(b'\x0E', b'\xFF'),
          ]),
        ),
      )
  }
}

///|
/// The underlying kind of an arbitrary [`Hir`] expression.
pub(all) enum HirKind {
  /// The empty regular expression, which matches everything, including the
  /// empty string.
  Empty
  /// A literal string that matches exactly these bytes.
  Literal(Literal)
  /// A single character class that matches any of the characters in the
  /// class. A class can either consist of Unicode scalar values as
  /// characters, or it can use bytes.
  Class(Class)
  /// A look-around assertion. A look-around match always has zero length.
  Look(Look)
  /// A repetition operation applied to a sub-expression.
  Repetition(Repetition)
  /// A capturing group, which contains a sub-expression.
  Capture(Capture)
  /// A concatenation of expressions.
  Concat(Array[Hir])
  /// An alternation of expressions.
  Alternation(Array[Hir])
} derive(Eq, Debug)

///|
/// Returns a slice of this kind's sub-expressions, if any.
pub fn HirKind::subs(self : HirKind) -> Array[Hir] {
  match self {
    Empty | Literal(_) | Class(_) | Look(_) => []
    Repetition(rep) => [rep.sub]
    Capture(cap) => [cap.sub]
    Concat(subs) => subs
    Alternation(subs) => subs
  }
}

///|
/// The high-level intermediate representation of a literal.
pub(all) struct Literal(Bytes) derive(Eq, Debug)

///|
/// The high-level intermediate representation of a character class.
pub(all) enum Class {
  /// A set of characters represented by Unicode scalar values.
  Unicode(ClassUnicode)
  /// A set of characters represented by arbitrary bytes (one byte per
  /// character).
  Bytes(ClassBytes)
} derive(Eq, Debug)

///|
/// Apply Unicode simple case folding to this character class, in place.
pub fn Class::case_fold_simple(self : Class) -> Unit {
  match self {
    Unicode(x) => x.case_fold_simple()
    Bytes(x) => x.case_fold_simple()
  }
}

///|
/// Apply Unicode simple case folding to this character class, in place.
pub fn Class::try_case_fold_simple(self : Class) -> Unit raise CaseFoldError {
  match self {
    Unicode(x) => x.try_case_fold_simple()
    Bytes(x) => x.case_fold_simple()
  }
}

///|
/// Negate this character class in place.
pub fn Class::negate(self : Class) -> Unit {
  match self {
    Unicode(x) => x.negate()
    Bytes(x) => x.negate()
  }
}

///|
/// Returns true if and only if this character class will only ever match
/// valid UTF-8.
pub fn Class::is_utf8(self : Class) -> Bool {
  match self {
    Unicode(_) => true
    Bytes(x) => x.is_ascii()
  }
}

///|
/// Returns the length, in bytes, of the smallest string matched by this
/// character class.
pub fn Class::minimum_len(self : Class) -> UInt64? {
  match self {
    Unicode(x) => x.minimum_len()
    Bytes(x) => x.minimum_len()
  }
}

///|
/// Returns the length, in bytes, of the longest string matched by this
/// character class.
pub fn Class::maximum_len(self : Class) -> UInt64? {
  match self {
    Unicode(x) => x.maximum_len()
    Bytes(x) => x.maximum_len()
  }
}

///|
/// Returns true if and only if this character class is empty. That is,
/// it has no elements.
pub fn Class::is_empty(self : Class) -> Bool {
  match self {
    Unicode(x) => x.ranges().is_empty()
    Bytes(x) => x.ranges().is_empty()
  }
}

///|
/// If this class consists of exactly one element (whether a codepoint or a
/// byte), then return it as a literal byte string.
pub fn Class::literal(self : Class) -> Bytes? {
  match self {
    Unicode(x) => x.literal()
    Bytes(x) => x.literal()
  }
}

///|
/// A set of characters represented by Unicode scalar values.
pub struct ClassUnicode {
  priv set : IntervalSet[ClassUnicodeRange]
} derive(Eq, Debug)

///|
/// Create a new class from a sequence of ranges.
///
/// The given ranges do not need to be in any specific order, and ranges
/// may overlap. Ranges will automatically be sorted into a canonical
/// non-overlapping order.
pub fn ClassUnicode::new(ranges : Array[ClassUnicodeRange]) -> ClassUnicode {
  { set: IntervalSet::new(ranges), }
}

///|
/// Create a new class with no ranges.
pub fn ClassUnicode::empty() -> ClassUnicode {
  ClassUnicode::new([])
}

///|
/// A copy of this class (Rust `Clone`).
pub fn ClassUnicode::copy(self : ClassUnicode) -> ClassUnicode {
  { set: self.set.copy(), }
}

///|
/// Add a new range to this set.
pub fn ClassUnicode::push(
  self : ClassUnicode,
  range : ClassUnicodeRange,
) -> Unit {
  self.set.push(range)
}

///|
/// Return an iterator over all ranges in this class.
pub fn ClassUnicode::iter(self : ClassUnicode) -> Iter[ClassUnicodeRange] {
  self.set.iter()
}

///|
/// Return the underlying ranges as a slice.
pub fn ClassUnicode::ranges(
  self : ClassUnicode,
) -> ArrayView[ClassUnicodeRange] {
  self.set.intervals()
}

///|
/// Expand this character class such that it contains all case folded
/// characters, according to Unicode's "simple" mapping.
pub fn ClassUnicode::case_fold_simple(self : ClassUnicode) -> Unit {
  self.set.case_fold_simple() catch {
    _ => abort("unicode-case feature must be enabled")
  }
}

///|
/// Expand this character class such that it contains all case folded
/// characters, according to Unicode's "simple" mapping.
pub fn ClassUnicode::try_case_fold_simple(
  self : ClassUnicode,
) -> Unit raise CaseFoldError {
  self.set.case_fold_simple()
}

///|
/// Negate this character class.
pub fn ClassUnicode::negate(self : ClassUnicode) -> Unit {
  self.set.negate()
}

///|
/// Union this character class with the given character class, in place.
pub fn ClassUnicode::union(self : ClassUnicode, other : ClassUnicode) -> Unit {
  self.set.union(other.set)
}

///|
/// Intersect this character class with the given character class, in
/// place.
pub fn ClassUnicode::intersect(
  self : ClassUnicode,
  other : ClassUnicode,
) -> Unit {
  self.set.intersect(other.set)
}

///|
/// Subtract the given character class from this character class, in place.
pub fn ClassUnicode::difference(
  self : ClassUnicode,
  other : ClassUnicode,
) -> Unit {
  self.set.difference(other.set)
}

///|
/// Compute the symmetric difference of the given character classes, in
/// place.
pub fn ClassUnicode::symmetric_difference(
  self : ClassUnicode,
  other : ClassUnicode,
) -> Unit {
  self.set.symmetric_difference(other.set)
}

///|
/// Returns true if and only if this character class will either match
/// nothing or only ASCII bytes. Stated differently, this returns false
/// if and only if this class contains a non-ASCII codepoint.
pub fn ClassUnicode::is_ascii(self : ClassUnicode) -> Bool {
  match self.set.intervals().last() {
    None => true
    Some(r) => r.end <= 0x7F
  }
}

///|
/// Returns the length, in bytes, of the smallest string matched by this
/// character class.
pub fn ClassUnicode::minimum_len(self : ClassUnicode) -> UInt64? {
  guard self.ranges().get(0) is Some(first) else { return None }
  // Correct because c1 < c2 implies c1.len_utf8() < c2.len_utf8().
  Some(len_utf8(first.start).to_uint64())
}

///|
/// Returns the length, in bytes, of the longest string matched by this
/// character class.
pub fn ClassUnicode::maximum_len(self : ClassUnicode) -> UInt64? {
  guard self.ranges().last() is Some(last) else { return None }
  // Correct because c1 < c2 implies c1.len_utf8() < c2.len_utf8().
  Some(len_utf8(last.end).to_uint64())
}

///|
/// If this class consists of exactly one codepoint, then return its
/// corresponding UTF-8 encoding. Otherwise, return `None`.
pub fn ClassUnicode::literal(self : ClassUnicode) -> Bytes? {
  let rs = self.ranges()
  if rs.length() == 1 && rs[0].start == rs[0].end {
    let out = []
    encode_utf8_into(rs[0].start, out)
    Some(Bytes::from_array(out))
  } else {
    None
  }
}

///|
/// If this class consists of only ASCII ranges, then return its
/// corresponding and equivalent byte class.
pub fn ClassUnicode::to_byte_class(self : ClassUnicode) -> ClassBytes? {
  if !self.is_ascii() {
    return None
  }
  Some(
    ClassBytes::new(
      self
      .ranges()
      .iter()
      .map(r => ClassBytesRange::{
        // Since we are guaranteed that our codepoint range is ASCII, the
        // 'u8::try_from' calls below are guaranteed to be correct.
        start: r.start.to_byte(),
        end: r.end.to_byte(),
      })
      .collect(),
    ),
  )
}

///|
/// A single range of characters represented by Unicode scalar values.
///
/// The range is closed. That is, the start and end of the range are included
/// in the range.
pub(all) struct ClassUnicodeRange {
  start : Int32
  end : Int32
} derive(Eq, Compare, Debug)

///|
pub impl Interval for ClassUnicodeRange with fn lower(self) {
  self.start
}

///|
pub impl Interval for ClassUnicodeRange with fn upper(self) {
  self.end
}

///|
pub impl Interval for ClassUnicodeRange with fn create(lower, upper) {
  if lower <= upper {
    { start: lower, end: upper, }
  } else {
    { start: upper, end: lower, }
  }
}

///|
pub impl Interval for ClassUnicodeRange with fn bound_min_value() {
  0
}

///|
pub impl Interval for ClassUnicodeRange with fn bound_max_value() {
  0x10FFFF
}

///|
pub impl Interval for ClassUnicodeRange with fn bound_increment(c) {
  char_increment(c)
}

///|
pub impl Interval for ClassUnicodeRange with fn bound_decrement(c) {
  char_decrement(c)
}

///|
/// Apply simple case folding to this Unicode scalar value range.
///
/// Additional ranges are appended to the given vector. Canonical ordering
/// is *not* maintained in the given vector.
pub impl Interval for ClassUnicodeRange with fn case_fold_simple(self, ranges) {
  let folder = SimpleCaseFolder::new()
  if !folder.overlaps(self.start, self.end) {
    return
  }
  let (start, end) = (self.start, self.end)
  for cp in start..<=end {
    // `char::from_u32` skips the surrogates.
    if cp >= 0xD800 && cp <= 0xDFFF {
      continue
    }
    for cp_folded in folder.mapping(cp) {
      ranges.push(ClassUnicodeRange::new(cp_folded, cp_folded))
    }
  }
}

///|
/// Create a new Unicode scalar value range for a character class.
///
/// The returned range is always in a canonical form. That is, the range
/// returned always satisfies the invariant that `start <= end`.
pub fn ClassUnicodeRange::new(start : Int32, end : Int32) -> ClassUnicodeRange {
  Interval::create(start, end)
}

///|
/// Return the start of this range.
pub fn ClassUnicodeRange::start(self : ClassUnicodeRange) -> Int32 {
  self.start
}

///|
/// Return the end of this range.
pub fn ClassUnicodeRange::end(self : ClassUnicodeRange) -> Int32 {
  self.end
}

///|
/// Returns the number of codepoints in this range.
pub fn ClassUnicodeRange::len(self : ClassUnicodeRange) -> Int32 {
  1 + self.end - self.start
}

///|
/// A set of characters represented by arbitrary bytes.
///
/// Each byte corresponds to one character.
pub struct ClassBytes {
  priv set : IntervalSet[ClassBytesRange]
} derive(Eq, Debug)

///|
/// Create a new class from a sequence of ranges.
pub fn ClassBytes::new(ranges : Array[ClassBytesRange]) -> ClassBytes {
  { set: IntervalSet::new(ranges), }
}

///|
/// Create a new class with no ranges.
pub fn ClassBytes::empty() -> ClassBytes {
  ClassBytes::new([])
}

///|
/// A copy of this class (Rust `Clone`).
pub fn ClassBytes::copy(self : ClassBytes) -> ClassBytes {
  { set: self.set.copy(), }
}

///|
/// Add a new range to this set.
pub fn ClassBytes::push(self : ClassBytes, range : ClassBytesRange) -> Unit {
  self.set.push(range)
}

///|
/// Return an iterator over all ranges in this class.
pub fn ClassBytes::iter(self : ClassBytes) -> Iter[ClassBytesRange] {
  self.set.iter()
}

///|
/// Return the underlying ranges as a slice.
pub fn ClassBytes::ranges(self : ClassBytes) -> ArrayView[ClassBytesRange] {
  self.set.intervals()
}

///|
/// Expand this character class such that it contains all case folded
/// characters. For example, if this class consists of the range `a-z`,
/// then applying case folding will result in the class containing both the
/// ranges `a-z` and `A-Z`.
///
/// Note that this only applies ASCII case folding, which is limited to the
/// characters `a-z` and `A-Z`.
pub fn ClassBytes::case_fold_simple(self : ClassBytes) -> Unit {
  self.set.case_fold_simple() catch {
    _ => abort("ASCII case folding never fails")
  }
}

///|
/// Negate this byte class.
pub fn ClassBytes::negate(self : ClassBytes) -> Unit {
  self.set.negate()
}

///|
/// Union this byte class with the given byte class, in place.
pub fn ClassBytes::union(self : ClassBytes, other : ClassBytes) -> Unit {
  self.set.union(other.set)
}

///|
/// Intersect this byte class with the given byte class, in place.
pub fn ClassBytes::intersect(self : ClassBytes, other : ClassBytes) -> Unit {
  self.set.intersect(other.set)
}

///|
/// Subtract the given byte class from this byte class, in place.
pub fn ClassBytes::difference(self : ClassBytes, other : ClassBytes) -> Unit {
  self.set.difference(other.set)
}

///|
/// Compute the symmetric difference of the given byte classes, in place.
pub fn ClassBytes::symmetric_difference(
  self : ClassBytes,
  other : ClassBytes,
) -> Unit {
  self.set.symmetric_difference(other.set)
}

///|
/// Returns true if and only if this character class will either match
/// nothing or only ASCII bytes. Stated differently, this returns false
/// if and only if this class contains a non-ASCII byte.
pub fn ClassBytes::is_ascii(self : ClassBytes) -> Bool {
  match self.set.intervals().last() {
    None => true
    Some(r) => r.end <= 0x7F
  }
}

///|
/// Returns the length, in bytes, of the smallest string matched by this
/// character class.
pub fn ClassBytes::minimum_len(self : ClassBytes) -> UInt64? {
  if self.ranges().is_empty() {
    None
  } else {
    Some(1)
  }
}

///|
/// Returns the length, in bytes, of the longest string matched by this
/// character class.
pub fn ClassBytes::maximum_len(self : ClassBytes) -> UInt64? {
  if self.ranges().is_empty() {
    None
  } else {
    Some(1)
  }
}

///|
/// If this class consists of exactly one byte, then return it as
/// a literal byte string.
pub fn ClassBytes::literal(self : ClassBytes) -> Bytes? {
  let rs = self.ranges()
  if rs.length() == 1 && rs[0].start == rs[0].end {
    Some(Bytes::from_array([rs[0].start]))
  } else {
    None
  }
}

///|
/// If this class consists of only ASCII ranges, then return its
/// corresponding and equivalent Unicode class.
pub fn ClassBytes::to_unicode_class(self : ClassBytes) -> ClassUnicode? {
  if !self.is_ascii() {
    return None
  }
  Some(
    ClassUnicode::new(
      self
      .ranges()
      .iter()
      .map(r => ClassUnicodeRange::{
        // Since we are guaranteed that our byte range is ASCII, the
        // 'char::from' calls below are correct and will not erroneously
        // convert a raw byte value into its corresponding codepoint.
        start: r.start.to_int(),
        end: r.end.to_int(),
      })
      .collect(),
    ),
  )
}

///|
/// A single range of characters represented by arbitrary bytes.
///
/// The range is closed. That is, the start and end of the range are included
/// in the range.
pub(all) struct ClassBytesRange {
  start : Byte
  end : Byte
} derive(Eq, Compare, Debug)

///|
pub impl Interval for ClassBytesRange with fn lower(self) {
  self.start.to_int()
}

///|
pub impl Interval for ClassBytesRange with fn upper(self) {
  self.end.to_int()
}

///|
pub impl Interval for ClassBytesRange with fn create(lower, upper) {
  if lower <= upper {
    { start: lower.to_byte(), end: upper.to_byte(), }
  } else {
    { start: upper.to_byte(), end: lower.to_byte(), }
  }
}

///|
pub impl Interval for ClassBytesRange with fn bound_min_value() {
  0
}

///|
pub impl Interval for ClassBytesRange with fn bound_max_value() {
  0xFF
}

///|
pub impl Interval for ClassBytesRange with fn bound_increment(b) {
  byte_increment(b)
}

///|
pub impl Interval for ClassBytesRange with fn bound_decrement(b) {
  byte_decrement(b)
}

///|
/// Apply simple case folding to this byte range. Only ASCII case mappings
/// (for a-z) are applied.
///
/// Additional ranges are appended to the given vector. Canonical ordering
/// is *not* maintained in the given vector.
pub impl Interval for ClassBytesRange with fn case_fold_simple(self, ranges) {
  if !interval_is_intersection_empty(ClassBytesRange::new(b'a', b'z'), self) {
    let lower = @cmp.maximum(self.start, b'a')
    let upper = @cmp.minimum(self.end, b'z')
    ranges.push(ClassBytesRange::new(lower - 32, upper - 32))
  }
  if !interval_is_intersection_empty(ClassBytesRange::new(b'A', b'Z'), self) {
    let lower = @cmp.maximum(self.start, b'A')
    let upper = @cmp.minimum(self.end, b'Z')
    ranges.push(ClassBytesRange::new(lower + 32, upper + 32))
  }
}

///|
/// Create a new byte range for a character class.
///
/// The returned range is always in a canonical form. That is, the range
/// returned always satisfies the invariant that `start <= end`.
pub fn ClassBytesRange::new(start : Byte, end : Byte) -> ClassBytesRange {
  Interval::create(start.to_int(), end.to_int())
}

///|
/// Return the start of this range.
pub fn ClassBytesRange::start(self : ClassBytesRange) -> Byte {
  self.start
}

///|
/// Return the end of this range.
pub fn ClassBytesRange::end(self : ClassBytesRange) -> Byte {
  self.end
}

///|
/// Returns the number of bytes in this range.
pub fn ClassBytesRange::len(self : ClassBytesRange) -> Int32 {
  self.end.to_int() - self.start.to_int() + 1
}

///|
/// The high-level intermediate representation for a look-around assertion.
///
/// An assertion match is always zero-length. Also called an "empty match."
pub(all) enum Look {
  /// Match the beginning of text.
  Start
  /// Match the end of text.
  End
  /// Match the beginning of a line or the beginning of text.
  StartLF
  /// Match the end of a line or the end of text.
  EndLF
  /// Match the beginning of a line or the beginning of text (CRLF aware).
  StartCRLF
  /// Match the end of a line or the end of text (CRLF aware).
  EndCRLF
  /// Match an ASCII-only word boundary.
  WordAscii
  /// Match an ASCII-only negation of a word boundary.
  WordAsciiNegate
  /// Match a Unicode-aware word boundary.
  WordUnicode
  /// Match a Unicode-aware negation of a word boundary.
  WordUnicodeNegate
  /// Match the start of an ASCII-only word boundary.
  WordStartAscii
  /// Match the end of an ASCII-only word boundary.
  WordEndAscii
  /// Match the start of a Unicode word boundary.
  WordStartUnicode
  /// Match the end of a Unicode word boundary.
  WordEndUnicode
  /// Match the start half of an ASCII-only word boundary.
  WordStartHalfAscii
  /// Match the end half of an ASCII-only word boundary.
  WordEndHalfAscii
  /// Match the start half of a Unicode word boundary.
  WordStartHalfUnicode
  /// Match the end half of a Unicode word boundary.
  WordEndHalfUnicode
} derive(Eq, Debug)

///|
/// Flip the look-around assertion to its equivalent for reverse searches.
pub fn Look::reversed(self : Look) -> Look {
  match self {
    Start => End
    End => Start
    StartLF => EndLF
    EndLF => StartLF
    StartCRLF => EndCRLF
    EndCRLF => StartCRLF
    WordAscii => WordAscii
    WordAsciiNegate => WordAsciiNegate
    WordUnicode => WordUnicode
    WordUnicodeNegate => WordUnicodeNegate
    WordStartAscii => WordEndAscii
    WordEndAscii => WordStartAscii
    WordStartUnicode => WordEndUnicode
    WordEndUnicode => WordStartUnicode
    WordStartHalfAscii => WordEndHalfAscii
    WordEndHalfAscii => WordStartHalfAscii
    WordStartHalfUnicode => WordEndHalfUnicode
    WordEndHalfUnicode => WordStartHalfUnicode
  }
}

///|
/// Return the underlying representation of this look-around enumeration
/// as an integer. Giving the return value to the [`Look::from_repr`]
/// constructor is guaranteed to return the same look-around variant that
/// one started with within a semver compatible release of this crate.
pub fn Look::as_repr(self : Look) -> UInt32 {
  let bit = match self {
    Start => 0
    End => 1
    StartLF => 2
    EndLF => 3
    StartCRLF => 4
    EndCRLF => 5
    WordAscii => 6
    WordAsciiNegate => 7
    WordUnicode => 8
    WordUnicodeNegate => 9
    WordStartAscii => 10
    WordEndAscii => 11
    WordStartUnicode => 12
    WordEndUnicode => 13
    WordStartHalfAscii => 14
    WordEndHalfAscii => 15
    WordStartHalfUnicode => 16
    WordEndHalfUnicode => 17
  }
  1U << bit
}

///|
/// Given the underlying representation of a `Look` value, return the
/// corresponding `Look` value if the representation is valid. Otherwise
/// `None` is returned.
pub fn Look::from_repr(repr : UInt32) -> Look? {
  let all : Array[Look] = [
    Start,
    End,
    StartLF,
    EndLF,
    StartCRLF,
    EndCRLF,
    WordAscii,
    WordAsciiNegate,
    WordUnicode,
    WordUnicodeNegate,
    WordStartAscii,
    WordEndAscii,
    WordStartUnicode,
    WordEndUnicode,
    WordStartHalfAscii,
    WordEndHalfAscii,
    WordStartHalfUnicode,
    WordEndHalfUnicode,
  ]
  for look in all {
    if look.as_repr() == repr {
      return Some(look)
    }
  }
  None
}

///|
/// Returns a convenient single codepoint representation of this
/// look-around assertion.
pub fn Look::as_char(self : Look) -> Char {
  match self {
    Start => 'A'
    End => 'z'
    StartLF => '^'
    EndLF => '$'
    StartCRLF => 'r'
    EndCRLF => 'R'
    WordAscii => 'b'
    WordAsciiNegate => 'B'
    WordUnicode => '𝛃'
    WordUnicodeNegate => '𝚩'
    WordStartAscii => '<'
    WordEndAscii => '>'
    WordStartUnicode => '〈'
    WordEndUnicode => '〉'
    WordStartHalfAscii => '◁'
    WordEndHalfAscii => '▷'
    WordStartHalfUnicode => '◀'
    WordEndHalfUnicode => '▶'
  }
}

///|
/// The high-level intermediate representation for a capturing group.
pub(all) struct Capture {
  /// The capture index of the capture.
  index : UInt32
  /// The name of the capture, if it exists.
  name : String?
  /// The expression inside the capturing group, which may be empty.
  sub : Hir
} derive(Eq, Debug)

///|
/// The high-level intermediate representation of a repetition operator.
pub(all) struct Repetition {
  /// The minimum range of the repetition.
  min : UInt32
  /// The maximum range of the repetition.
  ///
  /// Note that when `max` is `None`, `min` acts as a lower bound but where
  /// there is no upper bound. For something like `x{5}` where the min and
  /// max are equivalent, `min` will be set to `5` and `max` will be set to
  /// `Some(5)`.
  max : UInt32?
  /// Whether this repetition operator is greedy or not.
  greedy : Bool
  /// The expression being repeated.
  sub : Hir
} derive(Eq, Debug)

///|
/// Returns a new repetition with the same `min`, `max` and `greedy`
/// values, but with its sub-expression replaced with the one given.
pub fn Repetition::with_sub(self : Repetition, sub : Hir) -> Repetition {
  { min: self.min, max: self.max, greedy: self.greedy, sub, }
}

///|
/// A type describing the different flavors of `.`.
pub(all) enum Dot {
  /// Matches the UTF-8 encoding of any Unicode scalar value.
  AnyChar
  /// Matches any byte value.
  AnyByte
  /// Matches the UTF-8 encoding of any Unicode scalar value except for the
  /// `char` given.
  AnyCharExcept(Int32)
  /// Matches the UTF-8 encoding of any Unicode scalar value except for `\n`.
  AnyCharExceptLF
  /// Matches the UTF-8 encoding of any Unicode scalar value except for `\r`
  /// and `\n`.
  AnyCharExceptCRLF
  /// Matches any byte value except for the `u8` given.
  AnyByteExcept(Byte)
  /// Matches any byte value except for `\n`.
  AnyByteExceptLF
  /// Matches any byte value except for `\r` and `\n`.
  AnyByteExceptCRLF
} derive(Eq, Debug)

///|
/// A type that collects various properties of an HIR value.
///
/// Properties are always scalar values and represent meta data that is
/// computed inductively on an HIR value. Properties are defined for all
/// HIR values.
pub struct Properties {
  priv minimum_len : UInt64?
  priv maximum_len : UInt64?
  priv look_set : LookSet
  priv look_set_prefix : LookSet
  priv look_set_suffix : LookSet
  priv look_set_prefix_any : LookSet
  priv look_set_suffix_any : LookSet
  priv utf8 : Bool
  priv explicit_captures_len : UInt64
  priv static_explicit_captures_len : UInt64?
  priv literal : Bool
  priv alternation_literal : Bool
} derive(Eq, Debug)

///|
/// Returns the length (in bytes) of the smallest string matched by this
/// HIR.
pub fn Properties::minimum_len(self : Properties) -> UInt64? {
  self.minimum_len
}

///|
/// Returns the length (in bytes) of the longest string matched by this
/// HIR.
pub fn Properties::maximum_len(self : Properties) -> UInt64? {
  self.maximum_len
}

///|
/// Returns a set of all look-around assertions that appear at least once
/// in this HIR value.
pub fn Properties::look_set(self : Properties) -> LookSet {
  self.look_set
}

///|
/// Returns a set of all look-around assertions that appear as a prefix for
/// this HIR value.
pub fn Properties::look_set_prefix(self : Properties) -> LookSet {
  self.look_set_prefix
}

///|
/// Returns a set of all look-around assertions that appear as a _possible_
/// prefix for this HIR value.
pub fn Properties::look_set_prefix_any(self : Properties) -> LookSet {
  self.look_set_prefix_any
}

///|
/// Returns a set of all look-around assertions that appear as a suffix for
/// this HIR value.
pub fn Properties::look_set_suffix(self : Properties) -> LookSet {
  self.look_set_suffix
}

///|
/// Returns a set of all look-around assertions that appear as a _possible_
/// suffix for this HIR value.
pub fn Properties::look_set_suffix_any(self : Properties) -> LookSet {
  self.look_set_suffix_any
}

///|
/// Return true if and only if the corresponding HIR will always match
/// valid UTF-8.
pub fn Properties::is_utf8(self : Properties) -> Bool {
  self.utf8
}

///|
/// Returns the total number of explicit capturing groups in the
/// corresponding HIR.
pub fn Properties::explicit_captures_len(self : Properties) -> UInt64 {
  self.explicit_captures_len
}

///|
/// Returns the total number of explicit capturing groups that appear in
/// every possible match.
pub fn Properties::static_explicit_captures_len(self : Properties) -> UInt64? {
  self.static_explicit_captures_len
}

///|
/// Return true if and only if this HIR is a simple literal.
pub fn Properties::is_literal(self : Properties) -> Bool {
  self.literal
}

///|
/// Return true if and only if this HIR is either a simple literal or an
/// alternation of simple literals.
pub fn Properties::is_alternation_literal(self : Properties) -> Bool {
  self.alternation_literal
}

///|
fn saturating_add(a : UInt64, b : UInt64) -> UInt64 {
  let s = a + b
  if s < a {
    18446744073709551615UL
  } else {
    s
  }
}

///|
fn saturating_mul(a : UInt64, b : UInt64) -> UInt64 {
  match checked_mul(a, b) {
    Some(p) => p
    None => 18446744073709551615UL
  }
}

///|
fn checked_mul(a : UInt64, b : UInt64) -> UInt64? {
  if a == 0 || b == 0 {
    return Some(0)
  }
  let p = a * b
  if p / b != a {
    None
  } else {
    Some(p)
  }
}

///|
fn checked_add(a : UInt64, b : UInt64) -> UInt64? {
  let s = a + b
  if s < a {
    None
  } else {
    Some(s)
  }
}

///|
/// Create a new set of HIR properties that represents the union of the
/// given properties.
///
/// This is useful when one has multiple `Hir` expressions and wants
/// to combine them into a single alternation without constructing the
/// corresponding `Hir`. This routine provides a way of combining the
/// properties of each `Hir` expression into one set of properties
/// representing the union of those expressions.
pub fn Properties::union(props : Array[Properties]) -> Properties {
  // While empty alternations aren't possible, we still behave as if they
  // are. When we have an empty alternate, then clearly the look-around
  // prefix and suffix is empty. Otherwise, it is the intersection of all
  // prefixes and suffixes (respectively) of the branches.
  let fix = if props.is_empty() { LookSet::empty() } else { LookSet::full() }
  // And also, an empty alternate means we have 0 static capture groups,
  // but we otherwise start with the number corresponding to the first
  // alternate. If any subsequent alternate has a different number of
  // static capture groups, then we overall have a variation and not a
  // static number of groups.
  let static_explicit_captures_len = match props.get(0) {
    Some(p) => p.static_explicit_captures_len()
    None => None
  }
  // The base case is an empty alternation, which matches nothing.
  // Note though that empty alternations aren't possible, because the
  // Hir::alternation smart constructor rewrites those as empty character
  // classes.
  let mut minimum_len : UInt64? = None
  let mut maximum_len : UInt64? = None
  let mut look_set = LookSet::empty()
  let mut look_set_prefix = fix
  let mut look_set_suffix = fix
  let mut look_set_prefix_any = LookSet::empty()
  let mut look_set_suffix_any = LookSet::empty()
  let mut utf8 = true
  let mut explicit_captures_len = 0UL
  let mut static_explicit_captures_len = static_explicit_captures_len
  let mut alternation_literal = true
  let mut min_poisoned = false
  let mut max_poisoned = false
  // Handle properties that need to visit every child hir.
  for p in props {
    look_set = look_set.union(p.look_set())
    look_set_prefix = look_set_prefix.intersect(p.look_set_prefix())
    look_set_suffix = look_set_suffix.intersect(p.look_set_suffix())
    look_set_prefix_any = look_set_prefix_any.union(p.look_set_prefix_any())
    look_set_suffix_any = look_set_suffix_any.union(p.look_set_suffix_any())
    utf8 = utf8 && p.is_utf8()
    explicit_captures_len = saturating_add(
      explicit_captures_len,
      p.explicit_captures_len(),
    )
    if static_explicit_captures_len != p.static_explicit_captures_len() {
      static_explicit_captures_len = None
    }
    alternation_literal = alternation_literal && p.is_literal()
    if !min_poisoned {
      match p.minimum_len() {
        Some(xmin) =>
          match minimum_len {
            Some(pmin) if !(xmin < pmin) => ()
            _ => minimum_len = Some(xmin)
          }
        None => {
          minimum_len = None
          min_poisoned = true
        }
      }
    }
    if !max_poisoned {
      match p.maximum_len() {
        Some(xmax) =>
          match maximum_len {
            Some(pmax) if !(xmax > pmax) => ()
            _ => maximum_len = Some(xmax)
          }
        None => {
          maximum_len = None
          max_poisoned = true
        }
      }
    }
  }
  {
    minimum_len,
    maximum_len,
    look_set,
    look_set_prefix,
    look_set_suffix,
    look_set_prefix_any,
    look_set_suffix_any,
    utf8,
    explicit_captures_len,
    static_explicit_captures_len,
    literal: false,
    alternation_literal,
  }
}

///|
/// Create a new set of HIR properties for an empty regex.
fn Properties::empty() -> Properties {
  {
    minimum_len: Some(0),
    maximum_len: Some(0),
    look_set: LookSet::empty(),
    look_set_prefix: LookSet::empty(),
    look_set_suffix: LookSet::empty(),
    look_set_prefix_any: LookSet::empty(),
    look_set_suffix_any: LookSet::empty(),
    // It is debatable whether an empty regex always matches at valid
    // UTF-8 boundaries. Strictly speaking, at a byte oriented view,
    // it is clearly false. There are, for example, many empty strings
    // between the bytes encoding a '☃'.
    //
    // However, when Unicode mode is enabled, the fundamental atom
    // of matching is really a codepoint. And in that scenario, an
    // empty regex is defined to only match at valid UTF-8 boundaries
    // and to never split a codepoint. It just so happens that this
    // enforcement is somewhat tricky to do for regexes that match
    // the empty string inside regex engines themselves. It usually
    // requires some layer above the regex engine to filter out such
    // matches.
    //
    // In any case, 'true' is really the only coherent option. If it
    // were false, for example, then 'a*' would also need to be false
    // since it too can match the empty string.
    utf8: true,
    explicit_captures_len: 0,
    static_explicit_captures_len: Some(0),
    literal: false,
    alternation_literal: false,
  }
}

///|
/// Create a new set of HIR properties for a literal regex.
fn Properties::literal(lit : Literal) -> Properties {
  let Literal(bytes) = lit
  {
    minimum_len: Some(bytes.length().to_uint64()),
    maximum_len: Some(bytes.length().to_uint64()),
    look_set: LookSet::empty(),
    look_set_prefix: LookSet::empty(),
    look_set_suffix: LookSet::empty(),
    look_set_prefix_any: LookSet::empty(),
    look_set_suffix_any: LookSet::empty(),
    utf8: try from_utf8(bytes[:]) |> ignore catch {
      _ => false
    } noraise {
      _ => true
    },
    explicit_captures_len: 0,
    static_explicit_captures_len: Some(0),
    literal: true,
    alternation_literal: true,
  }
}

///|
/// Create a new set of HIR properties for a character class.
fn Properties::class(class : Class) -> Properties {
  {
    minimum_len: class.minimum_len(),
    maximum_len: class.maximum_len(),
    look_set: LookSet::empty(),
    look_set_prefix: LookSet::empty(),
    look_set_suffix: LookSet::empty(),
    look_set_prefix_any: LookSet::empty(),
    look_set_suffix_any: LookSet::empty(),
    utf8: class.is_utf8(),
    explicit_captures_len: 0,
    static_explicit_captures_len: Some(0),
    literal: false,
    alternation_literal: false,
  }
}

///|
/// Create a new set of HIR properties for a look-around assertion.
fn Properties::look(look : Look) -> Properties {
  {
    minimum_len: Some(0),
    maximum_len: Some(0),
    look_set: LookSet::singleton(look),
    look_set_prefix: LookSet::singleton(look),
    look_set_suffix: LookSet::singleton(look),
    look_set_prefix_any: LookSet::singleton(look),
    look_set_suffix_any: LookSet::singleton(look),
    // This requires a little explanation. Basically, we don't consider
    // matching an empty string to be equivalent to matching invalid
    // UTF-8, even though technically matching every empty string will
    // split the UTF-8 encoding of a single codepoint when treating a
    // UTF-8 encoded string as a sequence of bytes. Our defense here is
    // that in such a case, a codepoint should logically be treated as
    // the fundamental atom for matching, and thus the only valid match
    // points are between codepoints and not bytes.
    //
    // More practically, this is true here because it's also true
    // for 'Hir::empty()', otherwise something like 'a*' would be
    // considered to match invalid UTF-8. That in turn makes this
    // property borderline useless.
    utf8: true,
    explicit_captures_len: 0,
    static_explicit_captures_len: Some(0),
    literal: false,
    alternation_literal: false,
  }
}

///|
/// Create a new set of HIR properties for a repetition.
fn Properties::repetition(rep : Repetition) -> Properties {
  let p = rep.sub.properties()
  let minimum_len = match p.minimum_len() {
    Some(child_min) => Some(saturating_mul(child_min, rep.min.to_uint64()))
    None => None
  }
  let maximum_len = match rep.max {
    Some(rep_max) =>
      match p.maximum_len() {
        Some(child_max) => checked_mul(child_max, rep_max.to_uint64())
        None => None
      }
    None => None
  }
  let mut inner : Properties = {
    minimum_len,
    maximum_len,
    look_set: p.look_set(),
    look_set_prefix: LookSet::empty(),
    look_set_suffix: LookSet::empty(),
    look_set_prefix_any: p.look_set_prefix_any(),
    look_set_suffix_any: p.look_set_suffix_any(),
    utf8: p.is_utf8(),
    explicit_captures_len: p.explicit_captures_len(),
    static_explicit_captures_len: p.static_explicit_captures_len(),
    literal: false,
    alternation_literal: false,
  }
  // If the repetition operator can match the empty string, then its
  // lookset prefix and suffixes themselves remain empty since they are
  // no longer required to match.
  if rep.min > 0 {
    inner = {
      ..inner,
      look_set_prefix: p.look_set_prefix(),
      look_set_suffix: p.look_set_suffix(),
    }
  }
  // If the static captures len of the sub-expression is not known or
  // is greater than zero, then it automatically propagates to the
  // repetition, regardless of the repetition. Otherwise, it might
  // change, but only when the repetition can match 0 times.
  if rep.min == 0 &&
    (match inner.static_explicit_captures_len {
      Some(len) => len > 0
      None => false
    }) {
    // If we require a match 0 times, then our captures len is
    // guaranteed to be zero. Otherwise, if we *can* match the empty
    // string, then it's impossible to know how many captures will be
    // in the resulting match.
    if rep.max == Some(0) {
      inner = { ..inner, static_explicit_captures_len: Some(0), }
    } else {
      inner = { ..inner, static_explicit_captures_len: None, }
    }
  }
  inner
}

///|
/// Create a new set of HIR properties for a capture.
fn Properties::capture(capture : Capture) -> Properties {
  let p = capture.sub.properties()
  {
    ..p,
    explicit_captures_len: saturating_add(p.explicit_captures_len(), 1),
    static_explicit_captures_len: match p.static_explicit_captures_len() {
      Some(len) => Some(saturating_add(len, 1))
      None => None
    },
    literal: false,
    alternation_literal: false,
  }
}

///|
/// Create a new set of HIR properties for a concatenation.
fn Properties::concat(concat : Array[Hir]) -> Properties {
  // The base case is an empty concatenation, which matches the empty
  // string. Note though that empty concatenations aren't possible,
  // because the Hir::concat smart constructor rewrites those as
  // Hir::empty.
  let mut minimum_len : UInt64? = Some(0)
  let mut maximum_len : UInt64? = Some(0)
  let mut look_set = LookSet::empty()
  let mut look_set_prefix = LookSet::empty()
  let mut look_set_suffix = LookSet::empty()
  let mut look_set_prefix_any = LookSet::empty()
  let mut look_set_suffix_any = LookSet::empty()
  let mut utf8 = true
  let mut explicit_captures_len = 0UL
  let mut static_explicit_captures_len : UInt64? = Some(0)
  let mut literal = true
  let mut alternation_literal = true
  // Handle properties that need to visit every child hir.
  for x in concat {
    let p = x.properties()
    look_set = look_set.union(p.look_set())
    utf8 = utf8 && p.is_utf8()
    explicit_captures_len = saturating_add(
      explicit_captures_len,
      p.explicit_captures_len(),
    )
    static_explicit_captures_len = match
      (p.static_explicit_captures_len(), static_explicit_captures_len) {
      (Some(len1), Some(len2)) => Some(saturating_add(len1, len2))
      _ => None
    }
    literal = literal && p.is_literal()
    alternation_literal = alternation_literal && p.is_alternation_literal()
    if minimum_len is Some(ml) {
      match p.minimum_len() {
        None => minimum_len = None
        Some(len) =>
          // We use saturating arithmetic here because the
          // minimum is just a lower bound. We can't go any
          // higher than what our number types permit.
          minimum_len = Some(saturating_add(ml, len))
      }
    }
    if maximum_len is Some(ml) {
      match p.maximum_len() {
        None => maximum_len = None
        Some(len) => maximum_len = checked_add(ml, len)
      }
    }
  }
  // Handle the prefix properties, which only requires visiting
  // child exprs until one matches more than the empty string.
  for x in concat {
    look_set_prefix = look_set_prefix.union(x.properties().look_set_prefix())
    look_set_prefix_any = look_set_prefix_any.union(
      x.properties().look_set_prefix_any(),
    )
    if (match x.properties().maximum_len() {
        Some(x) => x > 0
        None => true
      }) {
      break
    }
  }
  // Same thing for the suffix properties, but in reverse.
  for x in concat.rev_iter() {
    look_set_suffix = look_set_suffix.union(x.properties().look_set_suffix())
    look_set_suffix_any = look_set_suffix_any.union(
      x.properties().look_set_suffix_any(),
    )
    if (match x.properties().maximum_len() {
        Some(x) => x > 0
        None => true
      }) {
      break
    }
  }
  {
    minimum_len,
    maximum_len,
    look_set,
    look_set_prefix,
    look_set_suffix,
    look_set_prefix_any,
    look_set_suffix_any,
    utf8,
    explicit_captures_len,
    static_explicit_captures_len,
    literal,
    alternation_literal,
  }
}

///|
/// Create a new set of HIR properties for a concatenation.
fn Properties::alternation(alts : Array[Hir]) -> Properties {
  Properties::union(alts.map(hir => hir.properties()))
}

///|
/// A set of look-around assertions.
///
/// This is useful for efficiently tracking look-around assertions. For
/// example, an [`Hir`] provides properties that return `LookSet`s.
pub(all) struct LookSet {
  /// The underlying representation this set is exposed to make it possible
  /// to store it somewhere efficiently. The representation is that
  /// of a bitset, where each assertion occupies bit `i` where
  /// `i = Look::as_repr()`.
  bits : UInt32
} derive(Eq, Debug)

///|
/// Create an empty set of look-around assertions.
pub fn LookSet::empty() -> LookSet {
  { bits: 0, }
}

///|
/// Create a full set of look-around assertions.
pub fn LookSet::full() -> LookSet {
  { bits: 0xFFFFFFFFU, }
}

///|
/// Create a look-around set containing the look-around assertion given.
pub fn LookSet::singleton(look : Look) -> LookSet {
  LookSet::empty().insert(look)
}

///|
/// Returns the total number of look-around assertions in this set.
pub fn LookSet::len(self : LookSet) -> Int32 {
  self.bits.popcnt()
}

///|
/// Returns true if and only if this set is empty.
pub fn LookSet::is_empty(self : LookSet) -> Bool {
  self.len() == 0
}

///|
/// Returns true if and only if the given look-around assertion is in this
/// set.
pub fn LookSet::contains(self : LookSet, look : Look) -> Bool {
  (self.bits & look.as_repr()) != 0
}

///|
/// Return a new set that is equivalent to the original, but with the given
/// assertion added to it. If the assertion is already in the set, then the
/// returned set is equivalent to the original.
pub fn LookSet::insert(self : LookSet, look : Look) -> LookSet {
  { bits: self.bits | look.as_repr(), }
}

///|
/// Return a new set that is equivalent to the original, but with the given
/// assertion removed from it. If the assertion is not in the set, then the
/// returned set is equivalent to the original.
pub fn LookSet::remove(self : LookSet, look : Look) -> LookSet {
  { bits: self.bits & look.as_repr().lnot(), }
}

///|
/// Returns a new set that is the result of subtracting the given set from
/// this set.
pub fn LookSet::subtract(self : LookSet, other : LookSet) -> LookSet {
  { bits: self.bits & other.bits.lnot(), }
}

///|
/// Returns a new set that is the union of this and the one given.
pub fn LookSet::union(self : LookSet, other : LookSet) -> LookSet {
  { bits: self.bits | other.bits, }
}

///|
/// Returns a new set that is the intersection of this and the one given.
pub fn LookSet::intersect(self : LookSet, other : LookSet) -> LookSet {
  { bits: self.bits & other.bits, }
}

///|
/// Given a sequence of HIR values where each value corresponds to a Unicode
/// class (or an all-ASCII byte class), return a single Unicode class
/// corresponding to the union of the classes found.
fn class_chars(hirs : Array[Hir]) -> Class? {
  let cls = ClassUnicode::new([])
  for hir in hirs {
    match hir.kind() {
      Class(Unicode(cls2)) => cls.union(cls2)
      Class(Bytes(cls2)) =>
        match cls2.to_unicode_class() {
          Some(c) => cls.union(c)
          None => return None
        }
      _ => return None
    }
  }
  Some(Unicode(cls))
}

///|
/// Given a sequence of HIR values where each value corresponds to a byte class
/// (or an all-ASCII Unicode class), return a single byte class corresponding
/// to the union of the classes found.
fn class_bytes(hirs : Array[Hir]) -> Class? {
  let cls = ClassBytes::new([])
  for hir in hirs {
    match hir.kind() {
      Class(Unicode(cls2)) =>
        match cls2.to_byte_class() {
          Some(c) => cls.union(c)
          None => return None
        }
      Class(Bytes(cls2)) => cls.union(cls2)
      _ => return None
    }
  }
  Some(Bytes(cls))
}

///|
/// Given a sequence of HIR values where each value corresponds to a literal
/// that is a single `char`, return that sequence of `char`s. Otherwise return
/// None. No deduplication is done.
fn singleton_chars(hirs : Array[Hir]) -> Array[Int32]? {
  let singletons = []
  for hir in hirs {
    let literal = match hir.kind() {
      Literal(Literal(bytes)) => bytes
      _ => return None
    }
    let ch = match utf8_decode(literal[:]) {
      None => return None
      Some(Err(_)) => return None
      Some(Ok(ch)) => ch
    }
    if literal.length() != len_utf8(ch) {
      return None
    }
    singletons.push(ch)
  }
  Some(singletons)
}

///|
/// Given a sequence of HIR values where each value corresponds to a literal
/// that is a single byte, return that sequence of bytes. Otherwise return
/// None. No deduplication is done.
fn singleton_bytes(hirs : Array[Hir]) -> Array[Byte]? {
  let singletons = []
  for hir in hirs {
    let literal = match hir.kind() {
      Literal(Literal(bytes)) => bytes
      _ => return None
    }
    if literal.length() != 1 {
      return None
    }
    singletons.push(literal[0])
  }
  Some(singletons)
}

///|
/// Looks for a common prefix in the list of alternation branches given. If one
/// is found, then an equivalent but (hopefully) simplified Hir is returned.
/// Otherwise, the original given list of branches is returned unmodified.
///
/// This is not quite as good as it could be. Right now, it requires that
/// all branches are 'Concat' expressions. It also doesn't do well with
/// literals. For example, given 'foofoo|foobar', it will not refactor it to
/// 'foo(?:foo|bar)' because literals are flattened into their own special
/// concatenation. (One wonders if perhaps 'Literal' should be a single atom
/// instead of a string of bytes because of this. Otherwise, handling the
/// current representation in this routine will be pretty gnarly. Sigh.)
#warnings("-result_error_return")
fn lift_common_prefix(hirs : Array[Hir]) -> Result[Hir, Array[Hir]] {
  if hirs.length() <= 1 {
    return Err(hirs)
  }
  let mut prefix = match hirs[0].kind() {
    Concat(xs) => xs[:]
    _ => return Err(hirs)
  }
  if prefix.is_empty() {
    return Err(hirs)
  }
  for h in hirs[1:] {
    let concat = match h.kind() {
      Concat(xs) => xs
      _ => return Err(hirs)
    }
    let mut common_len = 0
    while common_len < prefix.length() &&
          common_len < concat.length() &&
          prefix[common_len] == concat[common_len] {
      common_len += 1
    }
    prefix = prefix[:common_len]
    if prefix.is_empty() {
      return Err(hirs)
    }
  }
  let len = prefix.length()
  guard len != 0 else { abort("assertion failed") }
  let mut prefix_concat = []
  let suffix_alts = []
  for h in hirs {
    let concat = match h.into_kind() {
      Concat(xs) => xs
      // We required all sub-expressions to be
      // concats above, so we're only here if we
      // have a concat.
      _ => abort("unreachable")
    }
    suffix_alts.push(Hir::concat(concat[len:].to_owned()))
    if prefix_concat.is_empty() {
      prefix_concat = concat[:len].to_owned()
    }
  }
  let concat = prefix_concat
  concat.push(Hir::alternation(suffix_alts))
  Ok(Hir::concat(concat))
}

///|
/// `debug::utf8_decode`: decode the first UTF-8 encoded code point in
/// `bytes`.
///
/// If no valid encoding of a code point exists at the beginning of the given
/// byte slice, then the first byte is returned instead. If `bytes` is empty,
/// `None` is returned.
#warnings("-result_error_return")
pub fn utf8_decode(bytes : BytesView) -> Result[Int32, Byte]? {
  fn len(byte : Byte) -> Int32? {
    if byte <= 0x7F {
      return Some(1)
    } else if (byte & 0b1100_0000) == 0b1000_0000 {
      return None
    } else if byte <= 0b1101_1111 {
      Some(2)
    } else if byte <= 0b1110_1111 {
      Some(3)
    } else if byte <= 0b1111_0111 {
      Some(4)
    } else {
      None
    }
  }

  if bytes.is_empty() {
    return None
  }
  let len = match len(bytes[0]) {
    None => return Some(Err(bytes[0]))
    Some(len) if len > bytes.length() => return Some(Err(bytes[0]))
    Some(1) => return Some(Ok(bytes[0].to_int()))
    Some(len) => len
  }
  try from_utf8(bytes[:len]) catch {
    _ => Some(Err(bytes[0]))
  } noraise {
    s => Some(Ok(s[0].to_int()))
  }
}

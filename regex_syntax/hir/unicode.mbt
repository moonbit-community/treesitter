// Port of regex-syntax 0.8.11 src/unicode.rs (with every `unicode-*` feature
// enabled, as in the crate's default build that tree-sitter uses). The
// module lives in the `hir` package because it builds `hir::ClassUnicode`
// values. Tables come from `@unicode_tables` (Unicode 16.0.0).

///|
/// An inclusive range of codepoints from a generated file.
type Range = Array[(Int32, Int32)]

///|
/// An error that occurs when dealing with Unicode (upstream
/// `unicode::Error`).
pub(all) suberror UnicodeError {
  PropertyNotFound
  PropertyValueNotFound
  // Not used when unicode-perl is enabled.
  PerlClassNotFound
} derive(Debug)

///|
/// An error that occurs when Unicode-aware simple case folding fails.
///
/// This error can occur when the case mapping tables necessary for Unicode
/// aware case folding are unavailable. This only occurs when the
/// `unicode-case` feature is disabled, so it never happens here.
pub(all) suberror CaseFoldError {
  CaseFoldError
} derive(Debug)

///|
pub impl Show for CaseFoldError with fn output(_self, f) {
  f.write_string(
    "Unicode-aware case folding is not available (probably because the unicode-case feature is not enabled)",
  )
}

///|
/// A state oriented traverser of the simple case folding table.
///
/// A case folder can be constructed via `SimpleCaseFolder::new()`, which will
/// return an error if the underlying case folding table is unavailable.
///
/// After construction, it is expected that callers will use
/// `SimpleCaseFolder::mapping` by calling it with codepoints in strictly
/// increasing order. For example, calling it on `b` and then on `a` is illegal
/// and will result in a panic.
pub struct SimpleCaseFolder {
  /// The simple case fold table. It's a sorted association list, where the
  /// keys are Unicode scalar values and the values are the corresponding
  /// equivalence class (not including the key) of the "simple" case folded
  /// Unicode scalar values.
  priv keys : FixedArray[Int32]
  priv values : FixedArray[FixedArray[Int32]]
  /// The last codepoint that was used for a lookup.
  priv mut last : Int32?
  /// The index to the entry in `table` corresponding to the smallest key `k`
  /// such that `k > k0`, where `k0` is the most recent key lookup. Note that
  /// in particular, `k0` may not be in the table!
  priv mut next : Int32
}

///|
let empty_mapping : FixedArray[Int32] = []

///|
/// Create a new simple case folder, returning an error if the underlying
/// case folding table is unavailable.
pub fn SimpleCaseFolder::new() -> SimpleCaseFolder raise CaseFoldError {
  let (keys, values) = @unicode_tables.case_folding_simple_table()
  { keys, values, last: None, next: 0, }
}

///|
/// Return the equivalence class of case folded codepoints for the given
/// codepoint. The equivalence class returned never includes the codepoint
/// given. If the given codepoint has no case folded codepoints (i.e.,
/// no entry in the underlying case folding table), then this returns an
/// empty slice.
///
/// # Panics
///
/// This panics when called with a `c` that is less than or equal to the
/// previous call. In other words, callers need to use this method with
/// strictly increasing values of `c`.
pub fn SimpleCaseFolder::mapping(
  self : SimpleCaseFolder,
  c : Int32,
) -> FixedArray[Int32] {
  if self.last is Some(last) {
    guard last < c else {
      abort("got codepoint U+\{c} which occurs before last codepoint U+\{last}")
    }
  }
  self.last = Some(c)
  if self.next >= self.keys.length() {
    return empty_mapping
  }
  let k = self.keys[self.next]
  if k == c {
    self.next += 1
    return self.values[self.next - 1]
  }
  match self.get(c) {
    Err(i) => {
      self.next = i
      empty_mapping
    }
    Ok(i) => {
      // Since we require lookups to proceed
      // in order, anything we find should be
      // after whatever we thought might be
      // next. Otherwise, the caller is either
      // going out of order or we would have
      // found our next key at 'self.next'.
      guard i > self.next else { abort("assertion failed: i > self.next") }
      self.next = i + 1
      self.values[i]
    }
  }
}

///|
/// Returns true if and only if the given range overlaps with any region
/// of the underlying case folding table. That is, when true, there exists
/// at least one codepoint in the inclusive range `[start, end]` that has
/// a non-trivial equivalence class of case folded codepoints. Conversely,
/// when this returns false, all codepoints in the range `[start, end]`
/// correspond to the trivial equivalence class of case folded codepoints,
/// i.e., itself.
///
/// # Panics
///
/// This panics when `end < start`.
pub fn SimpleCaseFolder::overlaps(
  self : SimpleCaseFolder,
  start : Int32,
  end : Int32,
) -> Bool {
  guard start <= end else { abort("assertion failed: start <= end") }
  let mut lo = 0
  let mut hi = self.keys.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let c = self.keys[mid]
    if start <= c && c <= end {
      return true
    } else if c > end {
      hi = mid
    } else {
      lo = mid + 1
    }
  }
  false
}

///|
/// Returns the index at which `c` occurs in the simple case fold table. If
/// `c` does not occur, then this returns an `i` such that `table[i-1].0 <
/// c` and `table[i].0 > c`.
fn SimpleCaseFolder::get(
  self : SimpleCaseFolder,
  c : Int32,
) -> Result[Int32, Int32] {
  let mut lo = 0
  let mut hi = self.keys.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let k = self.keys[mid]
    if k == c {
      return Ok(mid)
    } else if k < c {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  Err(lo)
}

///|
/// A query for finding a character class defined by Unicode. This supports
/// either use of a property name directly, or lookup by property value. The
/// former generally refers to Binary properties (see UTS#44, Table 8), but
/// as a special exception (see UTS#18, Section 1.2) both general categories
/// (an enumeration) and scripts (a catalog) are supported as if each of their
/// possible values were a binary property.
///
/// In all circumstances, property names and values are normalized and
/// canonicalized. That is, `GC == gc == GeneralCategory == general_category`.
pub(all) enum ClassQuery {
  /// Return a class corresponding to a Unicode binary property, named by
  /// a single letter.
  OneLetter(Char)
  /// Return a class corresponding to a Unicode binary property.
  ///
  /// Note that, by special exception (see UTS#18, Section 1.2), both
  /// general category values and script values are permitted here as if
  /// they were a binary property.
  Binary(String)
  /// Return a class corresponding to all codepoints whose property
  /// (identified by `property_name`) corresponds to the given value
  /// (identified by `property_value`).
  ByValue(property_name~ : String, property_value~ : String)
} derive(Debug)

///|
fn ClassQuery::canonicalize(
  self : ClassQuery,
) -> CanonicalClassQuery raise UnicodeError {
  match self {
    OneLetter(c) => self.canonical_binary(c.to_string())
    Binary(name) => self.canonical_binary(name)
    ByValue(property_name~, property_value~) => {
      let property_name = symbolic_name_normalize(property_name)
      let property_value = symbolic_name_normalize(property_value)
      let canon_name = match canonical_prop(property_name) {
        None => raise PropertyNotFound
        Some(canon_name) => canon_name
      }
      match canon_name {
        "General_Category" => {
          let canon = match canonical_gencat(property_value) {
            None => raise PropertyValueNotFound
            Some(canon) => canon
          }
          GeneralCategory(canon)
        }
        "Script" => {
          let canon = match canonical_script(property_value) {
            None => raise PropertyValueNotFound
            Some(canon) => canon
          }
          Script(canon)
        }
        _ => {
          let vals = match property_values(canon_name) {
            None => raise PropertyValueNotFound
            Some(vals) => vals
          }
          let canon_val = match canonical_value(vals, property_value) {
            None => raise PropertyValueNotFound
            Some(canon_val) => canon_val
          }
          ByValue(property_name=canon_name, property_value=canon_val)
        }
      }
    }
  }
}

///|
fn ClassQuery::canonical_binary(
  _self : ClassQuery,
  name : String,
) -> CanonicalClassQuery raise UnicodeError {
  let norm = symbolic_name_normalize(name)

  // This is a special case where 'cf' refers to the 'Format' general
  // category, but where the 'cf' abbreviation is also an abbreviation
  // for the 'Case_Folding' property. But we want to treat it as
  // a general category. (Currently, we don't even support the
  // 'Case_Folding' property. But if we do in the future, users will be
  // required to spell it out.)
  //
  // Also 'sc' refers to the 'Currency_Symbol' general category, but is
  // also the abbreviation for the 'Script' property. So we avoid calling
  // 'canonical_prop' for it too, which would erroneously normalize it
  // to 'Script'.
  //
  // Another case: 'lc' is an abbreviation for the 'Cased_Letter'
  // general category, but is also an abbreviation for the 'Lowercase_Mapping'
  // property. We don't currently support the latter, so as with 'cf'
  // above, we treat 'lc' as 'Cased_Letter'.
  if norm != "cf" && norm != "sc" && norm != "lc" {
    if canonical_prop(norm) is Some(canon) {
      return Binary(canon)
    }
  }
  if canonical_gencat(norm) is Some(canon) {
    return GeneralCategory(canon)
  }
  if canonical_script(norm) is Some(canon) {
    return Script(canon)
  }
  raise PropertyNotFound
}

///|
/// Like ClassQuery, but its parameters have been canonicalized. This also
/// differentiates binary properties from flattened general categories and
/// scripts.
priv enum CanonicalClassQuery {
  /// The canonical binary property name.
  Binary(String)
  /// The canonical general category name.
  GeneralCategory(String)
  /// The canonical script name.
  Script(String)
  /// An arbitrary association between property and value, both of which
  /// have been canonicalized.
  ///
  /// Note that by construction, the property name of ByValue will never
  /// be General_Category or Script. Those two cases are subsumed by the
  /// eponymous variants.
  ByValue(property_name~ : String, property_value~ : String)
}

///|
/// Looks up a Unicode class given a query. If one doesn't exist, then
/// `None` is returned.
pub fn class(query : ClassQuery) -> ClassUnicode raise UnicodeError {
  match query.canonicalize() {
    Binary(name) => bool_property(name)
    GeneralCategory(name) => gencat(name)
    Script(name) => script(name)
    ByValue(property_name="Age", property_value~) => {
      let class = ClassUnicode::empty()
      for set in ages(property_value) {
        class.union(hir_class(set))
      }
      class
    }
    ByValue(property_name="Script_Extensions", property_value~) =>
      script_extension(property_value)
    ByValue(property_name="Grapheme_Cluster_Break", property_value~) =>
      gcb(property_value)
    ByValue(property_name="Sentence_Break", property_value~) =>
      sb(property_value)
    ByValue(property_name="Word_Break", property_value~) => wb(property_value)
    _ =>
      // What else should we support?
      raise PropertyNotFound
  }
}

///|
/// Returns a Unicode aware class for \w.
///
/// This returns an error if the data is not available for \w.
pub fn perl_word() -> ClassUnicode raise UnicodeError {
  hir_class(@unicode_tables.decode_ranges(@unicode_tables.perl_word))
}

///|
/// Returns a Unicode aware class for \s.
///
/// This returns an error if the data is not available for \s.
pub fn perl_space() -> ClassUnicode raise UnicodeError {
  // `unicode-bool`: property_bool::WHITE_SPACE.
  hir_class(
    @unicode_tables.lookup_by_name(
      @unicode_tables.property_bool_by_name, "White_Space",
    ).unwrap(),
  )
}

///|
/// Returns a Unicode aware class for \d.
///
/// This returns an error if the data is not available for \d.
pub fn perl_digit() -> ClassUnicode raise UnicodeError {
  // `unicode-gencat`: general_category::DECIMAL_NUMBER.
  hir_class(
    @unicode_tables.lookup_by_name(
      @unicode_tables.general_category_by_name, "Decimal_Number",
    ).unwrap(),
  )
}

///|
/// Build a Unicode HIR class from a sequence of Unicode scalar value ranges.
pub fn hir_class(ranges : Array[(Int32, Int32)]) -> ClassUnicode {
  let hir_ranges : Array[ClassUnicodeRange] = ranges.map(r => {
    ClassUnicodeRange::new(r.0, r.1)
  })
  ClassUnicode::new(hir_ranges)
}

///|
/// Returns true only if the given codepoint is in the `\w` character class.
pub fn is_word_character(c : Int32) -> Bool {
  if c <= 0xFF && @ast.is_word_byte(c.to_byte()) {
    return true
  }
  let ranges = @unicode_tables.decode_ranges(@unicode_tables.perl_word)
  let mut lo = 0
  let mut hi = ranges.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let (start, end) = ranges[mid]
    if start <= c && c <= end {
      return true
    } else if start > c {
      hi = mid
    } else {
      lo = mid + 1
    }
  }
  false
}

///|
/// A mapping of property values for a specific property.
///
/// The first element of each tuple is a normalized property value while the
/// second element of each tuple is the corresponding canonical property
/// value.
type PropertyValues = Array[(String, String)]

///|
fn canonical_gencat(normalized_value : String) -> String? raise UnicodeError {
  match normalized_value {
    "any" => Some("Any")
    "assigned" => Some("Assigned")
    "ascii" => Some("ASCII")
    _ => {
      let gencats = property_values("General_Category").unwrap()
      canonical_value(gencats, normalized_value)
    }
  }
}

///|
fn canonical_script(normalized_value : String) -> String? raise UnicodeError {
  let scripts = property_values("Script").unwrap()
  canonical_value(scripts, normalized_value)
}

///|
/// Find the canonical property name for the given normalized property name.
///
/// If no such property exists, then `None` is returned.
///
/// The normalized property name must have been normalized according to
/// UAX44 LM3, which can be done using `symbolic_name_normalize`.
fn canonical_prop(normalized_name : String) -> String? raise UnicodeError {
  let names = @unicode_tables.property_names
  match
    @unicode_tables.binary_search_str(
      names.length(),
      i => names[i].0,
      normalized_name,
    ) {
    Some(i) => Some(names[i].1)
    None => None
  }
}

///|
/// Find the canonical property value for the given normalized property
/// value.
///
/// The given property values should correspond to the values for the property
/// under question, which can be found using `property_values`.
///
/// If no such property value exists, then `None` is returned.
fn canonical_value(vals : PropertyValues, normalized_value : String) -> String? {
  match
    @unicode_tables.binary_search_str(
      vals.length(),
      i => vals[i].0,
      normalized_value,
    ) {
    Some(i) => Some(vals[i].1)
    None => None
  }
}

///|
/// Return the table of property values for the given property name.
///
/// If the property values data is not available, then an error is returned.
fn property_values(
  canonical_property_name : String,
) -> PropertyValues? raise UnicodeError {
  let values = @unicode_tables.property_values
  match
    @unicode_tables.binary_search_str(
      values.length(),
      i => values[i].0,
      canonical_property_name,
    ) {
    Some(i) => Some(values[i].1)
    None => None
  }
}

///|
fn property_set(
  name_map : Array[(String, String)],
  canonical : String,
) -> Range? {
  @unicode_tables.lookup_by_name(name_map, canonical)
}

///|
/// The Unicode Age sets, in chronological order (upstream `AGES`).
let ages_in_order : Array[String] = [
  "V1_1", "V2_0", "V2_1", "V3_0", "V3_1", "V3_2", "V4_0", "V4_1", "V5_0", "V5_1",
  "V5_2", "V6_0", "V6_1", "V6_2", "V6_3", "V7_0", "V8_0", "V9_0", "V10_0", "V11_0",
  "V12_0", "V12_1", "V13_0", "V14_0", "V15_0", "V15_1", "V16_0",
]

///|
/// Returns an iterator over Unicode Age sets. Each item corresponds to a set
/// of codepoints that were added in a particular revision of Unicode. The
/// iterator yields items in chronological order.
///
/// If the given age value isn't valid or if the data isn't available, then an
/// error is returned instead.
fn ages(canonical_age : String) -> Array[Range] raise UnicodeError {
  guard ages_in_order.length() == @unicode_tables.age_by_name.length() else {
    abort("ages are out of sync")
  }
  let pos = ages_in_order.search(canonical_age)
  match pos {
    None => raise PropertyValueNotFound
    Some(i) =>
      ages_in_order[:i + 1]
      .iter()
      .map(age => property_set(@unicode_tables.age_by_name, age).unwrap())
      .collect()
  }
}

///|
/// Returns the Unicode HIR class corresponding to the given general category.
///
/// Name canonicalization is assumed to be performed by the caller.
///
/// If the given general category could not be found, or if the general
/// category data is not available, then an error is returned.
fn gencat(canonical_name : String) -> ClassUnicode raise UnicodeError {
  fn imp(name : String) -> ClassUnicode raise UnicodeError {
    match name {
      "ASCII" => hir_class([(0, 0x7F)])
      "Any" => hir_class([(0, 0x10FFFF)])
      "Assigned" => {
        let cls = gencat("Unassigned")
        cls.negate()
        cls
      }
      name =>
        match property_set(@unicode_tables.general_category_by_name, name) {
          Some(set) => hir_class(set)
          None => raise PropertyValueNotFound
        }
    }
  }

  match canonical_name {
    "Decimal_Number" => perl_digit()
    name => imp(name)
  }
}

///|
/// Returns the Unicode HIR class corresponding to the given script.
///
/// Name canonicalization is assumed to be performed by the caller.
///
/// If the given script could not be found, or if the script data is not
/// available, then an error is returned.
fn script(canonical_name : String) -> ClassUnicode raise UnicodeError {
  match property_set(@unicode_tables.script_by_name, canonical_name) {
    Some(set) => hir_class(set)
    None => raise PropertyValueNotFound
  }
}

///|
/// Returns the Unicode HIR class corresponding to the given script extension.
///
/// Name canonicalization is assumed to be performed by the caller.
///
/// If the given script extension could not be found, or if the script data is
/// not available, then an error is returned.
fn script_extension(canonical_name : String) -> ClassUnicode raise UnicodeError {
  match property_set(@unicode_tables.script_extension_by_name, canonical_name) {
    Some(set) => hir_class(set)
    None => raise PropertyValueNotFound
  }
}

///|
/// Returns the Unicode HIR class corresponding to the given Unicode boolean
/// property.
///
/// Name canonicalization is assumed to be performed by the caller.
///
/// If the given boolean property could not be found, or if the boolean
/// property data is not available, then an error is returned.
fn bool_property(canonical_name : String) -> ClassUnicode raise UnicodeError {
  match canonical_name {
    "Decimal_Number" => perl_digit()
    "White_Space" => perl_space()
    name =>
      match property_set(@unicode_tables.property_bool_by_name, name) {
        Some(set) => hir_class(set)
        None => raise PropertyNotFound
      }
  }
}

///|
/// Returns the Unicode HIR class corresponding to the given grapheme cluster
/// break property.
///
/// Name canonicalization is assumed to be performed by the caller.
///
/// If the given property could not be found, or if the corresponding data is
/// not available, then an error is returned.
fn gcb(canonical_name : String) -> ClassUnicode raise UnicodeError {
  match
    property_set(@unicode_tables.grapheme_cluster_break_by_name, canonical_name) {
    Some(set) => hir_class(set)
    None => raise PropertyValueNotFound
  }
}

///|
/// Returns the Unicode HIR class corresponding to the given word break
/// property.
///
/// Name canonicalization is assumed to be performed by the caller.
///
/// If the given property could not be found, or if the corresponding data is
/// not available, then an error is returned.
fn wb(canonical_name : String) -> ClassUnicode raise UnicodeError {
  match property_set(@unicode_tables.word_break_by_name, canonical_name) {
    Some(set) => hir_class(set)
    None => raise PropertyValueNotFound
  }
}

///|
/// Returns the Unicode HIR class corresponding to the given sentence
/// break property.
///
/// Name canonicalization is assumed to be performed by the caller.
///
/// If the given property could not be found, or if the corresponding data is
/// not available, then an error is returned.
fn sb(canonical_name : String) -> ClassUnicode raise UnicodeError {
  match property_set(@unicode_tables.sentence_break_by_name, canonical_name) {
    Some(set) => hir_class(set)
    None => raise PropertyValueNotFound
  }
}

///|
/// Like symbolic_name_normalize_bytes, but operates on a string.
fn symbolic_name_normalize(x : String) -> String {
  let tmp = utf8_encode(x)
  let len = symbolic_name_normalize_bytes(tmp)
  // This should always succeed because `symbolic_name_normalize_bytes`
  // guarantees that `&tmp[..len]` is always valid UTF-8 (ASCII).
  let buf = StringBuilder()
  for i in 0..<len {
    buf.write_char(tmp[i].to_int().unsafe_to_char())
  }
  buf.to_string()
}

///|
/// Normalize the given symbolic name in place according to UAX44-LM3,
/// returning the length of the normalized prefix.
///
/// A "symbolic name" typically corresponds to property names and property
/// value aliases. Note, though, that it should not be applied to property
/// string values.
///
/// The slice returned is guaranteed to be valid UTF-8 for all possible values
/// of `slice`.
///
/// See: https://unicode.org/reports/tr44/#UAX44-LM3
fn symbolic_name_normalize_bytes(slice : Array[Byte]) -> Int32 {
  // I couldn't find a place in the standard that specified that property
  // names/aliases had a particular structure (unlike character names), but
  // we assume that it's ASCII only and drop anything that isn't ASCII.
  let mut start = 0
  let mut starts_with_is = false
  if slice.length() >= 2 {
    // Ignore any "is" prefix.
    starts_with_is = (slice[0] == b'i' || slice[0] == b'I') &&
      (slice[1] == b's' || slice[1] == b'S')
    if starts_with_is {
      start = 2
    }
  }
  let mut next_write = 0
  for i in start..<slice.length() {
    // VALIDITY ARGUMENT: To guarantee that the resulting slice is valid
    // UTF-8, we ensure that the slice contains only ASCII bytes. In
    // particular, we drop every non-ASCII byte from the normalized string.
    let b = slice[i]
    if b == b' ' || b == b'_' || b == b'-' {
      continue
    } else if b'A' <= b && b <= b'Z' {
      slice[next_write] = b + (b'a' - b'A')
      next_write += 1
    } else if b <= 0x7F {
      slice[next_write] = b
      next_write += 1
    }
  }
  // Special case: ISO_Comment has a 'isc' abbreviation. Since we generally
  // ignore 'is' prefixes, the 'isc' abbreviation gets caught in the cross
  // fire and ends up creating an alias for 'c' to 'ISO_Comment', but it
  // is actually an alias for the 'Other' general category.
  if starts_with_is && next_write == 1 && slice[0] == b'c' {
    slice[0] = b'i'
    slice[1] = b's'
    slice[2] = b'c'
    next_write = 3
  }
  next_write
}

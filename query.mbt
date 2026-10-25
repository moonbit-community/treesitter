// Port of `Query` and its predicate parsing (`Query::new_raw`,
// `Query::from_raw_parts`, `Query::parse_property`), `QueryError`,
// `QueryProperty`, `QueryPredicate` and `CaptureQuantifier` from tree-sitter
// lib/binding_rust/lib.rs.

///|
/// A quantifier for captures.
pub(all) enum CaptureQuantifier {
  Zero
  ZeroOrOne
  ZeroOrMore
  One
  OneOrMore
} derive(Eq, Debug)

///|
fn CaptureQuantifier::from_ts(q : @query.Quantifier) -> CaptureQuantifier {
  match q {
    Zero => Zero
    ZeroOrOne => ZeroOrOne
    ZeroOrMore => ZeroOrMore
    One => One
    OneOrMore => OneOrMore
  }
}

///|
/// A key-value pair associated with a particular pattern in a [`Query`].
pub(all) struct QueryProperty {
  key : String
  value : String?
  capture_id : Int32?
} derive(Eq)

///|
/// Rust's derived `Debug`: `QueryProperty { key: "k", value: Some("v"),
/// capture_id: None }`.
pub impl Debug for QueryProperty with fn to_repr(self) {
  let value = match self.value {
    Some(value) => "Some(\{@serde_json.rust_debug_str(value)})"
    None => "None"
  }
  let capture_id = match self.capture_id {
    Some(id) => "Some(\{id})"
    None => "None"
  }
  Repr::literal(
    "QueryProperty { key: \{@serde_json.rust_debug_str(self.key)}, value: \{value}, capture_id: \{capture_id} }",
  )
}

///|
/// Create a query property.
pub fn QueryProperty::new(
  key : String,
  value : String?,
  capture_id : Int32?,
) -> QueryProperty {
  { key, value, capture_id, }
}

///|
/// An argument of a [`QueryPredicate`]: a capture index or a string.
pub(all) enum QueryPredicateArg {
  Capture(Int32)
  String(String)
} derive(Eq)

///|
/// Rust's derived `Debug`: `Capture(0)` or `String("text")`.
pub impl Debug for QueryPredicateArg with fn to_repr(self) {
  Repr::literal(self.debug_text())
}

///|
fn QueryPredicateArg::debug_text(self : QueryPredicateArg) -> String {
  match self {
    Capture(index) => "Capture(\{index})"
    String(text) => "String(\{@serde_json.rust_debug_str(text)})"
  }
}

///|
/// A predicate with a user-defined operator associated with a particular
/// pattern in a [`Query`].
pub(all) struct QueryPredicate {
  operator : String
  args : Array[QueryPredicateArg]
} derive(Eq)

///|
/// Rust's derived `Debug`: `QueryPredicate { operator: "op?", args:
/// [Capture(0), String("text")] }`.
pub impl Debug for QueryPredicate with fn to_repr(self) {
  let args = self.args.map(arg => arg.debug_text()).join(", ")
  Repr::literal(
    "QueryPredicate { operator: \{@serde_json.rust_debug_str(self.operator)}, args: [\{args}] }",
  )
}

///|
/// The kind of a [`QueryError`].
pub(all) enum QueryErrorKind {
  Syntax
  NodeType
  Field
  Capture
  Predicate
  Structure
  Language
} derive(Eq, Debug)

///|
/// An error that occurred when trying to create a [`Query`].
pub(all) suberror QueryError {
  QueryError(
    row~ : Int32,
    column~ : Int32,
    offset~ : Int32,
    message~ : String,
    kind~ : QueryErrorKind
  )
} derive(Eq)

///|
/// Rust's derived `Debug` of the `QueryError` struct: `QueryError { row: 0,
/// column: 0, offset: 0, message: "...", kind: Syntax }`.
pub impl Debug for QueryError with fn to_repr(self) {
  let QueryError(row~, column~, offset~, message~, kind~) = self
  let kind = match kind {
    Syntax => "Syntax"
    NodeType => "NodeType"
    Field => "Field"
    Capture => "Capture"
    Predicate => "Predicate"
    Structure => "Structure"
    Language => "Language"
  }
  Repr::literal(
    "QueryError { row: \{row}, column: \{column}, offset: \{offset}, message: \{@serde_json.rust_debug_str(message)}, kind: \{kind} }",
  )
}

///|
/// The zero-based row of the error.
pub fn QueryError::row(self : QueryError) -> Int32 {
  let QueryError(row~, ..) = self
  row
}

///|
/// The zero-based column of the error.
pub fn QueryError::column(self : QueryError) -> Int32 {
  let QueryError(column~, ..) = self
  column
}

///|
/// The byte offset of the error in the query source.
pub fn QueryError::offset(self : QueryError) -> Int32 {
  let QueryError(offset~, ..) = self
  offset
}

///|
/// The error message (without the `Query error at ...` prefix).
pub fn QueryError::message(self : QueryError) -> String {
  let QueryError(message~, ..) = self
  message
}

///|
/// The kind of the error.
pub fn QueryError::kind(self : QueryError) -> QueryErrorKind {
  let QueryError(kind~, ..) = self
  kind
}

///|
pub impl Show for QueryError with fn output(self, logger) {
  let QueryError(row~, column~, message~, kind~, ..) = self
  let msg = match kind {
    Field => "Invalid field name "
    NodeType => "Invalid node type "
    Capture => "Invalid capture name "
    Predicate => "Invalid predicate: "
    Structure => "Impossible pattern:\n"
    Syntax => "Invalid syntax:\n"
    Language => ""
  }
  if msg.is_empty() {
    logger.write_string(message)
  } else {
    logger.write_string(
      "Query error at \{row + 1}:\{column + 1}. \{msg}\{message}",
    )
  }
}

///|
fn predicate_error(row : Int32, message : String) -> QueryError {
  QueryError(kind=Predicate, row~, column=0, offset=0, message~)
}

///|
/// A text predicate, by capture index. The first `Bool` is whether the
/// predicate is positive; the last is whether it must hold for all captured
/// nodes (as opposed to any of them).
priv enum TextPredicateCapture {
  EqString(Int32, Bytes, Bool, Bool)
  EqCapture(Int32, Int32, Bool, Bool)
  MatchString(Int32, @regex.Regex, Bool, Bool)
  AnyString(Int32, Array[Bytes], Bool)
}

///|
/// A set of patterns that match nodes in a syntax tree.
pub struct Query {
  priv raw : @query.Query
  priv capture_names : Array[String]
  priv capture_quantifiers : Array[Array[CaptureQuantifier]]
  priv text_predicates : Array[Array[TextPredicateCapture]]
  priv property_settings : Array[Array[QueryProperty]]
  priv property_predicates : Array[Array[(QueryProperty, Bool)]]
  priv general_predicates : Array[Array[QueryPredicate]]
}

///|
/// The runtime query wrapped by this query.
pub fn Query::raw(self : Query) -> @query.Query {
  self.raw
}

///|
/// Queries are equal when they are the same object.
pub impl Eq for Query with fn equal(self, other) {
  physical_equal(self.raw, other.raw)
}

///|
/// Create a new query from a string containing one or more S-expression
/// patterns.
///
/// The query is associated with a particular language, and can only be run
/// on syntax nodes parsed with that language.
pub fn Query::new(
  language : Language,
  source : String,
) -> Query raise QueryError {
  let bytes = @utf8.encode(source)
  let raw = Query::new_raw(language, bytes)
  Query::from_raw_parts(raw, bytes)
}

///|
/// Constructs a raw query without performing extra checks specific to the
/// bindings, such as predicate validation, and computes the row, column and
/// message of a failure from the error offset.
pub fn Query::new_raw(
  language : Language,
  source : Bytes,
) -> @query.Query raise QueryError {
  let (error_type, error_offset) = try
    @query.Query::new(language.raw, source)
  catch {
    QueryError(kind~, offset~) => (kind, offset)
  } noraise {
    query => return query
  }
  // On failure, build an error based on the error code and offset.
  if error_type is Language {
    raise QueryError(
      row=0,
      column=0,
      offset=0,
      message=Show::to_string(LanguageError::Version(language.abi_version())),
      kind=Language,
    )
  }
  let offset = error_offset.reinterpret_as_int()
  let mut line_start = 0
  let mut row = 0
  let mut line_containing_error : BytesView? = None
  for line in rust_lines(source) {
    let line_end = line_start + line.length() + 1
    if line_end > offset {
      line_containing_error = Some(line)
      break
    }
    line_start = line_end
    row += 1
  }
  let column = offset - line_start
  let (message, kind) : (String, QueryErrorKind) = match error_type {
    // Error types that report names
    NodeType | Field | Capture => {
      let suffix = source[offset:]
      let in_quotes = offset > 0 && source[offset - 1] == b'"'
      let mut backslashes = 0
      let mut end_offset = suffix.length()
      let mut i = 0
      while i < suffix.length() {
        let (c, width) = decode_char(suffix, i)
        let stop = if in_quotes {
          if c == '"' && backslashes % 2 == 0 {
            true
          } else if c == '\\' {
            backslashes += 1
            false
          } else {
            backslashes = 0
            false
          }
        } else {
          !is_alphanumeric(c) && c != '_' && c != '-'
        }
        if stop {
          end_offset = i
          break
        }
        i += width
      }
      let kind : QueryErrorKind = match error_type {
        NodeType => NodeType
        Field => Field
        _ => Capture
      }
      ("\"\{@utf8.decode_lossy(suffix[:end_offset])}\"", kind)
    }
    // Error types that report positions
    _ => {
      let message = match line_containing_error {
        None => "Unexpected EOF"
        Some(line) =>
          @utf8.decode_lossy(line) +
          "\n" +
          " ".repeat(offset - line_start) +
          "^"
      }
      (message, if error_type is Structure { Structure } else { Syntax })
    }
  }
  raise QueryError(row~, column~, offset~, message~, kind~)
}

///|
/// Rust's `str::lines`: split after each `\n`, strip the `\n` and then one
/// `\r` before it, and yield no final empty line.
fn rust_lines(source : BytesView) -> Array[BytesView] {
  let lines = []
  let mut start = 0
  let len = source.length()
  while start < len {
    let mut end = start
    while end < len && source[end] != b'\n' {
      end += 1
    }
    let mut line_end = end
    if end < len && line_end > start && source[line_end - 1] == b'\r' {
      line_end -= 1
    }
    lines.push(source[start:line_end])
    start = end + 1
  }
  lines
}

///|
/// Decode the UTF-8 character at `i` (the replacement character for an
/// invalid byte), returning it with its width.
fn decode_char(bytes : BytesView, i : Int32) -> (Char, Int32) {
  match @hir.utf8_decode(bytes[i:]) {
    Some(Ok(cp)) => (cp.unsafe_to_char(), @hir.len_utf8(cp))
    _ => ('\u{FFFD}', 1)
  }
}

///|
let alphanumeric_class : Ref[@hir.ClassUnicode?] = Ref(None)

///|
/// Rust's `char::is_alphanumeric`: the `Alphabetic` property or a general
/// category of `Number`.
fn is_alphanumeric(c : Char) -> Bool {
  if c.is_ascii() {
    return c.is_ascii_alphabetic() || c.is_ascii_digit()
  }
  let cls = match alphanumeric_class.val {
    Some(cls) => cls
    None => {
      let cls = try! @hir.class(Binary("Alphabetic"))
      cls.union(try! @hir.class(OneLetter('N')))
      alphanumeric_class.val = Some(cls)
      cls
    }
  }
  let cp = c.to_int()
  let ranges = cls.ranges()
  let mut lo = 0
  let mut hi = ranges.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if cp < ranges[mid].start() {
      hi = mid
    } else if cp > ranges[mid].end() {
      lo = mid + 1
    } else {
      return true
    }
  }
  false
}

///|
/// Build a [`Query`] from a raw query, parsing and validating its predicates.
/// `source` is only used for the rows of predicate errors.
fn Query::from_raw_parts(
  raw : @query.Query,
  source : BytesView,
) -> Query raise QueryError {
  let string_count = raw.string_count()
  let capture_count = raw.capture_count()
  let pattern_count = raw.pattern_count()
  let capture_names = []
  let capture_quantifiers_vec = []
  let text_predicates_vec = []
  let property_predicates_vec = []
  let property_settings_vec = []
  let general_predicates_vec = []
  // Build a vector of strings to store the capture names.
  for i in 0..<capture_count {
    capture_names.push(raw.capture_name_for_id(i))
  }
  // Build a vector to store capture quantifiers.
  for i in 0..<pattern_count {
    let capture_quantifiers = []
    for j in 0..<capture_count {
      capture_quantifiers.push(
        CaptureQuantifier::from_ts(raw.capture_quantifier_for_id(i, j)),
      )
    }
    capture_quantifiers_vec.push(capture_quantifiers)
  }
  // Build a vector of strings to represent literal values used in predicates.
  let string_bytes = Array::makei(string_count, i => {
    raw.string_value_bytes_for_id(i)
  })
  let string_values = string_bytes.map(b => @utf8.decode_lossy(b))
  // Build a vector of predicates for each pattern.
  for i in 0..<pattern_count {
    let predicate_steps = raw.predicates_for_pattern(i)
    let byte_offset = raw.start_byte_for_pattern(i).reinterpret_as_int()
    let mut row = 0
    for k in 0..<byte_offset {
      if k < source.length() && source[k] == b'\n' {
        row += 1
      }
    }
    let text_predicates = []
    let property_predicates = []
    let property_settings = []
    let general_predicates = []
    for p in split_predicate_steps(predicate_steps) {
      if p.length() == 0 {
        continue
      }
      if !(p[0].type_ is String) {
        raise predicate_error(
          row,
          "Expected predicate to start with a function name. Got @\{capture_names[p[0].value_id]}.",
        )
      }
      // Build a predicate for each of the known predicate function names.
      let operator_name = string_values[p[0].value_id]
      match operator_name {
        "eq?" | "not-eq?" | "any-eq?" | "any-not-eq?" => {
          if p.length() != 3 {
            raise predicate_error(
              row,
              "Wrong number of arguments to #eq? predicate. Expected 2, got \{p.length() - 1}.",
            )
          }
          if !(p[1].type_ is Capture) {
            raise predicate_error(
              row,
              "First argument to #eq? predicate must be a capture name. Got literal \"\{string_values[p[1].value_id]}\".",
            )
          }
          let is_positive = operator_name == "eq?" || operator_name == "any-eq?"
          let match_all = operator_name is ("eq?" | "not-eq?")
          text_predicates.push(
            if p[2].type_ is Capture {
              EqCapture(p[1].value_id, p[2].value_id, is_positive, match_all)
            } else {
              EqString(
                p[1].value_id,
                string_bytes[p[2].value_id],
                is_positive,
                match_all,
              )
            },
          )
        }
        "match?" | "not-match?" | "any-match?" | "any-not-match?" => {
          if p.length() != 3 {
            raise predicate_error(
              row,
              "Wrong number of arguments to #match? predicate. Expected 2, got \{p.length() - 1}.",
            )
          }
          if !(p[1].type_ is Capture) {
            raise predicate_error(
              row,
              "First argument to #match? predicate must be a capture name. Got literal \"\{string_values[p[1].value_id]}\".",
            )
          }
          if p[2].type_ is Capture {
            raise predicate_error(
              row,
              "Second argument to #match? predicate must be a literal. Got capture @\{capture_names[p[2].value_id]}.",
            )
          }
          let is_positive = operator_name == "match?" ||
            operator_name == "any-match?"
          let match_all = operator_name is ("match?" | "not-match?")
          let regex = string_values[p[2].value_id]
          let compiled = @regex.Regex::new(regex) catch {
            _ => raise predicate_error(row, "Invalid regex '\{regex}'")
          }
          text_predicates.push(
            MatchString(p[1].value_id, compiled, is_positive, match_all),
          )
        }
        "set!" =>
          property_settings.push(
            parse_property(
              row,
              operator_name,
              capture_names,
              string_values,
              p[1:],
            ),
          )
        "is?" | "is-not?" =>
          property_predicates.push(
            (
              parse_property(
                row,
                operator_name,
                capture_names,
                string_values,
                p[1:],
              ),
              operator_name == "is?",
            ),
          )
        "any-of?" | "not-any-of?" => {
          if p.length() < 2 {
            raise predicate_error(
              row,
              "Wrong number of arguments to #any-of? predicate. Expected at least 1, got \{p.length() - 1}.",
            )
          }
          if !(p[1].type_ is Capture) {
            raise predicate_error(
              row,
              "First argument to #any-of? predicate must be a capture name. Got literal \"\{string_values[p[1].value_id]}\".",
            )
          }
          let is_positive = operator_name == "any-of?"
          let values = []
          for arg in p[2:] {
            if arg.type_ is Capture {
              raise predicate_error(
                row,
                "Arguments to #any-of? predicate must be literals. Got capture @\{capture_names[arg.value_id]}.",
              )
            }
            values.push(string_bytes[arg.value_id])
          }
          text_predicates.push(AnyString(p[1].value_id, values, is_positive))
        }
        _ =>
          general_predicates.push({
            operator: operator_name,
            args: p[1:]
            .iter()
            .map(a => {
              if a.type_ is Capture {
                QueryPredicateArg::Capture(a.value_id)
              } else {
                QueryPredicateArg::String(string_values[a.value_id])
              }
            })
            .to_array(),
          })
      }
    }
    text_predicates_vec.push(text_predicates)
    property_predicates_vec.push(property_predicates)
    property_settings_vec.push(property_settings)
    general_predicates_vec.push(general_predicates)
  }
  {
    raw,
    capture_names,
    capture_quantifiers: capture_quantifiers_vec,
    text_predicates: text_predicates_vec,
    property_predicates: property_predicates_vec,
    property_settings: property_settings_vec,
    general_predicates: general_predicates_vec,
  }
}

///|
/// Rust's `slice::split` on `Done` steps: the (possibly empty) runs of steps
/// between `Done` markers, including the run after the last marker.
fn split_predicate_steps(
  steps : ArrayView[@query.QueryPredicateStep],
) -> Array[ArrayView[@query.QueryPredicateStep]] {
  let result = []
  let mut start = 0
  for i, step in steps {
    if step.type_ is Done {
      result.push(steps[start:i])
      start = i + 1
    }
  }
  result.push(steps[start:])
  result
}

///|
fn parse_property(
  row : Int32,
  function_name : String,
  capture_names : Array[String],
  string_values : Array[String],
  args : ArrayView[@query.QueryPredicateStep],
) -> QueryProperty raise QueryError {
  if args.length() == 0 || args.length() > 3 {
    raise predicate_error(
      row,
      "Wrong number of arguments to \{function_name} predicate. Expected 1 to 3, got \{args.length()}.",
    )
  }
  let mut capture_id : Int32? = None
  let mut key : String? = None
  let mut value : String? = None
  for arg in args {
    if arg.type_ is Capture {
      if capture_id is Some(_) {
        raise predicate_error(
          row,
          "Invalid arguments to \{function_name} predicate. Unexpected second capture name @\{capture_names[arg.value_id]}",
        )
      }
      capture_id = Some(arg.value_id)
    } else if key is None {
      key = Some(string_values[arg.value_id])
    } else if value is None {
      value = Some(string_values[arg.value_id])
    } else {
      raise predicate_error(
        row,
        "Invalid arguments to \{function_name} predicate. Unexpected third argument @\{string_values[arg.value_id]}",
      )
    }
  }
  match key {
    Some(key) => QueryProperty::new(key, value, capture_id)
    None =>
      raise predicate_error(
        row,
        "Invalid arguments to \{function_name} predicate. Missing key argument",
      )
  }
}

///|
fn Query::check_pattern_index(self : Query, pattern_index : Int32) -> Unit {
  if pattern_index < 0 || pattern_index >= self.text_predicates.length() {
    abort(
      "Pattern index is \{pattern_index} but the pattern count is \{self.text_predicates.length()}",
    )
  }
}

///|
/// Get the byte offset where the given pattern starts in the query's source.
pub fn Query::start_byte_for_pattern(
  self : Query,
  pattern_index : Int32,
) -> Int32 {
  self.check_pattern_index(pattern_index)
  self.raw.start_byte_for_pattern(pattern_index).reinterpret_as_int()
}

///|
/// Get the byte offset where the given pattern ends in the query's source.
pub fn Query::end_byte_for_pattern(
  self : Query,
  pattern_index : Int32,
) -> Int32 {
  self.check_pattern_index(pattern_index)
  self.raw.end_byte_for_pattern(pattern_index).reinterpret_as_int()
}

///|
/// Get the number of patterns in the query.
pub fn Query::pattern_count(self : Query) -> Int32 {
  self.raw.pattern_count()
}

///|
/// Get the names of the captures used in the query.
pub fn Query::capture_names(self : Query) -> ArrayView[String] {
  self.capture_names[:]
}

///|
/// Get the quantifiers of the captures used in the given pattern.
pub fn Query::capture_quantifiers(
  self : Query,
  index : Int32,
) -> ArrayView[CaptureQuantifier] {
  self.capture_quantifiers[index][:]
}

///|
/// Get the index for a given capture name.
pub fn Query::capture_index_for_name(self : Query, name : StringView) -> Int32? {
  for i, n in self.capture_names {
    if n[:] == name {
      return Some(i)
    }
  }
  None
}

///|
/// Get the properties that are checked for the given pattern index.
///
/// This includes predicates with the operators `is?` and `is-not?`.
pub fn Query::property_predicates(
  self : Query,
  index : Int32,
) -> ArrayView[(QueryProperty, Bool)] {
  self.property_predicates[index][:]
}

///|
/// Get the properties that are set for the given pattern index.
///
/// This includes predicates with the operator `set!`.
pub fn Query::property_settings(
  self : Query,
  index : Int32,
) -> ArrayView[QueryProperty] {
  self.property_settings[index][:]
}

///|
/// Get the other user-defined predicates associated with the given index.
///
/// This includes predicate with operators other than `match?`, `eq?` and
/// `not-eq?` (and their `any-` variants), `any-of?` and `not-any-of?`, `is?`
/// and `is-not?`, and `set!`.
pub fn Query::general_predicates(
  self : Query,
  index : Int32,
) -> ArrayView[QueryPredicate] {
  self.general_predicates[index][:]
}

///|
/// Disable a certain capture within a query.
///
/// This prevents the capture from being returned in matches, and also avoids
/// any resource usage associated with recording the capture.
pub fn Query::disable_capture(self : Query, name : StringView) -> Unit {
  self.raw.disable_capture(name)
}

///|
/// Disable a certain pattern within a query.
///
/// This prevents the pattern from matching, and also avoids any resource
/// usage associated with the pattern.
pub fn Query::disable_pattern(self : Query, index : Int32) -> Unit {
  self.raw.disable_pattern(index)
}

///|
/// Create a deep copy of this query.
///
/// Queries can be shared across cursors without cloning. You should only need
/// this when you want an independent copy to mutate (e.g. via
/// [`disable_capture`](Query::disable_capture) or
/// [`disable_pattern`](Query::disable_pattern)).
pub fn Query::deep_clone(self : Query) -> Query {
  // A copy of an already-valid query cannot fail to build.
  try! Query::from_raw_parts(self.raw.copy(), b"")
}

///|
/// Check if a given pattern within a query has a single root node.
pub fn Query::is_pattern_rooted(self : Query, index : Int32) -> Bool {
  self.raw.is_pattern_rooted(index)
}

///|
/// Check if a given pattern within a query is non-local.
pub fn Query::is_pattern_non_local(self : Query, index : Int32) -> Bool {
  self.raw.is_pattern_non_local(index)
}

///|
/// Check if a given step in a query is 'definite'.
///
/// A query step is 'definite' if its parent pattern will be guaranteed to
/// match successfully once it reaches the step.
pub fn Query::is_pattern_guaranteed_at_step(
  self : Query,
  byte_offset : Int32,
) -> Bool {
  self.raw.is_pattern_guaranteed_at_step(to_u32(byte_offset))
}

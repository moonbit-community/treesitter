// Port of `QueryCursor`, `QueryMatches`, `QueryCaptures`, `QueryMatch`,
// `QueryCapture`, `TextProvider`, `QueryCursorOptions` and
// `QueryCursorState` from tree-sitter lib/binding_rust/lib.rs.

///|
/// A source of node text for evaluating text predicates (`#eq?`, `#match?`,
/// `#any-of?` and their variants): the text of a node as a sequence of
/// chunks, which are concatenated.
///
/// Implemented for source bytes (`Bytes`, `BytesView`) and for callbacks via
/// [`TextCallback`].
pub(open) trait TextProvider {
  fn text(Self, Node) -> Iter[BytesView]
}

///|
/// The node's byte range of the source.
pub impl TextProvider for Bytes with fn text(self, node) {
  // Rust's `&self[node.byte_range()]` panics when out of bounds.
  Iter::singleton(self.exact_view(start=node.start_byte(), end=node.end_byte()))
}

///|
/// The node's byte range of the source.
pub impl TextProvider for BytesView with fn text(self, node) {
  Iter::singleton(self.exact_view(start=node.start_byte(), end=node.end_byte()))
}

///|
/// A [`TextProvider`] backed by a function from a node to its text chunks
/// (upstream implements `TextProvider` for such closures directly).
pub struct TextCallback {
  priv f : (Node) -> Iter[BytesView]
}

///|
/// Wrap a function from a node to its text chunks.
pub fn TextCallback::new(f : (Node) -> Iter[BytesView]) -> TextCallback {
  { f, }
}

///|
pub impl TextProvider for TextCallback with fn text(self, node) {
  (self.f)(node)
}

///|
/// The state of a query cursor passed to a query progress callback.
pub struct QueryCursorState {
  priv current_byte_offset : Int32
}

///|
/// The byte offset the query execution has reached.
pub fn QueryCursorState::current_byte_offset(self : QueryCursorState) -> Int32 {
  self.current_byte_offset
}

///|
/// Options for query execution; currently a progress callback that can
/// cancel the execution by returning `Break`.
pub(all) struct QueryCursorOptions {
  progress_callback : ((QueryCursorState) -> ControlFlow)?
}

///|
/// Create query cursor options.
pub fn QueryCursorOptions::new(
  progress_callback? : (QueryCursorState) -> ControlFlow,
) -> QueryCursorOptions {
  { progress_callback, }
}

///|
/// A particular [`Node`] that has been captured with a particular name within
/// a [`Query`].
pub(all) struct QueryCapture {
  node : Node
  index : Int32
}

///|
/// Formats like upstream's derived `Debug`:
/// `QueryCapture { node: {Node ...}, index: 0 }`.
pub impl Debug for QueryCapture with fn to_repr(self) {
  Repr::literal(self.debug_text())
}

///|
fn QueryCapture::debug_text(self : QueryCapture) -> String {
  "QueryCapture { node: \{self.node.debug_text()}, index: \{self.index} }"
}

///|
/// A match of a [`Query`] to a particular set of [`Node`]s.
pub struct QueryMatch {
  /// The index of the pattern that matched.
  pattern_index : Int32
  priv captures : ArrayView[QueryCapture]
  priv id : UInt32
  priv cursor : @query.QueryCursor
}

///|
fn QueryMatch::new(
  m : @query.QueryMatch,
  cursor : @query.QueryCursor,
  captures : ArrayView[QueryCapture],
) -> QueryMatch {
  { cursor, id: m.id, pattern_index: m.pattern_index, captures }
}

///|
fn QueryCapture::convert(
  c : @query.QueryCapture,
  language : Language,
) -> QueryCapture {
  { node: { raw: c.node, language }, index: c.index }
}

///|
/// The id of this match.
pub fn QueryMatch::id(self : QueryMatch) -> UInt32 {
  self.id
}

///|
/// The captures of this match.
pub fn QueryMatch::captures(self : QueryMatch) -> ArrayView[QueryCapture] {
  self.captures
}

///|
/// Remove this match from its cursor's pending results.
pub fn QueryMatch::remove(self : QueryMatch) -> Unit {
  self.cursor.remove_match(self.id)
}

///|
/// The nodes captured with the given capture index, in order.
pub fn QueryMatch::nodes_for_capture_index(
  self : QueryMatch,
  capture_ix : Int32,
) -> Iter[Node] {
  self.captures
  .iter()
  .filter_map(capture => {
    if capture.index == capture_ix {
      Some(capture.node)
    } else {
      None
    }
  })
}

///|
/// Concatenate a node's text chunks (upstream's `NodeText::get_text`).
fn get_text(chunks : Iter[BytesView]) -> BytesView {
  // `NodeText::get_text` always asks for a second chunk, and unwraps the
  // first one when there is a second.
  let first_chunk = chunks.next()
  guard chunks.next() is Some(next_chunk) else {
    return first_chunk.unwrap_or(b""[:])
  }
  guard first_chunk is Some(first_chunk) else {
    abort("called `Option::unwrap()` on a `None` value")
  }
  let buffer = Buffer()
  buffer.write_bytesview(first_chunk)
  buffer.write_bytesview(next_chunk)
  for chunk in chunks {
    buffer.write_bytesview(chunk)
  }
  buffer.to_bytes()[:]
}

///|
/// Check the text predicates (`#eq?`, `#match?`, `#any-of?` and their
/// variants) of this match's pattern against the text of the captured nodes.
///
/// For a quantified capture, `eq?`/`match?`/`not-eq?`/`not-match?` must hold
/// for every captured node, while the `any-` variants need one node; `#eq?`
/// between two captures compares their nodes pairwise and fails when the
/// counts differ; `#any-of?` must hold for every node.
pub fn[T : TextProvider] QueryMatch::satisfies_text_predicates(
  self : QueryMatch,
  query : Query,
  text_provider : T,
) -> Bool {
  query.text_predicates[self.pattern_index]
  .iter()
  .all(predicate => {
    match predicate {
      EqCapture(i, j, is_positive, match_all_nodes) => {
        let nodes_1 = self.nodes_for_capture_index(i).to_array()
        let nodes_2 = self.nodes_for_capture_index(j).to_array()
        let n = if nodes_1.length() < nodes_2.length() {
          nodes_1.length()
        } else {
          nodes_2.length()
        }
        for k in 0..<n {
          // Both chunk iterators are created before either is consumed.
          let chunks1 = text_provider.text(nodes_1[k])
          let chunks2 = text_provider.text(nodes_2[k])
          let text1 = get_text(chunks1)
          let text2 = get_text(chunks2)
          let is_positive_match = text1 == text2
          if is_positive_match != is_positive && match_all_nodes {
            return false
          }
          if is_positive_match == is_positive && !match_all_nodes {
            return true
          }
        }
        nodes_1.length() == nodes_2.length()
      }
      EqString(i, s, is_positive, match_all_nodes) => {
        for node in self.nodes_for_capture_index(i) {
          let text = get_text(text_provider.text(node))
          let is_positive_match = text == s[:]
          if is_positive_match != is_positive && match_all_nodes {
            return false
          }
          if is_positive_match == is_positive && !match_all_nodes {
            return true
          }
        }
        true
      }
      MatchString(i, r, is_positive, match_all_nodes) => {
        for node in self.nodes_for_capture_index(i) {
          let text = get_text(text_provider.text(node))
          let is_positive_match = r.is_match(text)
          if is_positive_match != is_positive && match_all_nodes {
            return false
          }
          if is_positive_match == is_positive && !match_all_nodes {
            return true
          }
        }
        true
      }
      AnyString(i, v, is_positive) => {
        for node in self.nodes_for_capture_index(i) {
          let text = get_text(text_provider.text(node))
          if v.iter().any(s => text == s[:]) != is_positive {
            return false
          }
        }
        true
      }
    }
  })
}

///|
/// Formats like upstream:
/// `QueryMatch { id: 0, pattern_index: 0, captures: [...] }`.
pub impl Debug for QueryMatch with fn to_repr(self) {
  let captures = self.captures.map(c => c.debug_text()).join(", ")
  Repr::literal(
    "QueryMatch { id: \{self.id}, pattern_index: \{self.pattern_index}, captures: [\{captures}] }",
  )
}

///|
/// A stateful object for executing a [`Query`] on a syntax [`Tree`].
pub struct QueryCursor {
  priv raw : @query.QueryCursor
}

///|
/// Create a new cursor for executing a given query.
///
/// The cursor stores the state that is needed to iteratively search for
/// matches.
pub fn QueryCursor::new() -> QueryCursor {
  { raw: @query.QueryCursor::new(), }
}

///|
/// Return the maximum number of in-progress matches for this cursor.
pub fn QueryCursor::match_limit(self : QueryCursor) -> Int32 {
  from_u32(self.raw.match_limit())
}

///|
/// Set the maximum number of in-progress matches for this cursor. The limit
/// must be > 0 and <= 65536.
pub fn QueryCursor::set_match_limit(self : QueryCursor, limit : Int32) -> Unit {
  self.raw.set_match_limit(to_u32(limit))
}

///|
/// Check if, on its last execution, this cursor exceeded its maximum number
/// of in-progress matches.
pub fn QueryCursor::did_exceed_match_limit(self : QueryCursor) -> Bool {
  self.raw.did_exceed_match_limit()
}

///|
fn query_options_to_ts(
  options : QueryCursorOptions,
) -> @query.QueryCursorOptions? {
  match options.progress_callback {
    Some(callback) =>
      Some({
        progress_callback: Some(state => {
          let state : QueryCursorState = {
            current_byte_offset: from_u32(state.current_byte_offset),
          }
          callback(state) is Break
        }),
      })
    None => None
  }
}

///|
/// Iterate over all of the matches in the order that they were found.
///
/// Each match contains the index of the pattern that matched, and a list of
/// captures. Because multiple patterns can match the same set of nodes, one
/// match may contain captures that appear *before* some of the captures from
/// a previous match.
///
/// Matches whose text predicates fail (according to `text_provider`) are
/// skipped.
pub fn[T] QueryCursor::matches(
  self : QueryCursor,
  query : Query,
  node : Node,
  text_provider : T,
) -> QueryMatches[T] {
  self.raw.exec(query.raw, node.raw)
  { cursor: self.raw, query, text_provider, language: node.language, }
}

///|
/// Iterate over all of the matches in the order that they were found, with
/// options.
pub fn[T] QueryCursor::matches_with_options(
  self : QueryCursor,
  query : Query,
  node : Node,
  text_provider : T,
  options : QueryCursorOptions,
) -> QueryMatches[T] {
  self.raw.exec_with_options(query.raw, node.raw, query_options_to_ts(options))
  { cursor: self.raw, query, text_provider, language: node.language, }
}

///|
/// Iterate over all of the individual captures in the order that they
/// appear.
///
/// This is useful if you don't care about which pattern matched, and just
/// want a single, ordered sequence of captures.
pub fn[T] QueryCursor::captures(
  self : QueryCursor,
  query : Query,
  node : Node,
  text_provider : T,
) -> QueryCaptures[T] {
  self.raw.exec(query.raw, node.raw)
  {
    cursor: self.raw,
    query,
    text_provider,
    language: node.language,
    converted: @query.CaptureConversionCache::new(c => {
      QueryCapture::convert(c, node.language)
    }),
  }
}

///|
/// Iterate over all of the individual captures in the order that they
/// appear, with options.
pub fn[T] QueryCursor::captures_with_options(
  self : QueryCursor,
  query : Query,
  node : Node,
  text_provider : T,
  options : QueryCursorOptions,
) -> QueryCaptures[T] {
  self.raw.exec_with_options(query.raw, node.raw, query_options_to_ts(options))
  {
    cursor: self.raw,
    query,
    text_provider,
    language: node.language,
    converted: @query.CaptureConversionCache::new(c => {
      QueryCapture::convert(c, node.language)
    }),
  }
}

///|
/// Set the range in which the query will be executed, in terms of byte
/// offsets (`start..end`).
pub fn QueryCursor::set_byte_range(
  self : QueryCursor,
  start : Int32,
  end : Int32,
) -> QueryCursor {
  ignore(self.raw.set_byte_range(to_u32(start), to_u32(end)))
  self
}

///|
/// Set the range in which the query will be executed, in terms of rows and
/// columns (`start..end`).
pub fn QueryCursor::set_point_range(
  self : QueryCursor,
  start : Point,
  end : Point,
) -> QueryCursor {
  ignore(self.raw.set_point_range(start.to_ts(), end.to_ts()))
  self
}

///|
/// Set the byte range within which all matches must be fully contained.
///
/// In contrast to [`set_byte_range`](QueryCursor::set_byte_range), this will
/// restrict the query cursor to only return matches where _all_ nodes are
/// _fully_ contained within the given range. Both functions can be used
/// together, e.g. to search for any matches that intersect line 5000, as long
/// as they are fully contained within lines 4500-5500.
pub fn QueryCursor::set_containing_byte_range(
  self : QueryCursor,
  start : Int32,
  end : Int32,
) -> QueryCursor {
  ignore(self.raw.set_containing_byte_range(to_u32(start), to_u32(end)))
  self
}

///|
/// Set the point range within which all matches must be fully contained.
///
/// See [`set_containing_byte_range`](QueryCursor::set_containing_byte_range).
pub fn QueryCursor::set_containing_point_range(
  self : QueryCursor,
  start : Point,
  end : Point,
) -> QueryCursor {
  ignore(self.raw.set_containing_point_range(start.to_ts(), end.to_ts()))
  self
}

///|
/// Set the maximum start depth for a query cursor.
///
/// This prevents cursors from exploring children nodes at a certain depth.
/// Note if a pattern includes many children, then they will still be checked.
///
/// The zero max start depth value can be used as a special behavior and it
/// helps to destructure a subtree by staying on a node and using captures for
/// interested parts. Note that the zero max start depth only limits a search
/// depth for a pattern's root node but other nodes that are parts of the
/// pattern may be searched at any depth depending on what is defined by the
/// pattern structure.
///
/// Set to `None` to remove the maximum start depth.
pub fn QueryCursor::set_max_start_depth(
  self : QueryCursor,
  max_start_depth : Int32?,
) -> QueryCursor {
  self.raw.set_max_start_depth(
    match max_start_depth {
      Some(depth) => depth.reinterpret_as_uint()
      None => 0xFFFFFFFFU
    },
  )
  self
}

///|
/// A sequence of [`QueryMatch`]es associated with a given [`QueryCursor`].
pub struct QueryMatches[T] {
  priv cursor : @query.QueryCursor
  priv query : Query
  priv text_provider : T
  priv language : Language
}

///|
/// Advance to the next match whose text predicates are satisfied.
pub fn[T : TextProvider] QueryMatches::next(
  self : QueryMatches[T],
) -> QueryMatch? {
  while self.cursor.next_match() is Some(m) {
    let language = self.language
    let captures = m.captures.map(c => QueryCapture::convert(c, language))
    let result = QueryMatch::new(m, self.cursor, captures)
    if result.satisfies_text_predicates(self.query, self.text_provider) {
      return Some(result)
    }
  }
  None
}

///|
/// Iterate the remaining matches.
pub fn[T : TextProvider] QueryMatches::iter(
  self : QueryMatches[T],
) -> Iter[QueryMatch] {
  Iter::new(() => self.next())
}

///|
/// Set the byte range in which the remaining matches are searched.
pub fn[T] QueryMatches::set_byte_range(
  self : QueryMatches[T],
  start : Int32,
  end : Int32,
) -> Unit {
  ignore(self.cursor.set_byte_range(to_u32(start), to_u32(end)))
}

///|
/// Set the point range in which the remaining matches are searched.
pub fn[T] QueryMatches::set_point_range(
  self : QueryMatches[T],
  start : Point,
  end : Point,
) -> Unit {
  ignore(self.cursor.set_point_range(start.to_ts(), end.to_ts()))
}

///|
/// A sequence of [`QueryCapture`]s associated with a given [`QueryCursor`].
///
/// Each element contains a [`QueryMatch`] and the index of the new capture
/// within [`QueryMatch::captures`].
pub struct QueryCaptures[T] {
  priv cursor : @query.QueryCursor
  priv query : Query
  priv text_provider : T
  priv language : Language
  // The converted captures of the pending matches, shared by the captures of
  // a match (upstream's `QueryMatch` borrows the C capture list).
  priv converted : @query.CaptureConversionCache[QueryCapture]
}

///|
/// Advance to the next capture whose match satisfies its text predicates.
/// Matches that fail them are removed from the cursor.
pub fn[T : TextProvider] QueryCaptures::next(
  self : QueryCaptures[T],
) -> (QueryMatch, Int32)? {
  while self.cursor.next_capture() is Some((m, capture_index)) {
    let captures = self.converted.convert(m)
    let result = QueryMatch::new(m, self.cursor, captures)
    if result.satisfies_text_predicates(self.query, self.text_provider) {
      return Some((result, capture_index))
    }
    result.remove()
  }
  self.converted.clear()
  None
}

///|
/// Iterate the remaining captures.
pub fn[T : TextProvider] QueryCaptures::iter(
  self : QueryCaptures[T],
) -> Iter[(QueryMatch, Int32)] {
  Iter::new(() => self.next())
}

///|
/// Set the byte range in which the remaining captures are searched.
pub fn[T] QueryCaptures::set_byte_range(
  self : QueryCaptures[T],
  start : Int32,
  end : Int32,
) -> Unit {
  ignore(self.cursor.set_byte_range(to_u32(start), to_u32(end)))
}

///|
/// Set the point range in which the remaining captures are searched.
pub fn[T] QueryCaptures::set_point_range(
  self : QueryCaptures[T],
  start : Point,
  end : Point,
) -> Unit {
  ignore(self.cursor.set_point_range(start.to_ts(), end.to_ts()))
}

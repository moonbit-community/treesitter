// Port of tree-sitter crates/highlight/src/highlight.rs.
//
// The C API (`c_lib.rs`) is not ported. Upstream's `_QueryCaptures` is a
// transmuted copy of the binding's `QueryCaptures` iterator (it exists only
// to get a non-streaming iterator); `@api.QueryCaptures` already is one, with
// the same semantics (matches whose text predicates fail are removed).

///|
let cancellation_check_interval : Int32 = 100

///|
let standard_capture_names : Array[String] = [
  "attribute", "boolean", "carriage-return", "comment", "comment.documentation",
  "constant", "constant.builtin", "constructor", "constructor.builtin", "embedded",
  "error", "escape", "function", "function.builtin", "keyword", "markup", "markup.bold",
  "markup.heading", "markup.italic", "markup.link", "markup.link.url", "markup.list",
  "markup.list.checked", "markup.list.numbered", "markup.list.unchecked", "markup.list.unnumbered",
  "markup.quote", "markup.raw", "markup.raw.block", "markup.raw.inline", "markup.strikethrough",
  "module", "number", "operator", "property", "property.builtin", "punctuation",
  "punctuation.bracket", "punctuation.delimiter", "punctuation.special", "string",
  "string.escape", "string.regexp", "string.special", "string.special.symbol", "tag",
  "type", "type.builtin", "variable", "variable.builtin", "variable.member", "variable.parameter",
]

///|
/// `ffi::TSInputEncodingUTF8`.
pub let input_encoding_utf8 : UInt32 = 0

///|
/// `ffi::TSInputEncodingUTF16LE`.
pub let input_encoding_utf16le : UInt32 = 1

///|
/// `ffi::TSInputEncodingUTF16BE`.
pub let input_encoding_utf16be : UInt32 = 2

///|
/// Indicates which highlight should be applied to a region of source code.
pub(all) struct Highlight(Int32) derive(Eq, Debug)

///|
/// Represents the reason why syntax highlighting failed.
pub(all) suberror HighlightError {
  Cancelled
  InvalidLanguage(@api.LanguageError)
  Unknown
} derive(Eq, Debug)

///|
pub impl Show for HighlightError with fn output(self, logger) {
  match self {
    Cancelled => logger.write_string("Cancelled")
    InvalidLanguage(e) => logger.write_string("Invalid language: \{e}")
    Unknown => logger.write_string("Unknown error")
  }
}

///|
/// Represents a single step in rendering a syntax-highlighted document.
pub(all) enum HighlightEvent {
  Source(start~ : Int32, end~ : Int32)
  HighlightStart(Highlight)
  HighlightEnd
} derive(Eq, Debug)

///|
/// Contains the data needed to highlight code written in a particular
/// language.
pub struct HighlightConfiguration {
  language : @api.Language
  language_name : String
  query : @api.Query
  priv combined_injections_query : @api.Query?
  priv locals_pattern_index : Int32
  priv highlights_pattern_index : Int32
  priv highlight_indices : Array[Highlight?]
  priv non_local_variable_patterns : Array[Bool]
  priv injection_content_capture_index : Int32?
  priv injection_language_capture_index : Int32?
  priv local_scope_capture_index : Int32?
  priv local_def_capture_index : Int32?
  priv local_def_value_capture_index : Int32?
  priv local_ref_capture_index : Int32?
}

///|
/// Performs syntax highlighting, recognizing a given list of highlight names.
///
/// For the best performance `Highlighter` values should be reused between
/// syntax highlighting calls.
pub struct Highlighter {
  parser : @api.Parser
  priv cursors : Array[@api.QueryCursor]
}

///|
/// Converts a general-purpose syntax highlighting iterator into a sequence
/// of lines of HTML.
pub struct HtmlRenderer {
  html : Array[Byte]
  line_offsets : Array[UInt32]
  priv mut carriage_return_highlight : Highlight?
  // The offset in `self.html` of the last carriage return.
  priv mut last_carriage_return : Int32?
}

///|
priv struct LocalDef {
  name : BytesView
  value_range : (Int32, Int32)
  mut highlight : Highlight?
}

///|
priv struct LocalScope {
  mut inherits : Bool
  range : (Int32, Int32)
  local_defs : Array[LocalDef]
}

///|
/// The iterator of highlight events returned by [`Highlighter::highlight`].
pub struct HighlightIter {
  priv source : Bytes
  priv encoding : UInt32?
  priv language_name : String
  priv mut byte_offset : Int32
  priv highlighter : Highlighter
  priv injection_callback : (String) -> HighlightConfiguration?
  priv cancellation_flag : Ref[Int32]?
  priv layers : Array[HighlightIterLayer]
  priv mut iter_count : Int32
  priv mut next_event : HighlightEvent?
  priv mut last_highlight_range : (Int32, Int32, Int32)?
}

///|
priv struct HighlightIterLayer {
  _tree : @api.Tree
  cursor : @api.QueryCursor
  captures : @api.QueryCaptures[Bytes]
  /// The state of upstream's `Peekable`: `Some(next)` once peeked.
  mut peeked : (@api.QueryMatch, Int32)??
  config : HighlightConfiguration
  highlight_end_stack : Array[Int32]
  scope_stack : Array[LocalScope]
  ranges : Array[@api.Range]
  depth : Int32
}

///|
fn HighlightIterLayer::peek(
  self : HighlightIterLayer,
) -> (@api.QueryMatch, Int32)? {
  match self.peeked {
    Some(next) => next
    None => {
      let next = self.captures.next()
      self.peeked = Some(next)
      next
    }
  }
}

///|
fn HighlightIterLayer::next_capture(
  self : HighlightIterLayer,
) -> (@api.QueryMatch, Int32)? {
  match self.peeked {
    Some(next) => {
      self.peeked = None
      next
    }
    None => self.captures.next()
  }
}

///|
let usize_max : Int32 = 0x7FFFFFFF

///|
fn unbounded_range() -> @api.Range {
  {
    start_byte: 0,
    end_byte: usize_max,
    start_point: @api.Point::new(0, 0),
    end_point: @api.Point::new(usize_max, usize_max),
  }
}

///|
pub fn Highlighter::new() -> Highlighter {
  { parser: @api.Parser::new(), cursors: [], }
}

///|
pub fn Highlighter::parser(self : Highlighter) -> @api.Parser {
  self.parser
}

///|
/// Iterate over the highlighted regions for a given slice of source code.
pub fn Highlighter::highlight(
  self : Highlighter,
  config : HighlightConfiguration,
  source : Bytes,
  encoding? : UInt32,
  cancellation_flag? : Ref[Int32],
  injection_callback : (String) -> HighlightConfiguration?,
) -> HighlightIter raise HighlightError {
  let layers = HighlightIterLayer::new(
    source,
    encoding,
    None,
    self,
    cancellation_flag,
    injection_callback,
    config,
    0,
    [unbounded_range()],
  )
  guard! layers.length() != 0
  let result : HighlightIter = {
    source,
    encoding,
    language_name: config.language_name,
    byte_offset: 0,
    injection_callback,
    cancellation_flag,
    highlighter: self,
    iter_count: 0,
    layers,
    next_event: None,
    last_highlight_range: None,
  }
  result.sort_layers()
  result
}

///|
/// The UTF-8 byte length of a string.
fn utf8_len(s : String) -> Int32 {
  let mut len = 0
  for c in s {
    let cp = c.to_int()
    len += if cp < 0x80 {
      1
    } else if cp < 0x800 {
      2
    } else if cp < 0x10000 {
      3
    } else {
      4
    }
  }
  len
}

///|
/// Creates a `HighlightConfiguration` for a given `Language` and set of
/// highlighting queries.
///
/// # Parameters
///
/// * `language`  - The Tree-sitter `Language` that should be used for parsing.
/// * `highlights_query` - A string containing tree patterns for syntax
///   highlighting. This should be non-empty, otherwise no syntax highlights
///   will be added.
/// * `injections_query` -  A string containing tree patterns for injecting
///   other languages into the document. This can be empty if no injections
///   are desired.
/// * `locals_query` - A string containing tree patterns for tracking local
///   variable definitions and references. This can be empty if local
///   variable tracking is not needed.
///
/// Returns a `HighlightConfiguration` that can then be used with the
/// `highlight` method.
pub fn HighlightConfiguration::new(
  language : @api.Language,
  name : String,
  highlights_query : String,
  injection_query : String,
  locals_query : String,
) -> HighlightConfiguration raise @api.QueryError {
  // Concatenate the query strings, keeping track of the start offset of each section.
  let query_source = injection_query + locals_query + highlights_query
  let locals_query_offset = utf8_len(injection_query)
  let highlights_query_offset = locals_query_offset + utf8_len(locals_query)

  // Construct a single query by concatenating the three query strings, but record the
  // range of pattern indices that belong to each individual string.
  let query = @api.Query::new(language, query_source)
  let mut locals_pattern_index = 0
  let mut highlights_pattern_index = 0
  for i in 0..<query.pattern_count() {
    let pattern_offset = query.start_byte_for_pattern(i)
    if pattern_offset < highlights_query_offset {
      if pattern_offset < highlights_query_offset {
        highlights_pattern_index += 1
      }
      if pattern_offset < locals_query_offset {
        locals_pattern_index += 1
      }
    }
  }

  // Construct a separate query just for dealing with the 'combined injections'.
  // Disable the combined injection patterns in the main query.
  let combined_injections_query = @api.Query::new(language, injection_query)
  let mut has_combined_queries = false
  for pattern_index in 0..<locals_pattern_index {
    let settings = query.property_settings(pattern_index)
    if settings.iter().any(s => s.key == "injection.combined") {
      has_combined_queries = true
      query.disable_pattern(pattern_index)
    } else {
      combined_injections_query.disable_pattern(pattern_index)
    }
  }
  let combined_injections_query = if has_combined_queries {
    Some(combined_injections_query)
  } else {
    None
  }

  // Find all of the highlighting patterns that are disabled for nodes that
  // have been identified as local variables.
  let non_local_variable_patterns = Array::makei(query.pattern_count(), i => {
    query
    .property_predicates(i)
    .iter()
    .any(pair => {
      let (prop, positive) = pair
      !positive && prop.key == "local"
    })
  })

  // Store the numeric ids for all of the special captures.
  let mut injection_content_capture_index = None
  let mut injection_language_capture_index = None
  let mut local_def_capture_index = None
  let mut local_def_value_capture_index = None
  let mut local_ref_capture_index = None
  let mut local_scope_capture_index = None
  for i, name in query.capture_names() {
    let i = Some(i)
    match name {
      "injection.content" => injection_content_capture_index = i
      "injection.language" => injection_language_capture_index = i
      "local.definition" => local_def_capture_index = i
      "local.definition-value" => local_def_value_capture_index = i
      "local.reference" => local_ref_capture_index = i
      "local.scope" => local_scope_capture_index = i
      _ => ()
    }
  }
  let highlight_indices = Array::make(query.capture_names().length(), None)
  {
    language,
    language_name: name,
    query,
    combined_injections_query,
    locals_pattern_index,
    highlights_pattern_index,
    highlight_indices,
    non_local_variable_patterns,
    injection_content_capture_index,
    injection_language_capture_index,
    local_def_capture_index,
    local_def_value_capture_index,
    local_ref_capture_index,
    local_scope_capture_index,
  }
}

///|
/// Get a slice containing all of the highlight names used in the
/// configuration.
pub fn HighlightConfiguration::names(
  self : HighlightConfiguration,
) -> ArrayView[String] {
  self.query.capture_names()
}

///|
/// Set the list of recognized highlight names.
///
/// Tree-sitter syntax-highlighting queries specify highlights in the form of
/// dot-separated highlight names like `punctuation.bracket` and
/// `function.method.builtin`. Consumers of these queries can choose to
/// recognize highlights with different levels of specificity. For example,
/// the string `function.builtin` will match against `function.method.builtin`
/// and `function.builtin.constructor`, but will not match `function.method`.
///
/// When highlighting, results are returned as `Highlight` values, which
/// contain the index of the matched highlight in this list of highlight names.
pub fn HighlightConfiguration::configure(
  self : HighlightConfiguration,
  recognized_names : ArrayView[String],
) -> Unit {
  let capture_parts : Array[StringView] = []
  self.highlight_indices.clear()
  for capture_name in self.query.capture_names() {
    capture_parts.clear()
    for part in capture_name.split(".") {
      capture_parts.push(part)
    }
    let mut best_index = None
    let mut best_match_len = 0
    for i, recognized_name in recognized_names {
      let mut len = 0
      let mut matches = true
      for part in recognized_name.split(".") {
        len += 1
        if !capture_parts.contains(part) {
          matches = false
          break
        }
      }
      if matches && len > best_match_len {
        best_index = Some(i)
        best_match_len = len
      }
    }
    self.highlight_indices.push(best_index.map(i => Highlight(i)))
  }
}

///|
/// Return the list of this configuration's capture names that are neither
/// present in the list of predefined 'canonical' names nor start with an
/// underscore (denoting 'private' captures used as part of capture
/// internals).
pub fn HighlightConfiguration::nonconformant_capture_names(
  self : HighlightConfiguration,
  capture_names : @hashset.HashSet[String],
) -> Array[String] {
  let capture_names = if capture_names.is_empty() {
    @hashset.HashSet::from_array(standard_capture_names)
  } else {
    capture_names
  }
  self
  .names()
  .iter()
  .filter(n => !(n.has_prefix("_") || capture_names.contains(n)))
  .to_array()
}

///|
/// Create a new 'layer' of highlighting for this document.
///
/// In the event that the new layer contains "combined injections" (injections
/// where multiple disjoint ranges are parsed as one syntax tree), these will
/// be eagerly processed and added to the returned vector.
fn HighlightIterLayer::new(
  source : Bytes,
  encoding : UInt32?,
  parent_name : String?,
  highlighter : Highlighter,
  cancellation_flag : Ref[Int32]?,
  injection_callback : (String) -> HighlightConfiguration?,
  config : HighlightConfiguration,
  depth : Int32,
  ranges : Array[@api.Range],
) -> Array[HighlightIterLayer] raise HighlightError {
  let result = []
  let queue : Array[(HighlightConfiguration, Int32, Array[@api.Range])] = []
  let mut config = config
  let mut depth = depth
  let mut ranges = ranges
  for ;; {
    let included = try highlighter.parser.set_included_ranges(ranges) catch {
      _ => false
    } noraise {
      _ => true
    }
    if included {
      highlighter.parser.set_language(config.language) catch {
        e => raise InvalidLanguage(e)
      }
      let progress_callback = (_ : @api.ParseState) => {
        if cancellation_flag is Some(cancellation_flag) {
          if cancellation_flag.val != 0 {
            @api.ControlFlow::Break
          } else {
            @api.ControlFlow::Continue
          }
        } else {
          @api.ControlFlow::Continue
        }
      }
      let parse_opts = @api.ParseOptions::new(progress_callback~)
      let tree = match encoding {
        Some(encoding) if encoding == input_encoding_utf16le => {
          let source_code_utf16 = utf16_units(source, little_endian=true)
          highlighter.parser.parse_utf16_le_with_options(
            (i, _) => {
              if i < source_code_utf16.length() {
                source_code_utf16[i:]
              } else {
                [][:]
              }
            },
            options=parse_opts,
          )
        }
        Some(encoding) if encoding == input_encoding_utf16be => {
          let source_code_utf16 = utf16_units(source, little_endian=false)
          highlighter.parser.parse_utf16_be_with_options(
            (i, _) => {
              if i < source_code_utf16.length() {
                source_code_utf16[i:]
              } else {
                [][:]
              }
            },
            options=parse_opts,
          )
        }
        _ =>
          highlighter.parser.parse_with_options(
            (i, _) => if i < source.length() { source[i:] } else { b""[:] },
            options=parse_opts,
          )
      }
      guard tree is Some(tree) else { raise Cancelled }
      let cursor = match highlighter.cursors.pop() {
        Some(cursor) => cursor
        None => @api.QueryCursor::new()
      }

      // Process combined injections.
      if config.combined_injections_query is Some(combined_injections_query) {
        let injections_by_pattern_index : Array[
          (String?, Array[@api.Node], Bool),
        ] = Array::makei(combined_injections_query.pattern_count(), _ => {
          (None, [], false)
        })
        let matches = cursor.matches(
          combined_injections_query,
          tree.root_node(),
          source,
        )
        while matches.next() is Some(mat) {
          let entry = injections_by_pattern_index[mat.pattern_index]
          let (language_name, content_node, include_children) = injection_for_match(
            config, parent_name, combined_injections_query, mat, source,
          )
          let entry_0 = if language_name is Some(_) {
            language_name
          } else {
            entry.0
          }
          if content_node is Some(content_node) {
            entry.1.push(content_node)
          }
          injections_by_pattern_index[mat.pattern_index] = (
            entry_0,
            entry.1,
            include_children,
          )
        }
        for entry in injections_by_pattern_index {
          let (lang_name, content_nodes, includes_children) = entry
          if lang_name is Some(lang_name) &&
            !content_nodes.is_empty() &&
            injection_callback(lang_name) is Some(next_config) {
            let ranges = HighlightIterLayer::intersect_ranges(
              ranges, content_nodes, includes_children,
            )
            if !ranges.is_empty() {
              queue.push((next_config, depth + 1, ranges))
            }
          }
        }
      }
      let captures = cursor.captures(config.query, tree.root_node(), source)
      result.push({
        highlight_end_stack: [],
        scope_stack: [
          { inherits: false, range: (0, usize_max), local_defs: [], },
        ],
        cursor,
        depth,
        _tree: tree,
        captures,
        peeked: None,
        config,
        ranges,
      })
    }
    if queue.is_empty() {
      break
    }
    let (next_config, next_depth, next_ranges) = queue.remove(0)
    config = next_config
    depth = next_depth
    ranges = next_ranges
  }
  result
}

///|
/// `source.as_chunks::<2>().0` read as UTF-16 code units.
fn utf16_units(source : Bytes, little_endian~ : Bool) -> Array[UInt16] {
  Array::makei(source.length() / 2, i => {
    let a = source[2 * i].to_int()
    let b = source[2 * i + 1].to_int()
    (if little_endian { a | (b << 8) } else { (a << 8) | b }).to_uint16()
  })
}

///|
/// Compute the ranges that should be included when parsing an injection.
/// This takes into account three things:
/// * `parent_ranges` - The ranges must all fall within the *current* layer's
///   ranges.
/// * `nodes` - Every injection takes place within a set of nodes. The
///   injection ranges are the ranges of those nodes.
/// * `includes_children` - For some injections, the content nodes' children
///   should be excluded from the nested document, so that only the content
///   nodes' *own* content is reparsed. For other injections, the content
///   nodes' entire ranges should be reparsed, including the ranges of their
///   children.
fn HighlightIterLayer::intersect_ranges(
  parent_ranges : Array[@api.Range],
  nodes : Array[@api.Node],
  includes_children : Bool,
) -> Array[@api.Range] {
  let cursor = nodes[0].walk()
  let result : Array[@api.Range] = []
  let mut parent_range_index = 0
  guard parent_ranges.get(parent_range_index) is Some(first) else {
    abort("Layers should only be constructed with non-empty ranges vectors")
  }
  parent_range_index += 1
  let mut parent_range = first
  for node in nodes {
    let mut preceding_range : @api.Range = {
      start_byte: 0,
      start_point: @api.Point::new(0, 0),
      end_byte: node.start_byte(),
      end_point: node.start_position(),
    }
    let following_range : @api.Range = {
      start_byte: node.end_byte(),
      start_point: node.end_position(),
      end_byte: usize_max,
      end_point: @api.Point::new(usize_max, usize_max),
    }
    let excluded_ranges = node
      .children(cursor)
      .filter_map(child => {
        if includes_children {
          None
        } else {
          Some(child.range())
        }
      })
      .to_array()
    excluded_ranges.push(following_range)
    for excluded_range in excluded_ranges {
      let mut range : @api.Range = {
        start_byte: preceding_range.end_byte,
        start_point: preceding_range.end_point,
        end_byte: excluded_range.start_byte,
        end_point: excluded_range.start_point,
      }
      preceding_range = excluded_range
      if range.end_byte < parent_range.start_byte {
        continue
      }
      while parent_range.start_byte <= range.end_byte {
        if parent_range.end_byte > range.start_byte {
          if range.start_byte < parent_range.start_byte {
            range = {
              ..range,
              start_byte: parent_range.start_byte,
              start_point: parent_range.start_point,
            }
          }
          if parent_range.end_byte < range.end_byte {
            if range.start_byte < parent_range.end_byte {
              result.push({
                start_byte: range.start_byte,
                start_point: range.start_point,
                end_byte: parent_range.end_byte,
                end_point: parent_range.end_point,
              })
            }
            range = {
              ..range,
              start_byte: parent_range.end_byte,
              start_point: parent_range.end_point,
            }
          } else {
            if range.start_byte < range.end_byte {
              result.push(range)
            }
            break
          }
        }
        if parent_ranges.get(parent_range_index) is Some(next_range) {
          parent_range_index += 1
          parent_range = next_range
        } else {
          return result
        }
      }
    }
  }
  result
}

///|
/// First, sort scope boundaries by their byte offset in the document. At a
/// given position, emit scope endings before scope beginnings. Finally, emit
/// scope boundaries from deeper layers first.
fn HighlightIterLayer::sort_key(
  self : HighlightIterLayer,
) -> (Int32, Bool, Int32)? {
  let depth = -self.depth
  let next_start = match self.peek() {
    Some((m, i)) => Some(m.captures()[i].node.start_byte())
    None => None
  }
  let next_end = self.highlight_end_stack.last()
  match (next_start, next_end) {
    (Some(start), Some(end)) =>
      if start < end {
        Some((start, true, depth))
      } else {
        Some((end, false, depth))
      }
    (Some(i), None) => Some((i, true, depth))
    (None, Some(j)) => Some((j, false, depth))
    _ => None
  }
}

///|
fn HighlightIter::emit_event(
  self : HighlightIter,
  offset : Int32,
  event : HighlightEvent?,
) -> Result[HighlightEvent, HighlightError]? {
  let result = if self.byte_offset < offset {
    let result = Some(Ok(Source(start=self.byte_offset, end=offset)))
    self.byte_offset = offset
    self.next_event = event
    result
  } else {
    event.map(e => Ok(e))
  }
  self.sort_layers()
  result
}

///|
fn HighlightIter::sort_layers(self : HighlightIter) -> Unit {
  while !self.layers.is_empty() {
    if self.layers[0].sort_key() is Some(sort_key) {
      let mut i = 0
      while i + 1 < self.layers.length() {
        if self.layers[i + 1].sort_key() is Some(next_offset) &&
          next_offset < sort_key {
          i += 1
          continue
        }
        break
      }
      if i > 0 {
        // `self.layers[0..=i].rotate_left(1)`
        let first = self.layers[0]
        for j in 0..<i {
          self.layers[j] = self.layers[j + 1]
        }
        self.layers[i] = first
      }
      break
    }
    let layer = self.layers.remove(0)
    self.highlighter.cursors.push(layer.cursor)
  }
}

///|
fn HighlightIter::insert_layer(
  self : HighlightIter,
  layer : HighlightIterLayer,
) -> Unit {
  if layer.sort_key() is Some(sort_key) {
    let mut i = 1
    while i < self.layers.length() {
      if self.layers[i].sort_key() is Some(sort_key_i) {
        if sort_key_i > sort_key {
          self.layers.insert(i, layer)
          return
        }
        i += 1
      } else {
        ignore(self.layers.remove(i))
      }
    }
    self.layers.push(layer)
  }
}

///|
/// Whether `bytes` is valid UTF-8 (`str::from_utf8(bytes).is_ok()`).
fn is_valid_utf8(bytes : BytesView) -> Bool {
  try @hir.from_utf8(bytes) catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
/// The next highlight event, `Some(Err(_))` when highlighting fails or is
/// cancelled, and `None` at the end of the document.
pub fn HighlightIter::next(
  self : HighlightIter,
) -> Result[HighlightEvent, HighlightError]? {
  main~: for ;; {
    // If we've already determined the next highlight boundary, just return it.
    if self.next_event is Some(e) {
      self.next_event = None
      return Some(Ok(e))
    }

    // Periodically check for cancellation, returning `Cancelled` error if the
    // cancellation flag was flipped.
    if self.cancellation_flag is Some(cancellation_flag) {
      self.iter_count += 1
      if self.iter_count >= cancellation_check_interval {
        self.iter_count = 0
        if cancellation_flag.val != 0 {
          return Some(Err(Cancelled))
        }
      }
    }

    // If none of the layers have any more highlight boundaries, terminate.
    if self.layers.is_empty() {
      return if self.byte_offset < self.source.length() {
        let result = Some(
          Ok(Source(start=self.byte_offset, end=self.source.length())),
        )
        self.byte_offset = self.source.length()
        result
      } else {
        None
      }
    }

    // Get the next capture from whichever layer has the earliest highlight boundary.
    let layer = self.layers[0]
    let range = match layer.peek() {
      Some((next_match, capture_index)) => {
        let next_capture = next_match.captures()[capture_index]
        let range = next_capture.node.byte_range()

        // If any previous highlight ends before this node starts, then before
        // processing this capture, emit the source code up until the end of the
        // previous highlight, and an end event for that highlight.
        if layer.highlight_end_stack.last() is Some(end_byte) &&
          end_byte <= range.0 {
          ignore(layer.highlight_end_stack.pop())
          return self.emit_event(end_byte, Some(HighlightEnd))
        }
        range
      }
      // If there are no more captures, then emit any remaining highlight end events.
      // And if there are none of those, then just advance to the end of the document.
      None => {
        if layer.highlight_end_stack.last() is Some(end_byte) {
          ignore(layer.highlight_end_stack.pop())
          return self.emit_event(end_byte, Some(HighlightEnd))
        }
        return self.emit_event(self.source.length(), None)
      }
    }
    guard! layer.next_capture() is Some((match_, capture_index))
    let mut match_ = match_
    let mut capture = match_.captures()[capture_index]

    // If this capture represents an injection, then process the injection.
    if match_.pattern_index < layer.config.locals_pattern_index {
      let (language_name, content_node, include_children) = injection_for_match(
        layer.config,
        Some(self.language_name),
        layer.config.query,
        match_,
        self.source,
      )

      // Explicitly remove this match so that none of its other captures will remain
      // in the stream of captures.
      match_.remove()

      // If a language is found with the given name, then add a new language layer
      // to the highlighted document.
      if language_name is Some(language_name) &&
        content_node is Some(content_node) &&
        (self.injection_callback)(language_name) is Some(config) {
        let ranges = HighlightIterLayer::intersect_ranges(
          self.layers[0].ranges,
          [content_node],
          include_children,
        )
        if !ranges.is_empty() {
          let layers = HighlightIterLayer::new(
            self.source,
            self.encoding,
            Some(self.language_name),
            self.highlighter,
            self.cancellation_flag,
            self.injection_callback,
            config,
            self.layers[0].depth + 1,
            ranges,
          ) catch {
            e => return Some(Err(e))
          }
          for layer in layers {
            self.insert_layer(layer)
          }
        }
      }
      self.sort_layers()
      continue main~
    }

    // Remove from the local scope stack any local scopes that have already ended.
    while range.0 > layer.scope_stack[layer.scope_stack.length() - 1].range.1 {
      ignore(layer.scope_stack.pop())
    }

    // If this capture is for tracking local variables, then process the
    // local variable info.
    let mut reference_highlight : Highlight? = None
    let mut definition_highlight : LocalDef? = None
    while match_.pattern_index < layer.config.highlights_pattern_index {
      // If the node represents a local scope, push a new local scope onto
      // the scope stack.
      if Some(capture.index) == layer.config.local_scope_capture_index {
        definition_highlight = None
        let scope : LocalScope = { inherits: true, range, local_defs: [], }
        for prop in layer.config.query.property_settings(match_.pattern_index) {
          if prop.key == "local.scope-inherits" {
            scope.inherits = match prop.value {
              None => true
              Some(r) => r == "true"
            }
          }
        }
        layer.scope_stack.push(scope)
        // If the node represents a definition, add a new definition to the
        // local scope at the top of the scope stack.
      } else if Some(capture.index) == layer.config.local_def_capture_index {
        reference_highlight = None
        definition_highlight = None
        let scope = layer.scope_stack[layer.scope_stack.length() - 1]
        let mut value_range = (0, 0)
        for capture in match_.captures() {
          if Some(capture.index) == layer.config.local_def_value_capture_index {
            value_range = capture.node.byte_range()
          }
        }
        let name = self.source[range.0:range.1]
        if is_valid_utf8(name) {
          let def : LocalDef = { name, value_range, highlight: None, }
          scope.local_defs.push(def)
          definition_highlight = Some(def)
        }
        // If the node represents a reference, then try to find the corresponding
        // definition in the scope stack.
      } else if Some(capture.index) == layer.config.local_ref_capture_index &&
        definition_highlight is None {
        definition_highlight = None
        let name = self.source[range.0:range.1]
        if is_valid_utf8(name) {
          for i = layer.scope_stack.length() - 1; i >= 0; i = i - 1 {
            let scope = layer.scope_stack[i]
            let mut found : Highlight?? = None
            for j = scope.local_defs.length() - 1; j >= 0; j = j - 1 {
              let def = scope.local_defs[j]
              if def.name == name && range.0 >= def.value_range.1 {
                found = Some(def.highlight)
                break
              }
            }
            if found is Some(highlight) {
              reference_highlight = highlight
              break
            }
            if !scope.inherits {
              break
            }
          }
        }
      }

      // Continue processing any additional matches for the same node.
      if layer.peek() is Some((next_match, next_capture_index)) {
        let next_capture = next_match.captures()[next_capture_index]
        if next_capture.node == capture.node {
          capture = next_capture
          guard! layer.next_capture() is Some((m, _))
          match_ = m
          continue
        }
      }
      self.sort_layers()
      continue main~
    }

    // Otherwise, this capture must represent a highlight.
    // If this exact range has already been highlighted by an earlier pattern, or by
    // a different layer, then skip over this one.
    if self.last_highlight_range is Some((last_start, last_end, last_depth)) &&
      range.0 == last_start &&
      range.1 == last_end &&
      layer.depth < last_depth {
      self.sort_layers()
      continue main~
    }

    // Once a highlighting pattern is found for the current node, keep iterating over
    // any later highlighting patterns that also match this node and set the match to it.
    // Captures for a given node are ordered by pattern index, so these subsequent
    // captures are guaranteed to be for highlighting, not injections or
    // local variables.
    while layer.peek() is Some((next_match, next_capture_index)) {
      let next_capture = next_match.captures()[next_capture_index]
      if next_capture.node == capture.node {
        guard! layer.next_capture() is Some((following_match, _))
        // If the current node was found to be a local variable, then ignore
        // the following match if it's a highlighting pattern that is disabled
        // for local variables.
        if (definition_highlight is Some(_) || reference_highlight is Some(_)) &&
          layer.config.non_local_variable_patterns[following_match.pattern_index] {
          continue
        }
        match_.remove()
        capture = next_capture
        match_ = following_match
      } else {
        break
      }
    }
    let current_highlight = layer.config.highlight_indices[capture.index]

    // If this node represents a local definition, then store the current
    // highlight value on the local scope entry representing this node.
    if definition_highlight is Some(definition_highlight) {
      definition_highlight.highlight = current_highlight
    }

    // Emit a scope start event and push the node's end position to the stack.
    let highlight = match reference_highlight {
      Some(_) => reference_highlight
      None => current_highlight
    }
    if highlight is Some(highlight) {
      self.last_highlight_range = Some((range.0, range.1, layer.depth))
      layer.highlight_end_stack.push(range.1)
      return self.emit_event(range.0, Some(HighlightStart(highlight)))
    }
    self.sort_layers()
  }
}

///|
/// Iterate the remaining highlight events.
pub fn HighlightIter::iter(
  self : HighlightIter,
) -> Iter[Result[HighlightEvent, HighlightError]] {
  Iter::new(() => self.next())
}

///|
pub fn HtmlRenderer::new() -> HtmlRenderer {
  {
    html: [],
    line_offsets: [0],
    carriage_return_highlight: None,
    last_carriage_return: None,
  }
}

///|
pub fn HtmlRenderer::set_carriage_return_highlight(
  self : HtmlRenderer,
  highlight : Highlight?,
) -> Unit {
  self.carriage_return_highlight = highlight
}

///|
pub fn HtmlRenderer::reset(self : HtmlRenderer) -> Unit {
  self.html.clear()
  self.line_offsets.clear()
  self.line_offsets.push(0)
}

///|
/// Render the highlight events as HTML. `attribute_callback` writes the
/// attributes of the `<span>` of a highlight.
pub fn HtmlRenderer::render(
  self : HtmlRenderer,
  highlighter : Iter[Result[HighlightEvent, HighlightError]],
  source : BytesView,
  attribute_callback : (Highlight, Array[Byte]) -> Unit,
) -> Unit raise HighlightError {
  let highlights = []
  for event in highlighter {
    match event {
      Ok(HighlightStart(s)) => {
        highlights.push(s)
        self.start_highlight(s, attribute_callback)
      }
      Ok(HighlightEnd) => {
        ignore(highlights.pop())
        self.end_highlight()
      }
      Ok(Source(start~, end~)) =>
        self.add_text(source[start:end], highlights, attribute_callback)
      Err(a) => raise a
    }
  }
  if self.last_carriage_return is Some(offset) {
    self.last_carriage_return = None
    self.add_carriage_return(offset, attribute_callback)
  }
  if self.html.last() != Some(b'\n') {
    self.html.push(b'\n')
  }
  if self.line_offsets.last() == Some(self.html.length().reinterpret_as_uint()) {
    ignore(self.line_offsets.pop())
  }
}

///|
/// The rendered lines, each including its trailing newline.
pub fn HtmlRenderer::lines(self : HtmlRenderer) -> Iter[String] {
  let html = Bytes::from_array(self.html)
  let line_offsets = self.line_offsets
  let mut i = 0
  Iter::new(() => {
    if i >= line_offsets.length() {
      return None
    }
    let line_start = line_offsets[i].reinterpret_as_int()
    let line_end = if i + 1 == line_offsets.length() {
      html.length()
    } else {
      line_offsets[i + 1].reinterpret_as_int()
    }
    i += 1
    Some(@utf8.decode_lossy(html[line_start:line_end]))
  })
}

///|
fn HtmlRenderer::add_carriage_return(
  self : HtmlRenderer,
  offset : Int32,
  attribute_callback : (Highlight, Array[Byte]) -> Unit,
) -> Unit {
  if self.carriage_return_highlight is Some(highlight) {
    // If a CR is the last character in a `HighlightEvent::Source`
    // region, then we don't know until the next `Source` event or EOF
    // whether it is part of CRLF or on its own. To avoid unbounded
    // lookahead, save the offset of the CR and insert there now that we
    // know.
    let rest = self.html.drain(offset, self.html.length())
    push_bytes(self.html, b"<span ")
    attribute_callback(highlight, self.html)
    push_bytes(self.html, b"></span>")
    self.html.append(rest)
  }
}

///|
fn push_bytes(html : Array[Byte], bytes : BytesView) -> Unit {
  for b in bytes {
    html.push(b)
  }
}

///|
fn HtmlRenderer::start_highlight(
  self : HtmlRenderer,
  h : Highlight,
  attribute_callback : (Highlight, Array[Byte]) -> Unit,
) -> Unit {
  push_bytes(self.html, b"<span ")
  attribute_callback(h, self.html)
  push_bytes(self.html, b">")
}

///|
fn HtmlRenderer::end_highlight(self : HtmlRenderer) -> Unit {
  push_bytes(self.html, b"</span>")
}

///|
fn html_escape(c : Byte) -> Bytes? {
  match c {
    b'>' => Some(b"&gt;")
    b'<' => Some(b"&lt;")
    b'&' => Some(b"&amp;")
    b'\'' => Some(b"&#39;")
    b'"' => Some(b"&quot;")
    _ => None
  }
}

///|
fn HtmlRenderer::add_text(
  self : HtmlRenderer,
  src : BytesView,
  highlights : Array[Highlight],
  attribute_callback : (Highlight, Array[Byte]) -> Unit,
) -> Unit {
  let chunks = @api.LossyUtf8::new(src)
  while chunks.next() is Some(chunk) {
    for c in @utf8.encode(chunk) {
      // Don't render carriage return characters, but allow lone carriage returns (not
      // followed by line feeds) to be styled via the attribute callback.
      if c == b'\r' {
        self.last_carriage_return = Some(self.html.length())
        continue
      }
      if self.last_carriage_return is Some(offset) {
        self.last_carriage_return = None
        if c != b'\n' {
          self.add_carriage_return(offset, attribute_callback)
        }
      }

      // At line boundaries, close and re-open all of the open tags.
      if c == b'\n' {
        for _ in highlights {
          self.end_highlight()
        }
        self.html.push(c)
        self.line_offsets.push(self.html.length().reinterpret_as_uint())
        for scope in highlights {
          self.start_highlight(scope, attribute_callback)
        }
      } else if html_escape(c) is Some(escape) {
        push_bytes(self.html, escape)
      } else {
        self.html.push(c)
      }
    }
  }
}

///|
fn injection_for_match(
  config : HighlightConfiguration,
  parent_name : String?,
  query : @api.Query,
  query_match : @api.QueryMatch,
  source : Bytes,
) -> (String?, @api.Node?, Bool) {
  let content_capture_index = config.injection_content_capture_index
  let language_capture_index = config.injection_language_capture_index
  let mut language_name = None
  let mut content_node = None
  for capture in query_match.captures() {
    let index = Some(capture.index)
    if index == language_capture_index {
      language_name = try capture.node.utf8_text(source) catch {
        _ => None
      } noraise {
        text => Some(text)
      }
    } else if index == content_capture_index {
      content_node = Some(capture.node)
    }
  }
  let mut include_children = false
  for prop in query.property_settings(query_match.pattern_index) {
    match prop.key {
      // In addition to specifying the language name via the text of a
      // captured node, it can also be hard-coded via a `#set!` predicate
      // that sets the injection.language key.
      "injection.language" if language_name is None =>
        language_name = prop.value
      // Setting the `injection.self` key can be used to specify that the
      // language name should be the same as the language of the current
      // layer.
      "injection.self" if language_name is None =>
        language_name = Some(config.language_name)
      // Setting the `injection.parent` key can be used to specify that
      // the language name should be the same as the language of the parent
      // layer
      "injection.parent" if language_name is None => language_name = parent_name
      // By default, injections do not include the *children* of an
      // `injection.content` node - only the ranges that belong to the
      // node itself. This can be changed using a `#set!` predicate that
      // sets the `injection.include-children` key.
      "injection.include-children" => include_children = true
      _ => ()
    }
  }
  (language_name, content_node, include_children)
}

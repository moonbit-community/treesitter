// Port of tree-sitter crates/tags/src/tags.rs.
//
// The C API (`c_lib.rs`, including the NUL-terminated copies of the syntax
// type names it hands out) is not ported. `regex::Regex` (used for
// `#strip!`) is `@regex.Regex` in UTF-8 mode.

///|
let max_line_len : Int32 = 180

///|
let cancellation_check_interval : Int32 = 100

///|
/// Stands for `usize::MAX`.
let usize_max : Int32 = 0x7FFFFFFF

///|
/// Contains the data needed to compute tags for code written in a
/// particular language.
pub struct TagsConfiguration {
  language : @treesitter.Language
  query : @treesitter.Query
  priv syntax_type_names : Array[String]
  priv capture_map : Map[Int32, NamedCapture]
  priv doc_capture_index : Int32?
  priv name_capture_index : Int32?
  priv ignore_capture_index : Int32?
  priv local_scope_capture_index : Int32?
  priv local_definition_capture_index : Int32?
  priv tags_pattern_index : Int32
  priv pattern_info : Array[PatternInfo]
}

///|
pub(all) struct NamedCapture {
  syntax_type_id : Int32
  is_definition : Bool
} derive(Eq, Debug)

///|
pub struct TagsContext {
  parser : @treesitter.Parser
  priv cursor : @treesitter.QueryCursor
}

///|
/// A tag. Ranges are `(start, end)` pairs (upstream: `Range<usize>`).
pub(all) struct Tag {
  range : (Int32, Int32)
  name_range : (Int32, Int32)
  line_range : (Int32, Int32)
  span : (@treesitter.Point, @treesitter.Point)
  utf16_column_range : (Int32, Int32)
  docs : String?
  is_definition : Bool
  syntax_type_id : Int32
} derive(Eq, Debug)

///|
pub(all) suberror TagsError {
  Query(@treesitter.QueryError)
  Regex(@regex.RegexError)
  Cancelled
  InvalidLanguage(@treesitter.LanguageError)
  InvalidCapture(String)
} derive(Eq, Debug)

///|
pub impl Show for TagsError with fn output(self, logger) {
  match self {
    Query(e) => logger.write_string(e.to_string())
    Regex(e) => logger.write_string(e.to_string())
    Cancelled => logger.write_string("Cancelled")
    InvalidLanguage(e) => logger.write_string("Invalid language: \{e}")
    InvalidCapture(name) =>
      logger.write_string(
        "Invalid capture @\{name}. Expected one of: @definition.*, @reference.*, @doc, @name, @local.(scope|definition|reference).",
      )
  }
}

///|
priv struct PatternInfo {
  mut docs_adjacent_capture : Int32?
  mut local_scope_inherits : Bool
  mut name_must_be_non_local : Bool
  mut doc_strip_regex : @regex.Regex?
}

///|
priv struct LocalDef {
  name : BytesView
}

///|
priv struct LocalScope {
  inherits : Bool
  range : (Int32, Int32)
  local_defs : Array[LocalDef]
}

///|
/// The iterator of tags returned by [`TagsContext::generate_tags`].
pub struct TagsIter {
  priv matches : @treesitter.QueryMatches[Bytes]
  priv tree : @treesitter.Tree
  priv source : Bytes
  priv mut prev_line_info : LineInfo?
  priv config : TagsConfiguration
  priv cancellation_flag : Ref[Int32]?
  priv mut iter_count : Int32
  priv tag_queue : Array[(Tag, Int32)]
  priv scopes : Array[LocalScope]
}

///|
priv struct LineInfo {
  utf8_position : @treesitter.Point
  utf8_byte : Int32
  utf16_column : Int32
  line_range : (Int32, Int32)
}

///|
pub fn TagsConfiguration::new(
  language : @treesitter.Language,
  tags_query : String,
  locals_query : String,
) -> TagsConfiguration raise TagsError {
  let query = @treesitter.Query::new(language, "\{locals_query}\{tags_query}") catch {
    e => raise Query(e)
  }
  let tags_query_offset = @utf8.encode(locals_query).length()
  let mut tags_pattern_index = 0
  for i in 0..<query.pattern_count() {
    let pattern_offset = query.start_byte_for_pattern(i)
    if pattern_offset < tags_query_offset {
      tags_pattern_index += 1
    }
  }
  let capture_map : Map[Int32, NamedCapture] = Map([])
  let syntax_type_names : Array[String] = []
  let mut doc_capture_index = None
  let mut name_capture_index = None
  let mut ignore_capture_index = None
  let mut local_scope_capture_index = None
  let mut local_definition_capture_index = None
  for i, name in query.capture_names() {
    match name {
      "name" => name_capture_index = Some(i)
      "ignore" => ignore_capture_index = Some(i)
      "doc" => doc_capture_index = Some(i)
      "local.scope" => local_scope_capture_index = Some(i)
      "local.definition" => local_definition_capture_index = Some(i)
      "local.reference" | "" => ()
      _ => {
        let mut is_definition = false
        let kind = if name.has_prefix("definition.") {
          is_definition = true
          trim_start_matches(name, "definition.")
        } else if name.has_prefix("reference.") {
          trim_start_matches(name, "reference.")
        } else {
          raise InvalidCapture(name)
        }
        // `CString::new(kind)` fails when the kind contains a NUL byte.
        if !kind.contains_char('\u{0}') {
          let syntax_type_id = match
            syntax_type_names.search_by(n => n == kind) {
            Some(id) => id
            None => {
              syntax_type_names.push(kind)
              syntax_type_names.length() - 1
            }
          }
          capture_map[i] = { syntax_type_id, is_definition, }
        }
      }
    }
  }
  let pattern_info = []
  for pattern_index in 0..<query.pattern_count() {
    let info : PatternInfo = {
      docs_adjacent_capture: None,
      local_scope_inherits: false,
      name_must_be_non_local: false,
      doc_strip_regex: None,
    }
    for pair in query.property_predicates(pattern_index) {
      let (property, is_positive) = pair
      if !is_positive && property.key == "local" {
        info.name_must_be_non_local = true
      }
    }
    info.local_scope_inherits = true
    for property in query.property_settings(pattern_index) {
      if property.key == "local.scope-inherits" &&
        property.value is Some("false") {
        info.local_scope_inherits = false
      }
    }
    if doc_capture_index is Some(doc_capture_index) {
      for predicate in query.general_predicates(pattern_index) {
        if predicate.args.get(0) is Some(Capture(first)) &&
          first == doc_capture_index {
          match (predicate.operator, predicate.args.get(1)) {
            ("select-adjacent!", Some(Capture(index))) =>
              info.docs_adjacent_capture = Some(index)
            ("strip!", Some(String(pattern))) => {
              let regex = @regex.Regex::new(pattern, utf8=true) catch {
                e => raise Regex(e)
              }
              info.doc_strip_regex = Some(regex)
            }
            _ => ()
          }
        }
      }
    }
    pattern_info.push(info)
  }
  {
    language,
    query,
    syntax_type_names,
    capture_map,
    doc_capture_index,
    name_capture_index,
    ignore_capture_index,
    local_scope_capture_index,
    local_definition_capture_index,
    tags_pattern_index,
    pattern_info,
  }
}

///|
/// `str::trim_start_matches`: strip every leading repetition of `prefix`.
fn trim_start_matches(s : String, prefix : String) -> String {
  let mut rest = s[:]
  while rest.has_prefix(prefix) {
    rest = rest[prefix.length():]
  }
  rest.to_owned()
}

///|
pub fn TagsConfiguration::syntax_type_name(
  self : TagsConfiguration,
  id : Int32,
) -> String {
  self.syntax_type_names[id]
}

///|
pub fn TagsContext::new() -> TagsContext {
  { parser: @treesitter.Parser::new(), cursor: @treesitter.QueryCursor::new(), }
}

///|
pub fn TagsContext::parser(self : TagsContext) -> @treesitter.Parser {
  self.parser
}

///|
/// Parse `source` and return an iterator over its tags, and whether the
/// syntax tree contains errors.
pub fn TagsContext::generate_tags(
  self : TagsContext,
  config : TagsConfiguration,
  source : Bytes,
  cancellation_flag? : Ref[Int32],
) -> (TagsIter, Bool) raise TagsError {
  self.parser.set_language(config.language) catch {
    e => raise InvalidLanguage(e)
  }
  self.parser.reset()
  let tree = self.parser.parse_with_options(
    (i, _) => if i < source.length() { source[i:] } else { b""[:] },
    options=@treesitter.ParseOptions::new(progress_callback=_ => {
      if cancellation_flag is Some(cancellation_flag) {
        if cancellation_flag.val != 0 {
          Break
        } else {
          Continue
        }
      } else {
        Continue
      }
    }),
  )
  guard tree is Some(tree) else { raise Cancelled }
  let matches = self.cursor.matches(config.query, tree.root_node(), source)
  (
    {
      tree,
      matches,
      source,
      config,
      cancellation_flag,
      prev_line_info: None,
      tag_queue: [],
      iter_count: 0,
      scopes: [
        { range: (0, source.length()), inherits: false, local_defs: [], },
      ],
    },
    tree.root_node().has_error(),
  )
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
/// `regex.replace_all(content, "")`: the bytes of `content` outside of the
/// successive non-overlapping matches.
fn strip_matches(regex : @regex.Regex, content : BytesView) -> String {
  let out = Buffer()
  let mut last = 0
  for m in regex.find_iter(content) {
    out.write_bytesview(content[last:m.0])
    last = m.1
  }
  out.write_bytesview(content[last:])
  @utf8.decode_lossy(out.to_bytes())
}

///|
/// The next tag, `Some(Err(Cancelled))` when tagging was cancelled, and
/// `None` once every tag has been returned.
pub fn TagsIter::next(self : TagsIter) -> Result[Tag, TagsError]? {
  ignore(self.tree)
  for ;; {
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

    // If there is a queued tag for an earlier node in the syntax tree, then pop
    // it off of the queue and return it.
    if self.tag_queue.last() is Some(last_entry) &&
      self.tag_queue.length() > 1 &&
      self.tag_queue[0].0.name_range.1 < last_entry.0.name_range.0 {
      let tag = self.tag_queue.remove(0).0
      if tag.is_ignored() {
        continue
      }
      return Some(Ok(tag))
    }

    // If there is another match, then compute its tag and add it to the
    // tag queue.
    if self.matches.next() is Some(mat) {
      let pattern_info = self.config.pattern_info[mat.pattern_index]
      if mat.pattern_index < self.config.tags_pattern_index {
        for capture in mat.captures() {
          let index = Some(capture.index)
          let range = capture.node.byte_range()
          if index == self.config.local_scope_capture_index {
            self.scopes.push({
              range,
              inherits: pattern_info.local_scope_inherits,
              local_defs: [],
            })
          } else if index == self.config.local_definition_capture_index {
            for i = self.scopes.length() - 1; i >= 0; i = i - 1 {
              let scope = self.scopes[i]
              if scope.range.0 <= range.0 && scope.range.1 >= range.1 {
                scope.local_defs.push({ name: self.source[range.0:range.1], })
                break
              }
            }
          }
        }
        continue
      }
      let mut name_node = None
      let doc_nodes = []
      let mut tag_node = None
      let mut syntax_type_id = 0
      let mut is_definition = false
      let mut docs_adjacent_node = None
      let mut is_ignored = false
      for capture in mat.captures() {
        let index = Some(capture.index)
        if index == self.config.ignore_capture_index {
          is_ignored = true
          name_node = Some(capture.node)
        }
        if index ==
          self.config.pattern_info[mat.pattern_index].docs_adjacent_capture {
          docs_adjacent_node = Some(capture.node)
        }
        if index == self.config.name_capture_index {
          name_node = Some(capture.node)
        } else if index == self.config.doc_capture_index {
          doc_nodes.push(capture.node)
        }
        if self.config.capture_map.get(capture.index) is Some(named_capture) {
          tag_node = Some(capture.node)
          syntax_type_id = named_capture.syntax_type_id
          is_definition = named_capture.is_definition
        }
      }
      if name_node is Some(name_node) {
        let name_range = name_node.byte_range()
        let tag = if tag_node is Some(tag_node) {
          if name_node.has_error() {
            continue
          }
          if pattern_info.name_must_be_non_local {
            let mut is_local = false
            let name = self.source[name_range.0:name_range.1]
            for i = self.scopes.length() - 1; i >= 0; i = i - 1 {
              let scope = self.scopes[i]
              if scope.range.0 <= name_range.0 && scope.range.1 >= name_range.1 {
                if scope.local_defs.iter().any(d => d.name == name) {
                  is_local = true
                  break
                }
                if !scope.inherits {
                  break
                }
              }
            }
            if is_local {
              continue
            }
          }

          // If needed, filter the doc nodes based on their ranges, selecting
          // only the slice that are adjacent to some specified node.
          let mut docs_start_index = 0
          if docs_adjacent_node is Some(docs_adjacent_node) &&
            !doc_nodes.is_empty() {
            docs_start_index = doc_nodes.length()
            let mut start_row = docs_adjacent_node.start_position().row
            while docs_start_index > 0 {
              let doc_node = doc_nodes[docs_start_index - 1]
              let prev_doc_end_row = doc_node.end_position().row
              if prev_doc_end_row + 1 >= start_row {
                docs_start_index -= 1
                start_row = doc_node.start_position().row
              } else {
                break
              }
            }
          }

          // Generate a doc string from all of the doc nodes, applying any strip
          // regexes.
          let mut docs_builder : StringBuilder? = None
          for doc_node in doc_nodes[docs_start_index:] {
            let (start, end) = doc_node.byte_range()
            let bytes = self.source[start:end]
            if is_valid_utf8(bytes) {
              let content = match pattern_info.doc_strip_regex {
                None => @utf8.decode_lossy(bytes)
                Some(regex) => strip_matches(regex, bytes)
              }
              match docs_builder {
                None => {
                  let d = StringBuilder()
                  d.write_string(content)
                  docs_builder = Some(d)
                }
                Some(d) => {
                  d.write_char('\n')
                  d.write_string(content)
                }
              }
            }
          }
          let docs = docs_builder.map(d => d.to_string())
          let rng = tag_node.byte_range()
          let range = (
            @cmp.minimum(rng.0, name_range.0),
            @cmp.maximum(rng.1, name_range.1),
          )
          let span = (name_node.start_position(), name_node.end_position())

          // Compute tag properties that depend on the text of the containing line. If
          // the previous tag occurred on the same line, then
          // reuse results from the previous tag.
          let mut prev_utf16_column = 0
          let mut prev_utf8_byte = name_range.0 - span.0.column
          let line_info = match self.prev_line_info {
            Some(info) if info.utf8_position.row == span.0.row => Some(info)
            _ => None
          }
          let line_range = if line_info is Some(line_info) {
            if line_info.utf8_position.column <= span.0.column {
              prev_utf8_byte = line_info.utf8_byte
              prev_utf16_column = line_info.utf16_column
            }
            line_info.line_range
          } else {
            line_range(self.source, name_range.0, span.0, max_line_len)
          }
          let utf16_start_column = prev_utf16_column +
            utf16_len(self.source[prev_utf8_byte:name_range.0])
          let utf16_end_column = utf16_start_column +
            utf16_len(self.source[name_range.0:name_range.1])
          let utf16_column_range = (utf16_start_column, utf16_end_column)
          self.prev_line_info = Some({
            utf8_position: span.1,
            utf8_byte: name_range.1,
            utf16_column: utf16_end_column,
            line_range,
          })
          {
            range,
            name_range,
            line_range,
            span,
            utf16_column_range,
            docs,
            is_definition,
            syntax_type_id,
          }
        } else if is_ignored {
          Tag::ignored(name_range)
        } else {
          continue
        }

        // Only create one tag per node. The tag queue is sorted by node position
        // to allow for fast lookup.
        match
          binary_search_by_key(
            self.tag_queue,
            (tag.name_range.1, tag.name_range.0),
          ) {
          Ok(i) => {
            let (_, pattern_index) = self.tag_queue[i]
            if pattern_index > mat.pattern_index {
              self.tag_queue[i] = (tag, mat.pattern_index)
            }
          }
          Err(i) => self.tag_queue.insert(i, (tag, mat.pattern_index))
        }
      }
      // If there are no more matches, then drain the queue.
    } else if !self.tag_queue.is_empty() {
      return Some(Ok(self.tag_queue.remove(0).0))
    } else {
      return None
    }
  }
}

///|
/// Iterate the remaining tags.
pub fn TagsIter::iter(self : TagsIter) -> Iter[Result[Tag, TagsError]] {
  Iter::new(() => self.next())
}

///|
/// `tag_queue.binary_search_by_key(&key, |(tag, _)| (tag.name_range.end,
/// tag.name_range.start))`. The keys in the queue are distinct.
fn binary_search_by_key(
  queue : Array[(Tag, Int32)],
  key : (Int32, Int32),
) -> Result[Int32, Int32] {
  let mut lo = 0
  let mut hi = queue.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let tag = queue[mid].0
    let k = (tag.name_range.1, tag.name_range.0)
    if k < key {
      lo = mid + 1
    } else if k > key {
      hi = mid
    } else {
      return Ok(mid)
    }
  }
  Err(lo)
}

///|
fn Tag::ignored(name_range : (Int32, Int32)) -> Tag {
  {
    name_range,
    line_range: (0, 0),
    span: (@treesitter.Point::new(0, 0), @treesitter.Point::new(0, 0)),
    utf16_column_range: (0, 0),
    range: (usize_max, usize_max),
    docs: None,
    is_definition: false,
    syntax_type_id: 0,
  }
}

///|
fn Tag::is_ignored(self : Tag) -> Bool {
  self.range.0 == usize_max
}

///|
/// `u8::is_ascii_whitespace`: space, tab, line feed, form feed or carriage
/// return.
fn is_ascii_whitespace(b : Byte) -> Bool {
  b == b' ' || b == b'\t' || b == b'\n' || b == b'\x0c' || b == b'\r'
}

///|
fn line_range(
  text : Bytes,
  start_byte : Int32,
  start_point : @treesitter.Point,
  max_line_len : Int32,
) -> (Int32, Int32) {
  // Trim leading whitespace
  let mut line_start_byte = start_byte - start_point.column
  while line_start_byte < text.length() &&
        is_ascii_whitespace(text[line_start_byte]) {
    line_start_byte += 1
  }
  let max_line_len = @cmp.minimum(max_line_len, text.length() - line_start_byte)
  let text_after_line_start = text[line_start_byte:line_start_byte +
    max_line_len]
  let line_len = match memchr(b'\n', text_after_line_start) {
    Some(len) => len
    None =>
      try @hir.from_utf8(text_after_line_start) catch {
        Utf8Error(valid_up_to~, ..) => valid_up_to
      } noraise {
        _ => max_line_len
      }
  }

  // Trim trailing whitespace
  let mut line_end_byte = line_start_byte + line_len
  while line_end_byte > line_start_byte &&
        is_ascii_whitespace(text[line_end_byte - 1]) {
    line_end_byte -= 1
  }
  (line_start_byte, line_end_byte)
}

///|
fn memchr(needle : Byte, haystack : BytesView) -> Int32? {
  for i, b in haystack {
    if b == needle {
      return Some(i)
    }
  }
  None
}

///|
/// The number of UTF-16 code units of the lossily decoded bytes.
fn utf16_len(bytes : BytesView) -> Int32 {
  let chunks = @treesitter.LossyUtf8::new(bytes)
  let mut len = 0
  while chunks.next() is Some(chunk) {
    // MoonBit strings are UTF-16.
    len += chunk.length()
  }
  len
}

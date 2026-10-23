///|
pub suberror TagsError {
  InvalidCapture(String)
  UnsupportedEncoding
}

///|
pub(all) struct Tag {
  name : String
  syntax_type : String
  is_definition : Bool
  range : @ts.Range
  name_range : @ts.Range
  /// Trimmed UTF-8 byte range of the name's line, capped at 180 bytes.
  line_range : (Int32, Int32)
  /// UTF-16 code unit columns of the name, measured from its line start.
  utf16_column_range : (Int32, Int32)
  docs : String?
}

///|
pub struct Configuration {
  language : @language.Language
  priv query : @query.Query
  priv locals : @query.Query
}

///|
pub fn Configuration::new(
  language : @language.Language,
  source : String,
  locals~ : String = "",
) -> Configuration raise {
  let query = @query.Query::new(language, source)
  for name in query.capture_names {
    if name != "name" &&
      name != "doc" &&
      name != "ignore" &&
      !name.has_prefix("definition.") &&
      !name.has_prefix("reference.") {
      raise InvalidCapture(name)
    }
  }
  if !query.capture_names.contains("name") {
    raise InvalidCapture("missing @name")
  }
  { language, query, locals: @query.Query::new(language, locals), }
}

///|
/// Extract definitions and references from @definition.*, @reference.*,
/// @name and optional @doc captures. Ranges use UTF-8 byte coordinates.
/// Non-UTF-8 trees raise `UnsupportedEncoding` because line metadata follows
/// the upstream UTF-8 tagger contract.
pub fn Configuration::generate(
  self : Configuration,
  tree : @ts.Tree,
  cancelled~ : () -> Bool = () => false,
) -> Array[Tag] raise {
  if tree.encoding() != @ts.Utf8 {
    raise UnsupportedEncoding
  }
  let locals = @query.Locals::new(self.locals, tree)
  // General predicates are consumer metadata, as in the upstream tagger.
  // Documentation directives are interpreted by Match.texts below.
  let matches = self.query.matches(
    tree.root_node(),
    tree.source,
    cancelled~,
    property=(key, _, node) => {
      key == "local" && node is Some(node) && locals.is_local(node)
    },
    predicate=(_, _, _, _) => true,
  )
  matches.sort_by_key(m => m.pattern_index)
  let ignored = []
  for matched in matches {
    for capture in matched.captures {
      if capture.name == "ignore" {
        ignored.push(capture.node.range())
      }
    }
  }
  let seen : Map[(Int32, Int32), Bool] = Map([])
  let tags = []
  for matched in matches {
    if cancelled() {
      raise @query.Cancelled
    }
    for capture in matched.captures {
      let definition = capture.name.has_prefix("definition.")
      if !definition && !capture.name.has_prefix("reference.") {
        continue
      }
      let syntax_type = capture.name[if definition { 11 } else { 10 }:].to_owned()
      for name in matched.captures {
        if name.name != "name" || name.node.has_error() {
          continue
        }
        if ignored.any(r => {
            r.start_byte <= name.node.start_byte() &&
            r.end_byte >= name.node.end_byte()
          }) {
          continue
        }
        let key = (name.node.start_byte(), name.node.end_byte())
        if seen.contains(key) {
          continue
        }
        seen[key] = true
        let docs = matched.texts("doc", tree.source)
        let start = name.node.start_byte()
        let end = name.node.end_byte()
        let line_start = start - name.node.start_position().column
        let utf16_start = utf16_len(tree.source, line_start, start)
        tags.push(Tag::{
          name: name.node.text(tree.source),
          syntax_type,
          is_definition: definition,
          range: {
            start_byte: Int32::min(
              capture.node.start_byte(),
              name.node.start_byte(),
            ),
            end_byte: Int32::max(capture.node.end_byte(), name.node.end_byte()),
            start_point: if capture.node.start_byte() < name.node.start_byte() {
              capture.node.start_position()
            } else {
              name.node.start_position()
            },
            end_point: if capture.node.end_byte() > name.node.end_byte() {
              capture.node.end_position()
            } else {
              name.node.end_position()
            },
          },
          name_range: name.node.range(),
          line_range: line_range(tree.source, line_start, 180),
          utf16_column_range: (
            utf16_start,
            utf16_start + utf16_len(tree.source, start, end),
          ),
          docs: if docs.is_empty() {
            None
          } else {
            Some(docs.join("\n"))
          },
        })
      }
    }
  }
  tags.sort_by_key(t => t.range.start_byte)
  tags
}

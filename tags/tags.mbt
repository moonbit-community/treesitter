///|
pub suberror TagsError {
  InvalidCapture(String)
}

///|
pub(all) struct Tag {
  name : String
  syntax_type : String
  is_definition : Bool
  range : @ts.Range
  name_range : @ts.Range
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
pub fn Configuration::generate(
  self : Configuration,
  tree : @ts.Tree,
  cancelled~ : () -> Bool = () => false,
) -> Array[Tag] raise @query.QueryError {
  let locals = @query.Locals::new(self.locals, tree)
  let matches = self.query.matches(tree.root_node(), tree.source, cancelled~, property=(
    key,
    _,
    node,
  ) => key == "local" && node is Some(node) && locals.is_local(node))
  let ignored = []
  for matched in matches {
    for capture in matched.captures {
      if capture.name == "ignore" {
        ignored.push(capture.node.range())
      }
    }
  }
  let seen : Map[(Int32, Int32, String, Bool), Bool] = Map([])
  let tags = []
  for matched in matches {
    if cancelled() {
      raise Cancelled
    }
    for capture in matched.captures {
      let definition = capture.name.has_prefix("definition.")
      if !definition && !capture.name.has_prefix("reference.") {
        continue
      }
      let syntax_type = capture.name[if definition { 11 } else { 10 }:].to_owned()
      for name in matched.captures {
        if name.name != "name" ||
          name.node.start_byte() < capture.node.start_byte() ||
          name.node.end_byte() > capture.node.end_byte() {
          continue
        }
        if ignored.any(r => {
            r.start_byte <= name.node.start_byte() &&
            r.end_byte >= name.node.end_byte()
          }) {
          continue
        }
        let key = (
          name.node.start_byte(),
          name.node.end_byte(),
          syntax_type,
          definition,
        )
        if seen.contains(key) {
          continue
        }
        seen[key] = true
        let docs = matched.texts("doc", tree.source)
        tags.push(Tag::{
          name: name.node.text(tree.source),
          syntax_type,
          is_definition: definition,
          range: capture.node.range(),
          name_range: name.node.range(),
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

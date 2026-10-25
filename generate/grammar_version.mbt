// Port of the deserialization in `read_grammar_version` of tree-sitter
// crates/generate/src/generate.rs: its private `TreeSitterJson` and
// `Metadata` structs, as serde_derive deserializes them. The file system walk
// lives with the loader.

///|
/// `serde_json::from_str::<TreeSitterJson>(contents)?.metadata.version`: the
/// unparsed `metadata.version` of a `tree-sitter.json`. Upstream reports an
/// error as ``Failed to parse `{path}` -- {error}``.
pub fn tree_sitter_json_version(
  contents : String,
) -> String raise @serde_json.JsonError {
  @serde_json.from_str(contents, de => {
    de.deserialize_struct(
      @serde_json.Visitor::new(
        "struct TreeSitterJson",
        visit_seq=seq => {
          match seq.next_element(deserialize_metadata) {
            Some(version) => version
            None =>
              raise @serde_json.invalid_length(
                0, "struct TreeSitterJson with 1 element",
              )
          }
        },
        visit_map=map => {
          let mut metadata = None
          while map.next_key(key => key == "metadata") is Some(is_metadata) {
            if is_metadata {
              if metadata is Some(_) {
                raise @serde_json.duplicate_field("metadata")
              }
              metadata = Some(map.next_value(deserialize_metadata))
            } else {
              map.next_value(de => de.deserialize_ignored_any())
            }
          }
          match metadata {
            Some(version) => version
            None => raise @serde_json.missing_field("metadata")
          }
        },
      ),
    )
  })
}

///|
/// `Metadata::deserialize`, returning its only field, `version`.
fn deserialize_metadata(
  de : @serde_json.Deserializer,
) -> String raise @serde_json.JsonError {
  de.deserialize_struct(
    @serde_json.Visitor::new(
      "struct Metadata",
      visit_seq=seq => {
        match seq.next_element(de => de.deserialize_string()) {
          Some(version) => version
          None =>
            raise @serde_json.invalid_length(
              0, "struct Metadata with 1 element",
            )
        }
      },
      visit_map=map => {
        let mut version = None
        while map.next_key(key => key == "version") is Some(is_version) {
          if is_version {
            if version is Some(_) {
              raise @serde_json.duplicate_field("version")
            }
            version = Some(map.next_value(de => de.deserialize_string()))
          } else {
            map.next_value(de => de.deserialize_ignored_any())
          }
        }
        match version {
          Some(version) => version
          None => raise @serde_json.missing_field("version")
        }
      },
    ),
  )
}

// Port of tree-sitter crates/cli/src/test_tags.rs.
//
// `test_tags` (the directory walk that resolves languages through the loader
// and records results in the CLI's `TestSummary`) is not ported.

///|
pub fn test_tag(
  tags_context : @tags.TagsContext,
  tags_config : @tags.TagsConfiguration,
  source : Bytes,
) -> Int32 raise QueryTestError {
  let tags = get_tag_positions(tags_context, tags_config, source)
  let assertions = parse_position_comments(
    tags_context.parser(),
    tags_config.language,
    source,
  )

  // Iterate through all of the assertions, checking against the actual tags.
  let mut i = 0
  let actual_tags : Array[String] = []
  for assertion in assertions {
    let { position, length, negative, expected_capture_name: expected_tag, } = assertion
    let mut passed = false
    let mut end_column = assertion_end_column(position.column, length)
    tag_loop~: while tags.get(i) is Some(tag) {
      if tag.1 <= position {
        i += 1
        continue tag_loop~
      }

      // Iterate through all of the tags that start at or before this assertion's
      // position, looking for one that matches the assertion
      let mut j = i
      while !passed && tags.get(j) is Some(tag) {
        end_column = assertion_end_column(position.column, length)
        if tag.0.column > end_column {
          break tag_loop~
        }
        let tag_name = tag.2
        if (tag_name == expected_tag) == negative {
          actual_tags.push(tag_name)
        } else {
          passed = true
          break tag_loop~
        }
        j += 1
        if tag == tags[tags.length() - 1] {
          break tag_loop~
        }
      }
    }
    if !passed {
      raise TagsFailure(
        row=position.row,
        column=end_column,
        expected_tag~,
        actual_tags=actual_tags.copy(),
      )
    }
  }
  assertions.length()
}

///|
pub fn get_tag_positions(
  tags_context : @tags.TagsContext,
  tags_config : @tags.TagsConfiguration,
  source : Bytes,
) -> Array[(Utf8Point, Utf8Point, String)] raise QueryTestError {
  let (tags_iter, _has_error) = tags_context.generate_tags(tags_config, source) catch {
    e => raise Tags(e)
  }
  let tag_positions = []
  while tags_iter.next() is Some(tag) {
    guard tag is Ok(tag) else { continue }
    let tag_postfix = tags_config.syntax_type_name(tag.syntax_type_id)
    let tag_name = if tag.is_definition {
      "definition.\{tag_postfix}"
    } else {
      "reference.\{tag_postfix}"
    }
    tag_positions.push(
      (
        to_utf8_point(tag.span.0, source),
        to_utf8_point(tag.span.1, source),
        tag_name,
      ),
    )
  }
  tag_positions
}

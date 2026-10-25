// Helpers of the port of tree-sitter crates/cli/src/tests/text_provider_test.rs
// (text_provider_suite_test.mbt), and further text provider checks.

///|
async fn parse_text(text : BytesView) -> (@treesitter.Tree, @treesitter.Language)? {
  guard get_parsing_language("c") is Some(language) else { return None }
  let parser = parser_for(language)
  Some((parser.parse(text).unwrap(), language))
}

///|
async fn parse_text_with(
  callback : (Int32, @treesitter.Point) -> BytesView,
) -> (@treesitter.Tree, @treesitter.Language)? {
  guard get_parsing_language("c") is Some(language) else { return None }
  let parser = parser_for(language)
  let tree = parser.parse_with_options(callback).unwrap()
  assert_eq(tree.root_node().child(0).unwrap().kind(), "comment") catch {
    e => abort(e.to_string())
  }
  Some((tree, language))
}

///|
fn[T : @treesitter.TextProvider] tree_query(
  tree : @treesitter.Tree,
  text : T,
  language : @treesitter.Language,
) -> Unit raise {
  let query = @treesitter.Query::new(
    language, "((comment) @c (#eq? @c \"// comment\"))",
  )
  let cursor = @treesitter.QueryCursor::new()
  let captures = cursor.captures(query, tree.root_node(), text)
  let (match_, idx) = captures.next().unwrap()
  let capture = match_.captures()[idx]
  assert_eq(capture.index, idx)
  assert_eq("comment", capture.node.kind())
}

///|
async fn[T : @treesitter.TextProvider] check_parsing(
  parser_text : BytesView,
  text_provider : T,
) -> Unit {
  guard parse_text(parser_text) is Some((tree, language)) else { return }
  tree_query(tree, text_provider, language)
}

///|
async fn[T : @treesitter.TextProvider] check_parsing_callback(
  parser_callback : (Int32, @treesitter.Point) -> BytesView,
  text_provider : T,
) -> Unit {
  guard parse_text_with(parser_callback) is Some((tree, language)) else {
    return
  }
  tree_query(tree, text_provider, language)
}

///|
let comment_text : String = "// comment"

///|
fn comment_reader() -> (Int32, @treesitter.Point) -> BytesView {
  let text = utf8(comment_text)
  (offset, _) => if offset < text.length() { text[offset:] } else { b""[:] }
}

///|
async test "text_provider_for_sliced_bytes" {
  // The provider only needs the node's range to be in bounds.
  let text = utf8(comment_text + "\n\nint x;")
  check_parsing(text, text[0:text.length()])
}

///|
async test "text_provider_callback_with_chunks" {
  // The text predicate sees the concatenation of the chunks.
  let text = utf8(comment_text)
  check_parsing_callback(
    comment_reader(),
    @treesitter.TextCallback::new(_ => [text[0:3], text[3:4], text[4:]].iter()),
  )
  // An empty chunk sequence is the empty text, which does not match.
  guard parse_text(text) is Some((tree, language)) else { return }
  let query = @treesitter.Query::new(
    language, "((comment) @c (#eq? @c \"// comment\"))",
  )
  let cursor = @treesitter.QueryCursor::new()
  let captures = cursor.captures(
    query,
    tree.root_node(),
    @treesitter.TextCallback::new(_ => Iter::empty()),
  )
  assert_true(captures.next() is None)
}

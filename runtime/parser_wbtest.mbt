///|
/// tree-sitter's `extra_non_terminals` test grammar: `module` is
/// `a b c d`, and `comment`s (non-terminal extras) may appear anywhere.
let extra_non_terminals_grammar : String =
  #|{"name": "extra_non_terminals",
  #| "rules": {
  #|  "module": {"type": "SEQ", "members": [{"type": "STRING", "value": "a"}, {"type": "STRING", "value": "b"}, {"type": "STRING", "value": "c"}, {"type": "STRING", "value": "d"}]},
  #|  "comment": {"type": "CHOICE", "members": [{"type": "SYMBOL", "name": "paren_comment"}, {"type": "SYMBOL", "name": "line_comment"}]},
  #|  "paren_comment": {"type": "TOKEN", "content": {"type": "SEQ", "members": [{"type": "STRING", "value": "("}, {"type": "REPEAT", "content": {"type": "PATTERN", "value": "[a-z]+"}}, {"type": "STRING", "value": ")"}]}},
  #|  "line_comment": {"type": "TOKEN", "content": {"type": "SEQ", "members": [{"type": "STRING", "value": "//"}, {"type": "PATTERN", "value": ".*"}]}}},
  #| "extras": [{"type": "PATTERN", "value": "\\s"}, {"type": "SYMBOL", "name": "comment"}]}

///|
fn extra_non_terminals_parser() -> Parser raise {
  let generated = @generate.generate_from_grammar_json(
    extra_non_terminals_grammar,
  )
  let parser = Parser::new()
  assert_true(parser.set_language(Some(generated.language)))
  parser
}

///|
/// `"a" + "(x)" × n + "bcd" + "(y)" × n`.
fn extra_non_terminals_source(n : Int32) -> Bytes {
  let sb = StringBuilder()
  sb.write_string("a")
  for _ in 0..<n {
    sb.write_string("(x)")
  }
  sb.write_string("bcd")
  for _ in 0..<n {
    sb.write_string("(y)")
  }
  @utf8.encode(sb.to_string())
}

///|
/// The slots of `array` past its length. Native arrays keep whatever those
/// slots last held, so they must not refer to subtrees of a finished parse;
/// the other backends do not retain anything there.
/// `upto` bounds the slots read to those known to have been written.
#cfg(target="native")
fn[T] spare_slots(array : Array[T], upto? : Int32) -> Array[T] {
  let end = upto.unwrap_or(array.capacity())
  Array::makei(end - array.length(), i => array.unsafe_get(array.length() + i))
}

///|
#cfg(not(target="native"))
fn[T] spare_slots(array : Array[T], upto? : Int32) -> Array[T] {
  ignore(array)
  ignore(upto)
  []
}

///|
/// No scratch state of an idle parser refers to a tree or to the input.
fn assert_parser_scratch_released(parser : Parser) -> Unit raise {
  assert_true(physical_equal(parser.lexer.input, no_input))
  assert_true(!parser.lexer.has_chunk)
  assert_eq(parser.lexer.chunk.length(), 0)
  assert_eq(parser.stack.slices.length(), 0)
  for slice in spare_slots(parser.stack.slices) {
    assert_true(physical_equal(slice, stack_slice_none))
  }
  assert_eq(parser.stack.iterators.length(), 0)
  assert_eq(parser.reusable_node.stack.length(), 0)
  for entry in spare_slots(parser.reusable_node.stack) {
    assert_true(physical_equal(entry, reusable_stack_entry_none))
  }
  for
    array in [
      parser.trailing_extras,
      parser.trailing_extras2,
      parser.balance_stack,
    ] {
    assert_eq(array.length(), 0)
    for subtree in spare_slots(array) {
      assert_true(subtree is Null)
    }
  }
}

///|
/// `ts_parser__accept` replaces the root with its children in one splice
/// (it was quadratic in the number of trailing extras).
test "accept splices the root's children once" {
  let parser = extra_non_terminals_parser()
  let n = 3000
  let tree = parser.parse_string(None, extra_non_terminals_source(n)).unwrap()
  let root = tree.root()
  let language = parser.language.unwrap()
  let names = root
    .children()
    .map(child => language.symbol_name(child.symbol()).unwrap_or("?"))
  // a, n comments, b, c, d, n comments and the EOF token.
  assert_eq(names.length(), 2 * n + 5)
  assert_eq(names[0], "a")
  assert_eq(names[n + 1], "b")
  assert_eq(names[n + 2], "c")
  assert_eq(names[n + 3], "d")
  assert_eq(names[2 * n + 4], "end")
  for i in 0..<n {
    assert_eq(names[1 + i], "comment")
    assert_eq(names[n + 4 + i], "comment")
  }
  assert_eq(root.ptr().ref_count, 1)
  for child in root.children() {
    if child is Heap(d) {
      assert_eq(d.ref_count, 1)
    }
  }
}

///|
/// An idle parser keeps neither the previous tree nor the input callback
/// (and so the source it captures) alive: after a parse, after a cancelled
/// parse (input only), and after `reset`.
test "an idle parser drops its scratch references" {
  let parser = extra_non_terminals_parser()
  let source = extra_non_terminals_source(200)
  let tree = parser.parse_string(None, source).unwrap()
  assert_parser_scratch_released(parser)
  // Reparse with the old tree, which fills the reusable node stack.
  let tree2 = parser.parse_string(Some(tree), source).unwrap()
  assert_parser_scratch_released(parser)
  ignore(tree2)
  // A cancelled parse keeps its stack for resumption but not its input.
  let result = parser.parse_with_options(
    None,
    {
      read: (byte, _) => source[byte.reinterpret_as_int():],
      encoding: UTF8,
      decode: None,
    },
    { progress_callback: Some(_ => true), },
  )
  assert_true(result is None)
  assert_true(parser.has_outstanding_parse())
  assert_true(physical_equal(parser.lexer.input, no_input))
  assert_true(!parser.lexer.has_chunk)
  parser.reset()
  assert_parser_scratch_released(parser)
  ignore(parser.parse_string(None, source).unwrap())
  ignore(parser.set_language(None))
  assert_parser_scratch_released(parser)
}

///|
/// `ts_subtree_release` resets each slot of its global stack as it pops it,
/// so a released tree is not kept reachable from the stack's buffer.
test "subtree release leaves no references in its stack" {
  let parser = extra_non_terminals_parser()
  let tree = parser.parse_string(None, extra_non_terminals_source(50)).unwrap()
  let root = tree.root()
  let heap_children = root.children().filter(child => child is Heap(_)).length()
  assert_true(heap_children >= 100)
  root.release()
  assert_eq(release_stack.length(), 0)
  // The root's heap children were all pushed at once, into slots
  // 0..heap_children.
  let slots = spare_slots(release_stack, upto=heap_children)
  for slot in slots {
    assert_true(slot is Null)
  }
}

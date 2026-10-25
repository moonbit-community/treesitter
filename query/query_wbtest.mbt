// White-box tests of the C integer widths and memory behaviour of the query
// port (lib/src/query.c). Scenarios that need more than 65536 captures are
// too slow to compile in a test (upstream's capture lookup is quadratic), so
// the narrowing helpers are tested directly.

///|
test "symbol names compare like strncmp, then check name[length]" {
  // `strncmp` stops at the embedded NUL, but `!symbol_name[length]` fails.
  inspect(c_name_equals(b"a\x00b", b"a\x00"[:]), content="false")
  inspect(c_name_equals(b"a\x00", b"a\x00"[:]), content="true")
  inspect(c_name_equals(b"a\x00b", b"a\x00b"[:]), content="true")
  // Bytes after the NUL are not compared.
  inspect(c_name_equals(b"a\x00b", b"a\x00c"[:]), content="true")
  inspect(c_name_equals(b"ab", b"a"[:]), content="false")
  inspect(c_name_equals(b"a", b"ab"[:]), content="false")
  inspect(c_name_equals(b"ab", b"ab"[:]), content="true")
}

///|
test "symbol and field lookups read the name arrays like C" {
  let language = basic_cst()
  // An anonymous symbol whose name has an embedded NUL.
  language.symbol_names[1] = "a\u{0}b"
  inspect(symbol_for_name(language, b"a\x00"[:], false), content="0")
  inspect(symbol_for_name(language, b"a\x00b"[:], false), content="1")
  // `strncmp` stops at the NUL: the bytes after it are not compared.
  inspect(symbol_for_name(language, b"a\x00c"[:], false), content="1")
  inspect(field_id_for_name(language, b"name"[:]), content="1")
  inspect(field_id_for_name(language, b"nam"[:]), content="0")
  inspect(field_id_for_name(language, b"value"[:]), content="2")
}

///|
test "capture and string ids are uint16_t" {
  let table = SymbolTable::new()
  for i in 0..<=65536 {
    table.names.push(@utf8.encode("c\{i}"))
  }
  inspect(@utf8.decode_lossy(table.name_for_id(65536)), content="c0")
  inspect(@utf8.decode_lossy(table.name_for_id(65537)), content="c1")
  // The id of a newly inserted name is narrowed too.
  inspect(table.insert_name(b"new"[:]), content="1")
  let quantifiers = [OneOrMore, ZeroOrOne]
  debug_inspect(
    capture_quantifier_for_id(quantifiers, 65536),
    content="OneOrMore",
  )
  capture_quantifiers_add_for_id(quantifiers, 65537, One)
  debug_inspect(quantifiers, content="[OneOrMore, OneOrMore]")
  let step = QueryStep::new(1, 0, false)
  step.add_capture(0)
  step.add_capture(65537)
  step.add_capture(2)
  debug_inspect(step.capture_ids, content="<FixedArray: [0, 1, 2]>")
  step.remove_capture(65536)
  debug_inspect(step.capture_ids, content="<FixedArray: [1, 2, 65535]>")
}

///|
test "predicate capture ids are uint16_t in the analysis" {
  let source = b"(assignment (identifier) @a \"=\" @b (#is? @a))"
  let query = Query::new(basic_cst(), source)
  // `=` is at byte 28; its step is guaranteed because the predicate only
  // uses `@a`.
  inspect(query.is_pattern_guaranteed_at_step(28), content="true")
  // A predicate capture id beyond 65535 (only possible with more than 65536
  // captures) narrows to `@b`, which `=` carries.
  for i, step in query.predicate_steps {
    if step.type_ == Capture {
      query.predicate_steps[i] = { type_: Capture, value_id: 65536 + 1, }
    }
  }
  ignore(query.analyze_patterns())
  inspect(query.is_pattern_guaranteed_at_step(28), content="false")
}

///|
test "query compilation releases its string buffer" {
  let source = b"((identifier) @a (#eq? @a \"a long predicate string literal\"))"
  let query = Query::new(basic_cst(), source)
  inspect(query.string_buffer.length(), content="0")
  inspect(query.string_buffer.capacity(), content="0")
}

///|
/// A capture whose node is distinguishable from `null_capture`.
fn test_capture(index : Int) -> QueryCapture {
  { node: @runtime.Node::new(None, None, @runtime.length_zero(), 1), index }
}

///|
test "released capture lists do not keep their nodes" {
  let capture = test_capture(7)
  let pool = CaptureListPool::new()
  let id = pool.acquire()
  let list = pool.get_list(id)
  list.push(capture)
  list.push(capture)
  pool.release(id)
  inspect(pool.get(id).length(), content="0")
  inspect(physical_equal(list.items[0], null_capture), content="true")
  inspect(physical_equal(list.items[1], null_capture), content="true")
  // Reset and reuse also overwrite the previous captures.
  let id = pool.acquire()
  pool.get_list(id).push(capture)
  pool.reset()
  inspect(
    physical_equal(pool.get_list(id).items[0], null_capture),
    content="true",
  )
  let id = pool.acquire()
  pool.get_list(id).push(capture)
  pool.get_list(id).clear()
  inspect(
    physical_equal(pool.get_list(id).items[0], null_capture),
    content="true",
  )
}

///|
test "handed-out capture lists keep their elements" {
  let pool = CaptureListPool::new()
  let id = pool.acquire()
  let list = pool.get_list(id)
  list.push(test_capture(0))
  let serial = list.serial
  let exposed = list.expose()
  // Growing the list (in place and by reallocating) leaves the view alone.
  for i in 1..<20 {
    list.push(test_capture(i))
  }
  inspect(list.serial == serial, content="true")
  inspect(exposed.length(), content="1")
  inspect(exposed[0].index, content="0")
  let exposed = list.expose()
  // Releasing and reusing the list does not overwrite a view of it, and
  // changes the list's serial.
  pool.release(id)
  inspect(list.serial == serial, content="false")
  let id = pool.acquire()
  pool.get_list(id).push(test_capture(100))
  debug_inspect(
    exposed.map(c => c.index),
    content=(
      #|[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19]
    ),
  )
  debug_inspect(pool.get(id).map(c => c.index), content="[100]")
}

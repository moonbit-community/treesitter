// Port of tree-sitter crates/cli/src/tests/tags_test.rs.
//
// Tests that need a fixture language whose external scanner is not ported yet
// (javascript) are skipped with a notice until it is (see fixtures).
// `test_tags_via_c_api` is not ported (the C API is not ported); upstream's
// allocation tracking (`allocations::record`) has no equivalent.

///|
let python_tag_query : String =
  #|
  #|(
  #|  (function_definition
  #|    name: (identifier) @name
  #|    body: (block . (expression_statement (string) @doc))) @definition.function
  #|  (#strip! @doc "(^['\"\\s]*)|(['\"\\s]*$)")
  #|)
  #|
  #|(function_definition
  #|  name: (identifier) @name) @definition.function
  #|
  #|(
  #|  (class_definition
  #|    name: (identifier) @name
  #|    body: (block
  #|      . (expression_statement (string) @doc))) @definition.class
  #|  (#strip! @doc "(^['\"\\s]*)|(['\"\\s]*$)")
  #|)
  #|
  #|(class_definition
  #|  name: (identifier) @name) @definition.class
  #|
  #|(call
  #|  function: (identifier) @name) @reference.call
  #|
  #|(call
  #|  function: (attribute
  #|    attribute: (identifier) @name)) @reference.call
  #|

///|
let js_tag_query : String =
  #|
  #|(
  #|    (comment)* @doc .
  #|    (class_declaration
  #|        name: (identifier) @name) @definition.class
  #|    (#select-adjacent! @doc @definition.class)
  #|    (#strip! @doc "(^[/\\*\\s]*)|([/\\*\\s]*$)")
  #|)
  #|
  #|(
  #|    (comment)* @doc .
  #|    (method_definition
  #|        name: (property_identifier) @name) @definition.method
  #|    (#select-adjacent! @doc @definition.method)
  #|    (#strip! @doc "(^[/\\*\\s]*)|([/\\*\\s]*$)")
  #|)
  #|
  #|(
  #|    (comment)* @doc .
  #|    (function_declaration
  #|        name: (identifier) @name) @definition.function
  #|    (#select-adjacent! @doc @definition.function)
  #|    (#strip! @doc "(^[/\\*\\s]*)|([/\\*\\s]*$)")
  #|)
  #|
  #|(call_expression
  #|    function: (identifier) @name) @reference.call
  #|

///|
let ruby_tag_query : String =
  #|
  #|(method
  #|    name: (_) @name) @definition.method
  #|
  #|(call
  #|    method: (identifier) @name) @reference.call
  #|
  #|(setter (identifier) @ignore)
  #|
  #|((identifier) @name @reference.call
  #| (#is-not? local))
  #|

///|
fn substr(source : Bytes, range : (Int32, Int32)) -> String {
  @utf8.decode(source[range.0:range.1]) catch {
    _ => abort("not UTF-8")
  }
}

///|
/// Upstream's `strip_whitespace`: drop the first line and remove up to
/// `indent` leading bytes from each other line.
fn strip_whitespace(indent : Int32, s : String) -> String {
  let lines = s.split("\n").to_array()
  let out = []
  for i in 1..<lines.length() {
    let line = lines[i]
    let n = if line.length() < indent { line.length() } else { indent }
    out.push(line[n:].to_owned())
  }
  out.join("\n")
}

///|
fn collect(iter : @tags.TagsIter) -> Array[@tags.Tag] raise @tags.TagsError {
  let tags = []
  while iter.next() is Some(tag) {
    match tag {
      Ok(tag) => tags.push(tag)
      Err(e) => raise e
    }
  }
  tags
}

///|
async test "tags_python" {
  guard @fixtures.get_language("python") is Some(language) else { return }
  let tags_config = @tags.TagsConfiguration::new(language, python_tag_query, "")
  let tag_context = @tags.TagsContext::new()
  let source = @utf8.encode(
    (
      #|
      #|    class Customer:
      #|        """
      #|        Data about a customer
      #|        """
      #|
      #|        def age(self):
      #|            '''
      #|            Get the customer's age
      #|            '''
      #|            compute_age(self.id)
      #|    }
      #|
    ),
  )
  let tags = collect(tag_context.generate_tags(tags_config, source).0)
  assert_eq(
    tags.map(t => {
      (
        substr(source, t.name_range),
        tags_config.syntax_type_name(t.syntax_type_id),
      )
    }),
    [("Customer", "class"), ("age", "function"), ("compute_age", "call")],
  )
  assert_eq(substr(source, tags[0].line_range), "class Customer:")
  assert_eq(substr(source, tags[1].line_range), "def age(self):")
  assert_eq(tags[0].docs, Some("Data about a customer"))
  assert_eq(tags[1].docs, Some("Get the customer's age"))
}

///|
async test "tags_javascript" {
  guard @fixtures.get_language("javascript") is Some(language) else { return }
  let tags_config = @tags.TagsConfiguration::new(language, js_tag_query, "")
  let source = @utf8.encode(
    (
      #|
      #|    // hi
      #|
      #|    // Data about a customer.
      #|    // bla bla bla
      #|    class Customer {
      #|        /*
      #|         * Get the customer's age
      #|         */
      #|        getAge() {
      #|        }
      #|    }
      #|
      #|    // ok
      #|
      #|    class Agent {
      #|
      #|    }
      #|
    ),
  )
  let tag_context = @tags.TagsContext::new()
  let tags = collect(tag_context.generate_tags(tags_config, source).0)
  assert_eq(
    tags.map(t => {
      (
        substr(source, t.name_range),
        t.span,
        tags_config.syntax_type_name(t.syntax_type_id),
      )
    }),
    [
      ("Customer", (@treesitter.Point::new(5, 10), @treesitter.Point::new(5, 18)), "class"),
      ("getAge", (@treesitter.Point::new(9, 8), @treesitter.Point::new(9, 14)), "method"),
      ("Agent", (@treesitter.Point::new(15, 10), @treesitter.Point::new(15, 15)), "class"),
    ],
  )
  assert_eq(tags[0].docs, Some("Data about a customer.\nbla bla bla"))
  assert_eq(tags[1].docs, Some("Get the customer's age"))
  assert_eq(tags[2].docs, None)
}

///|
async test "tags_columns_measured_in_utf16_code_units" {
  guard @fixtures.get_language("python") is Some(language) else { return }
  let tags_config = @tags.TagsConfiguration::new(language, python_tag_query, "")
  let tag_context = @tags.TagsContext::new()
  let source = @utf8.encode("\"❤️❤️❤️\".hello_α_ω()")
  guard tag_context.generate_tags(tags_config, source).0.next() is Some(Ok(tag)) else {
    fail("expected a tag")
  }
  assert_eq(substr(source, tag.name_range), "hello_α_ω")
  assert_eq(tag.span, (@treesitter.Point::new(0, 21), @treesitter.Point::new(0, 32)))
  assert_eq(tag.utf16_column_range, (9, 18))
}

///|
async test "tags_ruby" {
  guard @fixtures.get_language("ruby") is Some(language) else { return }
  guard @fixtures.read_query("ruby", "locals.scm") is Some(locals_query) else {
    return
  }
  let tags_config = @tags.TagsConfiguration::new(
    language, ruby_tag_query, locals_query,
  )
  let source = strip_whitespace(
    8,
    (
      #|
      #|        b = 1
      #|
      #|        def foo=()
      #|            c = 1
      #|
      #|            # a is a method because it is not in scope
      #|            # b is a method because `b` doesn't capture variables from its containing scope
      #|            bar a, b, c
      #|
      #|            [1, 2, 3].each do |a|
      #|                # a is a parameter
      #|                # b is a method
      #|                # c is a variable, because the block captures variables from its containing scope.
      #|                baz a, b, c
      #|            end
      #|        end
    ),
  )
  let source = @utf8.encode(source)
  let tag_context = @tags.TagsContext::new()
  let tags = collect(tag_context.generate_tags(tags_config, source).0)
  assert_eq(
    tags.map(t => {
      (
        substr(source, t.name_range),
        tags_config.syntax_type_name(t.syntax_type_id),
        (t.span.0.row, t.span.0.column),
      )
    }),
    [
      ("foo=", "method", (2, 4)),
      ("bar", "call", (7, 4)),
      ("a", "call", (7, 8)),
      ("b", "call", (7, 11)),
      ("each", "call", (9, 14)),
      ("baz", "call", (13, 8)),
      ("b", "call", (13, 15)),
    ],
  )
}

///|
async test "tags_cancellation" {
  guard @fixtures.get_language("javascript") is Some(language) else { return }
  // Large javascript document
  let source = StringBuilder()
  for _ in 0..<500 {
    source.write_string("/* hi */ class A { /* ok */ b() {} }\n")
  }
  let source = @utf8.encode(source.to_string())
  let cancellation_flag = Ref::{ val: 0, }
  let tags_config = @tags.TagsConfiguration::new(language, js_tag_query, "")
  let tag_context = @tags.TagsContext::new()
  let tags = tag_context.generate_tags(tags_config, source, cancellation_flag~)
  let mut found_cancellation_error = false
  let mut i = 0
  while tags.0.next() is Some(tag) {
    if i == 150 {
      cancellation_flag.val = 1
    }
    i += 1
    match tag {
      Ok(_) => ()
      Err(@tags.Cancelled) => {
        found_cancellation_error = true
        break
      }
      Err(e) => abort("Unexpected error type while iterating tags: \{e}")
    }
  }
  assert_true(
    found_cancellation_error,
    msg="Expected to halt tagging with a cancellation error",
  )
}

///|
async test "invalid_capture" {
  guard @fixtures.get_language("python") is Some(language) else { return }
  try @tags.TagsConfiguration::new(language, "(identifier) @method", "") catch {
    e => assert_eq(e, InvalidCapture("method"))
  } noraise {
    _ => fail("expected InvalidCapture error")
  }
}

///|
async test "tags_with_parse_error" {
  guard @fixtures.get_language("python") is Some(language) else { return }
  let tags_config = @tags.TagsConfiguration::new(language, python_tag_query, "")
  let tag_context = @tags.TagsContext::new()
  let source = @utf8.encode(
    (
      #|
      #|    class Fine: pass
      #|    class Bad
      #|
    ),
  )
  let (tags, failed) = tag_context.generate_tags(tags_config, source)
  let newtags = collect(tags)
  assert_true(failed, msg="syntax error should have been detected")
  assert_eq(
    newtags.map(t => {
      (
        substr(source, t.name_range),
        tags_config.syntax_type_name(t.syntax_type_id),
      )
    }),
    [("Fine", "class")],
  )
}

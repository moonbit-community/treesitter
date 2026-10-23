// Port of the `#[cfg(test)]` tests of tree-sitter crates/cli/src/test.rs.
// `run_tests_single_passing` and `run_tests_fail_fast` test the `test`
// command runner, which is not ported yet.

///|
fn example(
  name : String,
  input : String,
  output : String,
  header_delim_len : Int32,
  divider_delim_len : Int32,
  attributes_str~ : String = "",
  attributes~ : TestAttributes = TestAttributes::default(),
) -> TestEntry {
  Example(
    name~,
    input=@utf8.encode(input),
    output~,
    header_delim_len~,
    divider_delim_len~,
    has_fields=false,
    attributes_str~,
    attributes~,
    file_name=None,
  )
}

///|
fn trimmed(s : String) -> String {
  trim_ws(s).to_owned()
}

///|
test "test_parse_test_content_simple" {
  let entry = parse_test_content(
    "the-filename",
    trimmed(
      (
        #|
        #|===============
        #|The first test
        #|===============
        #|
        #|a b c
        #|
        #|---
        #|
        #|(a
        #|    (b c))
        #|
        #|================
        #|The second test
        #|================
        #|d
        #|---
        #|(d)
        #|
      ),
    ),
    None,
  )
  assert_eq(
    entry,
    Group(
      name="the-filename",
      children=[
        example("The first test", "\na b c\n", "(a (b c))", 15, 3),
        example("The second test", "d", "(d)", 16, 3),
      ],
      file_path=None,
    ),
  )
}

///|
test "test_parse_test_content_with_dashes_in_source_code" {
  let entry = parse_test_content(
    "the-filename",
    trimmed(
      (
        #|
        #|==================
        #|Code with dashes
        #|==================
        #|abc
        #|---
        #|defg
        #|----
        #|hijkl
        #|-------
        #|
        #|(a (b))
        #|
        #|=========================
        #|Code ending with dashes
        #|=========================
        #|abc
        #|-----------
        #|-------------------
        #|
        #|(c (d))
        #|
      ),
    ),
    None,
  )
  assert_eq(
    entry,
    Group(
      name="the-filename",
      children=[
        example(
          "Code with dashes", "abc\n---\ndefg\n----\nhijkl", "(a (b))", 18, 7,
        ),
        example(
          "Code ending with dashes", "abc\n-----------", "(c (d))", 25, 19,
        ),
      ],
      file_path=None,
    ),
  )
}

///|
test "test_parse_test_content_with_equals_in_source_code" {
  // A literal `===` inside a test body must not be mistaken for an
  // opening header
  let entry = parse_test_content(
    "the-filename",
    trimmed(
      (
        #|
        #|==========
        #|First
        #|==========
        #|a
        #|===
        #|b
        #|---
        #|(a)
        #|
        #|==========
        #|Second
        #|==========
        #|c
        #|---
        #|(c)
        #|
      ),
    ),
    None,
  )
  assert_eq(
    entry,
    Group(
      name="the-filename",
      children=[
        example("First", "a\n===\nb", "(a)", 10, 3),
        example("Second", "c", "(c)", 10, 3),
      ],
      file_path=None,
    ),
  )
}

///|
test "test_parse_test_content_with_tied_divider_length" {
  // When two `---` lines in a body have the same length, the real
  // divider is the last one.
  let entry = parse_test_content(
    "the-filename",
    trimmed(
      (
        #|
        #|==========
        #|Tied dashes
        #|==========
        #|a
        #|---
        #|b
        #|---
        #|(c)
        #|
      ),
    ),
    None,
  )
  assert_eq(
    entry,
    Group(
      name="the-filename",
      children=[example("Tied dashes", "a\n---\nb", "(c)", 10, 3)],
      file_path=None,
    ),
  )
}

///|
test "test_format_sexp" {
  assert_eq(@api.format_sexp("", 0), "")
  assert_eq(
    @api.format_sexp("(a b: (c) (d) e: (f (g (h (MISSING i)))))", 0),
    trimmed(
      (
        #|
        #|(a
        #|  b: (c)
        #|  (d)
        #|  e: (f
        #|    (g
        #|      (h
        #|        (MISSING i)))))
        #|
      ),
    ),
  )
  assert_eq(
    @api.format_sexp("(program (ERROR (UNEXPECTED ' ')) (identifier))", 0),
    trimmed(
      (
        #|
        #|(program
        #|  (ERROR
        #|    (UNEXPECTED ' '))
        #|  (identifier))
        #|
      ),
    ),
  )
  assert_eq(
    @api.format_sexp("(source_file (MISSING \")\"))", 0),
    trimmed(
      (
        #|
        #|(source_file
        #|  (MISSING ")"))
        #|
      ),
    ),
  )
  assert_eq(
    @api.format_sexp(
      "(source_file (ERROR (UNEXPECTED 'f') (UNEXPECTED '+')))", 0,
    ),
    trimmed(
      (
        #|
        #|(source_file
        #|  (ERROR
        #|    (UNEXPECTED 'f')
        #|    (UNEXPECTED '+')))
        #|
      ),
    ),
  )
}

///|
test "test_write_tests_to_buffer" {
  let buffer = StringBuilder()
  let corrected_entries = [
    TestCorrection::new("title 1", "input 1", "output 1", "", 80, 80),
    TestCorrection::new("title 2", "input 2", "output 2", "", 80, 80),
  ]
  write_tests_to_buffer(buffer, corrected_entries)
  assert_eq(
    buffer.to_string(),
    trim_ws_start(
      (
        #|
        #|================================================================================
        #|title 1
        #|================================================================================
        #|input 1
        #|--------------------------------------------------------------------------------
        #|
        #|output 1
        #|
        #|================================================================================
        #|title 2
        #|================================================================================
        #|input 2
        #|--------------------------------------------------------------------------------
        #|
        #|output 2
        #|
      ),
    ).to_owned(),
  )
}

///|
test "test_parse_test_content_with_comments_in_sexp" {
  let entry = parse_test_content(
    "the-filename",
    trimmed(
      (
        #|
        #|==================
        #|sexp with comment
        #|==================
        #|code
        #|---
        #|
        #|; Line start comment
        #|(a (b))
        #|
        #|==================
        #|sexp with comment between
        #|==================
        #|code
        #|---
        #|
        #|; Line start comment
        #|(a
        #|; ignore this
        #|    (b)
        #|    ; also ignore this
        #|)
        #|
        #|=========================
        #|sexp with ';'
        #|=========================
        #|code
        #|---
        #|
        #|(MISSING ";")
        #|
      ),
    ),
    None,
  )
  assert_eq(
    entry,
    Group(
      name="the-filename",
      children=[
        example("sexp with comment", "code", "(a (b))", 18, 3),
        example("sexp with comment between", "code", "(a (b))", 18, 3),
        example("sexp with ';'", "code", "(MISSING \";\")", 25, 3),
      ],
      file_path=None,
    ),
  )
}

///|
test "test_parse_test_content_with_suffixes" {
  let entry = parse_test_content(
    "the-filename",
    trimmed(
      (
        #|
        #|==================asdf\()[]|{}*+?^$.-
        #|First test
        #|==================asdf\()[]|{}*+?^$.-
        #|
        #|=========================
        #|NOT A TEST HEADER
        #|=========================
        #|-------------------------
        #|
        #|---asdf\()[]|{}*+?^$.-
        #|
        #|(a)
        #|
        #|==================asdf\()[]|{}*+?^$.-
        #|Second test
        #|==================asdf\()[]|{}*+?^$.-
        #|
        #|=========================
        #|NOT A TEST HEADER
        #|=========================
        #|-------------------------
        #|
        #|---asdf\()[]|{}*+?^$.-
        #|
        #|(a)
        #|
        #|=========================asdf\()[]|{}*+?^$.-
        #|Test name with = symbol
        #|=========================asdf\()[]|{}*+?^$.-
        #|
        #|=========================
        #|NOT A TEST HEADER
        #|=========================
        #|-------------------------
        #|
        #|---asdf\()[]|{}*+?^$.-
        #|
        #|(a)
        #|
        #|==============================asdf\()[]|{}*+?^$.-
        #|Test containing equals
        #|==============================asdf\()[]|{}*+?^$.-
        #|
        #|===
        #|
        #|------------------------------asdf\()[]|{}*+?^$.-
        #|
        #|(a)
        #|
        #|==============================asdf\()[]|{}*+?^$.-
        #|Subsequent test containing equals
        #|==============================asdf\()[]|{}*+?^$.-
        #|
        #|===
        #|
        #|------------------------------asdf\()[]|{}*+?^$.-
        #|
        #|(a)
        #|
      ),
    ),
    None,
  )
  let expected_input = "\n=========================\nNOT A TEST HEADER\n=========================\n-------------------------\n"
  assert_eq(
    entry,
    Group(
      name="the-filename",
      children=[
        example("First test", expected_input, "(a)", 18, 3),
        example("Second test", expected_input, "(a)", 18, 3),
        example("Test name with = symbol", expected_input, "(a)", 25, 3),
        example("Test containing equals", "\n===\n", "(a)", 30, 30),
        example("Subsequent test containing equals", "\n===\n", "(a)", 30, 30),
      ],
      file_path=None,
    ),
  )
}

///|
test "test_parse_test_content_with_newlines_in_test_names" {
  let entry = parse_test_content(
    "the-filename",
    (
      #|
      #|===============
      #|name
      #|with
      #|newlines
      #|===============
      #|a
      #|---
      #|(b)
      #|
      #|====================
      #|name with === signs
      #|====================
      #|code with ----
      #|---
      #|(d)
      #|
    ),
    None,
  )
  assert_eq(
    entry,
    Group(name="the-filename", file_path=None, children=[
      example("name\nwith\nnewlines", "a", "(b)", 15, 3),
      example("name with === signs", "code with ----", "(d)", 20, 3),
    ]),
  )
}

///|
test "test_parse_test_with_markers" {
  // do one with :skip, we should not see it in the entry output
  let entry = parse_test_content(
    "the-filename",
    (
      #|
      #|=====================
      #|Test with skip marker
      #|:skip
      #|=====================
      #|a
      #|---
      #|(b)
      #|
    ),
    None,
  )
  assert_eq(
    entry,
    Group(name="the-filename", file_path=None, children=[
      example(
        "Test with skip marker",
        "a",
        "(b)",
        21,
        3,
        attributes_str=":skip",
        attributes={
          platform: true,
          fail_fast: false,
          expectation: Skip,
          cst: false,
          languages: [""],
        },
      ),
    ]),
  )
  let other_os = if current_os == "linux" { "macos" } else { "linux" }
  let entry = parse_test_content(
    "the-filename",
    (
      $|
      $|=========================
      $|Test with platform marker
      $|:platform(\{current_os})
      $|:fail-fast
      $|=========================
      $|a
      $|---
      $|(b)
      $|
      $|=============================
      $|Test with bad platform marker
      $|:platform(\{other_os})
      $|
      $|:language(foo)
      $|=============================
      $|a
      $|---
      $|(b)
      $|
      $|====================
      $|Test with cst marker
      $|:cst
      $|====================
      $|1
      $|---
      $|0:0 - 1:0   source_file
      $|0:0 - 0:1   expression
      $|0:0 - 0:1     number_literal `1`
      $|
    ),
    None,
  )
  assert_eq(
    entry,
    Group(name="the-filename", file_path=None, children=[
      example(
        "Test with platform marker",
        "a",
        "(b)",
        25,
        3,
        attributes_str=":platform(\{current_os})\n:fail-fast",
        attributes={
          platform: true,
          fail_fast: true,
          expectation: Pass,
          cst: false,
          languages: [""],
        },
      ),
      example(
        "Test with bad platform marker",
        "a",
        "(b)",
        29,
        3,
        attributes_str=":platform(\{other_os})\n\n:language(foo)",
        attributes={
          platform: false,
          fail_fast: false,
          expectation: Pass,
          cst: false,
          languages: ["foo"],
        },
      ),
      example(
        "Test with cst marker",
        "1",
        (
          #|0:0 - 1:0   source_file
          #|0:0 - 0:1   expression
          #|0:0 - 0:1     number_literal `1`
        ),
        20,
        3,
        attributes_str=":cst",
        attributes={
          platform: true,
          fail_fast: false,
          expectation: Pass,
          cst: true,
          languages: [""],
        },
      ),
    ]),
  )
}

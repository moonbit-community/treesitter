// Port of tree-sitter crates/cli/src/tests/corpus_test.rs: parse the corpus
// of each fixture grammar, then fuzz each example with random edits (see
// cli_test). Deviations:
// - A language whose external scanner is not ported yet is skipped with a
//   notice.
// - The example names are printed only when `TREE_SITTER_CORPUS_VERBOSE` is
//   set (moon shows the output of passing tests too); failures are always
//   printed.
// - `TREE_SITTER_DUMP_EDITS` is not supported, and with
//   `TREE_SITTER_LOG_GRAPHS` the inputs go to standard output and the graphs
//   to standard error (there is no `log.html`).

///|
/// `#[test_with_seed(retry=n, seed=seed, seed_fn=new_seed)]`: run `f` with
/// `seed`, retrying at most `retry` times with a new seed.
async fn test_with_seed(
  retry : Int32,
  seed : UInt64,
  f : async (UInt64) -> Unit,
) -> Unit {
  let mut seed = seed
  for i in 0..<=retry {
    try f(seed) catch {
      e => {
        if i == retry {
          raise e
        }
        seed = @cli_test.new_seed()
        if i < retry {
          println("\nRetry \{i + 1}/\{retry} with a new seed \{seed}")
        }
      }
    } noraise {
      _ => return
    }
  }
}

///|
fn corpus_verbose() -> Bool {
  @env.get_env_var("TREE_SITTER_CORPUS_VERBOSE") is Some(_)
}

///|
async test "corpus_for_bash_language" {
  test_with_seed(10, @cli_test.start_seed(), seed => {
    test_language_corpus(
      "bash",
      seed,
      Some([
        // Fragile tests where edit customization changes
        // lead to significant parse tree structure changes.
        "bash - corpus - commands - Nested Heredocs", "bash - corpus - commands - Quoted Heredocs",
        "bash - corpus - commands - Heredocs with weird characters",
      ]),
      None,
    )
  })
}

///|
async test "corpus_for_c_language" {
  test_with_seed(10, @cli_test.start_seed(), seed => {
    test_language_corpus("c", seed, None, None)
  })
}

///|
async test "corpus_for_cpp_language" {
  test_with_seed(10, @cli_test.start_seed(), seed => {
    test_language_corpus("cpp", seed, None, None)
  })
}

///|
async test "corpus_for_embedded_template_language" {
  test_with_seed(10, @cli_test.start_seed(), seed => {
    test_language_corpus("embedded-template", seed, None, None)
  })
}

///|
async test "corpus_for_go_language" {
  test_with_seed(10, @cli_test.start_seed(), seed => {
    test_language_corpus("go", seed, None, None)
  })
}

///|
async test "corpus_for_html_language" {
  test_with_seed(10, @cli_test.start_seed(), seed => {
    test_language_corpus("html", seed, None, None)
  })
}

///|
async test "corpus_for_java_language" {
  test_with_seed(10, @cli_test.start_seed(), seed => {
    test_language_corpus(
      "java",
      seed,
      Some([
        "java - corpus - expressions - switch with unnamed pattern variable",
      ]),
      None,
    )
  })
}

///|
async test "corpus_for_javascript_language" {
  test_with_seed(10, @cli_test.start_seed(), seed => {
    test_language_corpus("javascript", seed, None, None)
  })
}

///|
async test "corpus_for_json_language" {
  test_with_seed(10, @cli_test.start_seed(), seed => {
    test_language_corpus("json", seed, None, None)
  })
}

///|
async test "corpus_for_php_language" {
  test_with_seed(10, @cli_test.start_seed(), seed => {
    test_language_corpus("php", seed, None, Some("php"))
  })
}

///|
async test "corpus_for_python_language" {
  test_with_seed(10, @cli_test.start_seed(), seed => {
    test_language_corpus("python", seed, None, None)
  })
}

///|
async test "corpus_for_ruby_language" {
  test_with_seed(10, @cli_test.start_seed(), seed => {
    test_language_corpus("ruby", seed, None, None)
  })
}

///|
async test "corpus_for_rust_language" {
  test_with_seed(10, @cli_test.start_seed(), seed => {
    test_language_corpus("rust", seed, None, None)
  })
}

///|
async test "corpus_for_typescript_language" {
  test_with_seed(10, @cli_test.start_seed(), seed => {
    test_language_corpus("typescript", seed, None, Some("typescript"))
  })
}

///|
async test "corpus_for_tsx_language" {
  test_with_seed(10, @cli_test.start_seed(), seed => {
    test_language_corpus("typescript", seed, None, Some("tsx"))
  })
}

///|
/// The corpus tests of the file or directory at `path`, or an empty group
/// when it cannot be read (`parse_tests(path).unwrap_or_default()`).
async fn parse_tests_or_default(path : String) -> @cli_test.TestEntry {
  @cli_test.parse_tests(path) catch {
    _ => @cli_test.TestEntry::default()
  }
}

///|
async fn test_language_corpus(
  language_name : String,
  start_seed : UInt64,
  skipped : Array[String]?,
  language_dir : String?,
) -> Unit {
  if @cli_test.language_filter() is Some(filter) && language_name != filter {
    return
  }
  let language_dir = language_dir.unwrap_or("")
  guard fixtures_dir() is Some(fixtures_dir) else { return }
  let language_path = if language_dir.is_empty() {
    language_name
  } else {
    "\{language_name}/\{language_dir}"
  }
  // (Checked first: the language may be unavailable here.)
  guard get_parsing_language(language_path.replace_all(old="/", new="_"))
    is Some(language) else {
    return
  }
  let grammars_dir = "\{fixtures_dir}/grammars"
  let error_corpus_dir = "\{fixtures_dir}/error_corpus"
  let template_corpus_dir = "\{fixtures_dir}/template_corpus"
  let corpus_dir = "\{grammars_dir}/\{language_name}/test/corpus"
  println("Testing \{language_name} corpus @ \{corpus_dir}")
  let error_corpus_file = "\{error_corpus_dir}/\{language_name}_errors.txt"
  let template_corpus_file = "\{template_corpus_dir}/\{language_name}_templates.txt"
  let main_tests = @cli_test.parse_tests(corpus_dir)
  let error_tests = parse_tests_or_default(error_corpus_file)
  let template_tests = parse_tests_or_default(template_corpus_file)
  let include = @cli_test.example_include()
  let exclude = @cli_test.example_exclude()
  let tests = @cli_test.flatten_tests(main_tests, include, exclude)
  tests.append(@cli_test.flatten_tests(error_tests, include, exclude))
  for t in @cli_test.flatten_tests(template_tests, include, exclude) {
    t.template_delimiters = Some(("<%", "%>"))
    tests.push(t)
  }
  tests.retain(t => {
    t.languages[0].is_empty() || t.languages.contains(language_dir)
  })
  let skipped : Map[String, Int32]? = match skipped {
    Some(names) => Some(Map::from_array(names.map(x => (x, 0))))
    None => None
  }
  let mut failure_count = 0
  let log_seed = @env.get_env_var("TREE_SITTER_LOG_SEED") is Some(_)
  if log_seed {
    println("  start seed: \{start_seed}")
  }
  for test_index, test_case in tests {
    let test_name = "\{language_name} - \{test_case.name}"
    if skipped is Some(skipped) && skipped.get(test_name) is Some(counter) {
      if corpus_verbose() {
        println("  \{test_index}. \{test_name} - SKIPPED")
      }
      skipped[test_name] = counter + 1
      continue
    }
    if corpus_verbose() {
      println("  \{test_index}. \{test_name}")
    }
    let passed = test_case.check_initial_parse(language, test_name, true)
    if !passed {
      failure_count += 1
      continue
    }
    let parser = @treesitter.Parser::new()
    parser.set_language(language)
    let tree = parser.parse(test_case.input).unwrap()
    for trial in 0UL..<@cli_test.iteration_count() {
      let seed = start_seed + trial
      let passed = corpus_trial(
        language, tree, test_case, test_name, test_index, trial, seed, start_seed,
        log_seed,
      )
      if !passed {
        failure_count += 1
        break
      }
    }
  }
  assert_true(
    failure_count == 0,
    msg="\{failure_count} \{language_name} corpus tests failed",
  )
  if skipped is Some(skipped) {
    let unmatched = []
    for k, v in skipped {
      if v == 0 {
        unmatched.push(k)
      }
    }
    if !unmatched.is_empty() {
      println("Non matchable skip definitions:")
      for k in unmatched {
        println("  \{k}")
      }
      fail("Non matchable skip definitions needs to be removed")
    }
  }
}

///|
/// The body of one trial of `test_language_corpus` (a closure upstream).
async fn corpus_trial(
  language : @treesitter.Language,
  tree : @treesitter.Tree,
  test_case : @cli_test.FlattenedTest,
  test_name : String,
  test_index : Int32,
  trial : UInt64,
  seed : UInt64,
  start_seed : UInt64,
  log_seed : Bool,
) -> Bool {
  let rand = @cli_test.Rand::new(seed)
  let log_session = Ref(None)
  defer @cli_test.end_log_session(log_session.val)
  let parser = @cli_test.get_parser(log_session, "log.html")
  parser.set_language(language)
  let tree = tree.clone()
  let input = test_case.input.to_array()
  if @cli_test.log_graph_enabled() {
    println("\{@utf8.decode_lossy(Bytes::from_array(input))}\n")
  }

  // Perform a random series of edits and reparse.
  let edit_count = rand.unsigned(@cli_test.edit_count())
  let undo_stack = []
  for _ in 0UL..<=edit_count {
    let edit = @cli_test.get_random_edit(rand, input)
    undo_stack.push(@cli_test.invert_edit(input, edit))
    ignore(@cli_test.perform_edit(tree, input, edit))
  }
  if log_seed {
    println(
      "   \{test_index}.\{@cli_test.pad_right(trial.to_string(), 2)} seed: \{seed}",
    )
  }
  if @cli_test.log_graph_enabled() {
    println("\{@utf8.decode_lossy(Bytes::from_array(input))}\n")
  }
  @cli_test.set_included_ranges(
    parser,
    Bytes::from_array(input),
    test_case.template_delimiters,
  )
  let tree2 = parser.parse(Bytes::from_array(input), old_tree=tree).unwrap()

  // Check that the new tree is consistent.
  @cli_test.check_consistent_sizes(tree2, Bytes::from_array(input))
  if @cli_test.check_changed_ranges(tree, tree2, Bytes::from_array(input))
    is Err(message) {
    println(
      "\nUnexpected scope change in seed \{seed} with start seed \{start_seed}\n\{message}\n\n",
    )
    return false
  }

  // Undo all of the edits and re-parse again.
  while undo_stack.pop() is Some(edit) {
    ignore(@cli_test.perform_edit(tree2, input, edit))
  }
  if @cli_test.log_graph_enabled() {
    println("\{@utf8.decode_lossy(Bytes::from_array(input))}\n")
  }
  @cli_test.set_included_ranges(
    parser,
    test_case.input,
    test_case.template_delimiters,
  )
  let tree3 = parser.parse(Bytes::from_array(input), old_tree=tree2).unwrap()

  // Verify that the final tree matches the expectation from the corpus.
  let actual_output = @cli_test.render_test_output(
    Bytes::from_array(input),
    tree3,
    test_case.cst,
    test_case.has_fields,
  )
  if actual_output != test_case.output {
    println("Incorrect parse for \{test_name} - seed \{seed}")
    @cli_test.DiffKey::print()
    println(
      @cli_test.TestDiff::new(actual_output, test_case.output).to_string(),
    )
    println("")
    return false
  }

  // Check that the edited tree is consistent.
  @cli_test.check_consistent_sizes(tree3, Bytes::from_array(input))
  if @cli_test.check_changed_ranges(tree2, tree3, Bytes::from_array(input))
    is Err(message) {
    println(
      "Unexpected scope change in seed \{seed} with start seed \{start_seed}\n\{message}\n\n",
    )
    return false
  }
  true
}

///|
async test "feature_corpus_files" {
  // The test grammars, with their `grammar.json` (`load_grammar_file`), as
  // copied by tools/oracle/ref_generate.sh.
  guard ref_dir() is Some(test_grammars_dir) else {
    println(
      "note: skipping feature_corpus_files (run tools/oracle/ref_generate.sh)",
    )
    return
  }
  let mut failure_count = 0
  for language_name in @fs.readdir(test_grammars_dir, sort=true) {
    // (`_build/ref` also holds the fixture grammars.)
    if language_name.has_prefix("fixture_") {
      continue
    }
    let test_path = "\{test_grammars_dir}/\{language_name}"
    if @fs.kind(test_path, follow_symlink=true) != Directory {
      continue
    }
    if @cli_test.language_filter() is Some(filter) && language_name != filter {
      continue
    }
    let grammar_path = "\{test_path}/src/grammar.json"
    let error_message_path = "\{test_path}/expected_error.txt"
    let grammar_json = @fs.read_file(grammar_path).text()
    let generate_result : Result[(String, @generate.GeneratedParser), Error] = Ok(
      generate_parser(grammar_json),
    ) catch {
      e => Err(e)
    }
    if @fs.exists(error_message_path) {
      if @cli_test.example_include() is Some(_) ||
        @cli_test.example_exclude() is Some(_) {
        continue
      }
      println("test language: \{rust_debug_str(language_name)}")
      let expected_message = @fs.read_file(error_message_path)
        .text()
        .replace_all(old="\r\n", new="\n")
      match generate_result {
        Err(e) => {
          let actual_message = e.to_string().replace_all(old="\r\n", new="\n")
          if expected_message != actual_message {
            println(
              "Unexpected error message.\n\nExpected:\n\n`\{expected_message}`\nActual:\n\n`\{actual_message}`\n",
            )
            failure_count += 1
          }
        }
        Ok(_) => {
          println(
            "Expected error message but got none for test grammar '\{language_name}'",
          )
          failure_count += 1
        }
      }
    } else {
      let parser_code = match generate_result {
        Err(e) => {
          println("Unexpected error for test grammar '\{language_name}':\n\{e}")
          failure_count += 1
          continue
        }
        Ok((_, parser_code)) => parser_code
      }
      let corpus_path = "\{test_path}/corpus.txt"
      // `get_test_language(language_name, &c_code, Some(&test_path))`: with
      // the grammar's external scanner, if any.
      guard scanner_available(language_name, parser_code.language) else {
        continue
      }
      let language = get_test_language(
        language_name,
        parser_code,
        Some(test_path),
      )
      let test_entry = @cli_test.parse_tests(corpus_path)
      let tests = @cli_test.flatten_tests(
        test_entry,
        @cli_test.example_include(),
        @cli_test.example_exclude(),
      )
      if !tests.is_empty() {
        println("test language: \{rust_debug_str(language_name)}")
      }
      for test_case in tests {
        println("  example: \{rust_debug_str(test_case.name)}")
        let passed = test_case.check_initial_parse(
          language,
          test_case.name,
          true,
        )
        if !passed {
          failure_count += 1
        }
      }
    }
  }
  assert_true(failure_count == 0, msg="\{failure_count} corpus tests failed")
}

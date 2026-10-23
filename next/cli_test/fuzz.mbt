// Port of tree-sitter crates/cli/src/fuzz.rs. The allocation tracking of
// `fuzz/allocations.rs` has no MoonBit equivalent (memory is garbage
// collected) and is omitted: `allocations::record(f)` is just `f()`.

///|
pub fn log_enabled() -> Bool {
  @env.get_env_var("TREE_SITTER_LOG") is Some(_)
}

///|
pub fn log_graph_enabled() -> Bool {
  @env.get_env_var("TREE_SITTER_LOG_GRAPHS") is Some(_)
}

///|
pub fn language_filter() -> String? {
  @env.get_env_var("TREE_SITTER_LANGUAGE")
}

///|
pub fn example_include() -> @regex.Regex? {
  regex_env_var("TREE_SITTER_EXAMPLE_INCLUDE")
}

///|
pub fn example_exclude() -> @regex.Regex? {
  regex_env_var("TREE_SITTER_EXAMPLE_EXCLUDE")
}

///|
let start_seed_cache : Ref[Int32?] = Ref(None)

///|
/// The seed of this run (`START_SEED`), chosen once.
pub fn start_seed() -> Int32 {
  match start_seed_cache.val {
    Some(seed) => seed
    None => {
      let seed = new_seed()
      start_seed_cache.val = Some(seed)
      seed
    }
  }
}

///|
pub let default_edit_count : Int32 = 3

///|
pub fn edit_count() -> Int32 {
  int_env_var("TREE_SITTER_EDITS").unwrap_or(default_edit_count)
}

///|
pub let default_iteration_count : Int32 = 10

///|
pub fn iteration_count() -> Int32 {
  int_env_var("TREE_SITTER_ITERATIONS").unwrap_or(default_iteration_count)
}

///|
fn int_env_var(name : String) -> Int32? {
  guard @env.get_env_var(name) is Some(value) else { return None }
  try @string.parse_int(value) catch {
    _ => None
  } noraise {
    n if n >= 0 => Some(n)
    _ => None
  }
}

///|
fn regex_env_var(name : String) -> @regex.Regex? {
  guard @env.get_env_var(name) is Some(value) else { return None }
  try @regex.Regex::new(value) catch {
    _ => None
  } noraise {
    regex => Some(regex)
  }
}

///|
/// The seed from `TREE_SITTER_SEED`, or a random one (printed).
pub fn new_seed() -> Int32 {
  match int_env_var("TREE_SITTER_SEED") {
    Some(seed) => seed
    None => {
      let seed = match @env.rand(4) {
        Some(bytes) =>
          bytes[0].to_int() |
          (bytes[1].to_int() << 8) |
          (bytes[2].to_int() << 16) |
          ((bytes[3].to_int() & 0x3f) << 24)
        None => (@env.now() % 1000000000UL).to_int()
      }
      println("fuzz seed: \{seed}")
      seed
    }
  }
}

///|
pub(all) struct FuzzOptions {
  mut skipped : Array[String]?
  mut subdir : String?
  edits : Int32
  iterations : Int32
  include : @regex.Regex?
  exclude : @regex.Regex?
  log_graphs : Bool
  log : Bool
}

///|
/// Fuzz the corpus of the grammar at `grammar_dir` with random edits.
pub async fn fuzz_language_corpus(
  language : @api.Language,
  language_name : String,
  start_seed : Int32,
  grammar_dir : String,
  options : FuzzOptions,
) -> Unit {
  fn retain(entry : TestEntry, language_name : String) -> Bool {
    match entry {
      Example(attributes~, ..) =>
        attributes.languages[0].is_empty() ||
        attributes.languages.iter().any(lang => lang == language_name)
      Group(children~, ..) => {
        children.retain(child => retain(child, language_name))
        !children.is_empty()
      }
    }
  }

  let subdir = options.subdir.unwrap_or("")
  options.subdir = None
  let corpus_dir = if subdir.is_empty() {
    "\{grammar_dir}/test/corpus"
  } else {
    "\{grammar_dir}/\{subdir}/test/corpus"
  }
  if !is_dir(corpus_dir) {
    println(
      "No corpus directory found, ensure that you have a `test/corpus` directory in your grammar directory with at least one test file.",
    )
    return
  }
  if @fs.readdir(corpus_dir).is_empty() {
    println(
      "No corpus files found in `test/corpus`, ensure that you have at least one test file in your corpus directory.",
    )
    return
  }
  let main_tests = parse_tests(corpus_dir)
  match main_tests {
    Group(children~, ..) =>
      children.retain(child => retain(child, language_name))
    Example(..) => abort("unreachable")
  }
  let tests = flatten_tests(main_tests, options.include, options.exclude)
  let get_test_name = (flat : FlattenedTest) => {
    "\{language_name} - \{flat.name}"
  }
  let skipped : Map[String, Int32] = Map([])
  for name in options.skipped.unwrap_or([]) {
    skipped[name] = 0
  }
  options.skipped = None
  for flat in tests {
    if flat.skip() {
      skipped[get_test_name(flat)] = 0
    }
  }
  let mut failure_count = 0
  let log_seed = @env.get_env_var("TREE_SITTER_LOG_SEED") is Some(_)
  if log_seed {
    println("  start seed: \{start_seed}")
  }
  println("")
  for test_index, flat in tests {
    let test_name = get_test_name(flat)
    if skipped.get(test_name) is Some(counter) {
      println("  \{test_index}. \{test_name} - SKIPPED")
      skipped[test_name] = counter + 1
      continue
    }
    println("  \{test_index}. \{test_name}")
    let check_output = !flat.error()
    let passed = flat.check_initial_parse(language, test_name, check_output) catch {
      e => {
        println(e.to_string())
        false
      }
    }
    if !passed {
      failure_count += 1
      continue
    }
    let parser = @api.Parser::new()
    parser.set_language(language)
    let tree = parser.parse(flat.input).unwrap()
    for trial in 0..<options.iterations {
      let seed = start_seed + trial
      let passed = fuzz_trial(
        language,
        tree,
        flat,
        test_name,
        test_index,
        trial,
        seed,
        start_seed,
        options.edits,
        options.log_graphs,
        log_seed,
        check_output=!flat.error(),
      ) catch {
        e => {
          println(e.to_string())
          false
        }
      }
      if !passed {
        failure_count += 1
        break
      }
    }
  }
  if failure_count != 0 {
    println("\{failure_count} \{language_name} corpus tests failed fuzzing")
  }
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
    abort("Non matchable skip definitions need to be removed")
  }
}

///|
/// One trial of the corpus fuzzing loop: apply random edits to the input and
/// tree, reparse, check the tree, undo the edits, reparse and check that the
/// result matches the expected output. `false` (after printing the problem)
/// when a check fails.
pub fn fuzz_trial(
  language : @api.Language,
  tree : @api.Tree,
  flat : FlattenedTest,
  test_name : String,
  test_index : Int32,
  trial : Int32,
  seed : Int32,
  start_seed : Int32,
  edit_count : Int32,
  log_graphs : Bool,
  log_seed : Bool,
  check_output~ : Bool,
) -> Bool raise {
  let rand = Rand::new(seed)
  let parser = get_parser()
  parser.set_language(language)
  let tree = tree.clone()
  let input = flat.input.to_array()
  if log_graphs {
    println("\{@utf8.decode_lossy(Bytes::from_array(input))}\n")
  }

  // Perform a random series of edits and reparse.
  let edit_count = rand.unsigned(edit_count)
  let undo_stack = Array(capacity=edit_count)
  for _ in 0..<=edit_count {
    let edit = get_random_edit(rand, input)
    undo_stack.push(invert_edit(input, edit))
    ignore(perform_edit(tree, input, edit))
  }
  if log_seed {
    println("   \{test_index}.\{pad_right(trial.to_string(), 2)} seed: \{seed}")
  }
  if log_graphs {
    println("\{@utf8.decode_lossy(Bytes::from_array(input))}\n")
  }
  set_included_ranges(
    parser,
    Bytes::from_array(input),
    flat.template_delimiters,
  )
  let tree2 = parser.parse(Bytes::from_array(input), old_tree=tree).unwrap()

  // Check that the new tree is consistent.
  check_consistent_sizes(tree2, Bytes::from_array(input))
  if check_changed_ranges(tree, tree2, Bytes::from_array(input)) is Err(message) {
    println(
      "\nUnexpected scope change in seed \{seed} with start seed \{start_seed}\n\{message}\n\n",
    )
    return false
  }

  // Undo all of the edits and re-parse again.
  while undo_stack.pop() is Some(edit) {
    ignore(perform_edit(tree2, input, edit))
  }
  if log_graphs {
    println("\{@utf8.decode_lossy(Bytes::from_array(input))}\n")
  }
  set_included_ranges(parser, flat.input, flat.template_delimiters)
  let tree3 = parser.parse(Bytes::from_array(input), old_tree=tree2).unwrap()

  // Verify that the final tree matches the expectation from the corpus.
  let actual_output = render_test_output(
    Bytes::from_array(input),
    tree3,
    flat.cst,
    flat.has_fields,
  )
  if actual_output != flat.output && check_output {
    println("Incorrect parse for \{test_name} - seed \{seed}")
    DiffKey::print()
    println(TestDiff::new(actual_output, flat.output).to_string())
    println("")
    return false
  }

  // Check that the edited tree is consistent.
  check_consistent_sizes(tree3, Bytes::from_array(input))
  if check_changed_ranges(tree2, tree3, Bytes::from_array(input))
    is Err(message) {
    println(
      "Unexpected scope change in seed \{seed} with start seed \{start_seed}\n\{message}\n\n",
    )
    return false
  }
  true
}

///|
/// `format!("{s:<width$}")`.
fn pad_right(s : String, width : Int32) -> String {
  if s.length() >= width {
    s
  } else {
    s + " ".repeat(width - s.length())
  }
}

///|
pub(all) struct FlattenedTest {
  name : String
  input : Bytes
  output : String
  languages : Array[String]
  expectation : TestExpectation
  has_fields : Bool
  cst : Bool
  mut template_delimiters : (String, String)?
}

///|
fn FlattenedTest::skip(self : FlattenedTest) -> Bool {
  self.expectation == Skip
}

///|
fn FlattenedTest::error(self : FlattenedTest) -> Bool {
  self.expectation == Error
}

///|
/// Parse the test's input from scratch and, when `check_output` is set,
/// compare the tree with the expected output (printing a diff when they
/// differ).
pub fn FlattenedTest::check_initial_parse(
  self : FlattenedTest,
  language : @api.Language,
  display_name : String,
  check_output : Bool,
) -> Bool raise {
  let parser = get_parser()
  parser.set_language(language)
  set_included_ranges(parser, self.input, self.template_delimiters)
  let tree = parser.parse(self.input).unwrap()
  if !check_output {
    return true
  }
  let actual_output = render_test_output(
    self.input,
    tree,
    self.cst,
    self.has_fields,
  )
  if actual_output == self.output {
    true
  } else {
    println("Incorrect initial parse for \{display_name}")
    DiffKey::print()
    println(TestDiff::new(actual_output, self.output).to_string())
    println("")
    false
  }
}

///|
/// Flatten a tree of test entries into a list, prefixing each name with the
/// names of the groups containing it (the root's excepted).
pub fn flatten_tests(
  entry : TestEntry,
  include : @regex.Regex?,
  exclude : @regex.Regex?,
) -> Array[FlattenedTest] {
  fn helper(
    entry : TestEntry,
    include : @regex.Regex?,
    exclude : @regex.Regex?,
    is_root : Bool,
    prefix : String,
    result : Array[FlattenedTest],
  ) -> Unit {
    match entry {
      Example(name~, input~, output~, has_fields~, attributes~, ..) => {
        let name = if !prefix.is_empty() { "\{prefix} - \{name}" } else { name }
        if include is Some(include) {
          if !include.is_match(@utf8.encode(name)) {
            return
          }
        } else if exclude is Some(exclude) &&
          exclude.is_match(@utf8.encode(name)) {
          return
        }
        result.push({
          name,
          input,
          output,
          languages: attributes.languages,
          expectation: attributes.expectation,
          has_fields,
          cst: attributes.cst,
          template_delimiters: None,
        })
      }
      Group(name~, children~, ..) => {
        let name = if !is_root && !prefix.is_empty() {
          "\{prefix} - \{name}"
        } else {
          name
        }
        for child in children {
          helper(child, include, exclude, false, name, result)
        }
      }
    }
  }

  let result = []
  helper(entry, include, exclude, true, "", result)
  result
}

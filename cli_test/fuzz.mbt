// Port of tree-sitter crates/cli/src/fuzz.rs. The allocation tracking of
// `fuzz/allocations.rs` has no MoonBit equivalent (memory is garbage
// collected) and is omitted: `allocations::record_checked(f)` is `f()`, and
// the errors it would report are the errors `f` raises. `usize` is
// `UInt64` (the 64-bit targets).

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
let start_seed_cache : Ref[UInt64?] = Ref(None)

///|
/// The seed of this run (`START_SEED`), chosen once.
pub fn start_seed() -> UInt64 {
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
pub let default_edit_count : UInt64 = 3

///|
pub fn edit_count() -> UInt64 {
  int_env_var("TREE_SITTER_EDITS").unwrap_or(default_edit_count)
}

///|
pub let default_iteration_count : UInt64 = 10

///|
pub fn iteration_count() -> UInt64 {
  int_env_var("TREE_SITTER_ITERATIONS").unwrap_or(default_iteration_count)
}

///|
fn int_env_var(name : String) -> UInt64? {
  guard @env.get_env_var(name) is Some(value) else { return None }
  parse_usize(value)
}

///|
/// `str::parse::<usize>()` on a 64-bit target: an optional `+` followed by
/// ASCII digits, without overflow.
pub fn parse_usize(s : String) -> UInt64? {
  let digits = if s.has_prefix("+") { s[1:] } else { s[:] }
  if digits.is_empty() {
    return None
  }
  let mut n = 0UL
  for c in digits {
    guard c >= '0' && c <= '9' else { return None }
    let digit = (c.to_int() - '0'.to_int()).to_uint64()
    // overflow of `n * 10 + digit`
    if n > (0xFFFF_FFFF_FFFF_FFFFUL - digit) / 10 {
      return None
    }
    n = n * 10 + digit
  }
  Some(n)
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
/// The seed from `TREE_SITTER_SEED`, or a random one (printed to standard
/// error): `rand::rng().random_range(0..=usize::MAX)`.
pub fn new_seed() -> UInt64 {
  match int_env_var("TREE_SITTER_SEED") {
    Some(seed) => seed
    None => {
      let seed = match @env.rand(8) {
        Some(bytes) => {
          let mut seed = 0UL
          for byte in bytes {
            seed = (seed << 8) | byte.to_uint64()
          }
          seed
        }
        None => @env.now()
      }
      @support.print_err("fuzz seed: \{seed}\n")
      seed
    }
  }
}

///|
pub(all) struct FuzzOptions {
  mut skipped : Array[String]?
  mut subdir : String?
  edits : UInt64
  iterations : UInt64
  include : @regex.Regex?
  exclude : @regex.Regex?
  log_graphs : Bool
  log : Bool
}

///|
/// Fuzz the corpus of the grammar at `grammar_dir` with random edits.
pub async fn fuzz_language_corpus(
  language : @treesitter.Language,
  language_name : String,
  start_seed : UInt64,
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
  let corpus_dir = @support.path_join(
    @support.path_join(@support.path_join(grammar_dir, subdir), "test"),
    "corpus",
  )
  if !is_dir(corpus_dir) {
    @support.log_error(
      "No corpus directory found, ensure that you have a `test/corpus` directory in your grammar directory with at least one test file.",
    )
    return
  }
  if @fs.readdir(corpus_dir).is_empty() {
    @support.log_error(
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
  // A `HashMap` upstream: the unmatched definitions below are listed in its
  // (random) iteration order, here in insertion order.
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
  let dump_edits = @env.get_env_var("TREE_SITTER_DUMP_EDITS") is Some(_)
  if log_seed {
    @support.log_info("  start seed: \{start_seed}")
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
        @support.log_error(e.to_string())
        false
      }
    }
    if !passed {
      failure_count += 1
      continue
    }
    let parser = @treesitter.Parser::new()
    parser.set_language(language)
    let tree = parser.parse(flat.input).unwrap()
    for trial in 0UL..<options.iterations {
      // (`usize` addition, which wraps in release builds)
      let seed = start_seed + trial
      let passed = fuzz_trial(
        language, tree, flat, test_name, test_index, trial, seed, start_seed, options,
        log_seed, dump_edits,
      ) catch {
        e => {
          @support.log_error(e.to_string())
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
    @support.log_info(
      "\{failure_count} \{language_name} corpus tests failed fuzzing",
    )
  }
  let unmatched = []
  for k, v in skipped {
    if v == 0 {
      unmatched.push(k)
    }
  }
  if !unmatched.is_empty() {
    @support.log_info("Non matchable skip definitions:")
    for k in unmatched {
      @support.log_info("  \{k}")
    }
    @support.flush()
    abort("Non matchable skip definitions need to be removed")
  }
}

///|
/// One trial of the corpus fuzzing loop (a closure upstream): apply random
/// edits to the input and tree, reparse, check the tree, undo the edits,
/// reparse and check that the result matches the expected output. `false`
/// (after reporting the problem) when a check fails.
async fn fuzz_trial(
  language : @treesitter.Language,
  tree : @treesitter.Tree,
  flat : FlattenedTest,
  test_name : String,
  test_index : Int32,
  trial : UInt64,
  seed : UInt64,
  start_seed : UInt64,
  options : FuzzOptions,
  log_seed : Bool,
  dump_edits : Bool,
) -> Bool {
  let rand = Rand::new(seed)
  let log_session = Ref(None)
  // (the session is dropped when the trial ends)
  defer end_log_session(log_session.val)
  let parser = get_parser(log_session, "log.html")
  parser.set_language(language)
  let tree = tree.clone()
  let input = flat.input.to_array()
  if options.log_graphs {
    @support.log_info("\{@support.utf8_lossy(Bytes::from_array(input))}\n")
  }

  // Perform a random series of edits and reparse.
  let edit_count = rand.unsigned(options.edits)
  // (`Vec::with_capacity(edit_count)`; the capacity is only a hint here)
  let undo_stack = Array(
    capacity=if edit_count < 1024 { edit_count.to_int() } else { 1024 },
  )
  for _ in 0UL..<=edit_count {
    let edit = get_random_edit(rand, input)
    undo_stack.push(invert_edit(input, edit))
    ignore(perform_edit(tree, input, edit))
  }
  if log_seed {
    @support.log_info(
      "   \{test_index}.\{pad_right(trial.to_string(), 2)} seed: \{seed}",
    )
  }
  if dump_edits {
    @support.create_dir_all("fuzz") catch {
      e => unwrap_failed(e)
    }
    @fs.write_file(
      @support.path_join(
        "fuzz",
        "edit.\{seed}.\{test_index}.\{trial} \{test_name}",
      ),
      Bytes::from_array(input),
      create_mode=CreateOrTruncate,
    ) catch {
      e => unwrap_failed(e)
    }
  }
  if options.log_graphs {
    @support.log_info("\{@support.utf8_lossy(Bytes::from_array(input))}\n")
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
    @support.log_error(
      "\nUnexpected scope change in seed \{seed} with start seed \{start_seed}\n\{message}\n\n",
    )
    return false
  }

  // Undo all of the edits and re-parse again.
  while undo_stack.pop() is Some(edit) {
    ignore(perform_edit(tree2, input, edit))
  }
  if options.log_graphs {
    @support.log_info("\{@support.utf8_lossy(Bytes::from_array(input))}\n")
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
  if actual_output != flat.output && !flat.error() {
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
    @support.log_error(
      "Unexpected scope change in seed \{seed} with start seed \{start_seed}\n\{message}\n\n",
    )
    return false
  }
  true
}

///|
/// `.unwrap()` of a failed I/O result: a panic.
fn unwrap_failed(e : Error) -> Unit {
  @support.flush()
  abort(
    "called `Result::unwrap()` on an `Err` value: \{@support.io_error_message(e)}",
  )
}

///|
/// `format!("{s:<width$}")`.
pub fn pad_right(s : String, width : Int32) -> String {
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
pub async fn FlattenedTest::check_initial_parse(
  self : FlattenedTest,
  language : @treesitter.Language,
  display_name : String,
  check_output : Bool,
) -> Bool {
  let log_session = Ref(None)
  // (the session is dropped when this function returns)
  defer end_log_session(log_session.val)
  self.check_initial_parse_with(
    log_session, language, display_name, check_output,
  )
}

///|
async fn FlattenedTest::check_initial_parse_with(
  self : FlattenedTest,
  log_session : Ref[LogSession?],
  language : @treesitter.Language,
  display_name : String,
  check_output : Bool,
) -> Bool {
  let parser = get_parser(log_session, "log.html")
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

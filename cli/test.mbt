// Port of the test runner of tree-sitter crates/cli/src/test.rs
// (`TestSummary`, `run_tests_at_path`, `run_tests`, `check_queries_at_path`,
// `TestDiff` with colors, `write_tests`). Corpus parsing and output
// normalization are in cli_test.

///|
pub(all) enum TestStats {
  All
  OutliersAndTotal
  TotalOnly
} derive(Eq)

///|
pub struct TestOptions {
  path : String
  debug : Bool
  debug_graph : Bool
  include : @regex.Regex?
  exclude : @regex.Regex?
  file_name : String?
  update : Bool
  open_log : Bool
  /// A `BTreeMap<&str, &Language>`: unique names in Rust's `str` order (see
  /// `languages_by_name`).
  languages : Array[(String, @treesitter.Language)]
  show_fields : Bool
  overview_only : Bool
}

///|
pub(all) enum TestOutcome {
  Passed
  Failed
  Updated
  Skipped
  Platform
  AssertionPassed(assertion_count~ : Int32)
  AssertionFailed(error~ : String)
}

///|
pub(all) enum TestInfo {
  Group(children~ : Array[TestResult])
  ParseTest(
    outcome~ : TestOutcome,
    parse_rate~ : (Double, Double)?,
    test_num~ : Int32
  )
  AssertionTest(outcome~ : TestOutcome, test_num~ : Int32)
}

///|
pub(all) struct TestResult {
  name : String
  info : TestInfo
}

///|
/// Stores arbitrarily nested parent test groups and child cases. Supports
/// creation in DFS traversal order.
pub struct TestResultHierarchy {
  root_group : Array[TestResult]
  traversal_idxs : Array[Int32]
}

///|
pub fn TestResultHierarchy::new() -> TestResultHierarchy {
  { root_group: [], traversal_idxs: [], }
}

///|
/// Signifies the end of the current group's traversal during construction.
pub fn TestResultHierarchy::pop_traversal(self : TestResultHierarchy) -> Unit {
  ignore(self.traversal_idxs.pop())
}

///|
fn TestResultHierarchy::current_group(
  self : TestResultHierarchy,
) -> Array[TestResult] {
  let mut curr = self.root_group
  for idx in self.traversal_idxs {
    match curr[idx].info {
      Group(children~) => curr = children
      _ => abort("unreachable")
    }
  }
  curr
}

///|
/// Adds a new group as a child of the current group.
pub fn TestResultHierarchy::add_group(
  self : TestResultHierarchy,
  group_name : String,
) -> Unit {
  let group = self.current_group()
  let new_group_idx = group.length()
  group.push({ name: group_name, info: Group(children=[]), })
  self.traversal_idxs.push(new_group_idx)
}

///|
/// Adds a new test example as a child of the current group.
pub fn TestResultHierarchy::add_case(
  self : TestResultHierarchy,
  test_case : TestResult,
) -> Unit {
  self.current_group().push(test_case)
}

///|
/// DFS iteration with depths.
pub fn TestResultHierarchy::iter(
  self : TestResultHierarchy,
) -> Array[(Int32, TestResult)] {
  let result = []
  fn visit(depth : Int32, r : TestResult) {
    result.push((depth, r))
    if r.info is Group(children~) {
      for c in children {
        visit(depth + 1, c)
      }
    }
  }
  for r in self.root_group {
    visit(0, r)
  }
  result
}

///|
pub(all) struct TestFailure {
  name : String
  actual : String
  expected : String
  is_cst : Bool
}

///|
/// A stateful object used to collect results from running a grammar's test
/// suite.
pub struct TestSummary {
  parse_results : TestResultHierarchy
  parse_failures : Array[TestFailure]
  parse_stats : Stats
  mut has_parse_errors : Bool
  parse_stat_display : TestStats
  highlight_results : TestResultHierarchy
  tag_results : TestResultHierarchy
  query_results : TestResultHierarchy
  mut test_num : Int32
  mut use_markers : Bool
  overview_only : Bool
  update : Bool
  json : Bool
}

///|
pub fn TestSummary::new(
  stat_display : TestStats,
  parse_update : Bool,
  overview_only : Bool,
  json_summary : Bool,
) -> TestSummary {
  {
    parse_results: TestResultHierarchy::new(),
    parse_failures: [],
    parse_stats: Stats::default(),
    has_parse_errors: false,
    parse_stat_display: stat_display,
    highlight_results: TestResultHierarchy::new(),
    tag_results: TestResultHierarchy::new(),
    query_results: TestResultHierarchy::new(),
    test_num: 1,
    use_markers: false,
    overview_only,
    update: parse_update,
    json: json_summary,
  }
}

///|
fn outcome_json(outcome : TestOutcome) -> Json {
  match outcome {
    Passed => Json::string("Passed")
    Failed => Json::string("Failed")
    Updated => Json::string("Updated")
    Skipped => Json::string("Skipped")
    Platform => Json::string("Platform")
    AssertionPassed(assertion_count~) =>
      {
        "AssertionPassed": {
          "assertion_count": Json::number(assertion_count.to_double()),
        },
      }
    AssertionFailed(error~) =>
      { "AssertionFailed": { "error": Json::string(error) } }
  }
}

///|
fn TestResult::to_json(self : TestResult) -> Json {
  let obj : Map[String, Json] = Map([])
  obj["name"] = Json::string(self.name)
  match self.info {
    Group(children~) =>
      obj["children"] = Json::array(children.map(c => c.to_json()))
    ParseTest(outcome~, parse_rate~, test_num~) => {
      obj["outcome"] = outcome_json(outcome)
      obj["parse_rate"] = match parse_rate {
        Some((first, _)) => Json::number(first)
        None => Json::null()
      }
      obj["test_num"] = Json::number(test_num.to_double())
    }
    AssertionTest(outcome~, test_num~) => {
      obj["outcome"] = outcome_json(outcome)
      obj["test_num"] = Json::number(test_num.to_double())
    }
  }
  Json::object(obj)
}

///|
pub fn TestSummary::to_json(self : TestSummary) -> Json {
  let results = (h : TestResultHierarchy) => {
    Json::array(h.root_group.map(r => r.to_json()))
  }
  {
    "parse_results": results(self.parse_results),
    "parse_failures": Json::array(
      self.parse_failures.map(f => {
        "name": Json::string(f.name),
        "actual": Json::string(f.actual),
        "expected": Json::string(f.expected),
        "is_cst": Json::boolean(f.is_cst),
      }),
    ),
    "parse_stats": self.parse_stats.to_json(),
    "highlight_results": results(self.highlight_results),
    "tag_results": results(self.tag_results),
    "query_results": results(self.query_results),
  }
}

///|
/// `format!("{:.3}", x)`.
fn format_fixed3(x : Double) -> String {
  format_fixed(x, 3)
}

///|
fn TestSummary::fmt_parse_results(
  self : TestSummary,
  f : StringBuilder,
) -> Unit {
  let mut count = 0
  let mut total_adj_parse_time = 0.0
  for entry in self.parse_results.iter() {
    if entry.1.info is ParseTest(parse_rate=Some((_, adj_rate)), ..) {
      count += 1
      total_adj_parse_time += adj_rate
    }
  }
  let avg = total_adj_parse_time / count.to_double()
  let mut variance = 0.0
  for entry in self.parse_results.iter() {
    if entry.1.info is ParseTest(parse_rate=Some((_, rate_i)), ..) {
      variance += (rate_i - avg) * (rate_i - avg)
    }
  }
  let std_dev = (variance / count.to_double()).sqrt()
  for entry in self.parse_results.iter() {
    let (depth, entry) = entry
    f.write_string("  ".repeat(depth + 1))
    match entry.info {
      Group(_) => f.write_string("\{entry.name}:\n")
      ParseTest(outcome~, parse_rate~, test_num~) => {
        let (color, result_char) = match outcome {
          Passed => (green, "✓")
          Failed => (red, "✗")
          Updated => (blue, "✓")
          Skipped => (yellow, "⌀")
          _ => (magenta, "⌀")
        }
        let stat_display = match (self.parse_stat_display, parse_rate) {
          (TotalOnly, _) | (_, None) => ""
          (display, Some((true_rate, adj_rate))) => {
            let mut stats = if display == All {
              " (\{format_fixed3(true_rate)} bytes/ms)"
            } else {
              ""
            }
            // 3 standard deviations below the mean, aka the "Empirical
            // Rule"
            if adj_rate < -3.0 * std_dev + avg {
              stats = stats +
                paint(
                  Some(yellow),
                  " -- Warning: Slow parse rate (\{format_fixed3(true_rate)} bytes/ms)",
                )
            }
            stats
          }
        }
        f.write_string(
          "\{pad_left(test_num.to_string(), 3)}. \{result_char} \{paint(Some(color), entry.name)}\{stat_display}\n",
        )
      }
      AssertionTest(_) => abort("unreachable")
    }
  }
  // Parse failure info
  let n = self.parse_failures.length()
  if n > 0 && self.update && !self.has_parse_errors {
    f.write_string("\n\{n} update\{if n == 1 { "" } else { "s" }}:\n\n")
    for i, failure in self.parse_failures {
      f.write_string("  \{i + 1}. \{failure.name}\n")
    }
  } else if n > 0 && !self.overview_only {
    if !self.has_parse_errors {
      f.write_string("\n\{n} failure\{if n == 1 { "" } else { "s" }}:\n")
    }
    if color_enabled() {
      f.write_string(diff_key())
    }
    for i, failure in self.parse_failures {
      let { name, actual, expected, is_cst, } = failure
      if expected == "NO ERROR" {
        f.write_string("\n  \{i + 1}. \{name}:\n\n")
        f.write_string("  Expected an ERROR node, but got:\n")
        let actual = if is_cst {
          actual
        } else {
          @treesitter.format_sexp(actual, 2)
        }
        f.write_string("  \{paint(Some(red), actual)}\n")
      } else {
        f.write_string("\n  \{i + 1}. \{name}:\n")
        if is_cst {
          f.write_string(test_diff(actual, expected, self.use_markers) + "\n")
        } else {
          f.write_string(
            test_diff(
              @treesitter.format_sexp(actual, 2),
              @treesitter.format_sexp(expected, 2),
              self.use_markers,
            ) +
            "\n",
          )
        }
      }
    }
  } else {
    f.write_string("\n")
  }
}

///|
/// `Display for TestSummary`.
pub impl Show for TestSummary with fn output(self, logger) {
  let f = StringBuilder()
  self.fmt_parse_results(f)
  let render_assertion_results = (name : String, results : TestResultHierarchy) => {
    f.write_string("\{name}:\n")
    for entry in results.iter() {
      let (depth, entry) = entry
      f.write_string("  ".repeat(depth + 2))
      match entry.info {
        Group(_) => f.write_string("\{entry.name}\n")
        AssertionTest(outcome~, test_num~) =>
          match outcome {
            AssertionPassed(assertion_count~) =>
              f.write_string(
                "\{pad_left(test_num.to_string(), 3)}. ✓ \{paint(Some(green), entry.name)} (\{assertion_count} assertions)\n",
              )
            AssertionFailed(error~) => {
              f.write_string(
                "\{pad_left(test_num.to_string(), 3)}. ✗ \{paint(Some(red), entry.name)}\n",
              )
              f.write_string("\{"  ".repeat(depth + 1)}  \{error}\n")
            }
            _ => abort("unreachable")
          }
        ParseTest(_) => abort("unreachable")
      }
    }
  }
  if !self.highlight_results.root_group.is_empty() {
    render_assertion_results("syntax highlighting", self.highlight_results)
  }
  if !self.tag_results.root_group.is_empty() {
    render_assertion_results("tags", self.tag_results)
  }
  if !self.query_results.root_group.is_empty() {
    render_assertion_results("queries", self.query_results)
  }
  f.write_string(self.parse_stats.to_string())
  logger.write_string(f.to_string())
}

///|
/// `Display for DiffKey`.
fn diff_key() -> String {
  "\ncorrect / \{paint(Some(green), "expected")} / \{paint(Some(red), "unexpected")}"
}

///|
priv enum ChangeTag {
  Equal
  Delete
  Insert
}

///|
/// A line diff from `old` to `new` (`similar::TextDiff::from_lines`): the
/// lines keep their trailing newline. Computed from a longest common
/// subsequence of lines, with deletions before insertions in each changed
/// region.
fn diff_lines(old : String, new : String) -> Array[(ChangeTag, String)] {
  let a = split_inclusive_newline(old)
  let b = split_inclusive_newline(new)
  let n = a.length()
  let m = b.length()
  let lcs = Array::makei(n + 1, _ => Array::make(m + 1, 0))
  for i = n - 1; i >= 0; i = i - 1 {
    for j = m - 1; j >= 0; j = j - 1 {
      lcs[i][j] = if a[i] == b[j] {
        lcs[i + 1][j + 1] + 1
      } else if lcs[i + 1][j] >= lcs[i][j + 1] {
        lcs[i + 1][j]
      } else {
        lcs[i][j + 1]
      }
    }
  }
  let result = []
  let mut i = 0
  let mut j = 0
  while i < n || j < m {
    if i < n && j < m && a[i] == b[j] {
      result.push((ChangeTag::Equal, a[i]))
      i += 1
      j += 1
    } else if i < n && (j >= m || lcs[i + 1][j] >= lcs[i][j + 1]) {
      result.push((Delete, a[i]))
      i += 1
    } else {
      result.push((Insert, b[j]))
      j += 1
    }
  }
  result
}

///|
/// `Display for TestDiff`.
fn test_diff(actual : String, expected : String, use_markers : Bool) -> String {
  let use_markers = !color_enabled() || use_markers
  let f = StringBuilder()
  for change in diff_lines(actual, expected) {
    let (tag, line) = change
    // `similar::Change`'s `Display` adds the newline a last line lacks.
    let diff = if line.has_suffix("\n") { line } else { line + "\n" }
    let (symbol, color) = match tag {
      Equal => (" ", None)
      Insert => ("+", Some(green))
      Delete => ("-", Some(red))
    }
    match (color, use_markers) {
      (Some(color), true) => f.write_string(paint(Some(color), symbol + diff))
      (Some(color), false) => f.write_string(paint(Some(color), diff))
      (None, true) => f.write_string(symbol + diff)
      (None, false) => f.write_string(diff)
    }
  }
  f.to_string()
}

///|
priv struct TestCorrection {
  name : String
  input : String
  output : String
  attributes_str : String
  header_delim_len : Int32
  divider_delim_len : Int32
}

///|
pub async fn run_tests_at_path(
  parser : @treesitter.Parser,
  opts : TestOptions,
  test_summary : TestSummary,
) -> Unit {
  let test_entry = @cli_test.parse_tests(opts.path)
  let log_session = if opts.debug_graph {
    Some(log_graphs(parser, "log.html", opts.open_log))
  } else {
    None
  }
  // `Drop for LogSession` at the end of the function, also when an error
  // is returned.
  defer (if log_session is Some(session) { session.close() })
  if opts.debug {
    parser.set_logger(
      Some((log_type, message) => {
        if log_type is Lex {
          @support.print_err("  ")
        }
        @support.print_err("\{message}\n")
      }),
    )
  }
  let corrected_entries = []
  ignore(
    run_tests(parser, test_entry, opts, test_summary, corrected_entries, true),
  )
  parser.stop_printing_dot_graphs()
  if test_summary.parse_failures.is_empty() ||
    (opts.update && !test_summary.has_parse_errors) {
    ()
  } else if opts.update && test_summary.has_parse_errors {
    raise anyhow(
      "Some tests failed to parse with unexpected `ERROR` or `MISSING` nodes, as shown above, and cannot be updated automatically.\nEither fix the grammar or manually update the tests if this is expected.",
    )
  } else {
    raise anyhow("")
  }
}

///|
pub async fn check_queries_at_path(
  language : @treesitter.Language,
  path : String,
) -> Unit {
  for entry in walk_files(path) {
    if @support.extension(entry) != Some("scm") ||
      @support.path_starts_with(entry, ".") {
      continue
    }
    let filepath = @support.file_name(entry).unwrap_or("")
    let content = @support.read_to_string(entry) catch {
      e =>
        raise with_context(
          e,
          "Error reading query file \{@loader.rust_debug_str(filepath)}",
        )
    }
    ignore(
      @treesitter.Query::new(language, content) catch {
        e =>
          raise with_context(
            e,
            "Error in query file \{@loader.rust_debug_str(filepath)}",
          )
      },
    )
  }
}

///|
/// The paths of `walkdir::WalkDir::new(path).into_iter()
/// .filter_map(Result::ok).filter(|e| e.file_type().is_file())` (walkdir
/// 2.5.0 with its default options): a depth-first walk in the order the
/// file system lists each directory, which does not follow symbolic links
/// below the root (a symbolic link is neither a file nor a directory) but
/// follows a root that is a symbolic link to a directory. Entries that
/// cannot be read are skipped.
pub async fn walk_files(path : String) -> Array[String] {
  let result = []
  async fn visit(dir : String) -> Unit {
    let names = @fs.readdir(dir, include_hidden=true) catch { _ => return }
    for name in names {
      let child = @support.path_join(dir, name)
      match (@fs.kind(child, follow_symlink=false) catch { _ => Unknown }) {
        Directory => visit(child)
        Regular => result.push(child)
        _ => ()
      }
    }
  }

  // The root entry takes `symlink_metadata`; `follow_root_links` descends
  // into a root that links to a directory.
  match (@fs.kind(path, follow_symlink=false) catch { _ => Unknown }) {
    Directory => visit(path)
    Regular => result.push(path)
    SymLink =>
      if (@fs.kind(path, follow_symlink=true) catch { _ => Unknown })
        is Directory {
        visit(path)
      }
    _ => ()
  }
  result
}

///|
fn input_string(input : Bytes) -> String {
  @support.utf8_strict(input).unwrap()
}

///|
/// `languages.iter().map(|(l, n)| (n.as_str(), l)).collect::<BTreeMap<_, _>>()`:
/// keyed by name in Rust's `str` order; a later language replaces an earlier
/// one of the same name.
fn languages_by_name(
  languages : Array[(@treesitter.Language, String)],
) -> Array[(String, @treesitter.Language)] {
  let map : Array[(String, @treesitter.Language)] = []
  for entry in languages {
    let (language, name) = entry
    match map.search_by(e => e.0 == name) {
      Some(i) => map[i] = (name, language)
      None => map.push((name, language))
    }
  }
  map.sort_by((a, b) => compare_bytes(a.0, b.0))
  map
}

///|
/// `opts.languages.get(name)`.
fn language_named(opts : TestOptions, name : String) -> @treesitter.Language? {
  match opts.languages.search_by(e => e.0 == name) {
    Some(i) => Some(opts.languages[i].1)
    None => None
  }
}

///|
/// `adjusted_parse_rate`.
fn adjusted_parse_rate(
  tree : @treesitter.Tree,
  parse_time_ns : Int64,
) -> Double {
  let (start, end) = tree.root_node().byte_range()
  @math.ln((end - start).to_double() / (parse_time_ns.to_double() / 1000000.0))
}

///|
/// This returns false if we want to "fail fast": it bails and does not
/// parse any more tests.
async fn run_tests(
  parser : @treesitter.Parser,
  test_entry : @cli_test.TestEntry,
  opts : TestOptions,
  test_summary : TestSummary,
  corrected_entries : Array[TestCorrection],
  is_root : Bool,
) -> Bool {
  match test_entry {
    Example(
      name~,
      input~,
      output~,
      header_delim_len~,
      divider_delim_len~,
      has_fields~,
      attributes_str~,
      attributes~,
      ..
    ) => {
      let correction = (output : String) => TestCorrection::{
        name,
        input: input_string(input),
        output,
        attributes_str,
        header_delim_len,
        divider_delim_len,
      }
      if attributes.expectation is Skip {
        test_summary.parse_results.add_case({
          name,
          info: ParseTest(
            outcome=Skipped,
            parse_rate=None,
            test_num=test_summary.test_num,
          ),
        })
        test_summary.test_num += 1
        return true
      }
      if !attributes.platform {
        test_summary.parse_results.add_case({
          name,
          info: ParseTest(
            outcome=Platform,
            parse_rate=None,
            test_num=test_summary.test_num,
          ),
        })
        test_summary.test_num += 1
        return true
      }
      for i, language_name in attributes.languages {
        if !language_name.is_empty() {
          guard language_named(opts, language_name) is Some(language) else {
            raise anyhow("Language not found: \{language_name}")
          }
          parser.set_language(language)
        }
        let start = @support.now_ns()
        let tree = parser.parse(input).unwrap()
        let parse_time = @support.now_ns() - start
        let (bs, be) = tree.root_node().byte_range()
        let byte_len = be - bs
        let true_parse_rate = byte_len.to_double() /
          (parse_time.to_double() / 1000000.0)
        let adj_parse_rate = adjusted_parse_rate(tree, parse_time)
        test_summary.parse_stats.total_parses += 1
        test_summary.parse_stats.total_duration += parse_time
        test_summary.parse_stats.total_bytes += byte_len.to_uint64()
        let parse_rate = Some((true_parse_rate, adj_parse_rate))
        if attributes.expectation is Error {
          if tree.root_node().has_error() {
            test_summary.parse_results.add_case({
              name,
              info: ParseTest(
                outcome=Passed,
                parse_rate~,
                test_num=test_summary.test_num,
              ),
            })
            test_summary.parse_stats.successful_parses += 1
            if opts.update {
              let output = if attributes.cst {
                output
              } else {
                @treesitter.format_sexp(output, 0)
              }
              corrected_entries.push(correction(output))
            }
          } else {
            if opts.update {
              // Keep the original `expected` output if the actual output has
              // no error
              let output = if attributes.cst {
                output
              } else {
                @treesitter.format_sexp(output, 0)
              }
              corrected_entries.push(correction(output))
            }
            test_summary.parse_results.add_case({
              name,
              info: ParseTest(
                outcome=Failed,
                parse_rate~,
                test_num=test_summary.test_num,
              ),
            })
            let actual = @cli_test.render_test_output(
              input,
              tree,
              attributes.cst,
              true,
            )
            test_summary.parse_failures.push({
              name,
              actual,
              expected: "NO ERROR",
              is_cst: attributes.cst,
            })
          }
          if attributes.fail_fast {
            return false
          }
        } else {
          let actual = @cli_test.render_test_output(
            input,
            tree,
            attributes.cst,
            opts.show_fields || has_fields,
          )
          if actual == output {
            test_summary.parse_results.add_case({
              name,
              info: ParseTest(
                outcome=Passed,
                parse_rate~,
                test_num=test_summary.test_num,
              ),
            })
            test_summary.parse_stats.successful_parses += 1
            if opts.update {
              let output = if attributes.cst {
                actual
              } else {
                @treesitter.format_sexp(output, 0)
              }
              corrected_entries.push(correction(output))
            }
          } else {
            if opts.update {
              let (expected_output, actual_output) = if attributes.cst {
                (output, actual)
              } else {
                (
                  @treesitter.format_sexp(output, 0),
                  @treesitter.format_sexp(actual, 0),
                )
              }
              // Only bail early before updating if `actual` does not match
              // `output`. Sometimes users want to test cases that are
              // intended to have errors, hence why this check isn't shown
              // above.
              if tree.root_node().has_error() {
                test_summary.has_parse_errors = true
                // keep the original `expected` output if the tree has an
                // error.
                corrected_entries.push(correction(expected_output))
              } else {
                corrected_entries.push(correction(actual_output))
                test_summary.parse_results.add_case({
                  name,
                  info: ParseTest(
                    outcome=Updated,
                    parse_rate~,
                    test_num=test_summary.test_num,
                  ),
                })
              }
            } else {
              test_summary.parse_results.add_case({
                name,
                info: ParseTest(
                  outcome=Failed,
                  parse_rate~,
                  test_num=test_summary.test_num,
                ),
              })
            }
            test_summary.parse_failures.push({
              name,
              actual,
              expected: output,
              is_cst: attributes.cst,
            })
            if attributes.fail_fast {
              return false
            }
          }
        }
        if i == attributes.languages.length() - 1 {
          // reset to the first language
          // (`opts.languages.values().next().unwrap()`)
          parser.set_language(opts.languages[0].1)
        }
      }
      test_summary.test_num += 1
    }
    Group(name~, children~, file_path~) => {
      if children.is_empty() {
        return true
      }
      let mut ran_test_in_group = false
      let matches_filter = (name : String, file_name : String?) => {
        if file_name is Some(test_file_path) &&
          opts.file_name is Some(filter_file_name) &&
          filter_file_name != test_file_path {
          return false
        }
        match opts.include {
          Some(include) => include.is_match(@support.utf8(name))
          None =>
            match opts.exclude {
              Some(exclude) => !exclude.is_match(@support.utf8(name))
              None => true
            }
        }
      }
      for child in children {
        if child
          is Example(
            name~,
            file_name~,
            input~,
            output~,
            attributes_str~,
            header_delim_len~,
            divider_delim_len~,
            ..
          ) &&
          !matches_filter(name, file_name) {
          if opts.update {
            corrected_entries.push({
              name,
              input: input_string(input),
              output: @treesitter.format_sexp(output, 0),
              attributes_str,
              header_delim_len,
              divider_delim_len,
            })
          }
          test_summary.test_num += 1
          continue
        }
        if !ran_test_in_group && !is_root {
          test_summary.parse_results.add_group(name)
          ran_test_in_group = true
        }
        if !run_tests(
            parser, child, opts, test_summary, corrected_entries, false,
          ) {
          // fail fast
          return false
        }
      }
      // Now that we're done traversing the children of the current group,
      // pop the index
      test_summary.parse_results.pop_traversal()
      if file_path is Some(file_path) {
        if opts.update {
          write_tests(file_path, corrected_entries)
        }
        corrected_entries.clear()
      }
    }
  }
  true
}

///|
async fn write_tests(
  file_path : String,
  corrected_entries : Array[TestCorrection],
) -> Unit {
  let buffer = StringBuilder()
  for i, entry in corrected_entries {
    if i > 0 {
      buffer.write_string("\n")
    }
    let header = "=".repeat(entry.header_delim_len)
    let attributes = if entry.attributes_str.is_empty() {
      entry.attributes_str
    } else {
      "\{entry.attributes_str}\n"
    }
    buffer.write_string(
      "\{header}\n\{entry.name}\n\{attributes}\{header}\n\{entry.input}\n\{"-".repeat(entry.divider_delim_len)}\n\n\{entry.output.trim()}\n",
    )
  }
  @fs.write_file(
    file_path,
    buffer.to_string(),
    create_mode=CreateOrTruncate,
    permission=0o666,
  )
}

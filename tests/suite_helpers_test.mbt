// Helpers for the ports of upstream's parser, node, tree, language,
// text-provider, pathological and corpus test suites
// (crates/cli/src/tests/{helpers,*_test}.rs).
//
// Upstream compiles grammars at test time (`generate_parser` +
// `get_test_language`); here the grammar JSON goes through the MoonBit
// generator (`generate`) and its portable `Language` tables. The test
// grammars of `get_test_fixture_language` are read from their `grammar.json`
// as produced by `tools/oracle/ref_generate.sh` (`_build/ref/<name>`); the
// corpora come from the pinned upstream checkout.

///|
/// Prefixes under which the files of the module root are found: tests run
/// either from the module root or from this package's directory.
let root_prefixes : Array[String] = ["", "../../../"]

///|
/// The directory of the pinned upstream checkout, if present.
async fn upstream_dir() -> String? {
  let candidates = []
  if @env.get_env_var("TREE_SITTER_UPSTREAM") is Some(dir) {
    candidates.push(dir)
  }
  for prefix in root_prefixes {
    candidates.push("\{prefix}.repos/ts-pinned")
    // from a worktree under .claude/worktrees/<name>
    candidates.push("\{prefix}../../../.repos/ts-pinned")
  }
  for dir in candidates {
    if @fs.exists("\{dir}/test/fixtures/grammars") {
      return Some(dir)
    }
  }
  None
}

///|
/// The upstream test fixture directory (`fixtures_dir()`), or `None` with a
/// notice.
async fn fixtures_dir() -> String? {
  guard upstream_dir() is Some(dir) else {
    if !missing_languages.contains("<upstream>") {
      missing_languages["<upstream>"] = true
      println(
        "note: skipping tests that need the pinned upstream checkout (set TREE_SITTER_UPSTREAM)",
      )
    }
    return None
  }
  Some("\{dir}/test/fixtures")
}

///|
/// The directory holding the reference outputs of `tools/oracle/ref_generate.sh`
/// (`_build/ref`), if present.
async fn ref_dir() -> String? {
  for prefix in root_prefixes {
    let dir = "\{prefix}_build/ref"
    if @fs.exists(dir) {
      return Some(dir)
    }
  }
  None
}

///|
/// The `grammar.json` text of an upstream test grammar
/// (`load_grammar_file(test_grammars/<name>/grammar.js)`), or `None` with a
/// notice.
async fn load_test_grammar_json(name : String) -> String? {
  if ref_dir() is Some(dir) {
    let path = "\{dir}/\{name}/src/grammar.json"
    if @fs.exists(path) {
      return Some(@fs.read_file(path).text())
    }
  }
  if !missing_languages.contains(name) {
    missing_languages[name] = true
    println(
      "note: skipping tests that need the `\{name}` test grammar (run tools/oracle/ref_generate.sh)",
    )
  }
  None
}

///|
let test_fixture_language_cache : Map[String, @treesitter.Language] = Map([])

///|
/// Whether `name`'s external scanner can be used: either it has none, or it
/// has been ported (see `ported_scanners`). Prints a notice otherwise.
fn scanner_available(name : String, raw : @language.Language) -> Bool {
  if raw.external_token_count > 0 && !ported_scanners.contains(name) {
    if !missing_languages.contains(name) {
      missing_languages[name] = true
      println(
        "note: skipping tests that parse `\{name}` (external scanner pending)",
      )
    }
    return false
  }
  true
}

///|
/// The language of the upstream test grammar `name` with its external
/// scanner (if any), generated at test time (`get_test_fixture_language`).
/// `None` (with a notice) when the grammar is not available or its scanner
/// has not been ported yet.
async fn get_test_fixture_language(name : String) -> @treesitter.Language? {
  if test_fixture_language_cache.get(name) is Some(language) {
    return Some(language)
  }
  // The grammars the query suite needs are committed under testdata/.
  let committed = "testdata/test_grammars/\{name}/grammar.json"
  let grammar_json = match
    read_first(["api/tests/\{committed}", committed]) {
    Some(grammar_json) => grammar_json
    None => {
      guard load_test_grammar_json(name) is Some(grammar_json) else {
        return None
      }
      grammar_json
    }
  }
  let (parser_name, parser) = generate_parser(grammar_json) catch {
    e => abort("failed to generate the `\{name}` test grammar: \{e}")
  }
  guard scanner_available(name, parser.language) else { return None }
  let language = get_test_language(
    parser_name,
    parser,
    Some("test/fixtures/test_grammars/\{name}"),
  )
  test_fixture_language_cache[name] = language
  Some(language)
}

///|
/// Upstream's `ReadRecorder` (helpers/edits.rs): an input callback that
/// returns one byte at a time and records the offsets read.
struct ReadRecorder {
  content : Bytes
  indices_read : Array[Int32]
}

///|
fn ReadRecorder::new(content : ArrayView[Byte]) -> ReadRecorder {
  { content: Bytes::from_array(content), indices_read: [], }
}

///|
fn ReadRecorder::read(self : ReadRecorder, offset : Int32) -> BytesView {
  if offset < self.content.length() {
    if self.indices_read.binary_search(offset) is Err(i) {
      self.indices_read.insert(i, offset)
    }
    self.content[offset:offset + 1]
  } else {
    b""[:]
  }
}

///|
fn ReadRecorder::strings_read(self : ReadRecorder) -> Array[String] {
  let result = []
  let mut last_range : (Int32, Int32)? = None
  for index in self.indices_read {
    if last_range is Some((start, end)) {
      if end == index {
        last_range = Some((start, end + 1))
      } else {
        result.push(@utf8.decode_lossy(self.content[start:end]))
        last_range = None
      }
    } else {
      last_range = Some((index, index + 1))
    }
  }
  if last_range is Some((start, end)) {
    result.push(@utf8.decode_lossy(self.content[start:end]))
  }
  result
}

///|
/// `fuzz::edits::Edit { position, deleted_length, inserted_text }`.
fn edit(
  position : Int32,
  deleted_length : Int32,
  inserted_text : String,
) -> @cli_test.Edit {
  { position, deleted_length, inserted_text: utf8(inserted_text).to_array(), }
}

///|
/// `str::find`, as a byte offset of the UTF-8 text.
fn byte_find(haystack : String, needle : String) -> Int32 {
  let h = utf8(haystack)
  let n = utf8(needle)
  for i in 0..<=(h.length() - n.length()) {
    if h[i:i + n.length()] == n[:] {
      return i
    }
  }
  abort("`\{needle}` not found")
}

///|
/// `simple_range(start, end)` of parser_test.rs.
fn simple_range(start : Int32, end : Int32) -> @treesitter.Range {
  {
    start_byte: start,
    end_byte: end,
    start_point: @treesitter.Point::new(0, start),
    end_point: @treesitter.Point::new(0, end),
  }
}

///|
/// `chunked_input(text, size)` of parser_test.rs.
fn chunked_input(
  text : String,
  size : Int32,
) -> (Int32, @treesitter.Point) -> BytesView {
  let bytes = utf8(text)
  (offset, _) => {
    let end = if bytes.length() < offset + size {
      bytes.length()
    } else {
      offset + size
    }
    bytes[offset:end]
  }
}

///|
/// The process CPU time in microseconds (C's `clock()`; `CLOCKS_PER_SEC` is
/// 1000000 on POSIX systems), standing in for `std::time::Instant`.
extern "C" fn c_clock() -> Int64 = "clock"

///|
/// Microseconds elapsed since `start` (a [`c_clock`] reading).
fn elapsed_micros(start : Int64) -> Int64 {
  c_clock() - start
}

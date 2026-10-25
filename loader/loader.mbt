// Port of tree-sitter crates/loader/src/loader.rs.
//
// MoonBit has no dynamic loading, so a "parser library" is the portable
// language table generated from the grammar's `src/grammar.json` by
// generate. `tree-sitter generate` writes it to `src/language.json`;
// when that file is missing or older than `src/grammar.json`, the loader
// generates the language itself and caches it as
// `<parser_lib_path>/<name>.language.json` (the place upstream keeps compiled
// libraries), regenerating when `src/grammar.json` or an external file is
// newer than the cache, as `needs_recompile` does for `parser.c`.
//
// External scanners: a grammar with `src/scanner.mbtx` (a MoonBit program
// defining `pub fn scanner() -> @runtime.ExternalScanner`) needs a scanner
// registered by the embedding program; when it is missing the loader raises
// `ScannerRequired` and the CLI re-runs itself through a driver binary that
// is compiled with the scanners (see mbtx.mbt). A grammar with a C scanner
// (`src/scanner.c`) uses the pure MoonBit port of that scanner from
// scanners when there is one.

///|
pub let default_highlights_query_file_name : String = "highlights.scm"

///|
pub let default_injections_query_file_name : String = "injections.scm"

///|
pub let default_locals_query_file_name : String = "locals.scm"

///|
pub let default_tags_query_file_name : String = "tags.scm"

///|
/// `LoaderError`. `IO` and `Serialization` carry their display text.
pub(all) suberror LoaderError {
  IO(String)
  LockFileTimeout(String)
  CurrentDirectoryLoad(LoaderError)
  ExternalFile(String, String)
  FileNameLoad(String, LoaderError)
  GrammarJSON(String)
  HomeDir
  ModifiedTime(LoaderError)
  NoLanguage
  Query(@treesitter.QueryError, String?)
  ScopeLoad(String, LoaderError)
  Serialization(String)
  Tags(@tags.TagsError)
  UnknownScope(String)
  /// Generating the language from `src/grammar.json` failed.
  Generate(String, String)
  /// The grammar has an external scanner that cannot be loaded.
  Scanner(String)
  /// The grammar needs MoonBit scanners (`scanner.mbtx` paths by language
  /// name) that the running program does not have.
  ScannerRequired(Array[(String, String)])
  /// A `.mbtx` program failed.
  Script(String)
}

///|
pub impl Show for LoaderError with fn output(self, logger) {
  match self {
    IO(message) | Serialization(message) | Scanner(message) | Script(message) =>
      logger.write_string(message)
    LockFileTimeout(path) =>
      logger.write_string(
        "Lock file '\{path}' appears stale\nIf there isn't another concurrent tree-sitter instance, remove it",
      )
    CurrentDirectoryLoad(e) =>
      logger.write_string("Failed to load language in current directory:\n\{e}")
    ExternalFile(a, b) =>
      logger.write_string(
        "External file path \{a} is outside of parser directory \{b}",
      )
    FileNameLoad(name, e) =>
      logger.write_string(
        "Failed to load language for file name \{name}:\n\{e}",
      )
    GrammarJSON(path) =>
      logger.write_string(
        "Failed to parse the language name from grammar.json at \{path}",
      )
    HomeDir => logger.write_string("could not find home directory")
    ModifiedTime(e) =>
      logger.write_string(
        "Failed to compare binary and source timestamps:\n\{e}",
      )
    NoLanguage => logger.write_string("No language found")
    Query(error, file) => {
      if file is Some(path) {
        logger.write_string("Error in query file \{path}:\n")
      }
      logger.write_string(error.to_string())
    }
    ScopeLoad(scope, e) =>
      logger.write_string("Failed to load language for scope '\{scope}':\n\{e}")
    Tags(e) => logger.write_string(e.to_string())
    UnknownScope(scope) => logger.write_string("Unknown scope '\{scope}'")
    Generate(path, e) =>
      logger.write_string("Failed to generate the language from \{path}:\n\{e}")
    ScannerRequired(scanners) =>
      logger.write_string(
        "MoonBit external scanners are required: \{scanners.map(s => s.1).join(", ")}",
      )
  }
}

///|
/// The scanner registry of the running program: the external scanner
/// factory for a language name.
pub type ScannerRegistry = (String) -> @runtime.ExternalScannerFactory?

///|
/// A compiled regex together with its source pattern (`regex::Regex`, whose
/// `Debug` shows the pattern).
pub struct LoaderRegex {
  pattern : String
  regex : @regex.Regex
}

///|
/// `Debug for Regex`: `Regex("<pattern>")`.
pub fn LoaderRegex::debug(self : LoaderRegex) -> String {
  "Regex(\{rust_debug_str(self.pattern)})"
}

///|
pub fn LoaderRegex::find(self : LoaderRegex, text : String) -> (Int32, Int32)? {
  self.regex.find(@support.utf8(text))
}

///|
pub fn LoaderRegex::is_match(self : LoaderRegex, text : String) -> Bool {
  self.regex.is_match(@support.utf8(text))
}

///|
/// Rust's `Debug for str` (`@support.rust_debug_str`).
pub fn rust_debug_str(s : String) -> String {
  @support.rust_debug_str(s)
}

///|
/// Rust's `Debug` for a list of strings (`["a", "b"]`).
pub fn rust_debug_strs(items : Array[String]) -> String {
  "[" + items.map(rust_debug_str).join(", ") + "]"
}

///|
/// `LanguageConfiguration`.
pub struct LanguageConfiguration {
  scope : String?
  content_regex : LoaderRegex?
  first_line_regex : LoaderRegex?
  injection_regex : LoaderRegex?
  file_types : Array[String]
  root_path : String
  highlights_filenames : Array[String]?
  injections_filenames : Array[String]?
  locals_filenames : Array[String]?
  tags_filenames : Array[String]?
  language_name : String
  priv language_id : Int32
  priv mut highlight_config : @highlight.HighlightConfiguration??
  priv mut tags_config : @tags.TagsConfiguration??
  priv highlight_names : Ref[Array[String]]
  priv use_all_highlight_names : Bool
}

///|
priv struct LanguageEntry {
  path : String
  mut language : @treesitter.Language?
  external_files : Array[String]?
}

///|
/// `Loader`.
pub struct Loader {
  parser_lib_path : String
  priv languages_by_id : Array[LanguageEntry]
  priv language_configurations : Array[LanguageConfiguration]
  priv language_configuration_ids_by_file_type : Map[String, Array[Int32]]
  priv mut language_configuration_in_current_path : Int32?
  priv language_configuration_ids_by_first_line_regex : Map[
    String,
    Array[Int32],
  ]
  priv highlight_names : Ref[Array[String]]
  priv mut use_all_highlight_names : Bool
  priv mut debug_build : Bool
  priv mut sanitize_build : Bool
  priv mut force_rebuild : Bool
  priv mut scanners : ScannerRegistry
  /// MoonBit scanners discovered while loading, by language name.
  priv mbtx_scanners : Map[String, String]
  priv injection_cache : Map[String, @highlight.HighlightConfiguration?]
  priv pending_injections : Array[String]
}

///|
/// `log::warn!`/`log::info!` hooks, set by the CLI to its logger.
pub let warn_hook : Ref[(String) -> Unit] = Ref(@support.log_warn)

///|
pub let info_hook : Ref[(String) -> Unit] = Ref(@support.log_info)

///|
fn warn(message : String) -> Unit {
  (warn_hook.val)(message)
}

///|
/// `Loader::new`: `$TREE_SITTER_LIBDIR`, else `<cache dir>/tree-sitter/lib`.
/// Without `TREE_SITTER_LIBDIR`, macOS removes the libraries that older
/// versions cached in `~/Library/Caches/tree-sitter`.
pub async fn Loader::new() -> Loader {
  let parser_lib_path = match @env.get_env_var("TREE_SITTER_LIBDIR") {
    Some(path) => path
    None => {
      if @support.target_os() == "macos" {
        // `etcetera::base_strategy::Apple::new()?.cache_dir()`
        // (`$HOME/Library/Caches/`)
        let legacy_apple_path = match @support.home_dir() {
          Some(home) =>
            @support.path_join(
              @support.path_join(home, "Library/Caches/"),
              "tree-sitter",
            )
          None => raise HomeDir
        }
        if @fs.exists(legacy_apple_path) && @support.is_dir(legacy_apple_path) {
          @support.remove_dir_all(legacy_apple_path) catch {
            e =>
              raise IO(@support.io_error_with_path(e, Some(legacy_apple_path)))
          }
        }
      }
      match @support.cache_dir() {
        Some(dir) => @support.path_join(dir, "tree-sitter/lib")
        None => raise HomeDir
      }
    }
  }
  Loader::with_parser_lib_path(parser_lib_path)
}

///|
pub fn Loader::with_parser_lib_path(parser_lib_path : String) -> Loader {
  {
    parser_lib_path,
    languages_by_id: [],
    language_configurations: [],
    language_configuration_ids_by_file_type: Map([]),
    language_configuration_in_current_path: None,
    language_configuration_ids_by_first_line_regex: Map([]),
    highlight_names: Ref([]),
    use_all_highlight_names: true,
    debug_build: false,
    sanitize_build: false,
    force_rebuild: false,
    scanners: _ => None,
    mbtx_scanners: Map([]),
    injection_cache: Map([]),
    pending_injections: [],
  }
}

///|
/// Register the external scanners compiled into the running program.
pub fn Loader::set_scanners(self : Loader, scanners : ScannerRegistry) -> Unit {
  self.scanners = scanners
}

///|
pub fn Loader::configure_highlights(
  self : Loader,
  names : Array[String],
) -> Unit {
  self.use_all_highlight_names = false
  self.highlight_names.val.clear()
  self.highlight_names.val.append(names)
}

///|
pub fn Loader::highlight_names(self : Loader) -> Array[String] {
  self.highlight_names.val.copy()
}

///|
pub async fn Loader::find_all_languages(
  self : Loader,
  config : LoaderConfig,
) -> Unit {
  if config.parser_directories.is_empty() {
    warn(
      "You have not configured any parser directories!\nPlease run `tree-sitter init-config` and edit the resulting\nconfiguration file to indicate where we should look for\nlanguage grammars.\n",
    )
  }
  for parser_container_dir in config.parser_directories {
    let entries = @fs.readdir(parser_container_dir) catch { _ => continue }
    for parser_dir_name in entries {
      if parser_dir_name.has_prefix("tree-sitter-") {
        ignore(
          self.find_language_configurations_at_path(
            @support.path_join(parser_container_dir, parser_dir_name),
            false,
          ) catch {
            _ => []
          },
        )
      }
    }
  }
}

///|
pub async fn Loader::languages_at_path(
  self : Loader,
  path : String,
) -> Array[(@treesitter.Language, String)] {
  let configurations = self.find_language_configurations_at_path(path, true) catch {
    _ => return []
  }
  let language_ids = configurations.map(c => (c.language_id, c.language_name))
  // `sort_unstable` + `dedup` on (id, name) pairs: elements that compare
  // equal are identical, so the unstable sort is deterministic.
  language_ids.sort_by((a, b) => {
    let c = a.0.compare(b.0)
    if c != 0 {
      c
    } else {
      rust_str_cmp(a.1, b.1)
    }
  })
  let deduped : Array[(Int32, String)] = []
  for entry in language_ids {
    match deduped.last() {
      Some(last) if last.0 == entry.0 && last.1 == entry.1 => ()
      _ => deduped.push(entry)
    }
  }
  let result = []
  for entry in deduped {
    result.push((self.language_for_id(entry.0), entry.1))
  }
  result
}

///|
/// Rust's `str::cmp`: lexicographic by UTF-8 bytes, which is the order of
/// code points (MoonBit's `String::compare` orders by length first).
fn rust_str_cmp(a : String, b : String) -> Int32 {
  let a = a.iter()
  let b = b.iter()
  for ;; {
    match (a.next(), b.next()) {
      (Some(x), Some(y)) => if x != y { return x.to_int().compare(y.to_int()) }
      (Some(_), None) => return 1
      (None, Some(_)) => return -1
      (None, None) => return 0
    }
  }
}

///|
pub fn Loader::get_all_language_configurations(
  self : Loader,
) -> Array[(LanguageConfiguration, String)] {
  self.language_configurations.map(c => {
    (c, self.languages_by_id[c.language_id].path)
  })
}

///|
pub async fn Loader::language_configuration_for_scope(
  self : Loader,
  scope : String,
) -> (@treesitter.Language, LanguageConfiguration)? {
  for configuration in self.language_configurations {
    if configuration.scope == Some(scope) {
      let language = self.language_for_id(configuration.language_id)
      return Some((language, configuration))
    }
  }
  None
}

///|
/// `language_configuration_for_first_line_regex`. Upstream folds over a
/// `HashMap` whose iteration order depends on its per-process random hash
/// keys, and the fold returns the result of the last entry visited (`None`
/// if that entry's pattern does not match the first line). The port keeps
/// the fold semantics over the map's insertion order (the order in which the
/// patterns were first seen), which is one of the orders upstream may use;
/// with a single first-line pattern both agree.
pub async fn Loader::language_configuration_for_first_line_regex(
  self : Loader,
  path : String,
) -> (@treesitter.Language, LanguageConfiguration)? {
  let mut result = None
  for regex, ids in self.language_configuration_ids_by_first_line_regex {
    result = None
    guard make_regex(Some(regex)) is Some(regex) else { continue }
    let reader = LineReader::open(path) catch {
      e => raise IO(@support.io_error_with_path(e, Some(path)))
    }
    defer reader.close()
    let first_line = reader.next_line() catch {
      e => raise IO("\{line_error_message(e)} (\{path})")
    }
    if first_line is Some(first_line) &&
      regex.is_match(first_line) &&
      !ids.is_empty() {
      let configuration = self.language_configurations[ids[0]]
      let language = self.language_for_id(configuration.language_id)
      result = Some((language, configuration))
    }
  }
  result
}

///|
/// `Path::extension` iterated as upstream does to collect the extensions of
/// a file name, longest suffix first.
fn extension_keys(path : String) -> Array[String] {
  let extensions = []
  let mut current = path
  while @support.extension(current) is Some(extension) {
    extensions.push(extension)
    current = @support.file_stem(current).unwrap_or("")
  }
  extensions.rev_in_place()
  let keys = []
  for i in 0..<extensions.length() {
    keys.push(extensions[i:].to_owned().join("."))
  }
  keys
}

///|
pub async fn Loader::language_configuration_for_file_name(
  self : Loader,
  path : String,
) -> (@treesitter.Language, LanguageConfiguration)? {
  // Find all the language configurations that match this file name or a
  // suffix of the file name.
  let mut configuration_ids = match @support.file_name(path) {
    Some(file_name) =>
      self.language_configuration_ids_by_file_type.get(file_name)
    None => None
  }
  if configuration_ids is None {
    for key in extension_keys(path) {
      if self.language_configuration_ids_by_file_type.get(key) is Some(ids) {
        configuration_ids = Some(ids)
        break
      }
    }
  }
  guard configuration_ids is Some(configuration_ids) &&
    !configuration_ids.is_empty() else {
    return None
  }
  let configuration = if configuration_ids.length() == 1 {
    self.language_configurations[configuration_ids[0]]
  } else {
    // If multiple language configurations match, then determine which one
    // to use by applying the configurations' content regexes.
    let contents = @support.read_file(path) catch {
      e => raise IO(@support.io_error_with_path(e, Some(path)))
    }
    let file_contents = @support.utf8_lossy(contents)
    let mut best_score = -2
    let mut best_configuration_id = None
    for configuration_id in configuration_ids {
      let config = self.language_configurations[configuration_id]
      // If the language configuration has a content regex, assign a score
      // based on the length of the first match. If it does not match,
      // penalize the configuration so that configurations without content
      // regexes are preferred over those with non-matching ones.
      let score = match config.content_regex {
        Some(content_regex) =>
          match content_regex.find(file_contents) {
            Some((start, end)) => end - start
            None => -1
          }
        None => 0
      }
      if score > best_score {
        best_configuration_id = Some(configuration_id)
        best_score = score
      }
    }
    self.language_configurations[best_configuration_id.unwrap()]
  }
  let language = self.language_for_id(configuration.language_id)
  Some((language, configuration))
}

///|
pub async fn Loader::language_configuration_for_injection_string(
  self : Loader,
  string : String,
) -> (@treesitter.Language, LanguageConfiguration)? {
  let mut best_match_length = 0
  let mut best_match_position = None
  for i, configuration in self.language_configurations {
    if configuration.injection_regex is Some(injection_regex) &&
      injection_regex.find(string) is Some((start, end)) {
      let length = end - start
      if length > best_match_length {
        best_match_position = Some(i)
        best_match_length = length
      }
    }
  }
  match best_match_position {
    Some(i) => {
      let configuration = self.language_configurations[i]
      let language = self.language_for_id(configuration.language_id)
      Some((language, configuration))
    }
    None => None
  }
}

///|
pub async fn Loader::language_for_configuration(
  self : Loader,
  configuration : LanguageConfiguration,
) -> @treesitter.Language {
  self.language_for_id(configuration.language_id)
}

///|
async fn Loader::language_for_id(
  self : Loader,
  id : Int32,
) -> @treesitter.Language {
  let entry = self.languages_by_id[id]
  match entry.language {
    Some(language) => language
    None => {
      let src_path = @support.path_join(entry.path, "src")
      let language = self.load_language_at_path(src_path, entry.external_files)
      entry.language = Some(language)
      language
    }
  }
}

///|
/// `load_language_at_path`: the language of the grammar in `src_path`.
pub async fn Loader::load_language_at_path(
  self : Loader,
  src_path : String,
  external_files : Array[String]?,
) -> @treesitter.Language {
  let grammar_path = @support.path_join(src_path, "grammar.json")
  let name = Loader::grammar_json_name(grammar_path)
  let raw = self.load_language_tables(src_path, name, external_files)
  let scanner = self.scanner_for(src_path, name, raw)
  @treesitter.Language::new(raw, external_scanner?=scanner)
}

///|
async fn mtime(path : String) -> Int64 {
  let (sec, nsec) = @fs.mtime(path) catch {
    e => raise IO(@support.io_error_with_path(e, Some(path)))
  }
  sec * 1000000000L + nsec.to_int64()
}

///|
/// `needs_recompile`.
async fn needs_recompile(
  lib_path : String,
  paths_to_check : Array[String],
) -> Bool {
  if !@fs.exists(lib_path) {
    return true
  }
  let lib_mtime = mtime(lib_path) catch {
    e => raise ModifiedTime(to_loader_error(e))
  }
  for path in paths_to_check {
    let m = mtime(path) catch { e => raise ModifiedTime(to_loader_error(e)) }
    if m > lib_mtime {
      return true
    }
  }
  false
}

///|
fn to_loader_error(e : Error) -> LoaderError {
  match e {
    IO(m) => IO(m)
    LockFileTimeout(p) => LockFileTimeout(p)
    CurrentDirectoryLoad(l) => CurrentDirectoryLoad(l)
    ExternalFile(a, b) => ExternalFile(a, b)
    FileNameLoad(a, l) => FileNameLoad(a, l)
    GrammarJSON(a) => GrammarJSON(a)
    HomeDir => HomeDir
    ModifiedTime(l) => ModifiedTime(l)
    NoLanguage => NoLanguage
    Query(q, f) => Query(q, f)
    ScopeLoad(a, l) => ScopeLoad(a, l)
    Serialization(m) => Serialization(m)
    Tags(t) => Tags(t)
    UnknownScope(s) => UnknownScope(s)
    Generate(a, b) => Generate(a, b)
    Scanner(m) => Scanner(m)
    ScannerRequired(s) => ScannerRequired(s)
    Script(m) => Script(m)
    _ => IO(@support.io_error_message(e))
  }
}

///|
async fn read_language_json(path : String) -> @language.Language {
  let text = @fs.read_file(path).text() catch {
    e => raise IO(@support.io_error_with_path(e, Some(path)))
  }
  (@json.from_json(@json.parse(text)) : @language.Language) catch {
    e =>
      raise Serialization(
        "Failed to read the language tables at \{path} -- \{e}",
      )
  }
}

///|
/// The language tables of a grammar: `src/language.json` when it is up to
/// date, else the cached or freshly generated tables.
async fn Loader::load_language_tables(
  self : Loader,
  src_path : String,
  name : String,
  external_files : Array[String]?,
) -> @language.Language {
  let grammar_path = @support.path_join(src_path, "grammar.json")
  let paths_to_check = [grammar_path]
  if external_files is Some(files) {
    for f in files {
      paths_to_check.push(@support.path_join(src_path, f))
    }
  }
  let local = @support.path_join(src_path, "language.json")
  if !self.force_rebuild && !needs_recompile(local, paths_to_check) {
    return read_language_json(local)
  }
  @support.create_dir_all(self.parser_lib_path) catch {
    e => raise IO(@support.io_error_with_path(e, Some(self.parser_lib_path)))
  }
  let mut lib_name = name
  if self.debug_build {
    lib_name = lib_name + ".debug._"
  }
  if self.sanitize_build {
    lib_name = lib_name + ".sanitize._"
  }
  let output_path = @support.path_join(
    self.parser_lib_path,
    lib_name + ".language.json",
  )
  let recompile = self.force_rebuild ||
    needs_recompile(output_path, paths_to_check)
  // Create a unique lock path based on the output path hash to prevent
  // interference when multiple processes build the same grammar (by name)
  // to different output locations
  let lock_hash = path_hash_hex(output_path)
  let lock_path = match @support.cache_dir() {
    Some(dir) =>
      @support.path_join(dir, "tree-sitter/lock/\{name}-\{lock_hash}.lock")
    None => raise HomeDir
  }
  // Synchronize generation across processes using an atomic lock file.
  // Exactly one caller wins the race to generate. Losers wait for the lock
  // file to be removed, then skip generation and proceed to loading.
  //
  // Loading only (`recompile == false`) doesn't need a lock because
  // `generate_language_tables` writes to a temp file and atomically renames
  // it into place, so loaders always see a complete language file (either
  // the new or previous copy).
  //
  // `LockFile::drop` runs on every exit of the winner, and stale locks from
  // killed processes are detected via a timeout in `wait_for_removal`.
  if recompile {
    let parent_path = @support.parent(lock_path).unwrap()
    @support.create_dir_all(parent_path) catch {
      e => raise IO(@support.io_error_with_path(e, Some(parent_path)))
    }
    match LockFile::create(lock_path) {
      Some(lock) => {
        // We won the race, so generate with the lock.
        defer lock.drop()
        return generate_language_tables(src_path, output_path)
      }
      // Another process is generating (or a previous run crashed and left a
      // stale lock). Wait for it to finish.
      None => LockFile::wait_for_removal(lock_path, 30000)
    }
  }
  read_language_json(output_path)
}

///|
/// The port of `compile_parser_to_dylib`: generate the language tables from
/// `src/grammar.json` and publish them at `output_path`.
async fn generate_language_tables(
  src_path : String,
  output_path : String,
) -> @language.Language {
  let grammar_path = @support.path_join(src_path, "grammar.json")
  let grammar_json = @fs.read_file(grammar_path).text() catch {
    e => raise IO(@support.io_error_with_path(e, Some(grammar_path)))
  }
  let repo_path = @support.parent(src_path).unwrap_or(".")
  let semantic_version = read_grammar_version(repo_path) catch {
    IOError(e, path) => raise IO(@support.io_error_with_path(e, Some(path)))
    e => raise Serialization(e.to_string())
  }
  let generated = @generate.generate_from_grammar_json(
    grammar_json,
    semantic_version?,
  ) catch {
    e => raise Generate(grammar_path, e.to_string())
  }
  let language = generated.language
  // Write to a temporary path, then atomically rename into place. This
  // ensures loaders never see a half-written language file.
  let temp_output = temp_path(output_path)
  @fs.write_file(
    temp_output,
    language.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o666,
  ) catch {
    e => {
      @fs.remove(temp_output) catch {
        _ => ()
      }
      raise IO(@support.io_error_with_path(e, Some(temp_output)))
    }
  }
  @fs.rename(temp_output, output_path) catch {
    e => {
      @fs.remove(temp_output) catch {
        _ => ()
      }
      raise IO(@support.io_error_with_path(e, Some(output_path)))
    }
  }
  language
}

///|
/// The external scanner of a grammar, if it has one.
async fn Loader::scanner_for(
  self : Loader,
  src_path : String,
  name : String,
  raw : @language.Language,
) -> @runtime.ExternalScannerFactory? {
  if raw.external_token_count == 0 {
    return None
  }
  if (self.scanners)(name) is Some(factory) {
    return Some(factory)
  }
  let mbtx = @support.path_join(src_path, "scanner.mbtx")
  if @fs.exists(mbtx) {
    let path = @fs.realpath(mbtx)
    self.mbtx_scanners[name] = path
    required_mbtx_scanners[name] = path
    let required = []
    for n, p in self.mbtx_scanners {
      required.push((n, p))
    }
    raise ScannerRequired(required)
  }
  if @scanners.scanner_for(name) is Some(factory) {
    return Some(factory)
  }
  for c_scanner in ["scanner.c", "scanner.cc"] {
    let path = @support.path_join(src_path, c_scanner)
    if @fs.exists(path) {
      raise Scanner(
        "The external scanner \{path} of the language `\{name}` is written in C, which the MoonBit port cannot load; port it to MoonBit as \{mbtx}",
      )
    }
  }
  raise Scanner(
    "The language `\{name}` has external tokens but no external scanner (expected \{mbtx})",
  )
}

///|
/// `ParseVersionError` of the generate crate (`read_grammar_version`).
pub(all) suberror ParseVersionError {
  /// `Version(Box<str>)`.
  VersionError(String)
  /// `JSON(Box<str>)`.
  JSONError(String)
  /// `IO(IoError)`: the I/O error and its path.
  IOError(Error, String)
}

///|
pub impl Show for ParseVersionError with fn output(self, logger) {
  match self {
    VersionError(message) | JSONError(message) => logger.write_string(message)
    IOError(e, path) =>
      logger.write_string(@support.io_error_with_path(e, Some(path)))
  }
}

///|
/// `read_grammar_version` of the generate crate: the `metadata.version` of
/// the nearest `tree-sitter.json` in `repo_path` or its ancestors.
pub async fn read_grammar_version(
  repo_path : String,
) -> (Int32, Int32, Int32)? raise ParseVersionError {
  let filename = "tree-sitter.json"
  let mut dir : String? = Some(repo_path)
  while dir is Some(d) {
    let path = @support.path_join(d, filename)
    if (@fs.exists(path) catch { _ => false }) {
      let contents = @support.read_to_string(path) catch {
        e => raise IOError(e, path)
      }
      let version = @generate.tree_sitter_json_version(contents) catch {
        e => raise JSONError("Failed to parse `\{path}` -- \{e}")
      }
      let v = SemverVersion::parse(version) catch {
        e =>
          raise VersionError(
            "Failed to parse `\{path}` version as semver -- \{e}",
          )
      }
      return Some(
        (
          (v.major & 0xFFUL).to_int(),
          (v.minor & 0xFFUL).to_int(),
          (v.patch & 0xFFUL).to_int(),
        ),
      )
    }
    dir = match @support.parent(d) {
      Some("") =>
        if d == "." || @support.is_absolute(d) {
          None
        } else {
          Some(".")
        }
      p => p
    }
    if d == "." {
      dir = None
    }
  }
  None
}

///|
pub fn Loader::get_language_configuration_in_current_path(
  self : Loader,
) -> LanguageConfiguration? {
  self.language_configuration_in_current_path.map(i => {
    self.language_configurations[i]
  })
}

///|
pub async fn Loader::find_language_configurations_at_path(
  self : Loader,
  parser_path : String,
  set_current_path_config : Bool,
) -> Array[LanguageConfiguration] {
  let initial_language_configuration_count = self.language_configurations.length()
  let config = try TreeSitterJSON::from_file(parser_path) catch {
    Serialization(e) => {
      warn(
        "Failed to parse \{@support.path_join(parser_path, "tree-sitter.json")} -- \{e}",
      )
      None
    }
    _ => None
  } noraise {
    c => Some(c)
  }
  if config is Some(config) {
    let language_count = self.languages_by_id.length()
    for grammar in config.grammars {
      // Determine the path to the parser directory. This can be specified
      // in the tree-sitter.json, but defaults to the directory containing
      // the tree-sitter.json.
      let language_path = @support.path_join(
        parser_path,
        grammar.path.unwrap_or("."),
      )
      // Determine if a previous language configuration in this
      // tree-sitter.json file already uses the same language.
      let mut language_id = None
      for id in language_count..<self.languages_by_id.length() {
        if @support.path_eq(language_path, self.languages_by_id[id].path) {
          language_id = Some(id)
        }
      }
      let language_id = match language_id {
        Some(id) => id
        None => {
          let external_files = match grammar.external_files.into_vec() {
            Some(files) =>
              Some(
                files.map(path => {
                  let path = @support.path_join(parser_path, path)
                  // prevent p being above/outside of parser_path
                  if @support.path_starts_with(path, parser_path) {
                    path
                  } else {
                    raise ExternalFile(path, parser_path)
                  }
                }),
              )
            None => None
          }
          self.languages_by_id.push({
            path: language_path,
            language: None,
            external_files,
          })
          self.languages_by_id.length() - 1
        }
      }
      let configuration = LanguageConfiguration::{
        root_path: parser_path,
        language_name: grammar.name,
        scope: Some(grammar.scope),
        language_id,
        file_types: grammar.file_types.unwrap_or([]),
        content_regex: make_regex(grammar.content_regex),
        first_line_regex: make_regex(grammar.first_line_regex),
        injection_regex: make_regex(grammar.injection_regex),
        injections_filenames: grammar.injections.into_vec(),
        locals_filenames: grammar.locals.into_vec(),
        tags_filenames: grammar.tags.into_vec(),
        highlights_filenames: grammar.highlights.into_vec(),
        highlight_config: None,
        tags_config: None,
        highlight_names: self.highlight_names,
        use_all_highlight_names: self.use_all_highlight_names,
      }
      for file_type in configuration.file_types {
        match self.language_configuration_ids_by_file_type.get(file_type) {
          Some(ids) => ids.push(self.language_configurations.length())
          None =>
            self.language_configuration_ids_by_file_type[file_type] = [
              self.language_configurations.length(),
            ]
        }
      }
      if configuration.first_line_regex is Some(first_line_regex) {
        let key = first_line_regex.pattern
        match self.language_configuration_ids_by_first_line_regex.get(key) {
          Some(ids) => ids.push(self.language_configurations.length())
          None =>
            self.language_configuration_ids_by_first_line_regex[key] = [
              self.language_configurations.length(),
            ]
        }
      }
      self.language_configurations.push(configuration)
      if set_current_path_config &&
        self.language_configuration_in_current_path is None {
        self.language_configuration_in_current_path = Some(
          self.language_configurations.length() - 1,
        )
      }
    }
  }
  // If we didn't find any language configurations in the tree-sitter.json
  // file, but there is a grammar.json file, then use the grammar file to
  // form a simple language configuration.
  let grammar_path = @support.path_join(parser_path, "src/grammar.json")
  if self.language_configurations.length() ==
    initial_language_configuration_count &&
    @fs.exists(grammar_path) {
    let language_name = Loader::grammar_json_name(grammar_path)
    let configuration = LanguageConfiguration::{
      root_path: parser_path,
      language_name,
      language_id: self.languages_by_id.length(),
      file_types: [],
      scope: None,
      content_regex: None,
      first_line_regex: None,
      injection_regex: None,
      injections_filenames: None,
      locals_filenames: None,
      highlights_filenames: None,
      tags_filenames: None,
      highlight_config: None,
      tags_config: None,
      highlight_names: self.highlight_names,
      use_all_highlight_names: self.use_all_highlight_names,
    }
    self.language_configurations.push(configuration)
    self.languages_by_id.push({
      path: parser_path,
      language: None,
      external_files: None,
    })
  }
  self.language_configurations[initial_language_configuration_count:].to_owned()
}

///|
/// `Loader::regex`: a multi-line `regex::Regex`, or `None` if the pattern is
/// invalid.
fn make_regex(pattern : String?) -> LoaderRegex? {
  guard pattern is Some(pattern) else { return None }
  let regex = @regex.Regex::new("(?m)" + pattern, utf8=true) catch {
    _ => return None
  }
  Some({ pattern, regex, })
}

///|
/// `grammar_name`: matches `"name":\s*"(.*?)"`, returning the capture.
fn grammar_name(json_text : String) -> String? {
  guard json_text.find("\"name\":") is Some(i) else { return None }
  let rest = json_text.unsafe_substring(start=i + 7, end=json_text.length())
  let rest = rest.trim_start().to_owned()
  guard rest.has_prefix("\"") else { return None }
  let rest = rest.unsafe_substring(start=1, end=rest.length())
  guard rest.find("\"") is Some(end) else { return None }
  Some(rest.unsafe_substring(start=0, end~))
}

///|
/// `grammar_json_name`: the name in the first three lines of `grammar.json`.
pub async fn Loader::grammar_json_name(grammar_path : String) -> String {
  let reader = LineReader::open(grammar_path) catch {
    e => raise IO(@support.io_error_with_path(e, Some(grammar_path)))
  }
  defer reader.close()
  // `BufReader::new(file).lines().take(3).collect::<Result<Vec<_>, _>>()`
  let lines = []
  for _ in 0..<3 {
    match (reader.next_line() catch { _ => raise GrammarJSON(grammar_path) }) {
      Some(line) => lines.push(line)
      None => break
    }
  }
  let first_three_lines = lines.join("\n")
  match grammar_name(first_three_lines) {
    Some(name) => name
    None => raise GrammarJSON(grammar_path)
  }
}

///|
pub async fn Loader::select_language(
  self : Loader,
  path : String?,
  current_dir : String,
  scope : String?,
) -> @treesitter.Language {
  if scope is Some(scope) {
    match
      (self.language_configuration_for_scope(scope) catch {
        e => raise ScopeLoad(scope, to_loader_error(e))
      }) {
      Some(config) => return config.0
      None => raise UnknownScope(scope)
    }
  }
  if path is Some(path) {
    let found = self.language_configuration_for_file_name(path) catch {
      e =>
        raise FileNameLoad(
          @support.file_name(path).unwrap_or(path),
          to_loader_error(e),
        )
    }
    if found is Some((lang, _)) {
      return lang
    }
  }
  if self.language_configuration_in_current_path is Some(id) {
    return self.language_for_id(self.language_configurations[id].language_id)
  }
  let languages = self.languages_at_path(current_dir) catch {
    e => raise CurrentDirectoryLoad(to_loader_error(e))
  }
  if languages.get(0) is Some(lang) {
    return lang.0
  }
  if path is Some(path) {
    if self.language_configuration_for_first_line_regex(path) is Some(lang) {
      return lang.0
    }
  }
  raise NoLanguage
}

///|
pub fn Loader::debug_build(self : Loader, flag : Bool) -> Unit {
  self.debug_build = flag
}

///|
pub fn Loader::sanitize_build(self : Loader, flag : Bool) -> Unit {
  self.sanitize_build = flag
}

///|
pub fn Loader::force_rebuild(self : Loader, rebuild : Bool) -> Unit {
  self.force_rebuild = rebuild
}

///|
pub async fn Loader::highlight_config_for_injection_string(
  self : Loader,
  string : String,
) -> @highlight.HighlightConfiguration? {
  let found = self.language_configuration_for_injection_string(string) catch {
    e => {
      (info_hook.val)(
        "Error: Failed to load language for injection string '\{string}': \{e}",
      )
      return None
    }
  }
  match found {
    None => None
    Some((language, configuration)) =>
      configuration.highlight_config(language, None) catch {
        e => {
          (info_hook.val)(
            "Error: Failed to load highlight config for injection string '\{string}': \{e}",
          )
          None
        }
      }
  }
}

///|
pub async fn LanguageConfiguration::highlight_config(
  self : LanguageConfiguration,
  language : @treesitter.Language,
  paths : Array[String]?,
) -> @highlight.HighlightConfiguration? {
  if self.highlight_config is Some(config) {
    return config
  }
  let ends_with = (p : String, name : String) => {
    @support.file_name(p) == Some(name)
  }
  let (highlights_filenames, injections_filenames, locals_filenames) = match
    paths {
    Some(paths) =>
      (
        Some(
          paths.filter(p => ends_with(p, default_highlights_query_file_name)),
        ),
        Some(paths.filter(p => ends_with(p, default_tags_query_file_name))),
        Some(paths.filter(p => ends_with(p, default_locals_query_file_name))),
      )
    None => (None, None, None)
  }
  let (highlights_query, highlight_ranges) = self.read_queries(
    if highlights_filenames is Some(_) {
      highlights_filenames
    } else {
      self.highlights_filenames
    },
    default_highlights_query_file_name,
  )
  let (injections_query, injection_ranges) = self.read_queries(
    if injections_filenames is Some(_) {
      injections_filenames
    } else {
      self.injections_filenames
    },
    default_injections_query_file_name,
  )
  let (locals_query, locals_ranges) = self.read_queries(
    if locals_filenames is Some(_) {
      locals_filenames
    } else {
      self.locals_filenames
    },
    default_locals_query_file_name,
  )
  let result = if highlights_query.is_empty() {
    None
  } else {
    let config = @highlight.HighlightConfiguration::new(
      language,
      self.language_name,
      highlights_query,
      injections_query,
      locals_query,
    ) catch {
      error =>
        if error.kind() is Language {
          raise Query(error, None)
        } else if error.offset() < utf8_len(injections_query) {
          raise include_path_in_query_error(
            error, injection_ranges, injections_query, 0,
          )
        } else if error.offset() <
          utf8_len(injections_query) + utf8_len(locals_query) {
          raise include_path_in_query_error(
            error,
            locals_ranges,
            locals_query,
            utf8_len(injections_query),
          )
        } else {
          raise include_path_in_query_error(
            error,
            highlight_ranges,
            highlights_query,
            utf8_len(injections_query) + utf8_len(locals_query),
          )
        }
    }
    let all_highlight_names = self.highlight_names.val
    if self.use_all_highlight_names {
      for capture_name in config.query.capture_names() {
        if !all_highlight_names.contains(capture_name) {
          all_highlight_names.push(capture_name)
        }
      }
    }
    config.configure(all_highlight_names)
    Some(config)
  }
  self.highlight_config = Some(result)
  result
}

///|
pub async fn LanguageConfiguration::tags_config(
  self : LanguageConfiguration,
  language : @treesitter.Language,
) -> @tags.TagsConfiguration? {
  if self.tags_config is Some(config) {
    return config
  }
  let (tags_query, tags_ranges) = self.read_queries(
    self.tags_filenames,
    default_tags_query_file_name,
  )
  let (locals_query, locals_ranges) = self.read_queries(
    self.locals_filenames,
    default_locals_query_file_name,
  )
  let result = if tags_query.is_empty() {
    None
  } else {
    Some(
      @tags.TagsConfiguration::new(language, tags_query, locals_query) catch {
        @tags.TagsError::Query(error) =>
          if error.offset() < utf8_len(locals_query) {
            raise include_path_in_query_error(
              error, locals_ranges, locals_query, 0,
            )
          } else {
            raise include_path_in_query_error(
              error,
              tags_ranges,
              tags_query,
              utf8_len(locals_query),
            )
          }
        error => raise Tags(error)
      },
    )
  }
  self.tags_config = Some(result)
  result
}

///|
fn utf8_len(s : String) -> Int32 {
  @support.utf8_len(s)
}

///|
/// `include_path_in_query_error`: offsets are byte offsets into the
/// concatenated query text.
fn include_path_in_query_error(
  error : @treesitter.QueryError,
  ranges : Array[(String, Int32, Int32)],
  source : String,
  start_offset : Int32,
) -> LoaderError {
  let offset_within_section = error.offset() - start_offset
  let (path, range_start, _) = match
    ranges.search_by(r => {
      r.1 <= offset_within_section && offset_within_section < r.2
    }) {
    Some(i) => ranges[i]
    None => ranges[ranges.length() - 1]
  }
  let bytes = @support.utf8(source)
  let mut row = 0
  for i in range_start..<offset_within_section {
    if i < bytes.length() && bytes[i] == b'\n' {
      row += 1
    }
  }
  let error = @treesitter.QueryError::QueryError(
    row~,
    column=error.column(),
    offset=offset_within_section - range_start,
    message=error.message(),
    kind=error.kind(),
  )
  Query(error, Some(path))
}

///|
/// `read_queries`: the concatenated query text and the byte range of each
/// file in it.
async fn LanguageConfiguration::read_queries(
  self : LanguageConfiguration,
  paths : Array[String]?,
  default_path : String,
) -> (String, Array[(String, Int32, Int32)]) {
  let query = StringBuilder()
  let mut query_len = 0
  let path_ranges = []
  match paths {
    Some(paths) =>
      for path in paths {
        let abs_path = @support.path_join(self.root_path, path)
        let prev_query_len = query_len
        let text = @support.read_to_string(abs_path) catch {
          e => raise IO(@support.io_error_with_path(e, Some(abs_path)))
        }
        query.write_string(text)
        query_len += utf8_len(text)
        path_ranges.push((path, prev_query_len, query_len))
      }
    None => {
      // highlights.scm is needed to test highlights, and tags.scm to test
      // tags
      if default_path == default_highlights_query_file_name ||
        default_path == default_tags_query_file_name {
        warn(
          "You should add a `\{default_path.replace(old=".scm", new="")}` entry pointing to the \{default_path} path in the `tree-sitter` object in the grammar's tree-sitter.json file. See more here: https://tree-sitter.github.io/tree-sitter/3-syntax-highlighting#query-paths",
        )
      }
      let queries_path = @support.path_join(self.root_path, "queries")
      let path = @support.path_join(queries_path, default_path)
      if @fs.exists(path) {
        let text = @support.read_to_string(path) catch {
          e => raise IO(@support.io_error_with_path(e, Some(path)))
        }
        query.write_string(text)
        query_len = utf8_len(text)
        path_ranges.push((default_path, 0, query_len))
      }
    }
  }
  (query.to_string(), path_ranges)
}

///|
/// A synchronous `highlight_config_for_injection_string` for the
/// highlighter's injection callback. Loading a language is asynchronous in
/// MoonBit, so strings that have not been resolved yet return `None` and are
/// recorded; callers resolve them with `resolve_pending_injections` and
/// highlight again until nothing is pending, which gives the same result as
/// loading on demand.
pub fn Loader::injection_callback(
  self : Loader,
) -> (String) -> @highlight.HighlightConfiguration? {
  string => {
    match self.injection_cache.get(string) {
      Some(config) => config
      None => {
        if !self.pending_injections.contains(string) {
          self.pending_injections.push(string)
        }
        None
      }
    }
  }
}

///|
pub fn Loader::has_pending_injections(self : Loader) -> Bool {
  !self.pending_injections.is_empty()
}

///|
pub async fn Loader::resolve_pending_injections(self : Loader) -> Unit {
  let pending = self.pending_injections.copy()
  self.pending_injections.clear()
  for string in pending {
    self.injection_cache[string] = self.highlight_config_for_injection_string(
      string,
    )
  }
}

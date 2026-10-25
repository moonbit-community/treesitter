// Port of tree-sitter crates/cli/src/main.rs: the command implementations
// (`impl <Command> { fn run }`), `main` and `run`. The command line
// definitions are in next/cli/commands, parsed by next/clap.
//
// MoonBit-specific differences:
// - `build` emits a MoonBit module with the language tables (see `run_build`)
//   instead of compiling a dynamic library; `--wasm` is unsupported.
// - `--lib-path` names a language table file (`language.json`), the port's
//   equivalent of a compiled parser library.
// - `playground` needs a Wasm build of the parser and is unsupported.
// - Ctrl-C cancellation (`cancel_on_signal`) is not implemented.

///|
/// `get_lib_info`: the language file and language name.
fn get_lib_info(
  lib_path : String?,
  language_name : String?,
  current_dir : String,
) -> (String, String)? {
  guard lib_path is Some(lib_path) else { return None }
  let absolute_lib_path = if @support.is_absolute(lib_path) {
    lib_path
  } else {
    @support.path_join(current_dir, lib_path)
  }
  // Use the user-specified name if present, otherwise try to derive it from
  // the lib path
  match (language_name, @support.file_stem(lib_path)) {
    (Some(name), _) | (None, Some(name)) => Some((absolute_lib_path, name))
    _ => None
  }
}

///|
/// `Loader::select_language` with `lib_info`.
async fn select_language(
  loader : @loader.Loader,
  path : String?,
  current_dir : String,
  scope : String?,
  lib_info : (String, String)?,
) -> @api.Language {
  match lib_info {
    Some((lib_path, language_name)) =>
      loader.load_language_file(lib_path, language_name)
    None => loader.select_language(path, current_dir, scope)
  }
}

///|
/// Parse a range string of the form "start:end".
fn parse_range(range_str : String?) -> (Int, Int)? raise CliError {
  guard range_str is Some(range) else { return None }
  let err_msg = "Invalid range '\{range}', expected 'start:end'"
  let parts = range.split(":").map(p => p.to_owned()).collect()
  guard parts.length() >= 1 && parse_usize(parts[0]) is Some(start) else {
    raise anyhow(err_msg)
  }
  guard parts.length() >= 2 && parse_usize(parts[1]) is Some(end) else {
    raise anyhow(err_msg)
  }
  Some((start, end))
}

///|
fn wasm_unsupported() -> CliError {
  anyhow(
    "--wasm flag specified, but this build of tree-sitter-cli does not include the wasm feature",
  )
}

///|
fn parse_encoding(value : String?) -> InputEncoding? {
  match value {
    Some("utf8") => Some(Utf8)
    Some("utf16-le") => Some(Utf16LE)
    Some("utf16-be") => Some(Utf16BE)
    _ => None
  }
}

///|
async fn load_loader_config(config : @config.Config) -> @loader.LoaderConfig {
  @loader.LoaderConfig::from_json(config.get())
}

///|
async fn init_config_run() -> Unit {
  if @config.Config::find_config_file() is Some(config_path) {
    raise anyhow("Remove your existing config file first: \{config_path}")
  }
  let config = @config.Config::initial()
  config.add(@loader.LoaderConfig::initial().to_json())
  config.add({ "theme": Theme::default().to_json() })
  config.save()
  @support.log_info("Saved initial configuration to \{config.location}")
}

///|
async fn generate_run(
  m : @clap.ArgMatches,
  current_dir : String,
) -> Unit {
  if m.get_flag("log") {
    @support.enable_debug()
  }
  let abi_version = match m.get_one("abi_version") {
    None => @commands.default_generate_abi_version
    Some("latest") => @commands.language_version
    Some(version) =>
      match parse_usize(version) {
        Some(v) => v
        None => abort("invalid abi version flag")
      }
  }
  let json_summary = if m.get_flag("json") {
    @support.log_warn("--json is deprecated, use --json-summary instead")
    true
  } else {
    m.get_flag("json_summary")
  }
  let js_runtime = m.get_one("js_runtime")
  if js_runtime == Some("native") {
    // The `qjs-rt` QuickJS runtime is not available in the MoonBit port.
    raise with_context(
      anyhow("The native QuickJS runtime is not available in the MoonBit port"),
      "Error when generating parser",
    )
  }
  let diagnostics = []
  let result = generate_parser_in_directory(
    current_dir,
    m.get_one("output"),
    m.get_one("grammar_path"),
    abi_version,
    m.get_one("report_states_for_rule"),
    js_runtime,
    !m.get_flag("no_parser"),
    if m.get_flag("disable_optimizations") {
      { merge_states: false }
    } else {
      @generate.default_opt_level
    },
    diagnostics,
  ) catch {
    e => Err(e)
  } noraise {
    _ => Ok(())
  }
  if json_summary {
    let error = match result {
      Ok(_) => Json::null()
      Err(GenerateError(variant~, message~)) =>
        Json::object(Map::from_array([(variant, Json::string(message))]))
      Err(e) => { "Prepare": Json::string(error_message(e)) }
    }
    let envelope : Json = {
      "diagnostics": Json::array(diagnostics.map(diagnostic_json)),
      "error": error,
    }
    @support.print_err(@support.to_string_pretty(envelope) + "\n")
    if result is Err(_) {
      // Exit early to prevent errors from being printed a second time in
      // the caller
      @support.exit(1)
    }
  } else {
    for d in diagnostics {
      @support.log_warn(d.to_string())
    }
    if result is Err(err) {
      // Removes extra context associated with the error
      raise with_context(anyhow(error_message(err)), "Error when generating parser")
    }
  }
  if m.get_flag("build") {
    @support.log_warn("--build is deprecated, use the `build` command")
    let loader = match m.get_one("libdir") {
      Some(path) => @loader.Loader::with_parser_lib_path(path)
      None => @loader.Loader::new()
    }
    loader.debug_build(m.get_flag("debug_build"))
    ignore(loader.languages_at_path(current_dir))
  }
}

///|
/// `Serialize for Diagnostic` (externally tagged).
fn diagnostic_json(d : @generate.Diagnostic) -> Json {
  let opt = (s : String?) => match s {
    Some(s) => Json::string(s)
    None => Json::null()
  }
  match d {
    UnnecessaryConflicts(conflicts) =>
      {
        "UnnecessaryConflicts": Json::array(
          conflicts.map(c => Json::array(c.map(Json::string))),
        ),
      }
    UnaryChoice(name~) => { "UnaryChoice": { "name": opt(name) } }
    UnarySeq(name~) => { "UnarySeq": { "name": opt(name) } }
    UnsupportedRegexFlag(flag~, pattern~) =>
      {
        "UnsupportedRegexFlag": {
          "flag": Json::string(flag.to_string()),
          "pattern": Json::string(pattern),
        },
      }
    SupertypeInlined(name~) =>
      { "SupertypeInlined": { "name": Json::string(name) } }
  }
}

///|
/// `build`: write a MoonBit module that constructs the grammar's language
/// tables (`pub fn language() -> @language.Language raise`), for embedding a
/// parser in a MoonBit program. Upstream compiles a dynamic library or a
/// Wasm module here; those do not exist for MoonBit.
async fn build_run(
  m : @clap.ArgMatches,
  loader : @loader.Loader,
  current_dir : String,
) -> Unit {
  let grammar_path = @support.path_join(
    current_dir,
    m.get_one("path").unwrap_or(""),
  )
  if m.get_flag("wasm") {
    raise anyhow("Building Wasm modules is not supported by the MoonBit port")
  }
  loader.debug_build(m.get_flag("debug"))
  let output_path = match m.get_one("output") {
    Some(path) => {
      let full_path = if @support.is_absolute(path) {
        path
      } else {
        @support.path_join(current_dir, path)
      }
      guard @support.parent(full_path) is Some(parent_path) else {
        raise anyhow("Output path must have a parent")
      }
      @support.create_dir_all(if parent_path.is_empty() { "." } else { parent_path }) catch {
        e => raise with_context(e, "Failed to create output path")
      }
      full_path
    }
    None => {
      let stem = @support.file_stem(
        if grammar_path.has_suffix("/") {
          grammar_path.unsafe_substring(start=0, end=grammar_path.length() - 1)
        } else {
          grammar_path
        },
      ).unwrap_or("")
      let file_name = if stem.has_prefix("tree-sitter-") {
        stem.unsafe_substring(start=12, end=stem.length())
      } else {
        "parser"
      }
      @support.path_join(current_dir, file_name + ".mbt")
    }
  }
  loader.force_rebuild(true)
  let language = loader.language_tables_at_path(
    @support.path_join(grammar_path, "src"),
  ) catch {
    e => raise with_context(e, "Failed to compile parser")
  }
  if m.get_flag("verbose") {
    @support.log_info("[\{current_dir}] writing \{output_path}")
  }
  let json = language.to_json().stringify()
  let source = "///|\n// Generated by `tree-sitter build` (moonbit-community/treesitter). Do not edit.\n// Requires the packages moonbit-community/treesitter/language and\n// moonbitlang/core/json.\npub fn language() -> @language.Language raise {\n  @json.from_json(\n    @json.parse(\n      #|\{json}\n    ),\n  )\n}\n"
  @fs.write_file(output_path, source, create_mode=CreateOrTruncate) catch {
    e => raise with_context(e, "Failed to compile parser")
  }
}

///|
async fn parse_run(
  m : @clap.ArgMatches,
  loader : @loader.Loader,
  current_dir : String,
) -> Unit {
  let config = @config.Config::load(m.get_one("config_path"))
  let json_summary = if m.get_flag("json") {
    @support.log_warn("--json is deprecated, use --json-summary instead")
    true
  } else {
    m.get_flag("json_summary")
  }
  let output = if m.get_flag("output_dot") {
    ParseOutput::Dot
  } else if m.get_flag("output_xml") {
    Xml
  } else if m.get_flag("output_cst") {
    Cst
  } else if m.get_flag("quiet") || json_summary {
    Quiet
  } else {
    Normal
  }
  let parse_theme = if @support.color_enabled() {
    ParseTheme::from_config(config.get()) catch {
      e => raise with_context(e, "Failed to parse CST theme")
    }
  } else {
    ParseTheme::empty()
  }
  let encoding = parse_encoding(m.get_one("encoding"))
  let time = m.get_flag("time")
  let edits = m.get_many("edits").unwrap_or([])
  let parser = @api.Parser::new()
  loader.debug_build(m.get_flag("debug_build"))
  loader.force_rebuild(m.get_flag("rebuild") || m.contains_id("grammar_path"))
  if m.get_flag("wasm") {
    raise wasm_unsupported()
  }
  let timeout = match m.get_one("timeout") {
    Some(t) => @string.parse_uint64(t) catch { _ => 0UL }
    None => 0UL
  }
  let mut has_error = false
  let should_track_stats = m.get_flag("stat")
  let stats = ParseStats::default()
  let debug = if m.value_source("debug") is Some(CommandLine) {
    match m.get_one("debug") {
      None => ParseDebugType::Normal
      Some("quiet") => Quiet
      Some("normal") => Normal
      Some(_) => Pretty
    }
  } else {
    Quiet
  }
  let options : ParseFileOptions = {
    edits,
    output,
    print_time: time,
    timeout,
    stats,
    debug,
    debug_graph: m.get_flag("debug_graph"),
    encoding,
    open_log: m.get_flag("open_log"),
    no_ranges: m.get_flag("no_ranges"),
    parse_theme,
  }
  let update_stats = (stats : ParseStats) => {
    let parse_result = stats.parse_summaries[stats.parse_summaries.length() - 1]
    if should_track_stats || json_summary {
      stats.cumulative_stats.total_parses += 1
      if parse_result.successful {
        stats.cumulative_stats.successful_parses += 1
      }
      if parse_result.duration is Some(duration) &&
        parse_result.bytes is Some(bytes) {
        stats.cumulative_stats.total_bytes += bytes
        stats.cumulative_stats.total_duration += duration
      }
    }
    has_error = has_error || !parse_result.successful
  }
  let lib_info = get_lib_info(
    m.get_one("lib_path"),
    m.get_one("lang_name"),
    current_dir,
  )
  if lib_info is None {
    let loader_config = load_loader_config(config)
    loader.find_all_languages(loader_config)
  }
  let input = get_input(
    m.get_one("paths_file"),
    m.get_many("paths"),
    test_number(m),
    current_dir,
  )
  let scope = m.get_one("scope")
  match input {
    Paths(paths) => {
      let mut max_path_length = 0
      for p in paths {
        max_path_length = max_path_length.max(@support.char_count(p))
      }
      options.stats.source_count = paths.length()
      for path in paths {
        let language = select_language(
          loader,
          Some(path),
          current_dir,
          scope,
          lib_info,
        ) catch {
          e =>
            raise with_context(
              e,
              "Failed to load language for path \"\{path}\"",
            )
        }
        parse_file_at_path(parser, language, path, path, max_path_length, options)
        update_stats(options.stats)
      }
    }
    Test(name~, contents~, languages=language_names) => {
      let path = get_tmp_source_file(contents)
      let languages = loader.languages_at_path(current_dir)
      let language = match m.get_one("lib_path") {
        Some(lib_path) =>
          select_language(loader, None, current_dir, scope, lib_info) catch {
            e =>
              raise with_context(
                e,
                "Failed to load language for path \"\{lib_path}\"",
              )
          }
        None => pick_test_language(languages, language_names)
      }
      parse_file_at_path(
        parser,
        language,
        path,
        name,
        @support.char_count(name),
        options,
      )
      update_stats(stats)
      @fs.remove(path)
    }
    Stdin(contents) => {
      // Place user input and parser output on separate lines
      @support.print_out("\n")
      let path = get_tmp_source_file(contents)
      let name = "stdin"
      let language = select_language(loader, None, current_dir, scope, lib_info)
      parse_file_at_path(
        parser,
        language,
        path,
        name,
        @support.char_count(name),
        options,
      )
      update_stats(stats)
      @fs.remove(path)
    }
  }
  if should_track_stats {
    @support.print_out("\n\{stats.cumulative_stats}\n")
  }
  if json_summary {
    @support.print_out(@support.to_string_pretty(stats.to_json()) + "\n")
  }
  if has_error {
    raise anyhow("")
  }
}

///|
fn pick_test_language(
  languages : Array[(@api.Language, String)],
  language_names : Array[String],
) -> @api.Language raise CliError {
  for entry in languages {
    if language_names.contains(entry.1) {
      return entry.0
    }
  }
  match languages.get(0) {
    Some(entry) => entry.0
    None => raise anyhow("No language found")
  }
}

///|
fn test_number(m : @clap.ArgMatches) -> Int? {
  match m.get_one("test_number") {
    Some(n) => parse_usize(n)
    None => None
  }
}

///|
/// `check_test`: on error, print the summary and propagate the error.
async fn check_test(
  test_summary : TestSummary,
  json_summary : Bool,
  f : async () -> Unit,
) -> Unit {
  f() catch {
    e => {
      if json_summary {
        @support.print_out(
          @support.to_string_pretty(test_summary.to_json()) + "\n",
        )
      } else {
        @support.print_out("\{test_summary}\n")
      }
      raise e
    }
  }
}

///|
fn compile_regex(pattern : String?) -> @regex.Regex? {
  match pattern {
    Some(p) => Some(@regex.Regex::new(p, utf8=true)) catch { _ => None }
    None => None
  }
}

///|
async fn test_run(
  m : @clap.ArgMatches,
  loader : @loader.Loader,
  current_dir : String,
) -> Unit {
  let config = @config.Config::load(m.get_one("config_path"))
  let stat = match m.get_one("stat") {
    Some("all") => TestStats::All
    Some("total-only") => TotalOnly
    _ => OutliersAndTotal
  }
  loader.debug_build(m.get_flag("debug_build"))
  loader.force_rebuild(m.get_flag("rebuild") || m.contains_id("grammar_path"))
  let parser = @api.Parser::new()
  if m.get_flag("wasm") {
    raise wasm_unsupported()
  }
  let languages = loader.languages_at_path(current_dir)
  let language = match m.get_one("lib_path") {
    Some(lib_path) => {
      let lib_info = get_lib_info(
        m.get_one("lib_path"),
        m.get_one("lang_name"),
        current_dir,
      )
      select_language(loader, None, current_dir, None, lib_info) catch {
        e =>
          raise with_context(e, "Failed to load language for path \"\{lib_path}\"")
      }
    }
    None =>
      match languages.get(0) {
        Some(entry) => entry.0
        None => raise anyhow("No language found")
      }
  }
  parser.set_language(language)
  let test_dir = @support.path_join(current_dir, "test")
  let update = m.get_flag("update")
  let json_summary = m.get_flag("json_summary")
  let test_summary = TestSummary::new(
    stat,
    update,
    m.get_flag("overview_only"),
    json_summary,
  )
  test_summary.use_markers = m.get_flag("show_diff_markers")
  // Run the corpus tests. Look for them in `test/corpus`.
  let test_corpus_dir = @support.path_join(test_dir, "corpus")
  if is_dir(test_corpus_dir) {
    let opts : TestOptions = {
      path: test_corpus_dir,
      debug: m.get_flag("debug"),
      debug_graph: m.get_flag("debug_graph"),
      include: compile_regex(m.get_one("include")),
      exclude: compile_regex(m.get_one("exclude")),
      file_name: m.get_one("file_name"),
      update,
      open_log: m.get_flag("open_log"),
      languages: languages.map(entry => (entry.1, entry.0)),
      show_fields: m.get_flag("show_fields"),
      overview_only: m.get_flag("overview_only"),
    }
    check_test(test_summary, json_summary, () => run_tests_at_path(
      parser, opts, test_summary,
    ))
    test_summary.test_num = 1
  } else {
    @support.log_warn("Test corpus not found at \{test_corpus_dir}")
  }
  // Check that all of the queries are valid.
  let query_dir = @support.path_join(current_dir, "queries")
  if is_dir(query_dir) {
    check_test(test_summary, json_summary, () => check_queries_at_path(
      language, query_dir,
    ))
    test_summary.test_num = 1
  }
  // Run the syntax highlighting tests.
  let test_highlight_dir = @support.path_join(test_dir, "highlight")
  if is_dir(test_highlight_dir) {
    let highlighter = @highlight.Highlighter::new()
    let loader_config = load_loader_config(config)
    check_test(test_summary, json_summary, () => test_highlights(
      loader, loader_config, highlighter, test_highlight_dir, test_summary,
    ))
    test_summary.test_num = 1
  }
  let test_tag_dir = @support.path_join(test_dir, "tags")
  if is_dir(test_tag_dir) {
    let tags_context = @tags.TagsContext::new()
    let loader_config = load_loader_config(config)
    check_test(test_summary, json_summary, () => test_tags(
      loader, loader_config, tags_context, test_tag_dir, test_summary,
    ))
    test_summary.test_num = 1
  }
  // For the rest of the queries, find their tests and run them
  for entry in walk_files(query_dir) {
    let stem = @support.file_stem(entry).unwrap_or("")
    if stem != "highlights" && stem != "tags" {
      let entries = walk_files(@support.path_join(test_dir, stem))
      if !entries.is_empty() {
        test_summary.query_results.add_group(stem)
      }
      test_summary.test_num = 1
      let opts = QueryFileOptions::default()
      for path in entries {
        check_test(test_summary, json_summary, () => query_file_at_path(
          language,
          path,
          path,
          path,
          opts,
          Some(test_summary),
        ))
      }
      if !entries.is_empty() {
        test_summary.query_results.pop_traversal()
      }
    }
  }
  test_summary.test_num = 1
  if json_summary {
    @support.print_out(@support.to_string_pretty(test_summary.to_json()) + "\n")
  } else {
    @support.print_out("\{test_summary}\n")
  }
}

///|
async fn is_dir(path : String) -> Bool {
  (@fs.kind(path, follow_symlink=true) catch { _ => @fs.FileKind::Unknown })
  is Directory
}

///|
async fn fuzz_run(
  m : @clap.ArgMatches,
  loader : @loader.Loader,
  current_dir : String,
) -> Unit {
  loader.sanitize_build(true)
  loader.force_rebuild(m.get_flag("rebuild") || m.contains_id("grammar_path"))
  let languages = loader.languages_at_path(current_dir)
  let (language, language_name) = match m.get_one("lib_path") {
    Some(lib_path) => {
      guard get_lib_info(Some(lib_path), m.get_one("lang_name"), current_dir)
        is Some(lib_info) else {
        raise anyhow("No language name found for \{lib_path}")
      }
      let lang_name = lib_info.1
      (
        select_language(loader, None, current_dir, None, Some(lib_info)) catch {
          e =>
            raise with_context(
              e,
              "Failed to load language for path \"\{lib_path}\"",
            )
        },
        lang_name,
      )
    }
    None =>
      match languages.get(0) {
        Some(entry) => entry
        None => raise anyhow("No language found")
      }
  }
  let fuzz_options : @cli_test.FuzzOptions = {
    skipped: m.get_many("skip"),
    subdir: m.get_one("subdir"),
    edits: match m.get_one("edits") {
      Some(e) => parse_usize(e).unwrap_or(0)
      None => @cli_test.edit_count()
    },
    iterations: match m.get_one("iterations") {
      Some(e) => parse_usize(e).unwrap_or(0)
      None => @cli_test.iteration_count()
    },
    include: compile_regex(m.get_one("include")),
    exclude: compile_regex(m.get_one("exclude")),
    log_graphs: m.get_flag("log_graphs") || @cli_test.log_graph_enabled(),
    log: m.get_flag("log") || @cli_test.log_enabled(),
  }
  @cli_test.fuzz_language_corpus(
    language,
    language_name,
    @cli_test.start_seed(),
    current_dir,
    fuzz_options,
  )
}

///|
async fn query_run(
  m : @clap.ArgMatches,
  loader : @loader.Loader,
  current_dir : String,
) -> Unit {
  let config = @config.Config::load(m.get_one("config_path"))
  let lib_info = get_lib_info(
    m.get_one("lib_path"),
    m.get_one("lang_name"),
    current_dir,
  )
  if lib_info is None {
    let loader_config = load_loader_config(config)
    loader.find_all_languages(loader_config)
  }
  loader.force_rebuild(m.get_flag("rebuild") || m.contains_id("grammar_path"))
  let query_path = m.get_one("query_path").unwrap()
  let byte_range = parse_range(m.get_one("byte_range"))
  let point_range = parse_range(m.get_one("row_range")).map(r => (
    @api.Point::new(r.0, 0),
    @api.Point::new(r.1, 0),
  ))
  let containing_byte_range = parse_range(m.get_one("containing_byte_range"))
  let containing_point_range = parse_range(m.get_one("containing_row_range")).map(r => (
    @api.Point::new(r.0, 0),
    @api.Point::new(r.1, 0),
  ))
  let input = get_input(
    m.get_one("paths_file"),
    m.get_many("paths"),
    test_number(m),
    current_dir,
  )
  let opts = (stdin : Bool) => QueryFileOptions::{
    ordered_captures: m.get_flag("captures"),
    byte_range,
    point_range,
    containing_byte_range,
    containing_point_range,
    quiet: m.get_flag("quiet"),
    print_time: m.get_flag("time"),
    stdin,
  }
  match input {
    Paths(paths) => {
      let language = select_language(
        loader,
        Some(paths[0]),
        current_dir,
        m.get_one("scope"),
        lib_info,
      )
      for path in paths {
        query_file_at_path(language, path, path, query_path, opts(false), None)
      }
    }
    Test(name~, contents~, languages=language_names) => {
      let path = get_tmp_source_file(contents)
      let languages = loader.languages_at_path(current_dir)
      let language = match m.get_one("lib_path") {
        Some(lib_path) =>
          select_language(loader, None, current_dir, None, lib_info) catch {
            e =>
              raise with_context(
                e,
                "Failed to load language for path \"\{lib_path}\"",
              )
          }
        None => pick_test_language(languages, language_names)
      }
      query_file_at_path(language, path, name, query_path, opts(true), None)
      @fs.remove(path)
    }
    Stdin(contents) => {
      // Place user input and query output on separate lines
      @support.print_out("\n")
      let path = get_tmp_source_file(contents)
      let language = select_language(loader, None, current_dir, None, lib_info)
      query_file_at_path(language, path, "stdin", query_path, opts(true), None)
      @fs.remove(path)
    }
  }
}

///|
async fn first_language_in_current_path(
  loader : @loader.Loader,
  current_dir : String,
  language_names : Array[String]?,
) -> (@api.Language, @loader.LanguageConfiguration) {
  let languages = loader.languages_at_path(current_dir)
  let language = match language_names {
    Some(names) => {
      let mut found = None
      for entry in languages {
        if names.contains(entry.1) {
          found = Some(entry.0)
          break
        }
      }
      match found {
        Some(l) => l
        None =>
          match languages.get(0) {
            Some(e) => e.0
            None => raise anyhow("No language found in current path")
          }
      }
    }
    None =>
      match languages.get(0) {
        Some(e) => e.0
        None => raise anyhow("No language found in current path")
      }
  }
  guard loader.get_language_configuration_in_current_path() is Some(config) else {
    raise anyhow("No language configuration found in current path")
  }
  (language, config)
}

///|
async fn highlight_run(
  m : @clap.ArgMatches,
  loader : @loader.Loader,
  current_dir : String,
) -> Unit {
  let config = @config.Config::load(m.get_one("config_path"))
  let theme = theme_config_from_json(config.get())
  loader.configure_highlights(theme.highlight_names)
  let loader_config = load_loader_config(config)
  loader.find_all_languages(loader_config)
  loader.force_rebuild(m.get_flag("rebuild") || m.contains_id("grammar_path"))
  let mut language_and_config = None
  if m.get_one("scope") is Some(scope) {
    language_and_config = loader.language_configuration_for_scope(scope)
    if language_and_config is None {
      raise anyhow("Unknown scope '\{scope}'")
    }
  }
  let encoding = parse_encoding(m.get_one("encoding"))
  let style = if m.get_flag("css_classes") {
    @support.log_warn("--css-classes is deprecated, use --style classes instead")
    HtmlStyling::Classes
  } else {
    match m.get_one("style") {
      Some("inline") => Inline
      Some("minimal") => Minimal
      _ => Classes
    }
  }
  let layout = match m.get_one("layout") {
    Some("line-numbers") => HtmlOutput::NumberedDocument
    Some("fragment") => Fragment
    _ => Document
  }
  let options : HighlightOptions = {
    theme,
    check: m.get_flag("check"),
    captures_path: m.get_one("captures_path"),
    html: if m.get_flag("html") { Some((layout, style)) } else { None },
    quiet: m.get_flag("quiet"),
    print_time: m.get_flag("time"),
    encoding,
  }
  let query_paths = m.get_many("query_paths")
  let input = get_input(
    m.get_one("paths_file"),
    m.get_many("paths"),
    test_number(m),
    current_dir,
  )
  match input {
    Paths(paths) => {
      let print_name = paths.length() > 1
      for path in paths {
        let (language, language_config) = match language_and_config {
          Some(lc) => lc
          None =>
            match loader.language_configuration_for_file_name(path) {
              Some(lc) => lc
              None => {
                @support.log_warn(lang_not_found_for_path(path, loader_config))
                continue
              }
            }
        }
        match language_config.highlight_config(language, query_paths) {
          Some(highlight_config) =>
            highlight(loader, path, path, highlight_config, print_name, options)
          None =>
            @support.log_warn(
              "No syntax highlighting config found for path \{path}",
            )
        }
      }
    }
    Test(name~, contents~, languages=language_names) => {
      let path = get_tmp_source_file(contents)
      let (language, language_config) = first_language_in_current_path(
        loader,
        current_dir,
        Some(language_names),
      )
      match language_config.highlight_config(language, query_paths) {
        Some(highlight_config) =>
          highlight(loader, path, name, highlight_config, false, options)
        None =>
          @support.log_warn("No syntax highlighting config found for test \{name}")
      }
      @fs.remove(path)
    }
    Stdin(contents) => {
      // Place user input and highlight output on separate lines
      @support.print_out("\n")
      let path = get_tmp_source_file(contents)
      let (language, language_config) = match language_and_config {
        Some(lc) => lc
        None => first_language_in_current_path(loader, current_dir, None)
      }
      match language_config.highlight_config(language, query_paths) {
        Some(highlight_config) =>
          highlight(loader, path, "stdin", highlight_config, false, options)
        None =>
          @support.log_warn(
            "No syntax highlighting config found for path \{current_dir}",
          )
      }
      @fs.remove(path)
    }
  }
}

///|
async fn tags_run(
  m : @clap.ArgMatches,
  loader : @loader.Loader,
  current_dir : String,
) -> Unit {
  let config = @config.Config::load(m.get_one("config_path"))
  let loader_config = load_loader_config(config)
  loader.find_all_languages(loader_config)
  loader.force_rebuild(m.get_flag("rebuild") || m.contains_id("grammar_path"))
  let mut language_and_config = None
  let scope = m.get_one("scope")
  if scope is Some(scope) {
    language_and_config = loader.language_configuration_for_scope(scope)
    if language_and_config is None {
      raise anyhow("Unknown scope '\{scope}'")
    }
  }
  let options : TagsOptions = {
    scope,
    quiet: m.get_flag("quiet"),
    print_time: m.get_flag("time"),
  }
  let input = get_input(
    m.get_one("paths_file"),
    m.get_many("paths"),
    test_number(m),
    current_dir,
  )
  match input {
    Paths(paths) => {
      let indent = paths.length() > 1
      for path in paths {
        let (language, language_config) = match language_and_config {
          Some(lc) => lc
          None =>
            match loader.language_configuration_for_file_name(path) {
              Some(lc) => lc
              None => {
                @support.log_warn(lang_not_found_for_path(path, loader_config))
                continue
              }
            }
        }
        match language_config.tags_config(language) {
          Some(tags_config) =>
            generate_tags(path, path, tags_config, indent, options)
          None => @support.log_warn("No tags config found for path \{path}")
        }
      }
    }
    Test(name~, contents~, languages=language_names) => {
      let path = get_tmp_source_file(contents)
      let (language, language_config) = first_language_in_current_path(
        loader,
        current_dir,
        Some(language_names),
      )
      match language_config.tags_config(language) {
        Some(tags_config) => generate_tags(path, name, tags_config, false, options)
        None => @support.log_warn("No tags config found for test \{name}")
      }
      @fs.remove(path)
    }
    Stdin(contents) => {
      // Place user input and tags output on separate lines
      @support.print_out("\n")
      let path = get_tmp_source_file(contents)
      let (language, language_config) = match language_and_config {
        Some(lc) => lc
        None => first_language_in_current_path(loader, current_dir, None)
      }
      match language_config.tags_config(language) {
        Some(tags_config) =>
          generate_tags(path, "stdin", tags_config, false, options)
        None =>
          @support.log_warn("No tags config found for path \{current_dir}")
      }
      @fs.remove(path)
    }
  }
}

///|
async fn dump_languages_run(
  m : @clap.ArgMatches,
  loader : @loader.Loader,
) -> Unit {
  let config = @config.Config::load(m.get_one("config_path"))
  let loader_config = load_loader_config(config)
  loader.find_all_languages(loader_config)
  let debug_paths = (paths : Array[String]?) => match paths {
    Some(p) => "Some(\{@loader.rust_debug_strs(p)})"
    None => "None"
  }
  let debug_regex = (r : @loader.LoaderRegex?) => match r {
    Some(r) => "Some(\{r.debug()})"
    None => "None"
  }
  for entry in loader.get_all_language_configurations() {
    let (configuration, language_path) = entry
    @support.log_info(
      "name: \{configuration.language_name}\nscope: \{configuration.scope.unwrap_or("")}\nparser: \{language_path}\nhighlights: \{debug_paths(configuration.highlights_filenames)}\nfile_types: \{@loader.rust_debug_strs(configuration.file_types)}\ncontent_regex: \{debug_regex(configuration.content_regex)}\ninjection_regex: \{debug_regex(configuration.injection_regex)}\n",
    )
  }
}

///|
fn complete_run(m : @clap.ArgMatches) -> Unit {
  let cli = make_cli()
  let name = cli.get_name()
  let shell : @clap_complete.Shell = match m.get_one("shell") {
    Some("bash") => Bash
    Some("elvish") => Elvish
    Some("fish") => Fish
    Some("power-shell") => PowerShell
    Some("zsh") => Zsh
    _ => Nushell
  }
  @support.print_out(@clap_complete.generate(shell, cli, name))
}

///|
fn make_cli() -> @clap.Command {
  @commands.regex_validator.val = pattern => match
    (try Ok(@regex.Regex::new(pattern, utf8=true)) catch { e => Err(e) }) {
    Ok(_) => None
    Err(e) => Some(e.to_string())
  }
  @commands.semver_validator.val = v => match
    (try Ok(@loader.SemverVersion::parse(v)) catch { e => Err(e) }) {
    Ok(_) => None
    Err(e) => Some(e.to_string())
  }
  @commands.build_cli()
}

///|
/// `fn run()`: parse the command line and run the command. Returns the exit
/// status.
pub async fn run(
  args : Array[String],
  scanners? : @loader.ScannerRegistry,
  current_dir? : String,
) -> Int {
  let process_dir = match current_dir {
    Some(d) => d
    None => @env.current_dir().unwrap_or(".")
  }
  let cli = make_cli()
  let matches = cli.try_get_matches_from(args) catch {
    @clap.ClapError(_) as e => {
      if e.use_stderr() {
        @support.print_err(e.message())
      } else {
        @support.print_out(e.message())
      }
      return e.exit_code()
    }
  }
  guard matches.subcommand() is Some((command, m)) else { return 2 }
  let current_dir = match command {
    "init" | "parse" | "test" | "version" | "fuzz" | "query" | "highlight" | "tags"
    | "playground" =>
      match m.get_one("grammar_path") {
        Some(p) => p
        None => process_dir
      }
    _ => process_dir
  }
  let result = try
    Ok(
      run_command(command, m, current_dir, args, scanners.unwrap_or(_ => None)),
    )
  catch {
    e => Err(e)
  }
  match result {
    Ok(code) => code
    Err(_) if !@loader.required_mbtx_scanners.is_empty() => {
      let required = []
      for name, path in @loader.required_mbtx_scanners {
        required.push((name, path))
      }
      if @env.get_env_var(@loader.driver_env_var) is Some(_) {
        @support.log_error(
          "The MoonBit scanners \{required.map(r => r.1).join(", ")} are not registered in this driver",
        )
        1
      } else {
        @loader.run_with_scanners(required, args, process_dir) catch {
          e => {
            @support.log_error(with_context(e, "Failed to load the MoonBit external scanners").debug())
            1
          }
        }
      }
    }
    Err(err) => {
      let chain = CliError(error_chain(err))
      if !error_message(chain).is_empty() {
        @support.log_error(chain.debug())
      }
      1
    }
  }
}

///|
async fn run_command(
  command : String,
  m : @clap.ArgMatches,
  current_dir : String,
  args : Array[String],
  scanners : @loader.ScannerRegistry,
) -> Int {
  ignore(args)
  let loader = @loader.Loader::new()
  loader.set_scanners(scanners)
  match command {
    "init-config" => init_config_run()
    "init" => @init.run_init(current_dir, m.get_flag("update"))
    "generate" => generate_run(m, current_dir)
    "build" => build_run(m, loader, current_dir)
    "parse" => parse_run(m, loader, current_dir)
    "test" => test_run(m, loader, current_dir)
    "version" => {
      let version = match m.get_one("version") {
        Some(v) => Some(@loader.SemverVersion::parse(v))
        None => None
      }
      let bump = match m.get_one("bump") {
        Some("patch") => Some(@init.BumpLevel::Patch)
        Some("minor") => Some(Minor)
        Some("major") => Some(Major)
        _ => None
      }
      @init.Version::new(version, current_dir, bump).run()
    }
    "fuzz" => fuzz_run(m, loader, current_dir)
    "query" => query_run(m, loader, current_dir)
    "highlight" => highlight_run(m, loader, current_dir)
    "tags" => tags_run(m, loader, current_dir)
    "playground" =>
      raise anyhow(
        "The playground needs a Wasm build of the parser (web-tree-sitter), which the MoonBit port cannot produce",
      )
    "dump-languages" => dump_languages_run(m, loader)
    "complete" => complete_run(m)
    _ => ()
  }
  0
}

///|
/// `fn main()`: run the CLI and exit with its status.
pub async fn cli_main(args : Array[String], scanners? : @loader.ScannerRegistry) -> Unit {
  let code = run(args, scanners?)
  @support.flush()
  @support.exit(code)
}

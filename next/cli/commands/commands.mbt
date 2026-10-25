// Port of the clap derive definitions in tree-sitter crates/cli/src/main.rs
// (`Commands` and the argument structs), written as the builder calls
// clap_derive expands them to: doc comments become `help` (one paragraph,
// lines joined with spaces and a trailing period removed), fields get a
// `value_name` from their name, `Option<Vec<_>>` fields append values, and
// every argument gets the next display order.

///|
pub let build_version : String = "0.28.0"

///|
pub let default_generate_abi_version : Int32 = 15

///|
/// `tree_sitter::LANGUAGE_VERSION`.
pub let language_version : Int32 = 15

///|
let authors : String = "Max Brunsfeld <maxbrunsfeld@gmail.com>\nAmaan Qureshi <amaanq12@gmail.com>"

///|
/// The value parser of `Option<Regex>` fields. Set by the CLI, which owns
/// the regex engine; the default accepts every pattern.
pub let regex_validator : Ref[(String) -> String?] = Ref(_ => None)

///|
/// The value parser of `Option<semver::Version>` fields. Set by the CLI.
pub let semver_validator : Ref[(String) -> String?] = Ref(_ => None)

///|
fn flag(id : String) -> @clap.Arg {
  @clap.Arg::new(id).action(SetTrue)
}

///|
fn opt(id : String) -> @clap.Arg {
  @clap.Arg::new(id).action(Set)
}

///|
fn path_opt(id : String) -> @clap.Arg {
  opt(id).value_parser(PathBuf)
}

///|
fn regex_opt(id : String) -> @clap.Arg {
  opt(id).value_parser(Custom(pattern => (regex_validator.val)(pattern)))
}

///|
fn grammar_path_arg(help : String, short~ : Bool = true) -> @clap.Arg {
  let arg = path_opt("grammar_path").long("grammar-path").help(help)
  if short {
    arg.short('p')
  } else {
    arg
  }
}

///|
fn encoding_values() -> Array[@clap.PossibleValue] {
  [
    @clap.PossibleValue::new("utf8"),
    @clap.PossibleValue::new("utf16-le"),
    @clap.PossibleValue::new("utf16-be"),
  ]
}

///|
fn init_config_command() -> @clap.Command {
  @clap.Command::new("init-config").about("Generate a default config file")
}

///|
fn init_command() -> @clap.Command {
  @clap.Command::new("init")
  .alias("i")
  .about("Initialize a grammar repository")
  .arg(flag("update").long("update").short('u').help("Update outdated files"))
  .arg(grammar_path_arg("The path to the tree-sitter grammar directory"))
}

///|
fn generate_command() -> @clap.Command {
  let abi_help = "Select the language ABI version to generate (default \{default_generate_abi_version}).\nUse --abi=latest to generate the newest supported version (\{language_version})."
  @clap.Command::new("generate")
  .alias("gen")
  .alias("g")
  .about("Generate a parser")
  .arg(
    @clap.Arg::new("grammar_path")
    .index(1)
    .value_parser(PathBuf)
    .help("The path to the grammar file"),
  )
  .arg(
    flag("log").long("log").short('l').help("Show debug log during generation"),
  )
  .arg(
    opt("abi_version")
    .long("abi")
    .value_name("VERSION")
    .env("TREE_SITTER_ABI_VERSION", @env.get_env_var("TREE_SITTER_ABI_VERSION"))
    .help(abi_help),
  )
  .arg(
    flag("no_parser")
    .long("no-parser")
    .help("Only generate `grammar.json` and `node-types.json`"),
  )
  .arg(
    flag("build")
    .long("build")
    .short('b')
    .help("Deprecated: use the `build` command"),
  )
  .arg(
    flag("debug_build")
    .long("debug-build")
    .short('0')
    .help("Deprecated: use the `build` command"),
  )
  .arg(
    path_opt("libdir")
    .long("libdir")
    .value_name("PATH")
    .help("Deprecated: use the `build` command"),
  )
  .arg(
    path_opt("output")
    .long("output")
    .short('o')
    .value_name("DIRECTORY")
    .help("The path to output the generated source files"),
  )
  .arg(
    opt("report_states_for_rule")
    .long("report-states-for-rule")
    .conflicts_with("json")
    .conflicts_with("json_summary")
    .help(
      "Produce a report of the states for the given rule, use `-` to report every rule",
    ),
  )
  .arg(
    flag("json")
    .long("json")
    .conflicts_with("json_summary")
    .conflicts_with("report_states_for_rule")
    .help("Deprecated: use --json-summary"),
  )
  .arg(
    flag("json_summary")
    .long("json-summary")
    .conflicts_with("json")
    .conflicts_with("report_states_for_rule")
    .help("Report conflicts in a JSON format"),
  )
  .arg(
    opt("js_runtime")
    .long("js-runtime")
    .value_name("EXECUTABLE")
    .env("TREE_SITTER_JS_RUNTIME", @env.get_env_var("TREE_SITTER_JS_RUNTIME"))
    .default_value("node")
    .help(
      "The name or path of the JavaScript runtime to use for generating parsers, specify `native` to use the native `QuickJS` runtime",
    ),
  )
  .arg(
    flag("disable_optimizations")
    .long("disable-optimizations")
    .help(
      "Disable optimizations when generating the parser. Currently, this only affects the merging of compatible parse states",
    ),
  )
}

///|
/// `build`: in the MoonBit port it emits a MoonBit language module instead
/// of compiling a dynamic library; the command line is upstream's.
fn build_command() -> @clap.Command {
  @clap.Command::new("build")
  .alias("b")
  .about("Compile a parser")
  .arg(
    flag("wasm")
    .short('w')
    .long("wasm")
    .help("Build a Wasm module instead of a dynamic library"),
  )
  .arg(
    path_opt("output")
    .short('o')
    .long("output")
    .help("The path to output the compiled file"),
  )
  .arg(
    @clap.Arg::new("path")
    .index(1)
    .num_args(@clap.ValueRange::single())
    .value_parser(PathBuf)
    .help("The path to the grammar directory"),
  )
  .arg(
    flag("reuse_allocator")
    .long("reuse-allocator")
    .help("Make the parser reuse the same allocator as the library"),
  )
  .arg(
    flag("debug")
    .long("debug")
    .short('0')
    .help("Compile a parser in debug mode"),
  )
  .arg(
    flag("verbose")
    .short('v')
    .long("verbose")
    .help("Display verbose build information"),
  )
}

///|
fn lib_path_arg(short~ : Bool = true) -> @clap.Arg {
  let arg = path_opt("lib_path")
    .long("lib-path")
    .help("The path to the parser's dynamic library")
  if short {
    arg.short('l')
  } else {
    arg
  }
}

///|
fn lang_name_arg() -> @clap.Arg {
  opt("lang_name")
  .long("lang-name")
  .requires("lib_path")
  .help(
    "If `--lib-path` is used, the name of the language used to extract the library's language function",
  )
}

///|
fn parse_command() -> @clap.Command {
  @clap.Command::new("parse")
  .alias("p")
  .about("Parse files")
  .group(@clap.ArgGroup::new("graph_output").multiple(true))
  .arg(
    path_opt("paths_file")
    .long("paths")
    .help("The path to a file with paths to source file(s)"),
  )
  .arg(
    @clap.Arg::new("paths")
    .num_args(@clap.ValueRange::at_least(1))
    .action(Append)
    .value_parser(PathBuf)
    .help("The source file(s) to use"),
  )
  .arg(
    grammar_path_arg(
      "The path to the tree-sitter grammar directory, implies --rebuild",
    ).conflicts_with("rebuild"),
  )
  .arg(lib_path_arg())
  .arg(lang_name_arg())
  .arg(
    opt("scope")
    .long("scope")
    .help("Select a language by the scope instead of a file extension"),
  )
  .arg(
    opt("debug")
    .long("debug")
    .short('d')
    .num_args(@clap.ValueRange::new(0, 1))
    .value_parser(
      Enum([
        @clap.PossibleValue::new("quiet"),
        @clap.PossibleValue::new("normal"),
        @clap.PossibleValue::new("pretty"),
      ]),
    )
    .help("Show parsing debug log"),
  )
  .arg(
    flag("debug_build")
    .long("debug-build")
    .short('0')
    .help("Compile a parser in debug mode"),
  )
  .arg(
    flag("debug_graph")
    .long("debug-graph")
    .short('D')
    .group("graph_output")
    .help("Produce the log.html file with debug graphs"),
  )
  .arg(
    flag("wasm")
    .long("wasm")
    .hide(true)
    .help("Compile parsers to Wasm instead of native dynamic libraries"),
  )
  .arg(
    flag("output_dot")
    .long("dot")
    .group("graph_output")
    .help("Output the parse data with graphviz dot"),
  )
  .arg(
    flag("output_xml")
    .long("xml")
    .short('x')
    .help("Output the parse data in XML format"),
  )
  .arg(
    flag("output_cst")
    .long("cst")
    .short('c')
    .help("Output the parse data in a pretty-printed CST format"),
  )
  .arg(
    flag("stat")
    .long("stat")
    .short('s')
    .conflicts_with("json")
    .conflicts_with("json_summary")
    .help("Show parsing statistics"),
  )
  .arg(
    opt("timeout")
    .long("timeout")
    .value_parser(U64)
    .help("Interrupt the parsing process by timeout (µs)"),
  )
  .arg(flag("time").long("time").short('t').help("Measure execution time"))
  .arg(flag("quiet").long("quiet").short('q').help("Suppress main output"))
  .arg(
    @clap.Arg::new("edits")
    .long("edits")
    .action(Append)
    .num_args(@clap.ValueRange::at_least(1))
    .help(
      "Apply edits in the format: \\\"row,col|position delcount insert_text\\\", can be supplied multiple times",
    ),
  )
  .arg(
    opt("encoding")
    .long("encoding")
    .value_parser(Enum(encoding_values()))
    .help("The encoding of the input files"),
  )
  .arg(
    flag("open_log")
    .long("open-log")
    .requires("graph_output")
    .help(
      "Open `log.html` in the default browser, if `--debug-graph` or `--dot` is supplied",
    ),
  )
  .arg(
    flag("json")
    .long("json")
    .conflicts_with("json_summary")
    .conflicts_with("stat")
    .help("Deprecated: use --json-summary"),
  )
  .arg(
    flag("json_summary")
    .long("json-summary")
    .short('j')
    .conflicts_with("json")
    .conflicts_with("stat")
    .help("Output parsing results in a JSON format"),
  )
  .arg(config_path_arg())
  .arg(
    test_number_arg("Parse the contents of a specific test")
    .conflicts_with("paths")
    .conflicts_with("paths_file"),
  )
  .arg(rebuild_arg())
  .arg(flag("no_ranges").long("no-ranges").help("Omit ranges in the output"))
}

///|
fn config_path_arg() -> @clap.Arg {
  path_opt("config_path")
  .long("config-path")
  .help("The path to an alternative config.json file")
}

///|
fn test_number_arg(help : String) -> @clap.Arg {
  opt("test_number").long("test-number").short('n').value_parser(U32).help(help)
}

///|
fn rebuild_arg() -> @clap.Arg {
  flag("rebuild").short('r').long("rebuild").help("Force rebuild the parser")
}

///|
fn test_command() -> @clap.Command {
  @clap.Command::new("test")
  .alias("t")
  .about("Run a parser's tests")
  .arg(
    regex_opt("include")
    .long("include")
    .short('i')
    .help("Only run corpus test cases whose name matches the given regex"),
  )
  .arg(
    regex_opt("exclude")
    .long("exclude")
    .short('e')
    .help(
      "Only run corpus test cases whose name does not match the given regex",
    ),
  )
  .arg(
    opt("file_name")
    .long("file-name")
    .help("Only run corpus test cases from a given filename"),
  )
  .arg(
    grammar_path_arg(
      "The path to the tree-sitter grammar directory, implies --rebuild",
    ).conflicts_with("rebuild"),
  )
  .arg(lib_path_arg())
  .arg(lang_name_arg())
  .arg(
    flag("update")
    .long("update")
    .short('u')
    .help("Update all syntax trees in corpus files with current parser output"),
  )
  .arg(flag("debug").long("debug").short('d').help("Show parsing debug log"))
  .arg(
    flag("debug_build")
    .long("debug-build")
    .short('0')
    .help("Compile a parser in debug mode"),
  )
  .arg(
    flag("debug_graph")
    .long("debug-graph")
    .short('D')
    .help("Produce the log.html file with debug graphs"),
  )
  .arg(
    flag("wasm")
    .long("wasm")
    .hide(true)
    .help("Compile parsers to Wasm instead of native dynamic libraries"),
  )
  .arg(
    flag("open_log")
    .long("open-log")
    .requires("debug_graph")
    .help(
      "Open `log.html` in the default browser, if `--debug-graph` is supplied",
    ),
  )
  .arg(config_path_arg())
  .arg(
    flag("show_fields")
    .long("show-fields")
    .help("Force showing fields in test diffs"),
  )
  .arg(
    flag("show_diff_markers")
    .long("show-diff-markers")
    .help("Force showing '+' and '-' in test diffs"),
  )
  .arg(
    opt("stat")
    .long("stat")
    .value_parser(
      Enum([
        @clap.PossibleValue::new("all"),
        @clap.PossibleValue::new("outliers-and-total"),
        @clap.PossibleValue::new("total-only"),
      ]),
    )
    .help("Show parsing statistics"),
  )
  .arg(rebuild_arg())
  .arg(
    flag("overview_only")
    .long("overview-only")
    .help("Show only the pass-fail overview tree"),
  )
  .arg(
    flag("json_summary")
    .long("json-summary")
    .help("Output the test summary in a JSON format"),
  )
}

///|
fn version_command() -> @clap.Command {
  @clap.Command::new("version")
  .alias("publish")
  .about("Display or increment the version of a grammar")
  .arg(
    @clap.Arg::new("version")
    .conflicts_with("bump")
    .value_parser(Custom(v => (semver_validator.val)(v)))
    .help("The version to bump to")
    .long_help(
      "The version to bump to\n\nExamples:\n    tree-sitter version: display the current version\n    tree-sitter version <version>: bump to specified version\n    tree-sitter version --bump <level>: automatic bump",
    ),
  )
  .arg(grammar_path_arg("The path to the tree-sitter grammar directory"))
  .arg(
    opt("bump")
    .long("bump")
    .value_parser(
      Enum([
        @clap.PossibleValue::new("patch"),
        @clap.PossibleValue::new("minor"),
        @clap.PossibleValue::new("major"),
      ]),
    )
    .conflicts_with("version")
    .help("Automatically bump from the current version"),
  )
}

///|
fn fuzz_command() -> @clap.Command {
  @clap.Command::new("fuzz")
  .alias("f")
  .about("Fuzz a parser")
  .arg(
    @clap.Arg::new("skip")
    .long("skip")
    .short('s')
    .action(Append)
    .help("List of test names to skip"),
  )
  .arg(path_opt("subdir").long("subdir").help("Subdirectory to the language"))
  .arg(
    grammar_path_arg(
      "The path to the tree-sitter grammar directory, implies --rebuild",
    ).conflicts_with("rebuild"),
  )
  .arg(lib_path_arg(short=false))
  .arg(lang_name_arg())
  .arg(
    opt("edits")
    .long("edits")
    .value_parser(Usize)
    .help("Maximum number of edits to perform per fuzz test (Default: 3)"),
  )
  .arg(
    opt("iterations")
    .long("iterations")
    .value_parser(Usize)
    .help("Number of fuzzing iterations to run per test (Default: 10)"),
  )
  .arg(
    regex_opt("include")
    .long("include")
    .short('i')
    .help("Only fuzz corpus test cases whose name matches the given regex"),
  )
  .arg(
    regex_opt("exclude")
    .long("exclude")
    .short('e')
    .help(
      "Only fuzz corpus test cases whose name does not match the given regex",
    ),
  )
  .arg(
    flag("log_graphs")
    .long("log-graphs")
    .help("Enable logging of graphs and input"),
  )
  .arg(flag("log").long("log").short('l').help("Enable parser logging"))
  .arg(rebuild_arg())
}

///|
fn range_opt(id : String, long : String, help : String) -> @clap.Arg {
  opt(id).long(long).help(help)
}

///|
fn query_command() -> @clap.Command {
  @clap.Command::new("query")
  .alias("q")
  .about("Search files using a syntax tree query")
  .arg(
    @clap.Arg::new("query_path")
    .index(1)
    .required(true)
    .value_parser(PathBuf)
    .help("Path to a file with queries"),
  )
  .arg(
    grammar_path_arg(
      "The path to the tree-sitter grammar directory, implies --rebuild",
    ).conflicts_with("rebuild"),
  )
  .arg(lib_path_arg())
  .arg(lang_name_arg())
  .arg(flag("time").long("time").short('t').help("Measure execution time"))
  .arg(flag("quiet").long("quiet").short('q').help("Suppress main output"))
  .arg(
    path_opt("paths_file")
    .long("paths")
    .help("The path to a file with paths to source file(s)"),
  )
  .arg(
    @clap.Arg::new("paths")
    .index(2)
    .num_args(@clap.ValueRange::at_least(1))
    .action(Append)
    .value_parser(PathBuf)
    .help("The source file(s) to use"),
  )
  .arg(
    range_opt(
      "byte_range", "byte-range", "The range of byte offsets in which the query will be executed",
    ),
  )
  .arg(
    range_opt(
      "row_range", "row-range", "The range of rows in which the query will be executed",
    ),
  )
  .arg(
    range_opt(
      "containing_byte_range", "containing-byte-range", "The range of byte offsets in which the query will be executed. Only the matches that are fully contained within the provided byte range will be returned",
    ),
  )
  .arg(
    range_opt(
      "containing_row_range", "containing-row-range", "The range of rows in which the query will be executed. Only the matches that are fully contained within the provided row range will be returned",
    ),
  )
  .arg(
    opt("scope")
    .long("scope")
    .help("Select a language by the scope instead of a file extension"),
  )
  .arg(
    flag("captures")
    .long("captures")
    .short('c')
    .help("Order by captures instead of matches"),
  )
  .arg(flag("test").long("test").help("Whether to run query tests or not"))
  .arg(config_path_arg())
  .arg(
    test_number_arg("Query the contents of a specific test")
    .conflicts_with("paths")
    .conflicts_with("paths_file"),
  )
  .arg(rebuild_arg())
}

///|
fn highlight_command() -> @clap.Command {
  @clap.Command::new("highlight")
  .alias("hi")
  .about("Highlight a file")
  .arg(
    flag("html")
    .long("html")
    .short('H')
    .help("Generate highlighting as an HTML document"),
  )
  .arg(
    flag("css_classes")
    .long("css-classes")
    .requires("html")
    .conflicts_with("style")
    .help("Deprecated: use `--style classes`"),
  )
  .arg(
    opt("layout")
    .long("layout")
    .requires("html")
    .value_parser(
      Enum([
        @clap.PossibleValue::new(
          "document",
          help="A complete, self-contained document wrapping a plain `<div class=\"highlight\"><pre><code>` block",
        ),
        @clap.PossibleValue::new(
          "line-numbers",
          help="A complete document with a line-number column (a `<table>` layout)",
        ),
        @clap.PossibleValue::new(
          "fragment",
          help="Only the code markup, without the surrounding document",
        ),
      ]),
    )
    .default_value("document")
    .help("When generating HTML, the document structure to emit"),
  )
  .arg(
    opt("style")
    .long("style")
    .requires("html")
    .value_parser(
      Enum([
        @clap.PossibleValue::new(
          "classes",
          help="`class=\"...\"` spans plus a generated `<style>` carrying the theme's colors",
        ),
        @clap.PossibleValue::new(
          "inline",
          help="`style=\"...\"` spans with the colors inlined",
        ),
        @clap.PossibleValue::new(
          "minimal",
          help="`class=\"...\"` spans with no colors emitted (supply your own stylesheet)",
        ),
      ]),
    )
    .default_value("classes")
    .help("When generating HTML, how token colors are applied"),
  )
  .arg(
    flag("check")
    .long("check")
    .help("Check that highlighting captures conform strictly to standards"),
  )
  .arg(
    path_opt("captures_path")
    .long("captures-path")
    .requires("check")
    .help("The path to a file with captures"),
  )
  .arg(
    @clap.Arg::new("query_paths")
    .long("query-paths")
    .action(Append)
    .num_args(@clap.ValueRange::at_least(1))
    .value_parser(PathBuf)
    .help("The paths to files with queries"),
  )
  .arg(
    opt("scope")
    .long("scope")
    .help("Select a language by the scope instead of a file extension"),
  )
  .arg(flag("time").long("time").short('t').help("Measure execution time"))
  .arg(flag("quiet").long("quiet").short('q').help("Suppress main output"))
  .arg(
    path_opt("paths_file")
    .long("paths")
    .help("The path to a file with paths to source file(s)"),
  )
  .arg(
    @clap.Arg::new("paths")
    .num_args(@clap.ValueRange::at_least(1))
    .action(Append)
    .value_parser(PathBuf)
    .help("The source file(s) to use"),
  )
  .arg(
    grammar_path_arg(
      "The path to the tree-sitter grammar directory, implies --rebuild",
    ).conflicts_with("rebuild"),
  )
  .arg(config_path_arg())
  .arg(
    test_number_arg("Highlight the contents of a specific test")
    .conflicts_with("paths")
    .conflicts_with("paths_file"),
  )
  .arg(rebuild_arg())
  .arg(
    opt("encoding")
    .long("encoding")
    .value_parser(Enum(encoding_values()))
    .help("The encoding of the input files"),
  )
}

///|
fn tags_command() -> @clap.Command {
  @clap.Command::new("tags")
  .about("Generate a list of tags")
  .arg(
    opt("scope")
    .long("scope")
    .help("Select a language by the scope instead of a file extension"),
  )
  .arg(flag("time").long("time").short('t').help("Measure execution time"))
  .arg(flag("quiet").long("quiet").short('q').help("Suppress main output"))
  .arg(
    path_opt("paths_file")
    .long("paths")
    .help("The path to a file with paths to source file(s)"),
  )
  .arg(
    @clap.Arg::new("paths")
    .num_args(@clap.ValueRange::at_least(1))
    .action(Append)
    .value_parser(PathBuf)
    .help("The source file(s) to use"),
  )
  .arg(
    grammar_path_arg(
      "The path to the tree-sitter grammar directory, implies --rebuild",
    ).conflicts_with("rebuild"),
  )
  .arg(config_path_arg())
  .arg(
    test_number_arg("Generate tags from the contents of a specific test")
    .conflicts_with("paths")
    .conflicts_with("paths_file"),
  )
  .arg(rebuild_arg())
}

///|
fn playground_command() -> @clap.Command {
  @clap.Command::new("playground")
  .alias("play")
  .alias("pg")
  .alias("web-ui")
  .about("Start local playground for a parser in the browser")
  .arg(
    flag("quiet").long("quiet").short('q').help("Don't open in default browser"),
  )
  .arg(
    grammar_path_arg(
      "Path to the directory containing the grammar and Wasm files",
      short=false,
    ),
  )
  .arg(
    path_opt("export")
    .long("export")
    .short('e')
    .help(
      "Export playground files to specified directory instead of serving them",
    ),
  )
}

///|
fn dump_languages_command() -> @clap.Command {
  @clap.Command::new("dump-languages")
  .alias("langs")
  .about("Print info about all known language parsers")
  .arg(config_path_arg())
}

///|
fn complete_command() -> @clap.Command {
  @clap.Command::new("complete")
  .alias("comp")
  .about("Generate shell completions")
  .arg(
    opt("shell")
    .long("shell")
    .short('s')
    .required(true)
    .value_parser(
      Enum([
        @clap.PossibleValue::new("bash"),
        @clap.PossibleValue::new("elvish"),
        @clap.PossibleValue::new("fish"),
        @clap.PossibleValue::new("power-shell"),
        @clap.PossibleValue::new("zsh"),
        @clap.PossibleValue::new("nushell"),
      ]),
    )
    .help("The shell to generate completions for"),
  )
}

///|
/// The `tree-sitter` command (`run`'s `Command::new("tree-sitter")` plus
/// `Commands::augment_subcommands`).
pub fn build_cli() -> @clap.Command {
  @clap.Command::new("tree-sitter")
  .help_template(
    "\n{before-help}{name} {version}\n{author-with-newline}{about-with-newline}\n{usage-heading} {usage}\n\n{all-args}{after-help}\n\n",
  )
  .version(build_version)
  .subcommand_required(true)
  .arg_required_else_help(true)
  .disable_help_subcommand(true)
  .about("Generates and tests parsers")
  .author(authors)
  .subcommand(init_config_command())
  .subcommand(init_command())
  .subcommand(generate_command())
  .subcommand(build_command())
  .subcommand(parse_command())
  .subcommand(test_command())
  .subcommand(version_command())
  .subcommand(fuzz_command())
  .subcommand(query_command())
  .subcommand(highlight_command())
  .subcommand(tags_command())
  .subcommand(playground_command())
  .subcommand(dump_languages_command())
  .subcommand(complete_command())
}

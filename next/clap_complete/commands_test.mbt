// Commands for the snapshot tests. They mirror commands built with clap
// 4.6.7's builder API; the expected scripts in the `*_test.mbt` files are
// the output of clap_complete 4.6.11 / clap_complete_nushell 4.6.2 for
// those Rust commands. (Value names are given explicitly, as this package's
// clap model names values after the argument id like clap_derive does.)

///|
fn my_app() -> @clap.Command {
  @clap.Command::new("my-app")
  .version("1.0")
  .about("My app")
  .arg(
    @clap.Arg::new("verbose")
    .short('v')
    .long("verbose")
    .action(Count)
    .help("Verbosity [level]"),
  )
  .arg(
    @clap.Arg::new("config")
    .short('c')
    .long("config")
    .value_name("FILE")
    .value_parser(PathBuf)
    .help("Config file: it's `$HOME`"),
  )
  .arg(
    @clap.Arg::new("color")
    .long("color")
    .value_name("WHEN")
    .value_parser(
      Enum([
        @clap.PossibleValue::new("always", help="Always color"),
        @clap.PossibleValue::new("never"),
        { name: "auto", help: None, aliases: [], hide: true, },
      ]),
    )
    .help("When to color"),
  )
  .arg(
    @clap.Arg::new("mode")
    .long("mode")
    .value_name("MODE")
    .value_parser(
      Enum([
        @clap.PossibleValue::new("fast"),
        @clap.PossibleValue::new("slow mode"),
      ]),
    ),
  )
  .arg(
    @clap.Arg::new("out")
    .short('o')
    .long("out")
    .value_name("DIR")
    .value_hint(DirPath)
    .visible_alias("output")
    .visible_short_alias('O')
    .conflicts_with("verbose")
    .help("Output directory"),
  )
  .arg(
    @clap.Arg::new("name")
    .long("name")
    .value_name("NAME")
    .value_hint(Other)
    .action(Append)
    .help("A name"),
  )
  .arg(
    @clap.Arg::new("file")
    .long("file")
    .value_name("F")
    .value_hint(FilePath)
    .num_args(@clap.ValueRange::new(2, 2))
    .help("Two files"),
  )
  .arg(
    @clap.Arg::new("quiet")
    .short('q')
    .long("quiet")
    .action(SetTrue)
    .visible_alias("silent")
    .alias("shh")
    .short_alias('Q')
    .visible_short_alias('s')
    .help("Be quiet,\nplease"),
  )
  .arg(@clap.Arg::new("secret").long("secret").action(SetTrue).hide(true))
  .subcommand(
    @clap.Command::new("build")
    .visible_alias("b")
    .alias("bb")
    .about("Build it")
    .arg(
      @clap.Arg::new("release")
      .long("release")
      .action(SetTrue)
      .help("Release mode"),
    )
    .arg(
      @clap.Arg::new("target")
      .value_parser(
        Enum([
          @clap.PossibleValue::new("x86", help="Intel"),
          @clap.PossibleValue::new("arm"),
        ]),
      )
      .required(true)
      .help("The [target]"),
    )
    .arg(
      @clap.Arg::new("inputs")
      .value_parser(PathBuf)
      .num_args(@clap.ValueRange::at_least(1))
      .help("Input files"),
    )
    .subcommand(@clap.Command::new("clean").about("Clean up")),
  )
  .subcommand(
    @clap.Command::new("test-all")
    .about("Run 'all' tests")
    .arg(
      @clap.Arg::new("jobs")
      .short('j')
      .value_name("N")
      .num_args(@clap.ValueRange::new(0, 1))
      .help("Jobs"),
    ),
  )
  .subcommand(@clap.Command::new("hidden").hide(true))
}

///|
/// Nested subcommands without `disable_help_subcommand`, for the expanded
/// help tree.
fn nested() -> @clap.Command {
  @clap.Command::new("nested")
  .subcommand(
    @clap.Command::new("a")
    .about("A")
    .subcommand(
      @clap.Command::new("b").about("B").subcommand(@clap.Command::new("c")),
    ),
  )
  .subcommand(@clap.Command::new("d").hide(true))
}

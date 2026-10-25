///|
fn demo() -> @clap.Command {
  @clap.Command::new("demo")
  .version("1.0")
  .about("A demo")
  .subcommand_required(true)
  .disable_help_subcommand(true)
  .subcommand(
    @clap.Command::new("run")
    .alias("r")
    .about("Run things")
    .arg(@clap.Arg::new("quiet").long("quiet").short('q').action(SetTrue).help("Be quiet"))
    .arg(
      @clap.Arg::new("level")
      .long("level")
      .action(Set)
      .value_parser(
        Enum([@clap.PossibleValue::new("low"), @clap.PossibleValue::new("high")]),
      )
      .help("The level"),
    )
    .arg(@clap.Arg::new("files").num_args(@clap.ValueRange::at_least(1)).help("Files")),
  )
}

///|
fn outcome(args : Array[String]) -> String {
  try {
    let m = demo().try_get_matches_from(args)
    match m.subcommand() {
      Some((name, sub)) =>
        "\{name} quiet=\{sub.get_flag("quiet")} level=\{to_repr(sub.get_one("level"))} files=\{to_repr(sub.get_many("files"))}"
      None => "none"
    }
  } catch {
    @clap.ClapError(_) as e => "exit \{e.exit_code()}:\n\{e.message()}"
    e => "\{e}"
  }
}

///|
test "parse arguments" {
  inspect(
    outcome(["demo", "r", "-q", "--level", "high", "a", "b"]),
    content="run quiet=true level=Some(\"high\") files=Some([\"a\", \"b\"])",
  )
  inspect(
    outcome(["demo", "run", "--level=low"]),
    content="run quiet=false level=Some(\"low\") files=None",
  )
}

///|
test "help and errors" {
  inspect(
    outcome(["demo", "run", "-h"]),
    content=(
      #|exit 0:
      #|Run things
      #|
      #|Usage: demo run [OPTIONS] [FILES]...
      #|
      #|Arguments:
      #|  [FILES]...  Files
      #|
      #|Options:
      #|  -q, --quiet          Be quiet
      #|      --level <LEVEL>  The level [possible values: low, high]
      #|  -h, --help           Print help
      #|
    ),
  )
  inspect(
    outcome(["demo", "run", "--levl", "x"]),
    content=(
      #|exit 2:
      #|error: unexpected argument '--levl' found
      #|
      #|  tip: a similar argument exists: '--level'
      #|
      #|Usage: demo run --level <LEVEL> [FILES]...
      #|
      #|For more information, try '--help'.
      #|
    ),
  )
  inspect(
    outcome(["demo", "run", "--level", "mid"]),
    content=(
      #|exit 2:
      #|error: invalid value 'mid' for '--level <LEVEL>'
      #|  [possible values: low, high]
      #|
      #|For more information, try '--help'.
      #|
    ),
  )
  inspect(outcome(["demo", "-V"]), content="exit 0:\ndemo 1.0\n")
}

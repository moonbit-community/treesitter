// Behaviour of clap 4.6.7 that the tree-sitter command line does not
// exercise. Expected outputs come from equivalent Rust programs against
// clap 4.6.7 (`try_get_matches_from`; errors and help rendered without
// colors). Value names are explicit because this port defaults them to the
// uppercased id, as clap_derive does.

///|
fn run_cmd(cmd : @clap.Command, args : Array[String]) -> String {
  try {
    let _ = cmd.try_get_matches_from(args)
    "ok"
  } catch {
    @clap.ClapError(_) as e => "exit \{e.exit_code()}:\n\{e.message()}"
  }
}

///|
fn describe_arg(m : @clap.ArgMatches, id : String) -> String {
  match m.value_source(id) {
    Some(src) => "\{id}=\{Repr(m.get_many(id).unwrap())}@\{Repr(src)}"
    None => "\{id}=None"
  }
}

///|
fn count_cmd(env : String?) -> @clap.Command {
  @clap.Command::new("prog").arg(
    @clap.Arg::new("verbose")
    .short('v')
    .long("verbose")
    .action(Count)
    .env("PROG_VERBOSE", env),
  )
}

///|
fn count_outcome(env : String?, args : Array[String]) -> String {
  try {
    let m = count_cmd(env).try_get_matches_from(args)
    "ok \{describe_arg(m, "verbose")}"
  } catch {
    @clap.ClapError(_) as e => "exit \{e.exit_code()}:\n\{e.message()}"
  }
}

///|
test "Count action: default, increments, environment and u8 saturation" {
  inspect(
    count_outcome(None, ["prog"]),
    content=(
      #|ok verbose=["0"]@DefaultValue
    ),
  )
  inspect(
    count_outcome(None, ["prog", "-vvv", "--verbose"]),
    content=(
      #|ok verbose=["4"]@CommandLine
    ),
  )
  inspect(
    count_outcome(None, ["prog", ..Array::make(300, "-v")]),
    content=(
      #|ok verbose=["255"]@CommandLine
    ),
  )
  inspect(
    count_outcome(Some("7"), ["prog"]),
    content=(
      #|ok verbose=["7"]@EnvVariable
    ),
  )
  inspect(
    count_outcome(Some("7"), ["prog", "-v"]),
    content=(
      #|ok verbose=["1"]@CommandLine
    ),
  )
  inspect(
    count_outcome(Some("300"), ["prog"]),
    content=(
      #|exit 2:
      #|error: invalid value '300' for '--verbose...': 300 is not in 0..=255
      #|
      #|For more information, try '--help'.
      #|
    ),
  )
  inspect(
    count_outcome(Some("-0"), ["prog"]),
    content=(
      #|ok verbose=["-0"]@EnvVariable
    ),
  )
  inspect(
    count_outcome(Some("x"), ["prog"]),
    content=(
      #|exit 2:
      #|error: invalid value 'x' for '--verbose...': invalid digit found in string
      #|
      #|For more information, try '--help'.
      #|
    ),
  )
  inspect(
    count_outcome(None, ["prog", "-h"]),
    content=(
      #|exit 0:
      #|Usage: prog [OPTIONS]
      #|
      #|Options:
      #|  -v, --verbose...  [env: PROG_VERBOSE=]
      #|  -h, --help        Print help
      #|
    ),
  )
}

///|
fn global_cmd() -> @clap.Command {
  @clap.Command::new("prog")
  .arg(
    @clap.Arg::new("verbose")
    .long("verbose")
    .short('v')
    .global(true)
    .action(SetTrue)
    .help("Verbose"),
  )
  .arg(
    @clap.Arg::new("color")
    .long("color")
    .value_name("color")
    .global(true)
    .default_value("auto")
    .help("Color"),
  )
  .subcommand(
    @clap.Command::new("sub")
    .about("A sub")
    .arg(@clap.Arg::new("x").long("x").value_name("x").help("X"))
    .subcommand(@clap.Command::new("leaf").about("A leaf")),
  )
}

///|
fn describe_globals(m : @clap.ArgMatches) -> String {
  let parts = [describe_arg(m, "verbose"), describe_arg(m, "color")]
  match m.subcommand() {
    Some((name, sub)) =>
      "\{parts.join(" ")} [\{name}: \{describe_globals(sub)}]"
    None => parts.join(" ")
  }
}

///|
fn global_outcome(args : Array[String]) -> String {
  try "ok " + describe_globals(global_cmd().try_get_matches_from(args)) catch {
    @clap.ClapError(_) as e => "exit \{e.exit_code()}:\n\{e.message()}"
  }
}

///|
test "global arguments are propagated to subcommands and their matches" {
  inspect(
    global_outcome(["prog", "sub", "--verbose"]),
    content=(
      #|ok verbose=["true"]@CommandLine color=["auto"]@DefaultValue [sub: verbose=["true"]@CommandLine color=["auto"]@DefaultValue]
    ),
  )
  inspect(
    global_outcome(["prog", "--verbose", "sub"]),
    content=(
      #|ok verbose=["true"]@CommandLine color=["auto"]@DefaultValue [sub: verbose=["true"]@CommandLine color=["auto"]@DefaultValue]
    ),
  )
  inspect(
    global_outcome(["prog", "sub", "leaf", "-v", "--color", "never"]),
    content=(
      #|ok verbose=["true"]@CommandLine color=["never"]@CommandLine [sub: verbose=["true"]@CommandLine color=["never"]@CommandLine [leaf: verbose=["true"]@CommandLine color=["never"]@CommandLine]]
    ),
  )
  inspect(
    global_outcome(["prog", "--color", "always", "sub", "leaf"]),
    content=(
      #|ok verbose=["false"]@DefaultValue color=["always"]@CommandLine [sub: verbose=["false"]@DefaultValue color=["always"]@CommandLine [leaf: verbose=["false"]@DefaultValue color=["always"]@CommandLine]]
    ),
  )
  inspect(
    global_outcome(["prog", "--color", "always", "sub", "--color", "never"]),
    content=(
      #|ok verbose=["false"]@DefaultValue color=["never"]@CommandLine [sub: verbose=["false"]@DefaultValue color=["never"]@CommandLine]
    ),
  )
  inspect(
    global_outcome(["prog", "sub", "--help"]),
    content=(
      #|exit 0:
      #|A sub
      #|
      #|Usage: prog sub [OPTIONS] [COMMAND]
      #|
      #|Commands:
      #|  leaf  A leaf
      #|  help  Print this message or the help of the given subcommand(s)
      #|
      #|Options:
      #|  -v, --verbose        Verbose
      #|      --x <x>          X
      #|      --color <color>  Color [default: auto]
      #|  -h, --help           Print help
      #|
    ),
  )
  inspect(
    global_outcome(["prog", "sub", "leaf", "--help"]),
    content=(
      #|exit 0:
      #|A leaf
      #|
      #|Usage: prog sub leaf [OPTIONS]
      #|
      #|Options:
      #|  -v, --verbose        Verbose
      #|      --color <color>  Color [default: auto]
      #|  -h, --help           Print help
      #|
    ),
  )
  inspect(
    global_outcome(["prog", "sub", "--colr", "x"]),
    content=(
      #|exit 2:
      #|error: unexpected argument '--colr' found
      #|
      #|  tip: a similar argument exists: '--color'
      #|
      #|Usage: prog sub --color <color>
      #|
      #|For more information, try '--help'.
      #|
    ),
  )
}

///|
test "disable_help_subcommand is a global setting" {
  let cmd = () => {
    @clap.Command::new("prog")
    .disable_help_subcommand(true)
    .subcommand(
      @clap.Command::new("a")
      .about("A")
      .subcommand(@clap.Command::new("b").about("B")),
    )
  }
  inspect(
    run_cmd(cmd(), ["prog", "a", "help"]),
    content=(
      #|exit 2:
      #|error: unrecognized subcommand 'help'
      #|
      #|Usage: prog a [COMMAND]
      #|
      #|For more information, try '--help'.
      #|
    ),
  )
  inspect(
    run_cmd(cmd(), ["prog", "a", "--help"]),
    content=(
      #|exit 0:
      #|A
      #|
      #|Usage: prog a [COMMAND]
      #|
      #|Commands:
      #|  b   B
      #|
      #|Options:
      #|  -h, --help  Print help
      #|
    ),
  )
  inspect(
    run_cmd(cmd(), ["prog", "help"]),
    content=(
      #|exit 2:
      #|error: unrecognized subcommand 'help'
      #|
      #|Usage: prog [COMMAND]
      #|
      #|For more information, try '--help'.
      #|
    ),
  )
  let cmd = () => {
    @clap.Command::new("prog").subcommand(
      @clap.Command::new("a")
      .about("A")
      .disable_help_subcommand(true)
      .subcommand(
        @clap.Command::new("b").about("B").subcommand(@clap.Command::new("c")),
      ),
    )
  }
  inspect(
    run_cmd(cmd(), ["prog", "a", "b", "help"]),
    content=(
      #|exit 2:
      #|error: unrecognized subcommand 'help'
      #|
      #|Usage: prog a b [COMMAND]
      #|
      #|For more information, try '--help'.
      #|
    ),
  )
  inspect(
    run_cmd(cmd(), ["prog", "--help"]),
    content=(
      #|exit 0:
      #|Usage: prog [COMMAND]
      #|
      #|Commands:
      #|  a     A
      #|  help  Print this message or the help of the given subcommand(s)
      #|
      #|Options:
      #|  -h, --help  Print help
      #|
    ),
  )
}

///|
test "display order: counter and Rust string order" {
  let cmd = @clap.Command::new("prog")
    .arg(
      @clap.Arg::new("z").long("z").display_order(0).action(SetTrue).help("Z"),
    )
    .arg(@clap.Arg::new("b").long("b").action(SetTrue).help("B"))
  inspect(
    run_cmd(cmd, ["prog", "-h"]),
    content=(
      #|exit 0:
      #|Usage: prog [OPTIONS]
      #|
      #|Options:
      #|      --z     Z
      #|      --b     B
      #|  -h, --help  Print help
      #|
    ),
  )
  let cmd = @clap.Command::new("prog")
    .arg(@clap.Arg::new("pos").value_name("pos").help("Pos"))
    .arg(@clap.Arg::new("b").long("b").action(SetTrue).help("B"))
    .arg(
      @clap.Arg::new("a").long("a").display_order(1).action(SetTrue).help("A"),
    )
  inspect(
    run_cmd(cmd, ["prog", "-h"]),
    content=(
      #|exit 0:
      #|Usage: prog [OPTIONS] [pos]
      #|
      #|Arguments:
      #|  [pos]  Pos
      #|
      #|Options:
      #|      --b     B
      #|      --a     A
      #|  -h, --help  Print help
      #|
    ),
  )
  let cmd = @clap.Command::new("prog")
    .arg(
      @clap.Arg::new("u1")
      .long("\u{10000}")
      .display_order(5)
      .action(SetTrue)
      .help("Supplementary"),
    )
    .arg(
      @clap.Arg::new("u2")
      .long("\u{E000}")
      .display_order(5)
      .action(SetTrue)
      .help("Private use"),
    )
    .arg(
      @clap.Arg::new("u3")
      .long("\u{FF5E}")
      .display_order(5)
      .action(SetTrue)
      .help("Fullwidth tilde"),
    )
    .subcommand(@clap.Command::new("\u{10000}").display_order(1).about("S1"))
    .subcommand(@clap.Command::new("\u{E000}").display_order(1).about("S2"))
    .subcommand(@clap.Command::new("plain").about("S3"))
    .subcommand(@clap.Command::new("first").display_order(0).about("S4"))
  inspect(
    run_cmd(cmd, ["prog", "-h"]),
    content=(
      #|exit 0:
      #|Usage: prog [OPTIONS] [COMMAND]
      #|
      #|Commands:
      #|  first  S4
      #|        S2
      #|  𐀀      S1
      #|  plain  S3
      #|  help   Print this message or the help of the given subcommand(s)
      #|
      #|Options:
      #|      --     Private use
      #|      --～     Fullwidth tilde
      #|      --𐀀     Supplementary
      #|  -h, --help  Print help
      #|
    ),
  )
}

///|
test "possible values and defaults are Debug-quoted when empty or with whitespace" {
  let cmd = @clap.Command::new("prog")
    .arg(
      @clap.Arg::new("mode")
      .long("mode")
      .value_name("mode")
      .help("Mode")
      .value_parser(
        Enum(
          [
            "", "plain", "a b", "ideo\u{3000}space", "nbsp\u{a0}x", "quote\" b",
            "tab\tback\\slash", "x \u{301}acute", "del\u{7f} z", "nul\u{0} w", "apos' \u{e9}\u{1F600}\u{200B}\u{feff}\u{e0001}",
            "lone\u{301}",
          ].map(n => @clap.PossibleValue::new(n)),
        ),
      ),
    )
    .arg(
      @clap.Arg::new("def")
      .long("def")
      .value_name("def")
      .default_value("a \"b\"\u{85}")
      .help("Def"),
    )
  inspect(
    run_cmd(cmd, ["prog", "-h"]),
    content=(
      #|exit 0:
      #|Usage: prog [OPTIONS]
      #|
      #|Options:
      #|      --mode <mode>  Mode [possible values: "", plain, "a b", "ideo\u{3000}space", "nbsp\u{a0}x", "quote\" b", "tab\tback\\slash", "x \u{301}acute", "del\u{7f} z", "nul\0 w", "apos' é😀\u{200b}\u{feff}\u{e0001}", loné]
      #|      --def <def>    Def [default: "a \"b\"\u{85}"]
      #|  -h, --help         Print help
      #|
    ),
  )
  inspect(
    run_cmd(cmd, ["prog", "--mode", "nope"]),
    content=(
      #|exit 2:
      #|error: invalid value 'nope' for '--mode <mode>'
      #|  [possible values: "", plain, "a b", "ideo\u{3000}space", "nbsp\u{a0}x", "quote\" b", "tab\tback\\slash", "x \u{301}acute", "del\u{7f} z", "nul\0 w", "apos' é😀\u{200b}\u{feff}\u{e0001}", loné]
      #|
      #|For more information, try '--help'.
      #|
    ),
  )
}

///|
test "the binary name is the file name of argv[0]" {
  let cmd = () => {
    @clap.Command::new("prog")
    .arg(@clap.Arg::new("x").long("x").value_name("x").required(true))
    .subcommand(
      @clap.Command::new("sub").arg(
        @clap.Arg::new("y").long("y").value_name("y").required(true),
      ),
    )
  }
  let usages = []
  for
    argv0 in [
      "/usr/local/bin/other-name", "rel/dir/", "a/b/.", "./", "", "..", "/", "x/..",
      "./tool",
    ] {
    for args in [[argv0], [argv0, "--x", "1", "sub"]] {
      let out = run_cmd(cmd(), args)
      let usage = out
        .split("\n")
        .filter(l => l.has_prefix("Usage: "))
        .map(l => l.to_owned())
        .collect()
      usages.push("\{Repr(args)} => \{usage.join("")}")
    }
  }
  inspect(
    usages.join("\n"),
    content=(
      #|["/usr/local/bin/other-name"] => Usage: other-name --x <x>
      #|["/usr/local/bin/other-name", "--x", "1", "sub"] => Usage: other-name --x <x> sub --y <y>
      #|["rel/dir/"] => Usage: dir --x <x>
      #|["rel/dir/", "--x", "1", "sub"] => Usage: dir --x <x> sub --y <y>
      #|["a/b/."] => Usage: b --x <x>
      #|["a/b/.", "--x", "1", "sub"] => Usage: b --x <x> sub --y <y>
      #|["./"] => Usage: prog --x <x>
      #|["./", "--x", "1", "sub"] => Usage: sub --y <y>
      #|[""] => Usage: prog --x <x>
      #|["", "--x", "1", "sub"] => Usage: sub --y <y>
      #|[".."] => Usage: prog --x <x>
      #|["..", "--x", "1", "sub"] => Usage: sub --y <y>
      #|["/"] => Usage: prog --x <x>
      #|["/", "--x", "1", "sub"] => Usage: sub --y <y>
      #|["x/.."] => Usage: prog --x <x>
      #|["x/..", "--x", "1", "sub"] => Usage: sub --y <y>
      #|["./tool"] => Usage: tool --x <x>
      #|["./tool", "--x", "1", "sub"] => Usage: tool --x <x> sub --y <y>
    ),
  )
}

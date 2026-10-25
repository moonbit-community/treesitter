// Port of clap_complete 4.6.11 `aot/shells/elvish.rs`.

///|
fn generate_elvish(cmd : @clap.Command, buf : StringBuilder) -> Unit {
  let bin_name = cmd.get_bin_name().unwrap()
  let subcommands_cases = elvish_generate_inner(cmd, "")
  buf.write_string(
    (
      $|
      $|use builtin;
      $|use str;
      $|
      $|set edit:completion:arg-completer[\{bin_name}] = {|@words|
      $|    fn spaces {|n|
      $|        builtin:repeat $n ' ' | str:join ''
      $|    }
      $|    fn cand {|text desc|
      $|        edit:complex-candidate $text &display=$text' '(spaces (- 14 (wcswidth $text)))$desc
      $|    }
      $|    var command = '\{bin_name}'
      $|    for word $words[1..-1] {
      $|        if (str:has-prefix $word '-') {
      $|            break
      $|        }
      $|        set command = $command';'$word
      $|    }
      $|    var completions = [\{subcommands_cases}
      $|    ]
      $|    $completions[$command]
      $|}
      $|
    ),
  )
}

///|
/// Escape string inside single quotes.
fn elvish_escape_string(s : String) -> String {
  s.replace_all(old="'", new="''")
}

///|
fn elvish_escape_help(help : String?, data : String) -> String {
  match help {
    Some(help) => elvish_escape_string(help.replace_all(old="\n", new=" "))
    None => data
  }
}

///|
fn elvish_generate_inner(
  p : @clap.Command,
  previous_command_name : String,
) -> String {
  let command_names = if previous_command_name.is_empty() {
    [p.get_bin_name().unwrap()]
  } else {
    p
    .get_name_and_visible_aliases()
    .map(name => "\{previous_command_name};\{name}")
  }
  let completions = StringBuilder()
  let preamble = "\n            cand "
  let add_arg = (arg : @clap.Arg) => {
    if arg.get_short_and_visible_aliases() is Some(shorts) {
      let tooltip = elvish_escape_help(arg.get_help(), shorts[0].to_string())
      for short in shorts {
        completions.write_string(preamble)
        completions.write_string("-\{short} '\{tooltip}'")
      }
    }
    if arg.get_long_and_visible_aliases() is Some(longs) {
      let tooltip = elvish_escape_help(arg.get_help(), longs[0])
      for long in longs {
        completions.write_string(preamble)
        completions.write_string("--\{long} '\{tooltip}'")
      }
    }
  }
  for option in p.get_opts() {
    add_arg(option)
  }
  for flag in flags(p) {
    add_arg(flag)
  }
  for subcommand in p.get_subcommands() {
    for name in subcommand.get_name_and_visible_aliases() {
      let tooltip = elvish_escape_help(subcommand.get_about(), name)
      completions.write_string(preamble)
      completions.write_string("\{name} '\{tooltip}'")
    }
  }
  let completions = completions.to_string()
  let subcommands_cases = StringBuilder()
  for command_name in command_names {
    subcommands_cases.write_string(
      (
        $|
        $|        &'\{command_name}'= {\{completions}
        $|        }
      ),
    )
  }
  for subcommand in p.get_subcommands() {
    for command_name in command_names {
      subcommands_cases.write_string(
        elvish_generate_inner(subcommand, command_name),
      )
    }
  }
  subcommands_cases.to_string()
}

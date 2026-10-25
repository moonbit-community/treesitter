// Port of clap_complete 4.6.11 `aot/shells/fish.rs`.
//
// Note: The fish generator currently only supports named options
// (-o/--option), not positional arguments.

///|
fn generate_fish(cmd : @clap.Command, buf : StringBuilder) -> Unit {
  let bin_name = cmd.get_bin_name().unwrap()
  let name = fish_escape_name(bin_name)
  let mut needs_fn_name = "__fish_\{name}_needs_command"
  let mut using_fn_name = "__fish_\{name}_using_subcommand"
  // Given `git --git-dir somedir status`, using `__fish_seen_subcommand_from` won't help us
  // find out `status` is the real subcommand, and not `somedir`. However, when there are no subcommands,
  // there is no need to use our custom stubs.
  if cmd.has_subcommands() {
    fish_gen_subcommand_helpers(name, cmd, buf, needs_fn_name, using_fn_name)
  } else {
    needs_fn_name = "__fish_use_subcommand"
    using_fn_name = "__fish_seen_subcommand_from"
  }
  fish_gen_inner(bin_name, [], cmd, buf, needs_fn_name, using_fn_name)
}

///|
/// Escape string inside single quotes.
fn fish_escape_string(s : String, escape_comma : Bool) -> String {
  let s = s.replace_all(old="\\", new="\\\\").replace_all(old="'", new="\\'")
  if escape_comma {
    s.replace_all(old=",", new="\\,")
  } else {
    s
  }
}

///|
fn fish_escape_help(help : String) -> String {
  fish_escape_string(help.replace_all(old="\n", new=" "), false)
}

///|
fn fish_escape_name(name : String) -> String {
  name.replace_all(old="-", new="_")
}

///|
fn fish_gen_inner(
  root_command : String,
  parent_commands : Array[String],
  cmd : @clap.Command,
  buffer : StringBuilder,
  needs_fn_name : String,
  using_fn_name : String,
) -> Unit {
  // example :
  //
  // complete
  //      -c {command}
  //      -d "{description}"
  //      -s {short}
  //      -l {long}
  //      -a "{possible_arguments}"
  //      -r # if require parameter
  //      -f # don't use file completion
  //      -n "{needs_fn_name}"            # complete for command "myprog"
  //      -n "{using_fn_name} subcmd1"    # complete for command "myprog subcmd1"
  let mut basic_template = "complete -c \{root_command}"
  match parent_commands {
    [] =>
      if cmd.has_subcommands() {
        basic_template += " -n \"\{needs_fn_name}\""
      }
    [command] => {
      let out = StringBuilder()
      out.write_string(using_fn_name)
      out.write_string(" \{command}")
      if cmd.has_subcommands() {
        out.write_string("; and not __fish_seen_subcommand_from")
      }
      for sc in cmd.get_subcommands() {
        for name in sc.get_name_and_visible_aliases() {
          out.write_string(" \{name}")
        }
      }
      basic_template += " -n \"\{out.to_string()}\""
    }
    [command, subcommand] =>
      basic_template += " -n \"\{using_fn_name} \{command}; and __fish_seen_subcommand_from \{subcommand}\""
    // HACK: Assuming subcommands are only nested less than 3 levels as more than that is
    // unwieldy and takes more effort to support.
    // For example, `rustup toolchain help install` is the longest valid command line of `rustup`
    // that uses nested subcommands, and it cannot receive any flags to it.
    _ => return
  }
  for option in cmd.get_opts() {
    let template = StringBuilder()
    template.write_string(basic_template)
    if option.get_short_and_visible_aliases() is Some(shorts) {
      for short in shorts {
        template.write_string(" -s \{short}")
      }
    }
    if option.get_long_and_visible_aliases() is Some(longs) {
      for long in longs {
        template.write_string(" -l \{fish_escape_string(long, false)}")
      }
    }
    if option.get_help() is Some(data) {
      template.write_string(" -d '\{fish_escape_help(data)}'")
    }
    template.write_string(fish_value_completion(option))
    buffer.write_string(template.to_string())
    buffer.write_char('\n')
  }
  for flag in flags(cmd) {
    let template = StringBuilder()
    template.write_string(basic_template)
    if flag.get_short_and_visible_aliases() is Some(shorts) {
      for short in shorts {
        template.write_string(" -s \{short}")
      }
    }
    if flag.get_long_and_visible_aliases() is Some(longs) {
      for long in longs {
        template.write_string(" -l \{fish_escape_string(long, false)}")
      }
    }
    if flag.get_help() is Some(data) {
      template.write_string(" -d '\{fish_escape_help(data)}'")
    }
    buffer.write_string(template.to_string())
    buffer.write_char('\n')
  }
  let has_positionals = !cmd.get_positionals().is_empty()
  if !has_positionals {
    basic_template += " -f"
  }
  for subcommand in cmd.get_subcommands() {
    for subcommand_name in subcommand.get_name_and_visible_aliases() {
      buffer.write_string(basic_template)
      buffer.write_string(" -a \"\{subcommand_name}\"")
      if subcommand.get_about() is Some(data) {
        buffer.write_string(" -d '\{fish_escape_help(data)}'")
      }
      buffer.write_char('\n')
    }
  }
  // generate options of subcommands
  for subcommand in cmd.get_subcommands() {
    for subcommand_name in subcommand.get_name_and_visible_aliases() {
      let parent_commands = [..parent_commands, subcommand_name]
      fish_gen_inner(
        root_command, parent_commands, subcommand, buffer, needs_fn_name, using_fn_name,
      )
    }
  }
}

///|
/// Print fish's helpers for easy handling subcommands.
fn fish_gen_subcommand_helpers(
  bin_name : String,
  cmd : @clap.Command,
  buf : StringBuilder,
  needs_fn_name : String,
  using_fn_name : String,
) -> Unit {
  let optspecs = StringBuilder()
  for option in cmd.get_arguments() {
    if option.is_positional() {
      continue
    }
    optspecs.write_char(' ')
    let mut has_short = false
    if option.get_short() is Some(short) {
      has_short = true
      optspecs.write_char(short)
    }
    if option.get_long() is Some(long) {
      if has_short {
        optspecs.write_char('/')
      }
      optspecs.write_string(fish_escape_string(long, false))
    }
    let is_an_option = match option.get_num_args() {
      Some(r) => r.takes_values()
      None => true
    }
    if is_an_option {
      optspecs.write_char('=')
    }
  }
  let optspecs = optspecs.to_string()
  let optspecs_fn_name = "__fish_\{bin_name}_global_optspecs"
  buf.write_string(
    (
      $|# Print an optspec for argparse to handle cmd's options that are independent of any subcommand.
      $|function \{optspecs_fn_name}
      $|    string join \{"\\n"}\{optspecs}
      $|end
      $|
      $|function \{needs_fn_name}
      $|    # Figure out if the current invocation already has a command.
      $|    set -l cmd (commandline -opc)
      $|    set -e cmd[1]
      $|    argparse -s (\{optspecs_fn_name}) -- $cmd 2>/dev/null
      $|    or return
      $|    if set -q argv[1]
      $|        # Also print the command, so this can be used to figure out what it is.
      $|        echo $argv[1]
      $|        return 1
      $|    end
      $|    return 0
      $|end
      $|
      $|function \{using_fn_name}
      $|    set -l cmd (\{needs_fn_name})
      $|    test -z "$cmd"
      $|    and return 1
      $|    contains -- $cmd[1] $argv
      $|end
      $|
      $|
    ),
  )
}

///|
fn fish_value_completion(option : @clap.Arg) -> String {
  if !num_args(option).takes_values() {
    return ""
  }
  if possible_values(option) is Some(data) {
    // We return the possible values with their own empty description e.g. "a\t''\nb\t''"
    // this makes sure that a and b don't get the description of the option or argument
    let items = []
    for value in data {
      if !value.is_hide_set() {
        // The help text after \t is wrapped in '' to make sure that the it is taken literally
        // and there is no command substitution or variable expansion resulting in unexpected errors
        items.push(
          "\{fish_escape_string(value.get_name(), true)}\\t'\{fish_escape_help(or_empty(value.get_help()))}'",
        )
      }
    }
    " -r -f -a \"\{items.join("\n")}\""
  } else {
    match option.get_value_hint() {
      Unknown => " -r"
      // fish has no built-in support to distinguish these
      AnyPath | FilePath | ExecutablePath => " -r -F"
      DirPath => " -r -f -a \"(__fish_complete_directories)\""
      // It seems fish has no built-in support for completing command + arguments as
      // single string (CommandString). Complete just the command name.
      CommandString | CommandName => " -r -f -a \"(__fish_complete_command)\""
      Username => " -r -f -a \"(__fish_complete_users)\""
      Hostname => " -r -f -a \"(__fish_print_hostnames)\""
      // Disable completion for others
      _ => " -r -f"
    }
  }
}

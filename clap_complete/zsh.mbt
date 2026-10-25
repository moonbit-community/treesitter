// Port of clap_complete 4.6.11 `aot/shells/zsh.rs`.

///|
let zsh_cmd_sep : String = "__subcmd__"

///|
fn generate_zsh(cmd : @clap.Command, buf : StringBuilder) -> Unit {
  let name = cmd.get_bin_name().unwrap()
  let initial_args = zsh_get_args_of(cmd, None)
  let subcommands = zsh_get_subcommands_of(cmd)
  let subcommand_details = zsh_subcommand_details(cmd)
  buf.write_string(
    (
      $|#compdef \{name}
      $|
      $|autoload -U is-at-least
      $|
      $|_\{name}() {
      $|    typeset -A opt_args
      $|    typeset -a _arguments_options
      $|    local ret=1
      $|
      $|    if is-at-least 5.2; then
      $|        _arguments_options=(-s -S -C)
      $|    else
      $|        _arguments_options=(-s -C)
      $|    fi
      $|
      $|    local context curcontext="$curcontext" state line
      $|    \{initial_args}\{subcommands}
      $|}
      $|
      $|\{subcommand_details}
      $|
      $|if [ "$funcstack[1]" = "_\{name}" ]; then
      $|    _\{name} "$@"
      $|else
      $|    compdef _\{name} \{name}
      $|fi
      $|
    ),
  )
}

///|
fn zsh_commands_function(
  bin_name : String,
  subcommands_and_args : String,
) -> String {
  let bin_name_underscore = bin_name.replace_all(old=" ", new=zsh_cmd_sep)
  (
    $|(( $+functions[_\{bin_name_underscore}_commands] )) ||
    $|_\{bin_name_underscore}_commands() {
    $|    local commands; commands=(\{subcommands_and_args})
    $|    _describe -t commands '\{bin_name} commands' commands "$@"
    $|}
  )
}

///|
fn zsh_subcommand_details(p : @clap.Command) -> String {
  let bin_name = p.get_bin_name().unwrap()
  let ret = []
  // First we do ourself
  ret.push(zsh_commands_function(bin_name, zsh_subcommands_of(p)))
  // Next we start looping through all the children, grandchildren, etc.
  let all_subcommand_bins = sort_dedup(all_subcommands(p).map(x => x.1))
  for bin_name in all_subcommand_bins {
    ret.push(
      zsh_commands_function(
        bin_name,
        zsh_subcommands_of(zsh_parser_of(p, bin_name).unwrap()),
      ),
    )
  }
  ret.join("\n")
}

///|
fn zsh_subcommands_of(p : @clap.Command) -> String {
  let segments = []
  fn add_subcommands(
    subcommand : @clap.Command,
    name : String,
    ret : Array[String],
  ) -> Unit {
    ret.push(
      "'\{name}:\{zsh_escape_help(or_empty(subcommand.get_about()))}' \\",
    )
  }

  // The subcommands
  for command in p.get_subcommands() {
    add_subcommands(command, command.get_name(), segments)
    for alias in command.get_visible_aliases() {
      add_subcommands(command, alias, segments)
    }
  }
  // Surround the text with newlines for proper formatting.
  // We need this to prevent weirdly formatted `command=(\n        \n)` sections.
  // When there are no (sub-)commands.
  if !segments.is_empty() {
    segments.insert(0, "")
    segments.push("    ")
  }
  segments.join("\n")
}

///|
fn zsh_get_subcommands_of(parent : @clap.Command) -> String {
  if !parent.has_subcommands() {
    return ""
  }
  let subcommand_names = subcommands(parent)
  let all_subcommands = []
  for sc in subcommand_names {
    let (name, bin_name) = sc
    let segments = ["(\{name})"]
    let subcommand_args = zsh_get_args_of(
      zsh_parser_of(parent, bin_name).unwrap(),
      Some(parent),
    )
    if !subcommand_args.is_empty() {
      segments.push(subcommand_args)
    }
    // Get the help text of all child subcommands.
    let children = zsh_get_subcommands_of(
      zsh_parser_of(parent, bin_name).unwrap(),
    )
    if !children.is_empty() {
      segments.push(children)
    }
    segments.push(";;")
    all_subcommands.push(segments.join("\n"))
  }
  let parent_bin_name = parent.get_bin_name().unwrap()
  let name = parent.get_name()
  let name_hyphen = parent_bin_name.replace_all(old=" ", new="-")
  let subcommands = all_subcommands.join("\n")
  let pos = parent.get_positionals().length() + 1
  (
    $|
    $|    case $state in
    $|    (\{name})
    $|        words=($line[\{pos}] "${words[@]}")
    $|        (( CURRENT += 1 ))
    $|        curcontext="${curcontext%:*:*}:\{name_hyphen}-command-$line[\{pos}]:"
    $|        case $line[\{pos}] in
    $|            \{subcommands}
    $|        esac
    $|    ;;
    $|esac
  )
}

///|
/// Get the Command for a given subcommand tree.
fn zsh_parser_of(parent : @clap.Command, bin_name : String) -> @clap.Command? {
  if bin_name == parent.get_bin_name().unwrap_or("") {
    return Some(parent)
  }
  for subcommand in parent.get_subcommands() {
    if zsh_parser_of(subcommand, bin_name) is Some(ret) {
      return Some(ret)
    }
  }
  None
}

///|
fn zsh_get_args_of(parent : @clap.Command, p_global : @clap.Command?) -> String {
  let segments = ["_arguments \"${_arguments_options[@]}\" : \\"]
  let opts = zsh_write_opts_of(parent, p_global)
  let flags = zsh_write_flags_of(parent, p_global)
  let positionals = zsh_write_positionals_of(parent)
  if !opts.is_empty() {
    segments.push(opts)
  }
  if !flags.is_empty() {
    segments.push(flags)
  }
  if !positionals.is_empty() {
    segments.push(positionals)
  }
  if parent.has_subcommands() {
    let parent_bin_name = parent.get_bin_name().unwrap()
    segments.push(
      "\":: :_\{parent_bin_name.replace_all(old=" ", new=zsh_cmd_sep)}_commands\" \\",
    )
    segments.push("\"*::: :->\{parent.get_name()}\" \\")
  } else if parent.is_allow_external_subcommands_set() {
    // If the command has an external subcommand value parser, we need to
    // add a catch-all for the subcommand. Otherwise there would be no autocompletion whatsoever.
    segments.push("\"*::external_command:_default\" \\")
  }
  segments.push("&& ret=0")
  segments.join("\n")
}

///|
/// Uses either `possible_vals` or `value_hint` to give hints about possible
/// argument values.
fn zsh_value_completion(arg : @clap.Arg) -> String? {
  if possible_values(arg) is Some(values) {
    if values.iter().any(v => !v.is_hide_set() && v.get_help() is Some(_)) {
      let items = []
      for value in values {
        if !value.is_hide_set() {
          items.push(
            "\{zsh_escape_value(value.get_name())}\\:\"\{zsh_escape_help(or_empty(value.get_help()))}\"",
          )
        }
      }
      Some("((\{items.join("\n")}))")
    } else {
      let items = values
        .filter(pv => !pv.is_hide_set())
        .map(pv => zsh_escape_value(pv.get_name()))
      Some("(\{items.join(" ")})")
    }
  } else {
    Some(
      match arg.get_value_hint() {
        Unknown => "_default"
        Other => ""
        AnyPath => "_files"
        FilePath => "_files"
        DirPath => "_files -/"
        ExecutablePath => "_absolute_command_paths"
        CommandName => "_command_names -e"
        CommandString => "_cmdstring"
        CommandWithArguments => "_cmdambivalent"
        Username => "_users"
        Hostname => "_hosts"
        Url => "_urls"
        EmailAddress => "_email_addresses"
      },
    )
  }
}

///|
/// Escape help string inside single quotes and brackets.
fn zsh_escape_help(s : String) -> String {
  s
  .replace_all(old="\\", new="\\\\")
  .replace_all(old="'", new="'\\''")
  .replace_all(old="[", new="\\[")
  .replace_all(old="]", new="\\]")
  .replace_all(old=":", new="\\:")
  .replace_all(old="$", new="\\$")
  .replace_all(old="`", new="\\`")
  .replace_all(old="\n", new=" ")
}

///|
/// Escape value string inside single quotes and parentheses.
fn zsh_escape_value(s : String) -> String {
  s
  .replace_all(old="\\", new="\\\\")
  .replace_all(old="'", new="'\\''")
  .replace_all(old="[", new="\\[")
  .replace_all(old="]", new="\\]")
  .replace_all(old=":", new="\\:")
  .replace_all(old="$", new="\\$")
  .replace_all(old="`", new="\\`")
  .replace_all(old="(", new="\\(")
  .replace_all(old=")", new="\\)")
  .replace_all(old=" ", new="\\ ")
}

///|
fn zsh_multiple(a : @clap.Arg) -> String {
  if a.get_action() is (Count | Append) {
    "*"
  } else {
    ""
  }
}

///|
fn zsh_write_opts_of(p : @clap.Command, p_global : @clap.Command?) -> String {
  let ret = []
  for o in p.get_opts() {
    let help = zsh_escape_help(or_empty(o.get_help()))
    let conflicts = zsh_arg_conflicts(p, o, p_global)
    let multiple = zsh_multiple(o)
    let vn = match o.get_value_names() {
      None => " "
      Some(val) => val[0]
    }
    let vc = match zsh_value_completion(o) {
      Some(val) => ":\{vn}:\{val}"
      None => ":\{vn}: "
    }
    let vc = match num_args(o).min_values() {
      0 => ":\{vc}"
      min_value => vc.repeat(min_value)
    }
    if o.get_short_and_visible_aliases() is Some(shorts) {
      for short in shorts {
        ret.push("'\{conflicts}\{multiple}-\{short}+[\{help}]\{vc}' \\")
      }
    }
    if o.get_long_and_visible_aliases() is Some(longs) {
      for long in longs {
        ret.push("'\{conflicts}\{multiple}--\{long}=[\{help}]\{vc}' \\")
      }
    }
  }
  ret.join("\n")
}

///|
fn zsh_arg_conflicts(
  cmd : @clap.Command,
  arg : @clap.Arg,
  app_global : @clap.Command?,
) -> String {
  let conflicts = match (app_global, arg.is_global_set()) {
    (Some(x), true) => x.get_arg_conflicts_with(arg)
    _ => cmd.get_arg_conflicts_with(arg)
  }
  if conflicts.is_empty() {
    return ""
  }
  let res = []
  for conflict in conflicts {
    if conflict.get_short() is Some(s) {
      res.push("-\{s}")
    }
    if conflict.get_long() is Some(l) {
      res.push("--\{l}")
    }
  }
  "(\{res.join(" ")})"
}

///|
fn zsh_write_flags_of(p : @clap.Command, p_global : @clap.Command?) -> String {
  let ret = []
  for f in flags(p) {
    let help = zsh_escape_help(or_empty(f.get_help()))
    let conflicts = zsh_arg_conflicts(p, f, p_global)
    let multiple = zsh_multiple(f)
    if f.get_short() is Some(short) {
      ret.push("'\{conflicts}\{multiple}-\{short}[\{help}]' \\")
      if f.get_visible_short_aliases() is Some(short_aliases) {
        for alias in short_aliases {
          ret.push("'\{conflicts}\{multiple}-\{alias}[\{help}]' \\")
        }
      }
    }
    if f.get_long() is Some(long) {
      ret.push("'\{conflicts}\{multiple}--\{long}[\{help}]' \\")
      if f.get_visible_aliases() is Some(aliases) {
        for alias in aliases {
          ret.push("'\{conflicts}\{multiple}--\{alias}[\{help}]' \\")
        }
      }
    }
  }
  ret.join("\n")
}

///|
fn zsh_write_positionals_of(p : @clap.Command) -> String {
  let ret = []
  // Completions for commands that end with two Vec arguments require special care.
  // - You can have two Vec args separated with a custom value terminator.
  // - You can have two Vec args with the second one set to last (raw sets last)
  //   which will require a '--' separator to be used before the second argument
  //   on the command-line.
  //
  // We use the '-S' _arguments option to disable completion after '--'. Thus, the
  // completion for the second argument in scenario (B) does not need to be emitted
  // because it is implicitly handled by the '-S' option.
  // We only need to emit the first catch-all.
  //
  // Have we already emitted a catch-all multi-valued positional argument
  // without a custom value terminator?
  let mut catch_all_emitted = false
  for arg in p.get_positionals() {
    let is_multi_valued = num_args(arg).max_values() > 1
    if catch_all_emitted && (arg.is_last_set() || is_multi_valued) {
      // This is the final argument and it also takes multiple arguments.
      // We've already emitted a catch-all positional argument so we don't need
      // to emit anything for this argument because it is implicitly handled by
      // the use of the '-S' _arguments option.
      continue
    }
    // If we have any subcommands, we'll emit a catch-all argument, so we shouldn't
    // emit one here.
    let cardinality = if is_multi_valued && !p.has_subcommands() {
      match arg.get_value_terminator() {
        Some(terminator) => "*\{zsh_escape_value(terminator)}:"
        None => {
          catch_all_emitted = true
          "*:"
        }
      }
    } else if !arg.is_required_set() {
      ":"
    } else {
      ""
    }
    let help = (match arg.get_help() {
        Some(v) => " -- \{v}"
        None => ""
      })
      .replace_all(old="[", new="\\[")
      .replace_all(old="]", new="\\]")
      .replace_all(old="'", new="'\\''")
      .replace_all(old=":", new="\\:")
    let value_completion = zsh_value_completion(arg).unwrap_or("")
    ret.push("'\{cardinality}:\{arg.get_id()}\{help}:\{value_completion}' \\")
  }
  ret.join("\n")
}

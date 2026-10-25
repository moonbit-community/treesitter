// Port of clap_complete_nushell 4.6.2 `lib.rs`.

///|
fn generate_nushell(cmd : @clap.Command, buf : StringBuilder) -> Unit {
  let completions = StringBuilder()
  completions.write_string("module completions {\n\n")
  nushell_generate_completion(completions, cmd, false)
  for sub in cmd.get_subcommands() {
    nushell_generate_completion(completions, sub, true)
  }
  completions.write_string("}\n\n")
  completions.write_string("export use completions *\n")
  buf.write_string(completions.to_string())
}

///|
/// The text after the last newline of `s` (the line `str::lines().last()`
/// yields while `s` does not end with a newline).
fn nushell_last_line(s : StringBuilder) -> String? {
  let s = s.to_string()
  if s.is_empty() {
    return None
  }
  let s = if s.has_suffix("\n") {
    // `lines()` does not yield an empty last line.
    let t = s.view(end_offset=s.length() - 1)
    let t = if t.has_suffix("\r") {
      t.view(end_offset=t.length() - 1)
    } else {
      t
    }
    t
  } else {
    s.view()
  }
  let line = match s.rev_find("\n") {
    Some(i) => s.view(start_offset=i + 1)
    None => s
  }
  let line = if line.has_suffix("\r") {
    line.view(end_offset=line.length() - 1)
  } else {
    line
  }
  Some(line.to_owned())
}

///|
fn nushell_append_value_completion_and_help(
  arg : @clap.Arg,
  name : String,
  possible_values : Array[@clap.PossibleValue],
  s : StringBuilder,
) -> Unit {
  let takes_values = match arg.get_num_args() {
    Some(r) => r.takes_values()
    None => false
  }
  if takes_values {
    let nu_type = match arg.get_value_hint() {
      Unknown => "string"
      Other => "string"
      AnyPath => "path"
      FilePath => "path"
      DirPath => "directory"
      ExecutablePath => "path"
      CommandName => "string"
      CommandString => "string"
      CommandWithArguments => "string"
      Username => "string"
      Hostname => "string"
      Url => "string"
      EmailAddress => "string"
    }
    s.write_string(": \{nu_type}")
    if !possible_values.is_empty() {
      s.write_string("@\"nu-complete \{name} \{arg.get_id()}\"")
    }
  }
  if arg.get_help() is Some(help) {
    let indent = 30
    let width = match nushell_last_line(s) {
      Some(line) => {
        let w = indent - utf8_len(line)
        if w < 0 {
          0
        } else {
          w
        }
      }
      None => 0
    }
    // `format!("{:>width$}", ' ')`: at least the one space.
    let pad = if width > 1 { width } else { 1 }
    s.write_string(" ".repeat(pad))
    s.write_string("# \{nushell_single_line(help)}")
  }
  s.write_char('\n')
}

///|
fn nushell_append_value_completion_defs(
  arg : @clap.Arg,
  name : String,
  s : StringBuilder,
) -> Unit {
  let possible_values = arg.get_possible_values()
  if possible_values.is_empty() {
    return
  }
  s.write_string("  def \"nu-complete \{name} \{arg.get_id()}\" [] {")
  s.write_string("\n    [")
  for value in possible_values {
    let vname = value.get_name()
    if vname.iter().any(c => c.is_whitespace()) {
      s.write_string(" \"\\\"\{vname}\\\"\"")
    } else {
      s.write_string(" \"\{vname}\"")
    }
  }
  s.write_string(" ]\n  }\n\n")
}

///|
fn nushell_append_argument(
  arg : @clap.Arg,
  name : String,
  s : StringBuilder,
) -> Unit {
  let possible_values = arg.get_possible_values()
  if arg.is_positional() {
    // rest arguments
    if arg.is_last_set() {
      // skipped, as it's not currently supported by nushell
      return
    }
    if arg.get_action() is Append {
      s.write_string("    ...\{arg.get_id()}")
    } else {
      s.write_string("    \{arg.get_id()}")
      if !arg.is_required_set() {
        s.write_char('?')
      }
    }
    nushell_append_value_completion_and_help(arg, name, possible_values, s)
    return
  }
  let shorts = arg.get_short_and_visible_aliases()
  let longs = arg.get_long_and_visible_aliases()
  match (shorts, longs) {
    (Some(shorts), Some(longs)) => {
      // short options and long options
      s.write_string("    --\{longs[0]}(-\{shorts[0]})")
      nushell_append_value_completion_and_help(arg, name, possible_values, s)
      // long alias
      for long in longs[1:] {
        s.write_string("    --\{long}")
        nushell_append_value_completion_and_help(arg, name, possible_values, s)
      }
      // short alias
      for short in shorts[1:] {
        s.write_string("    -\{short}")
        nushell_append_value_completion_and_help(arg, name, possible_values, s)
      }
    }
    (Some(shorts), None) =>
      // short options only
      for short in shorts {
        s.write_string("    -\{short}")
        nushell_append_value_completion_and_help(arg, name, possible_values, s)
      }
    (None, Some(longs)) =>
      // long options only
      for long in longs {
        s.write_string("    --\{long}")
        nushell_append_value_completion_and_help(arg, name, possible_values, s)
      }
    (None, None) => abort("No short or long options found")
  }
}

///|
fn nushell_generate_completion(
  completions : StringBuilder,
  cmd : @clap.Command,
  is_subcommand : Bool,
) -> Unit {
  let name = cmd.get_bin_name().unwrap()
  for arg in cmd.get_arguments() {
    if arg.is_last_set() {
      // skipped, as it's not currently supported by nushell
      continue
    }
    nushell_append_value_completion_defs(arg, name, completions)
  }
  if cmd.get_about() is Some(about) {
    completions.write_string("  # \{nushell_single_line(about)}\n")
  }
  if is_subcommand {
    completions.write_string("  export extern \"\{name}\" [\n")
  } else {
    completions.write_string("  export extern \{name} [\n")
  }
  let flags = cmd.get_arguments().filter(a => !a.is_positional())
  let positionals = cmd.get_positionals()
  // `sort_by_key(get_index)`: stable, `None` first.
  stable_sort_by(positionals, (a, b) => {
    match (a.get_index(), b.get_index()) {
      (None, None) => 0
      (None, Some(_)) => -1
      (Some(_), None) => 1
      (Some(x), Some(y)) => x.compare(y)
    }
  })
  for arg in flags {
    nushell_append_argument(arg, name, completions)
  }
  for arg in positionals {
    nushell_append_argument(arg, name, completions)
  }
  completions.write_string("  ]\n\n")
  if is_subcommand {
    for sub in cmd.get_subcommands() {
      nushell_generate_completion(completions, sub, true)
    }
  }
}

///|
fn nushell_single_line(text : String) -> String {
  text.replace_all(old="\n", new=" ")
}

// Port of clap_complete 4.6.11 `aot/shells/bash.rs`.

///|
let bash_cmd_sep : String = "__subcmd__"

///|
fn generate_bash(cmd : @clap.Command, buf : StringBuilder) -> Unit {
  let bin_name = cmd.get_bin_name().unwrap()
  let fn_name = bin_name.replace_all(old="-", new="__")
  let name_opts = bash_all_options_for_path(cmd, bin_name)
  let name_opts_details = bash_option_details_for_path(cmd, bin_name)
  let subcmds = bash_all_subcommands(cmd, fn_name)
  let subcmd_details = bash_subcommand_details(cmd)
  buf.write_string(
    (
      $|_\{fn_name}() {
      $|    local i cur prev opts cmd
      $|    COMPREPLY=()
      $|    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
      $|        cur="$2"
      $|    else
      $|        cur="${COMP_WORDS[COMP_CWORD]}"
      $|    fi
      $|    prev="$3"
      $|    cmd=""
      $|    opts=""
      $|
      $|    for i in "${COMP_WORDS[@]:0:COMP_CWORD}"
      $|    do
      $|        case "${cmd},${i}" in
      $|            ",$1")
      $|                cmd="\{fn_name}"
      $|                ;;\{subcmds}
      $|            *)
      $|                ;;
      $|        esac
      $|    done
      $|
      $|    case "${cmd}" in
      $|        \{fn_name})
      $|            opts="\{name_opts}"
      $|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 1 ]] ; then
      $|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      $|                return 0
      $|            fi
      $|            case "${prev}" in\{name_opts_details}
      $|                *)
      $|                    COMPREPLY=()
      $|                    ;;
      $|            esac
      $|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      $|            return 0
      $|            ;;\{subcmd_details}
      $|    esac
      $|}
      $|
      $|if [[ "${BASH_VERSINFO[0]}" -eq 4 && "${BASH_VERSINFO[1]}" -ge 4 || "${BASH_VERSINFO[0]}" -gt 4 ]]; then
      $|    complete -F _\{fn_name} -o nosort -o bashdefault -o default \{bin_name}
      $|else
      $|    complete -F _\{fn_name} -o bashdefault -o default \{bin_name}
      $|fi
      $|
    ),
  )
}

///|
fn bash_all_subcommands(cmd : @clap.Command, parent_fn_name : String) -> String {
  fn add_command(
    parent_fn_name : String,
    cmd : @clap.Command,
    subcmds : Array[(String, String, String)],
  ) -> Unit {
    let fn_name = "\{parent_fn_name}\{bash_cmd_sep}\{cmd.get_name().replace_all(old="-", new=bash_cmd_sep)}"
    subcmds.push((parent_fn_name, cmd.get_name(), fn_name))
    for alias in cmd.get_visible_aliases() {
      subcmds.push((parent_fn_name, alias, fn_name))
    }
    for subcmd in cmd.get_subcommands() {
      add_command(fn_name, subcmd, subcmds)
    }
  }

  let subcmds = []
  for subcmd in cmd.get_subcommands() {
    add_command(parent_fn_name, subcmd, subcmds)
  }
  subcmds.sort_by((a, b) => {
    let c = str_cmp(a.0, b.0)
    if c != 0 {
      return c
    }
    let c = str_cmp(a.1, b.1)
    if c != 0 {
      return c
    }
    str_cmp(a.2, b.2)
  })
  let cases = [""]
  for sc in subcmds {
    let (parent_fn_name, name, fn_name) = sc
    cases.push(
      (
        $|\{parent_fn_name},\{name})
        $|                cmd="\{fn_name}"
        $|                ;;
      ),
    )
  }
  cases.join("\n            ")
}

///|
fn bash_subcommand_details(cmd : @clap.Command) -> String {
  let subcmd_dets = [""]
  let scs = sort_dedup(
    all_subcommands(cmd).map(x => x.1.replace_all(old=" ", new=bash_cmd_sep)),
  )
  for sc in scs {
    let subcmd = sc.replace_all(old="-", new=bash_cmd_sep)
    let sc_opts = bash_all_options_for_path(cmd, sc)
    let level = sc.split(bash_cmd_sep).count()
    let opts_details = bash_option_details_for_path(cmd, sc)
    subcmd_dets.push(
      (
        $|\{subcmd})
        $|            opts="\{sc_opts}"
        $|            if [[ ${cur} == -* || ${COMP_CWORD} -eq \{level} ]] ; then
        $|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
        $|                return 0
        $|            fi
        $|            case "${prev}" in\{opts_details}
        $|                *)
        $|                    COMPREPLY=()
        $|                    ;;
        $|            esac
        $|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
        $|            return 0
        $|            ;;
      ),
    )
  }
  subcmd_dets.join("\n        ")
}

///|
/// `path.split(CMD_SEP).skip(1)`.
fn bash_path_components(path : String) -> Array[String] {
  path.split(bash_cmd_sep).drop(1).map(s => s.to_owned()).to_array()
}

///|
fn bash_option_details_for_path(cmd : @clap.Command, path : String) -> String {
  let p = find_subcommand_with_path(cmd, bash_path_components(path))
  let opts = [""]
  for o in p.get_opts() {
    let compopt = match o.get_value_hint() {
      FilePath => Some("compopt -o filenames")
      DirPath => Some("compopt -o plusdirs")
      Other => Some("compopt -o nospace")
      _ => None
    }
    let entry = (flag : String) => {
      let v = ["\{flag})"]
      if o.get_value_hint() is FilePath {
        v.push_iter(
          [
            "local oldifs",
            "if [ -n \"${IFS+x}\" ]; then",
            "    oldifs=\"$IFS\"",
            "fi",
            "IFS=$'\\n'",
            "COMPREPLY=(\{bash_vals_for(o)})",
            "if [ -n \"${oldifs+x}\" ]; then",
            "    IFS=\"$oldifs\"",
            "fi",
          ].iter(),
        )
      } else {
        v.push("COMPREPLY=(\{bash_vals_for(o)})")
      }
      if compopt is Some(copt) {
        v.push_iter(
          ["if [[ \"${BASH_VERSINFO[0]}\" -ge 4 ]]; then", "    \{copt}", "fi"].iter(),
        )
      }
      v.push("return 0")
      v.push(";;")
      v.join("\n                    ")
    }
    if o.get_long_and_visible_aliases() is Some(longs) {
      for long in longs {
        opts.push(entry("--\{long}"))
      }
    }
    if o.get_short_and_visible_aliases() is Some(shorts) {
      for short in shorts {
        opts.push(entry("-\{short}"))
      }
    }
  }
  opts.join("\n                ")
}

///|
fn bash_vals_for(o : @clap.Arg) -> String {
  if possible_values(o) is Some(vals) {
    let names = vals.filter(pv => !pv.is_hide_set()).map(pv => pv.get_name())
    "$(compgen -W \"\{names.join(" ")}\" -- \"${cur}\")"
  } else if o.get_value_hint() is DirPath {
    // should be empty to avoid duplicate candidates
    ""
  } else if o.get_value_hint() is Other {
    "\"${cur}\""
  } else {
    "$(compgen -f \"${cur}\")"
  }
}

///|
fn bash_all_options_for_path(cmd : @clap.Command, path : String) -> String {
  let p = find_subcommand_with_path(cmd, bash_path_components(path))
  let opts = StringBuilder()
  for short in shorts_and_visible_aliases(p) {
    opts.write_char('-')
    opts.write_char(short)
    opts.write_char(' ')
  }
  for long in longs_and_visible_aliases(p) {
    opts.write_string("--\{long} ")
  }
  for pos in p.get_positionals() {
    if possible_values(pos) is Some(vals) {
      for value in vals {
        opts.write_string("\{value.get_name()} ")
      }
    }
    // A positional without possible values has no literal completion word to
    // offer here; emitting its `<NAME>`/`[NAME]` usage placeholder would make
    // bash glob-expand the brackets (#6407), so leave it to the `-o default`
    // (filename) fallback instead.
  }
  for sc in subcommands(p) {
    opts.write_string("\{sc.0} ")
  }
  let opts = opts.to_string()
  // `String::pop`
  if opts.is_empty() {
    opts
  } else {
    opts.view(end_offset=opts.length() - 1).to_owned()
  }
}

// Parts of clap_builder 4.6.7 `builder/command.rs` that clap_complete uses
// and that the parser does not need: the expanded help tree built by the
// public `Command::build` (`_build_recursive(true)`) and
// `Command::get_arg_conflicts_with`.

///|
/// clap's public `Command::build`: `_build_recursive(true)` followed by
/// `_build_bin_names_internal`. Unlike `Command::build` of this package
/// (the parser's lazy `_build_self(false)` path, applied recursively), the
/// auto-generated `help` subcommand gets a copy of the subcommand tree
/// instead of its `subcommand` positional, as clap_complete expects.
pub fn Command::build_with_help_tree(self : Command) -> Unit {
  self.build_recursive_expanded()
  self.build_bin_names()
}

///|
/// `Command::_build_recursive(true)`.
fn Command::build_recursive_expanded(self : Command) -> Unit {
  self.build_self_expanded()
  for sc in self.subcommands {
    sc.build_recursive_expanded()
  }
}

///|
/// `Command::_build_self(true)`.
fn Command::build_self_expanded(self : Command) -> Unit {
  if self.built {
    return
  }
  // `_propagate`: `DisableHelpSubcommand` is a global setting. (When it was
  // set by `_build_self` because there are no subcommands, there is nothing
  // to propagate it to.)
  if self.disable_help_subcommand {
    for sc in self.subcommands {
      sc.disable_help_subcommand = true
    }
  }
  if !self.has_subcommands() || self.disable_help_subcommand {
    self.build_self()
    return
  }
  // `_check_help_and_version` with `expand_help_tree`.
  let help_about = "Print this message or the help of the given subcommand(s)"
  let help = Command::new("help").about(help_about)
  help.disable_help_subcommand = true
  help.disable_help_flag = true
  help.disable_version_flag = true
  for sc in self.subcommands {
    let _ = help.subcommand(sc.copy_subtree_for_help())
  }
  let help_help = Command::new("help").about(help_about)
  help_help.disable_help_flag = true
  help_help.disable_version_flag = true
  let _ = help.subcommand(help_help)
  // Let `build_self` add the flags without its own (unexpanded) help
  // subcommand, then add the expanded one.
  self.disable_help_subcommand = true
  self.build_self()
  self.disable_help_subcommand = false
  self.subcommands.push(help)
}

///|
/// `Command::_copy_subtree_for_help`.
fn Command::copy_subtree_for_help(self : Command) -> Command {
  let cmd = Command::new(self.name).hide(self.hide)
  cmd.disable_help_flag = true
  cmd.disable_version_flag = true
  for sc in self.subcommands {
    let copy = sc.copy_subtree_for_help()
    let _ = cmd.subcommand(copy)
  }
  if self.about is Some(about) {
    cmd.about = Some(about)
  }
  cmd
}

///|
/// `Command::get_arg_conflicts_with`: the arguments `arg` conflicts with,
/// with groups unrolled.
pub fn Command::get_arg_conflicts_with(self : Command, arg : Arg) -> Array[Arg] {
  if arg.global {
    self.get_global_arg_conflicts_with(arg)
  } else {
    let result = []
    for id in arg.conflicts {
      if self.find(id) is Some(a) {
        result.push(a)
      } else if self.find_group(id) is Some(group) {
        for id in self.unroll_args_in_group(group.id) {
          guard self.find(id) is Some(a) else {
            abort("Fatal internal error. Please consider filing a bug report")
          }
          result.push(a)
        }
      } else {
        abort(
          "Command::get_arg_conflicts_with: The passed arg conflicts with an arg unknown to the cmd",
        )
      }
    }
    result
  }
}

///|
/// `Command::get_global_arg_conflicts_with`.
fn Command::get_global_arg_conflicts_with(self : Command, arg : Arg) -> Array[Arg] {
  let candidates = [..self.args]
  for sc in self.get_subcommands_containing(arg) {
    candidates.push_iter(sc.args.iter())
  }
  arg.conflicts.map(id => {
    for a in candidates {
      if a.id == id {
        return a
      }
    }
    abort(
      "Command::get_arg_conflicts_with: The passed arg conflicts with an arg unknown to the cmd",
    )
  })
}

///|
/// `Command::get_subcommands_containing`.
fn Command::get_subcommands_containing(self : Command, arg : Arg) -> Array[Command] {
  let result = []
  for sc in self.subcommands {
    if sc.args.iter().any(a => a.id == arg.id) {
      result.push(sc)
      result.push_iter(sc.get_subcommands_containing(arg).iter())
    }
  }
  result
}

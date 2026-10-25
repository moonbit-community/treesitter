// Port of the parts of clap_builder 4.6.7 `builder/command.rs` and
// `builder/arg_group.rs` that the tree-sitter CLI uses.

///|
/// `clap::ArgGroup`.
pub struct ArgGroup {
  id : String
  priv mut args : Array[String]
  priv mut required : Bool
  priv mut multiple : Bool
  priv mut conflicts : Array[String]
  priv mut requires : Array[String]
}

///|
pub fn ArgGroup::new(id : String) -> ArgGroup {
  {
    id,
    args: [],
    required: false,
    multiple: false,
    conflicts: [],
    requires: [],
  }
}

///|
pub fn ArgGroup::multiple(self : ArgGroup, m : Bool) -> ArgGroup {
  self.multiple = m
  self
}

///|
pub fn ArgGroup::required(self : ArgGroup, r : Bool) -> ArgGroup {
  self.required = r
  self
}

///|
pub fn ArgGroup::arg(self : ArgGroup, id : String) -> ArgGroup {
  self.args.push(id)
  self
}

///|
/// `ArgGroup::args`: add each of `ids` to the group.
pub fn ArgGroup::args(self : ArgGroup, ids : Array[String]) -> ArgGroup {
  for id in ids {
    self.args.push(id)
  }
  self
}

///|
pub fn ArgGroup::get_id(self : ArgGroup) -> String {
  self.id
}

///|
pub fn ArgGroup::get_args(self : ArgGroup) -> Array[String] {
  self.args
}

///|
/// `clap::Command`.
pub struct Command {
  priv mut name : String
  priv mut bin_name : String?
  priv mut display_name : String?
  priv mut usage_name : String?
  priv mut author : String?
  priv mut version : String?
  priv mut about : String?
  priv mut long_about : String?
  priv mut before_help : String?
  priv mut after_help : String?
  priv mut help_template : String?
  priv mut aliases : Array[(String, Bool)]
  priv mut short_flag : Char?
  priv mut long_flag : String?
  priv mut args : Array[Arg]
  priv mut groups : Array[ArgGroup]
  priv mut subcommands : Array[Command]
  priv mut subcommand_required : Bool
  priv mut arg_required_else_help : Bool
  priv mut disable_help_subcommand : Bool
  // `g_settings`: the global settings (only `DisableHelpSubcommand` is
  // modelled), propagated to subcommands by `_propagate`.
  priv mut g_disable_help_subcommand : Bool
  priv mut disable_help_flag : Bool
  priv mut disable_version_flag : Bool
  priv mut hide : Bool
  priv mut disp_ord : Int32?
  priv mut current_disp_ord : Int32
  priv mut subcommand_value_name : String?
  priv mut subcommand_help_heading : String?
  priv mut long_help_exists : Bool
  priv mut built : Bool
  priv mut bin_names_built : Bool
}

///|
pub fn Command::new(name : String) -> Command {
  {
    name,
    bin_name: None,
    display_name: None,
    usage_name: None,
    author: None,
    version: None,
    about: None,
    long_about: None,
    before_help: None,
    after_help: None,
    help_template: None,
    aliases: [],
    short_flag: None,
    long_flag: None,
    args: [],
    groups: [],
    subcommands: [],
    subcommand_required: false,
    arg_required_else_help: false,
    disable_help_subcommand: false,
    g_disable_help_subcommand: false,
    disable_help_flag: false,
    disable_version_flag: false,
    hide: false,
    disp_ord: None,
    current_disp_ord: 0,
    subcommand_value_name: None,
    subcommand_help_heading: None,
    long_help_exists: false,
    built: false,
    bin_names_built: false,
  }
}

///|
/// `Command::arg` (`arg_internal`): every non-positional argument advances
/// the display-order counter, and gets its value unless it has an explicit
/// display order.
pub fn Command::arg(self : Command, arg : Arg) -> Command {
  if !arg.is_positional() {
    let current = self.current_disp_ord
    if arg.disp_ord is None {
      arg.disp_ord = Some(current)
    }
    self.current_disp_ord = current + 1
  }
  self.args.push(arg)
  self
}

///|
pub fn Command::group(self : Command, group : ArgGroup) -> Command {
  self.groups.push(group)
  self
}

///|
/// `Command::subcommand` (`subcommand_internal`): every subcommand advances
/// the display-order counter, and gets its value unless it has an explicit
/// display order.
pub fn Command::subcommand(self : Command, sub : Command) -> Command {
  let current = self.current_disp_ord
  if sub.disp_ord is None {
    sub.disp_ord = Some(current)
  }
  self.current_disp_ord = current + 1
  self.subcommands.push(sub)
  self
}

///|
pub fn Command::about(self : Command, about : String) -> Command {
  self.about = Some(about)
  self
}

///|
pub fn Command::long_about(self : Command, about : String) -> Command {
  self.long_about = Some(about)
  self
}

///|
pub fn Command::author(self : Command, author : String) -> Command {
  self.author = Some(author)
  self
}

///|
pub fn Command::version(self : Command, version : String) -> Command {
  self.version = Some(version)
  self
}

///|
pub fn Command::help_template(self : Command, template : String) -> Command {
  self.help_template = Some(template)
  self
}

///|
pub fn Command::alias(self : Command, name : String) -> Command {
  self.aliases.push((name, false))
  self
}

///|
pub fn Command::visible_alias(self : Command, name : String) -> Command {
  self.aliases.push((name, true))
  self
}

///|
pub fn Command::subcommand_required(self : Command, yes : Bool) -> Command {
  self.subcommand_required = yes
  self
}

///|
pub fn Command::arg_required_else_help(self : Command, yes : Bool) -> Command {
  self.arg_required_else_help = yes
  self
}

///|
/// `Command::disable_help_subcommand`: a global setting
/// (`global_setting`/`unset_global_setting`).
pub fn Command::disable_help_subcommand(self : Command, yes : Bool) -> Command {
  self.disable_help_subcommand = yes
  self.g_disable_help_subcommand = yes
  self
}

///|
pub fn Command::hide(self : Command, yes : Bool) -> Command {
  self.hide = yes
  self
}

///|
pub fn Command::display_order(self : Command, ord : Int32) -> Command {
  self.disp_ord = Some(ord)
  self
}

///|
pub fn Command::bin_name(self : Command, name : String) -> Command {
  self.bin_name = Some(name)
  self
}

// Getters.

///|
pub fn Command::get_name(self : Command) -> String {
  self.name
}

///|
pub fn Command::get_bin_name(self : Command) -> String? {
  self.bin_name
}

///|
pub fn Command::set_bin_name(self : Command, name : String) -> Unit {
  self.bin_name = Some(name)
}

///|
pub fn Command::get_display_name(self : Command) -> String? {
  self.display_name
}

///|
pub fn Command::get_author(self : Command) -> String? {
  self.author
}

///|
pub fn Command::get_version(self : Command) -> String? {
  self.version
}

///|
pub fn Command::get_about(self : Command) -> String? {
  self.about
}

///|
pub fn Command::get_long_about(self : Command) -> String? {
  self.long_about
}

///|
pub fn Command::get_before_help(self : Command) -> String? {
  self.before_help
}

///|
pub fn Command::get_after_help(self : Command) -> String? {
  self.after_help
}

///|
pub fn Command::get_short_flag(self : Command) -> Char? {
  self.short_flag
}

///|
pub fn Command::get_long_flag(self : Command) -> String? {
  self.long_flag
}

///|
pub fn Command::get_arguments(self : Command) -> Array[Arg] {
  self.args
}

///|
pub fn Command::get_groups(self : Command) -> Array[ArgGroup] {
  self.groups
}

///|
pub fn Command::get_positionals(self : Command) -> Array[Arg] {
  self.args.filter(a => a.is_positional())
}

///|
pub fn Command::get_non_positionals(self : Command) -> Array[Arg] {
  self.args.filter(a => !a.is_positional())
}

///|
/// `Command::get_opts`: non-positional arguments that take values.
pub fn Command::get_opts(self : Command) -> Array[Arg] {
  self.args.filter(a => a.is_takes_value_set() && !a.is_positional())
}

///|
pub fn Command::get_subcommands(self : Command) -> Array[Command] {
  self.subcommands
}

///|
pub fn Command::has_subcommands(self : Command) -> Bool {
  !self.subcommands.is_empty()
}

///|
pub fn Command::has_visible_subcommands(self : Command) -> Bool {
  self.subcommands.iter().any(s => s.name != "help" && !s.hide)
}

///|
pub fn Command::get_visible_aliases(self : Command) -> Array[String] {
  self.aliases.filter(a => a.1).map(a => a.0)
}

///|
pub fn Command::get_all_aliases(self : Command) -> Array[String] {
  self.aliases.map(a => a.0)
}

///|
/// `Command::get_name_and_visible_aliases`.
pub fn Command::get_name_and_visible_aliases(self : Command) -> Array[String] {
  [self.name, ..self.get_visible_aliases()]
}

///|
pub fn Command::is_hide_set(self : Command) -> Bool {
  self.hide
}

///|
pub fn Command::is_subcommand_required_set(self : Command) -> Bool {
  self.subcommand_required
}

///|
pub fn Command::is_arg_required_else_help_set(self : Command) -> Bool {
  self.arg_required_else_help
}

///|
pub fn Command::is_allow_external_subcommands_set(_self : Command) -> Bool {
  false
}

///|
pub fn Command::get_display_order(self : Command) -> Int32 {
  self.disp_ord.unwrap_or(999)
}

///|
/// `Command::get_usage_name_fallback`.
fn Command::get_usage_name_fallback(self : Command) -> String {
  match self.usage_name {
    Some(n) => n
    None =>
      match self.bin_name {
        Some(n) => n
        None => self.name
      }
  }
}

///|
/// `Command::get_bin_name_fallback`.
fn Command::get_bin_name_fallback(self : Command) -> String {
  self.bin_name.unwrap_or(self.name)
}

///|
pub fn Command::find_subcommand(self : Command, name : String) -> Command? {
  for sc in self.subcommands {
    if sc.name == name || sc.aliases.iter().any(a => a.0 == name) {
      return Some(sc)
    }
  }
  None
}

///|
/// `Command::all_subcommand_names`: names and all aliases.
fn Command::all_subcommand_names(self : Command) -> Array[String] {
  let names = []
  for sc in self.subcommands {
    names.push(sc.name)
    for a in sc.aliases {
      names.push(a.0)
    }
  }
  names
}

///|
pub fn Command::find(self : Command, id : String) -> Arg? {
  for a in self.args {
    if a.id == id {
      return Some(a)
    }
  }
  None
}

///|
fn Command::find_group(self : Command, id : String) -> ArgGroup? {
  for g in self.groups {
    if g.id == id {
      return Some(g)
    }
  }
  None
}

///|
fn Command::groups_for_arg(self : Command, id : String) -> Array[String] {
  self.groups.filter(g => g.args.contains(id)).map(g => g.id)
}

///|
fn Command::unroll_args_in_group(
  self : Command,
  group : String,
) -> Array[String] {
  let result = []
  let pending = [group]
  let processed = []
  while pending.pop() is Some(g) {
    if processed.contains(g) {
      continue
    }
    processed.push(g)
    guard self.find_group(g) is Some(grp) else { continue }
    for n in grp.args {
      if result.contains(n) {
        continue
      }
      if self.find(n) is Some(_) {
        result.push(n)
      } else {
        pending.push(n)
      }
    }
  }
  result
}

///|
/// `Command::format_group`.
fn Command::format_group(self : Command, g : String) -> String {
  let parts = []
  for id in self.unroll_args_in_group(g) {
    guard self.find(id) is Some(x) else { continue }
    parts.push(
      if x.is_positional() {
        x.name_no_brackets()
      } else {
        x.to_string()
      },
    )
  }
  "<\{parts.join("|")}>"
}

///|
/// `Command::required_graph`: required args and groups.
fn Command::required_graph(self : Command) -> Array[String] {
  let reqs = []
  for a in self.args {
    if a.required {
      reqs.push(a.id)
    }
  }
  for g in self.groups {
    if g.required {
      reqs.push(g.id)
    }
  }
  reqs
}

///|
/// `Command::unroll_arg_requires` for `ArgPredicate::IsPresent` requirements.
fn Command::unroll_arg_requires(self : Command, arg : String) -> Array[String] {
  let processed = []
  let r_vec = [arg]
  let args = []
  while r_vec.pop() is Some(a) {
    if processed.contains(a) {
      continue
    }
    processed.push(a)
    if self.find(a) is Some(arg) {
      for r in arg.requires {
        if !args.contains(r) {
          args.push(r)
        }
        if self.find_group(r) is None {
          r_vec.push(r)
        }
      }
    }
  }
  args
}

///|
/// `Command::long_help_exists_`.
fn Command::long_help_exists_(self : Command) -> Bool {
  let should_long = (v : Arg) => {
    !v.hide &&
    (
      v.long_help is Some(_) ||
      (
        !v.hide_possible_values &&
        v.get_possible_values().iter().any(p => p.should_show_help())
      )
    )
  }
  self.long_about is Some(_) || self.args.iter().any(should_long)
}

///|
pub fn Command::long_help_exists(self : Command) -> Bool {
  self.long_help_exists
}

///|
/// `Command::build` (`_build_recursive`): build this command and all of its
/// subcommands, including bin names.
pub fn Command::build(self : Command) -> Unit {
  self.build_self()
  for sc in self.subcommands {
    sc.build()
  }
  self.build_bin_names()
}

///|
/// `Command::_build_self`.
fn Command::build_self(self : Command) -> Unit {
  if self.built {
    return
  }
  self.build_settings()
  if self.version is None {
    self.disable_version_flag = true
  }
  // `_check_help_and_version`.
  self.long_help_exists = self.long_help_exists_()
  if !self.disable_help_flag {
    let arg = Arg::new("help").short('h').long("help").action(Help)
    if self.long_help_exists {
      arg.help = Some("Print help (see more with '--help')")
      arg.long_help = Some("Print help (see a summary with '-h')")
    } else {
      arg.help = Some("Print help")
    }
    self.args.push(arg)
  }
  if !self.disable_version_flag {
    let arg = Arg::new("version")
      .short('V')
      .long("version")
      .action(Version)
      .help("Print version")
    self.args.push(arg)
  }
  if !self.disable_help_subcommand {
    let help = Command::new("help").about(
      "Print this message or the help of the given subcommand(s)",
    )
    help.disable_help_flag = true
    help.disable_version_flag = true
    let _ = help.arg(
      Arg::new("subcommand")
      .action(Append)
      .num_args(ValueRange::at_least(0))
      .value_name("COMMAND")
      .help("Print help for the subcommand(s)"),
    )
    self.subcommands.push(help)
  }
  self.propagate_global_args()
  let mut pos_counter = 1
  for a in self.args {
    for g in a.groups {
      match self.find_group(g) {
        Some(grp) => grp.args.push(a.id)
        None => {
          let grp = ArgGroup::new(g)
          grp.args.push(a.id)
          self.groups.push(grp)
        }
      }
    }
    a.build()
    if a.is_positional() && a.index is None {
      a.index = Some(pos_counter)
      pos_counter += 1
    }
  }
  self.built = true
}

///|
/// The settings part of `Command::_build_self` that precedes
/// `_check_help_and_version`: merge the global settings, disable the help
/// subcommand of a command without subcommands, and `_propagate`.
fn Command::build_settings(self : Command) -> Unit {
  // Make sure all the globally set flags apply to us as well.
  if self.g_disable_help_subcommand {
    self.disable_help_subcommand = true
  }
  if !self.has_subcommands() {
    self.disable_help_subcommand = true
  }
  self.propagate()
}

///|
/// `Command::_propagate`: `_propagate_subcommand` for each subcommand.
fn Command::propagate(self : Command) -> Unit {
  for sc in self.subcommands {
    if self.g_disable_help_subcommand {
      sc.disable_help_subcommand = true
      sc.g_disable_help_subcommand = true
    }
  }
}

///|
/// `Command::_propagate_global_args`: copy global arguments into each
/// subcommand that does not define an argument with the same id (except the
/// auto-generated `help` subcommand).
fn Command::propagate_global_args(self : Command) -> Unit {
  let autogenerated_help_subcommand = !self.disable_help_subcommand
  for sc in self.subcommands {
    if sc.name == "help" && autogenerated_help_subcommand {
      // Avoid propagating args to the autogenerated help subtrees used in
      // completion.
      continue
    }
    for a in self.args {
      if !a.global {
        continue
      }
      if sc.find(a.id) is Some(_) {
        continue
      }
      sc.args.push(a.clone())
    }
  }
}

///|
/// `Command::_build_subcommand`: set the usage, bin and display names of the
/// subcommand `name` and build it, as the parser does when it reaches it.
fn Command::build_subcommand(self : Command, name : String) -> Command? {
  let mid_string = StringBuilder()
  mid_string.write_char(' ')
  let reqs = Usage::new(self).get_required_usage_from([], None, true)
  for s in reqs {
    mid_string.write_string(s)
    mid_string.write_char(' ')
  }
  let mid_string = mid_string.to_string()
  guard self.subcommands.search_by(s => s.name == name) is Some(i) else {
    return None
  }
  let sc = self.subcommands[i]
  // Flag subcommands (`|--long`, `|-s`) are not modelled.
  let sc_names = sc.name
  sc.usage_name = Some(
    match self.bin_name {
      Some(bin_name) => "\{bin_name}\{mid_string}\{sc_names}"
      None => sc_names
    },
  )
  // bin_name should be parent's bin_name + [<reqs>] + the sc's name separated
  // by a space
  sc.bin_name = Some(
    match self.bin_name {
      Some(bin_name) => "\{bin_name} \{sc.name}"
      None => sc.name
    },
  )
  if sc.display_name is None {
    let self_display_name = self.display_name.unwrap_or(self.name)
    let sep = if self_display_name.is_empty() { "" } else { "-" }
    sc.display_name = Some("\{self_display_name}\{sep}\{sc.name}")
  }
  // Ensure all args are built and ready to parse
  sc.build_self()
  Some(sc)
}

///|
/// `Command::_build_bin_names_internal`.
fn Command::build_bin_names(self : Command) -> Unit {
  if self.bin_names_built {
    return
  }
  let mid_string = StringBuilder()
  mid_string.write_char(' ')
  let reqs = Usage::new(self).get_required_usage_from([], None, true)
  for s in reqs {
    mid_string.write_string(s)
    mid_string.write_char(' ')
  }
  let mid_string = mid_string.to_string()
  let self_bin_name = self.bin_name.unwrap_or(self.name)
  for sc in self.subcommands {
    if sc.usage_name is None {
      sc.usage_name = Some("\{self_bin_name}\{mid_string}\{sc.name}")
    }
    if sc.bin_name is None {
      let sep = if self_bin_name.is_empty() { "" } else { " " }
      sc.bin_name = Some("\{self_bin_name}\{sep}\{sc.name}")
    }
    if sc.display_name is None {
      let self_display_name = self.display_name.unwrap_or(self.name)
      let sep = if self_display_name.is_empty() { "" } else { "-" }
      sc.display_name = Some("\{self_display_name}\{sep}\{sc.name}")
    }
    sc.build_bin_names()
  }
  self.bin_names_built = true
}

///|
/// `Command::_render_version`.
fn Command::render_version(self : Command) -> String {
  let display_name = self.display_name.unwrap_or(self.name)
  "\{display_name} \{self.version.unwrap_or("")}\n"
}

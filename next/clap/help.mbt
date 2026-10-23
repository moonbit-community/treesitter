// Port of clap_builder 4.6.7 `output/help.rs` and `output/help_template.rs`,
// built without the `wrap_help` feature (text is never wrapped and the
// terminal width is 100) and rendered without styles.

///|
let tab : String = "  "

///|
let tab_width : Int = 2

///|
let short_size : Int = 4

///|
let next_line_indent : String = "        "

///|
let term_w : Int = 100

///|
let default_template : String = "{before-help}{about-with-newline}\n{usage-heading} {usage}\n\n{all-args}{after-help}"

///|
let default_no_args_template : String = "{before-help}{about-with-newline}\n{usage-heading} {usage}{after-help}"

///|
/// `output::help::write_help`.
pub fn Command::render_help(self : Command, use_long : Bool) -> String {
  let use_long = use_long && self.long_help_exists
  let writer = StringBuilder()
  let template = HelpTemplate::{ writer, cmd: self, use_long }
  match self.help_template {
    Some(tmpl) => template.write_templated_help(tmpl)
    None => {
      let pos = self.get_positionals().iter().any(a => should_show_arg(use_long, a))
      let non_pos = self
        .get_non_positionals()
        .iter()
        .any(a => should_show_arg(use_long, a))
      let subcmds = self.has_visible_subcommands()
      template.write_templated_help(
        if non_pos || pos || subcmds {
          default_template
        } else {
          default_no_args_template
        },
      )
    }
  }
  // `trim_start_lines`, `trim_end`, then a trailing newline.
  let mut text = writer.to_string()
  if text.find("\n") is Some(pos) {
    let leading = text.unsafe_substring(start=0, end=pos + 1)
    if leading.trim().is_empty() {
      text = text.unsafe_substring(start=pos + 1, end=text.length())
    }
  }
  trim_end(text) + "\n"
}

///|
priv struct HelpTemplate {
  writer : StringBuilder
  cmd : Command
  use_long : Bool
}

///|
fn HelpTemplate::write_templated_help(
  self : HelpTemplate,
  template : String,
) -> Unit {
  let parts = template.split("{").collect()
  self.writer.write_view(parts[0])
  for part in parts[1:] {
    guard part.find("}") is Some(close) else { continue }
    let tag = part.view(end_offset=close).to_owned()
    let rest = part.view(start_offset=close + 1)
    match tag {
      "name" =>
        self.writer.write_string(self.cmd.display_name.unwrap_or(self.cmd.name))
      "bin" => self.writer.write_string(self.cmd.name)
      "version" =>
        if self.cmd.version is Some(v) {
          self.writer.write_string(v)
        }
      "author" => self.write_author(false, false)
      "author-with-newline" => self.write_author(false, true)
      "author-section" => self.write_author(true, true)
      "about" => self.write_about(false, false)
      "about-with-newline" => self.write_about(false, true)
      "about-section" => self.write_about(true, true)
      "usage-heading" => self.writer.write_string("Usage:")
      "usage" =>
        self.writer.write_string(Usage::new(self.cmd).create_usage_no_title([]))
      "all-args" => self.write_all_args()
      "options" =>
        self.write_args(self.cmd.get_non_positionals(), option_sort_key)
      "positionals" =>
        self.write_args(self.cmd.get_positionals(), positional_sort_key)
      "subcommands" => self.write_subcommands(self.cmd)
      "tab" => self.writer.write_string(tab)
      "after-help" => self.write_after_help()
      "before-help" => self.write_before_help()
      _ => self.writer.write_string("{\{tag}}")
    }
    self.writer.write_view(rest)
  }
}

///|
fn HelpTemplate::write_author(
  self : HelpTemplate,
  before_new_line : Bool,
  after_new_line : Bool,
) -> Unit {
  if self.cmd.author is Some(author) {
    if before_new_line {
      self.writer.write_string("\n")
    }
    self.writer.write_string(author)
    if after_new_line {
      self.writer.write_string("\n")
    }
  }
}

///|
fn HelpTemplate::write_about(
  self : HelpTemplate,
  before_new_line : Bool,
  after_new_line : Bool,
) -> Unit {
  let about = if self.use_long {
    first_some(self.cmd.long_about, self.cmd.about)
  } else {
    self.cmd.about
  }
  if about is Some(output) {
    if before_new_line {
      self.writer.write_string("\n")
    }
    self.writer.write_string(output.replace_all(old="{n}", new="\n"))
    if after_new_line {
      self.writer.write_string("\n")
    }
  }
}

///|
fn HelpTemplate::write_before_help(self : HelpTemplate) -> Unit {
  if self.cmd.before_help is Some(output) {
    self.writer.write_string(output.replace_all(old="{n}", new="\n"))
    self.writer.write_string("\n\n")
  }
}

///|
fn HelpTemplate::write_after_help(self : HelpTemplate) -> Unit {
  if self.cmd.after_help is Some(output) {
    self.writer.write_string("\n\n")
    self.writer.write_string(output.replace_all(old="{n}", new="\n"))
  }
}

///|
fn HelpTemplate::write_all_args(self : HelpTemplate) -> Unit {
  let pos = self.cmd
    .get_positionals()
    .filter(a => a.help_heading is None && should_show_arg(self.use_long, a))
  let non_pos = self.cmd
    .get_non_positionals()
    .filter(a => a.help_heading is None && should_show_arg(self.use_long, a))
  let subcmds = self.cmd.has_visible_subcommands()
  let custom_headings = []
  for a in self.cmd.args {
    if a.help_heading is Some(h) {
      insert_unique(custom_headings, h)
    }
  }
  let mut first = true
  if subcmds {
    if !first {
      self.writer.write_string("\n\n")
    }
    first = false
    let heading = self.cmd.subcommand_help_heading.unwrap_or("Commands")
    self.writer.write_string("\{heading}:\n")
    self.write_subcommands(self.cmd)
  }
  if !pos.is_empty() {
    if !first {
      self.writer.write_string("\n\n")
    }
    first = false
    self.writer.write_string("Arguments:\n")
    self.write_args(pos, positional_sort_key)
  }
  if !non_pos.is_empty() {
    if !first {
      self.writer.write_string("\n\n")
    }
    first = false
    self.writer.write_string("Options:\n")
    self.write_args(non_pos, option_sort_key)
  }
  for heading in custom_headings {
    let args = self.cmd.args.filter(a => a.help_heading == Some(heading) &&
      should_show_arg(self.use_long, a))
    if !args.is_empty() {
      if !first {
        self.writer.write_string("\n\n")
      }
      first = false
      self.writer.write_string("\{heading}:\n")
      self.write_args(args, option_sort_key)
    }
  }
}

///|
fn positional_sort_key(arg : Arg) -> (Int, String) {
  (arg.index.unwrap_or(0), "")
}

///|
fn option_sort_key(arg : Arg) -> (Int, String) {
  let key = match arg.short {
    Some(x) => {
      let lower = if x >= 'A' && x <= 'Z' {
        Int::unsafe_to_char(x.to_int() + 32)
      } else {
        x
      }
      let suffix = if x >= 'a' && x <= 'z' { "0" } else { "1" }
      "\{lower}\{suffix}"
    }
    None =>
      match arg.long {
        Some(l) => l
        None => "{" + arg.id
      }
  }
  (arg.get_display_order(), key)
}

///|
fn compare_keys(a : (Int, String), b : (Int, String)) -> Int {
  let c = a.0.compare(b.0)
  if c != 0 {
    c
  } else {
    a.1.compare_bytes(b.1)
  }
}

///|
/// Byte-wise string comparison (Rust's `Ord for str`).
fn String::compare_bytes(self : String, other : String) -> Int {
  let n = if self.length() < other.length() {
    self.length()
  } else {
    other.length()
  }
  for i in 0..<n {
    let c = self[i].to_int().compare(other[i].to_int())
    if c != 0 {
      return c
    }
  }
  self.length().compare(other.length())
}

///|
fn HelpTemplate::write_args(
  self : HelpTemplate,
  args : Array[Arg],
  sort_key : (Arg) -> (Int, String),
) -> Unit {
  let mut longest = 2
  // `BTreeMap<key, &Arg>`: sorted by key; a duplicate key replaces the value.
  let ord_v : Array[((Int, String), Arg)] = []
  for arg in args {
    if !should_show_arg(self.use_long, arg) {
      continue
    }
    let width = display_width(arg.to_string())
    let actual_width = if arg.long is Some(_) {
      width + short_size
    } else {
      width
    }
    longest = longest.max(actual_width)
    let key = sort_key(arg)
    match ord_v.search_by(e => compare_keys(e.0, key) == 0) {
      Some(i) => ord_v[i] = (key, arg)
      None => ord_v.push((key, arg))
    }
  }
  ord_v.sort_by((a, b) => compare_keys(a.0, b.0))
  let next_line_help = self.will_args_wrap(args, longest)
  for i, entry in ord_v {
    if i != 0 {
      self.writer.write_string("\n")
      if next_line_help && self.use_long {
        self.writer.write_string("\n")
      }
    }
    self.write_arg(entry.1, next_line_help, longest)
  }
}

///|
fn HelpTemplate::write_arg(
  self : HelpTemplate,
  arg : Arg,
  next_line_help : Bool,
  longest : Int,
) -> Unit {
  let spec_vals = self.spec_vals(arg)
  self.writer.write_string(tab)
  if arg.short is Some(s) {
    self.writer.write_char('-')
    self.writer.write_char(s)
  } else if arg.long is Some(_) {
    self.writer.write_string("    ")
  }
  if arg.long is Some(l) {
    if arg.short is Some(_) {
      self.writer.write_string(", ")
    }
    self.writer.write_string("--\{l}")
  }
  self.writer.write_string(arg.stylize_arg_suffix())
  self.align_to_about(arg, next_line_help, longest)
  let about = if self.use_long {
    first_some(arg.long_help, arg.help).unwrap_or("")
  } else {
    first_some(arg.help, arg.long_help).unwrap_or("")
  }
  self.help(Some(arg), about, spec_vals, next_line_help, longest)
}

///|
fn HelpTemplate::align_to_about(
  self : HelpTemplate,
  arg : Arg,
  next_line_help : Bool,
  longest : Int,
) -> Unit {
  let padding = if self.use_long || next_line_help {
    0
  } else if !arg.is_positional() {
    let self_len = display_width(arg.to_string()) + short_size
    let padding = if arg.long is Some(_) { tab_width } else { tab_width + 4 }
    longest + padding - self_len
  } else {
    let self_len = display_width(arg.to_string())
    longest + tab_width - self_len
  }
  self.writer.write_string(" ".repeat(padding))
}

///|
fn indent_text(text : String, trailing : String) -> String {
  text.replace_all(old="\n", new="\n" + trailing)
}

///|
fn HelpTemplate::help(
  self : HelpTemplate,
  arg : Arg?,
  about : String,
  spec_vals : String,
  next_line_help : Bool,
  longest : Int,
) -> Unit {
  if next_line_help {
    self.writer.write_string("\n")
    self.writer.write_string(tab)
    self.writer.write_string(next_line_indent)
  }
  let spaces = if next_line_help {
    tab.length() + next_line_indent.length()
  } else {
    longest + tab_width * 2
  }
  let trailing_indent = " ".repeat(spaces)
  let mut help = about
  let mut help_is_empty = help.is_empty()
  help = help.replace_all(old="{n}", new="\n")
  let next_line_specs = self.use_long && arg is Some(_)
  if !spec_vals.is_empty() && !next_line_specs {
    if !help_is_empty {
      help = help + " "
    }
    help = help + spec_vals
    help_is_empty = help.is_empty()
  }
  self.writer.write_string(indent_text(help, trailing_indent))
  let mut has_possible_values = false
  if arg is Some(arg) {
    if !arg.hide_possible_values && self.use_long_pv(arg) {
      let possible_vals = arg.get_possible_values()
      if !possible_vals.is_empty() {
        has_possible_values = true
        let mut longest_pv = 0
        for f in possible_vals {
          if !f.hide {
            longest_pv = longest_pv.max(display_width(f.name))
          }
        }
        let spaces = spaces + tab_width - 2
        let trailing_indent = " ".repeat(spaces + 2)
        if !help_is_empty {
          self.writer.write_string("\n\n" + " ".repeat(spaces))
        }
        self.writer.write_string("Possible values:")
        for pv in possible_vals {
          if pv.hide {
            continue
          }
          let mut descr = pv.name
          if pv.help is Some(h) {
            let padding = longest_pv - display_width(pv.name)
            descr = descr + ": " + " ".repeat(padding) + h
          }
          descr = descr.replace_all(old="{n}", new="\n")
          self.writer.write_string("\n" + " ".repeat(spaces) + "- ")
          self.writer.write_string(indent_text(descr, trailing_indent))
        }
      }
    }
  }
  if !spec_vals.is_empty() && next_line_specs {
    let mut help = ""
    if !help_is_empty || has_possible_values {
      help = "\n\n"
    }
    help = help + spec_vals
    self.writer.write_string(indent_text(help, trailing_indent))
  }
}

///|
fn HelpTemplate::will_args_wrap(
  self : HelpTemplate,
  args : Array[Arg],
  longest : Int,
) -> Bool {
  args
  .iter()
  .filter(a => should_show_arg(self.use_long, a))
  .any(a => self.arg_next_line_help(a, self.spec_vals(a), longest))
}

///|
fn HelpTemplate::arg_next_line_help(
  self : HelpTemplate,
  arg : Arg,
  spec_vals : String,
  longest : Int,
) -> Bool {
  if arg.next_line_help || self.use_long {
    true
  } else {
    let h = first_some(arg.help, arg.long_help).unwrap_or("")
    let h_w = display_width(h) + display_width(spec_vals)
    let taken = longest + tab_width * 2
    term_w >= taken &&
    taken.to_double() / term_w.to_double() > 0.40 &&
    h_w > term_w - taken
  }
}

///|
fn HelpTemplate::spec_vals(self : HelpTemplate, a : Arg) -> String {
  let spec_vals = []
  if a.env is Some((name, value)) {
    spec_vals.push("[env: \{name}=\{value.unwrap_or("")}]")
  }
  if a.is_takes_value_set() &&
    !a.hide_default_value &&
    !a.default_vals.is_empty() {
    let dvs = a.default_vals.map(escape).join(" ")
    spec_vals.push("[default: \{dvs}]")
  }
  let als = []
  for s in a.short_aliases {
    if s.1 {
      als.push("-\{s.0}")
    }
  }
  for l in a.aliases {
    if l.1 {
      als.push("--\{l.0}")
    }
  }
  if !als.is_empty() {
    let plural = if als.length() == 1 { "" } else { "es" }
    spec_vals.push("[alias\{plural}: \{als.join(", ")}]")
  }
  if !a.hide_possible_values && !self.use_long_pv(a) {
    let possible_vals = a.get_possible_values()
    if !possible_vals.is_empty() {
      let pvs = possible_vals
        .filter_map(p => p.get_visible_quoted_name())
        .join(", ")
      spec_vals.push("[possible values: \{pvs}]")
    }
  }
  spec_vals.join(if self.use_long { "\n" } else { " " })
}

///|
fn HelpTemplate::use_long_pv(self : HelpTemplate, arg : Arg) -> Bool {
  self.use_long &&
  arg.get_possible_values().iter().any(p => p.should_show_help())
}

///|
fn HelpTemplate::write_subcommands(self : HelpTemplate, cmd : Command) -> Unit {
  let mut longest = 2
  let ord_v : Array[((Int, String), Command)] = []
  for subcommand in cmd.subcommands {
    if !should_show_subcommand(subcommand) {
      continue
    }
    let sb = StringBuilder()
    sb.write_string(subcommand.name)
    if subcommand.short_flag is Some(s) {
      sb.write_string(", -")
      sb.write_char(s)
    }
    if subcommand.long_flag is Some(l) {
      sb.write_string(", --\{l}")
    }
    let styled = sb.to_string()
    longest = longest.max(display_width(styled))
    ord_v.push(((subcommand.get_display_order(), styled), subcommand))
  }
  ord_v.sort_by((a, b) => compare_keys(a.0, b.0))
  let next_line_help = cmd.subcommands
    .iter()
    .filter(should_show_subcommand)
    .any(s => self.subcommand_next_line_help(s, sc_spec_vals(s), longest))
  for i, entry in ord_v {
    if i > 0 {
      self.writer.write_string("\n")
    }
    let (key, sc) = entry
    let spec_vals = sc_spec_vals(sc)
    let about = first_some(sc.about, sc.long_about).unwrap_or("")
    self.writer.write_string(tab)
    self.writer.write_string(key.1)
    if !next_line_help {
      let padding = longest + tab_width - display_width(key.1)
      self.writer.write_string(" ".repeat(padding))
    }
    self.help(None, about, spec_vals, next_line_help, longest)
  }
}

///|
fn sc_spec_vals(a : Command) -> String {
  let als = a.get_visible_aliases()
  if als.is_empty() {
    ""
  } else {
    let plural = if als.length() == 1 { "" } else { "es" }
    "[alias\{plural}: \{als.join(", ")}]"
  }
}

///|
fn HelpTemplate::subcommand_next_line_help(
  _self : HelpTemplate,
  cmd : Command,
  spec_vals : String,
  longest : Int,
) -> Bool {
  let h = first_some(cmd.about, cmd.long_about).unwrap_or("")
  let h_w = display_width(h) + display_width(spec_vals)
  let taken = longest + tab_width * 2
  term_w >= taken &&
  taken.to_double() / term_w.to_double() > 0.40 &&
  h_w > term_w - taken
}

///|
fn should_show_arg(use_long : Bool, arg : Arg) -> Bool {
  // `hide_short_help`/`hide_long_help` are not modelled.
  ignore(use_long)
  !arg.hide
}

///|
fn should_show_subcommand(subcommand : Command) -> Bool {
  !subcommand.hide
}

///|
/// `output::display_width` (the `unicode` feature is off: one column per
/// `char`).
fn display_width(s : String) -> Int {
  let mut width = 0
  let mut control_sequence = false
  for ch in s {
    if ch.to_int() < 0x20 || ch.to_int() == 0x7f {
      control_sequence = true
    } else if control_sequence && ch == 'm' {
      control_sequence = false
      continue
    }
    if !control_sequence {
      width += 1
    }
  }
  width
}

///|
/// `util::Escape`: values that are empty or contain whitespace are printed
/// with `Debug` quoting.
fn escape(s : String) -> String {
  if s.is_empty() || s.iter().any(c => c.is_whitespace()) {
    debug_str(s)
  } else {
    s
  }
}

///|
/// Rust's `Debug for str` for the characters that occur in option values.
fn debug_str(s : String) -> String {
  let sb = StringBuilder()
  sb.write_char('"')
  for c in s {
    match c {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      _ => sb.write_char(c)
    }
  }
  sb.write_char('"')
  sb.to_string()
}

///|
/// `Option::or`.
fn[T] first_some(a : T?, b : T?) -> T? {
  match a {
    Some(_) => a
    None => b
  }
}

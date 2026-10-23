// Port of clap_builder 4.6.7 `output/usage.rs` (without styles).

///|
let default_sub_value_name : String = "COMMAND"

///|
priv struct Usage {
  cmd : Command
  required : Array[String]?
}

///|
fn Usage::new(cmd : Command) -> Usage {
  { cmd, required: None }
}

///|
fn Usage::with_required(self : Usage, required : Array[String]) -> Usage {
  { ..self, required: Some(required) }
}

///|
fn Usage::create_usage_with_title(self : Usage, used : Array[String]) -> String {
  let styled = StringBuilder()
  styled.write_string("Usage: ")
  self.write_usage_no_title(styled, used)
  trim_end(styled.to_string())
}

///|
fn Usage::create_usage_no_title(self : Usage, used : Array[String]) -> String {
  let styled = StringBuilder()
  self.write_usage_no_title(styled, used)
  trim_end(styled.to_string())
}

///|
fn Usage::write_usage_no_title(
  self : Usage,
  styled : StringBuilder,
  used : Array[String],
) -> Unit {
  if used.is_empty() {
    self.write_help_usage(styled)
  } else {
    self.write_smart_usage(styled, used)
  }
}

///|
fn Usage::write_help_usage(self : Usage, styled : StringBuilder) -> Unit {
  self.write_arg_usage(styled, [], true)
  self.write_subcommand_usage(styled)
}

///|
fn Usage::write_smart_usage(
  self : Usage,
  styled : StringBuilder,
  used : Array[String],
) -> Unit {
  self.write_arg_usage(styled, used, true)
  if self.cmd.subcommand_required {
    let value_name = self.cmd.subcommand_value_name.unwrap_or(
      default_sub_value_name,
    )
    styled.write_string("<\{value_name}>")
  }
}

///|
fn Usage::write_arg_usage(
  self : Usage,
  styled : StringBuilder,
  used : Array[String],
  incl_reqs : Bool,
) -> Unit {
  let bin_name = self.cmd.get_usage_name_fallback()
  if !bin_name.is_empty() {
    styled.write_string("\{bin_name} ")
  }
  if used.is_empty() && self.needs_options_tag() {
    styled.write_string("[OPTIONS] ")
  }
  self.write_args(styled, used, !incl_reqs)
}

///|
fn Usage::write_subcommand_usage(self : Usage, styled : StringBuilder) -> Unit {
  if self.cmd.has_visible_subcommands() {
    let value_name = self.cmd.subcommand_value_name.unwrap_or(
      default_sub_value_name,
    )
    if self.cmd.subcommand_required {
      styled.write_string("<\{value_name}>")
    } else {
      styled.write_string("[\{value_name}]")
    }
  }
}

///|
fn Usage::needs_options_tag(self : Usage) -> Bool {
  for f in self.cmd.get_non_positionals() {
    if f.long == Some("help") || f.long == Some("version") {
      continue
    }
    if f.get_action() is (Help | HelpShort | HelpLong | Version) {
      continue
    }
    if f.hide || f.required {
      continue
    }
    if self.cmd
      .groups_for_arg(f.id)
      .iter()
      .any(g => self.cmd.groups.iter().any(grp => grp.id == g && grp.required)) {
      continue
    }
    return true
  }
  false
}

///|
fn Usage::required_list(self : Usage) -> Array[String] {
  match self.required {
    Some(r) => r
    None => self.cmd.required_graph()
  }
}

///|
fn insert_unique(set : Array[String], value : String) -> Unit {
  if !set.contains(value) {
    set.push(value)
  }
}

///|
/// `FlatSet` iteration order is insertion order; clap sorts nothing here.
fn Usage::write_args(
  self : Usage,
  styled : StringBuilder,
  incls : Array[String],
  force_optional : Bool,
) -> Unit {
  let unrolled_reqs = []
  for a in self.required_list() {
    for aa in self.cmd.unroll_arg_requires(a) {
      unrolled_reqs.push(aa)
    }
    unrolled_reqs.push(a)
  }
  let required_groups_members = []
  let required_groups = []
  for req in [..unrolled_reqs, ..incls] {
    if self.cmd.find_group(req) is Some(_) {
      let group_members = self.cmd.unroll_args_in_group(req)
      insert_unique(required_groups, self.cmd.format_group(req))
      for m in group_members {
        insert_unique(required_groups_members, m)
      }
    }
  }
  let required_opts = []
  let required_positionals : Array[String?] = []
  for req in [..unrolled_reqs, ..incls] {
    guard self.cmd.find(req) is Some(arg) else { continue }
    if required_groups_members.contains(arg.id) {
      continue
    }
    let stylized = arg.stylized(required=!force_optional)
    if arg.index is Some(index) {
      while required_positionals.length() < index + 1 {
        required_positionals.push(None)
      }
      required_positionals[index] = Some(stylized)
    } else {
      insert_unique(required_opts, stylized)
    }
  }
  for pos in self.cmd.get_positionals() {
    if pos.hide || required_groups_members.contains(pos.id) {
      continue
    }
    let index = pos.index.unwrap()
    while required_positionals.length() < index + 1 {
      required_positionals.push(None)
    }
    if required_positionals[index] is Some(s) {
      if pos.last {
        required_positionals[index] = Some("-- \{s}")
      }
    } else if pos.last {
      required_positionals[index] = Some("[-- \{pos.stylized(required=true)}]")
    } else {
      required_positionals[index] = Some(pos.stylized(required=false))
    }
    if pos.last && force_optional {
      required_positionals[index] = None
    }
  }
  if !force_optional {
    for arg in required_opts {
      styled.write_string(arg)
      styled.write_string(" ")
    }
    for arg in required_groups {
      styled.write_string(arg)
      styled.write_string(" ")
    }
  }
  for arg in required_positionals {
    if arg is Some(arg) {
      styled.write_string(arg)
      styled.write_string(" ")
    }
  }
}

///|
/// `Usage::get_required_usage_from`.
fn Usage::get_required_usage_from(
  self : Usage,
  incls : Array[String],
  matcher : ArgMatches?,
  incl_last : Bool,
) -> Array[String] {
  let unrolled_reqs = []
  for a in self.required_list() {
    for aa in self.cmd.unroll_arg_requires(a) {
      unrolled_reqs.push(aa)
    }
    unrolled_reqs.push(a)
  }
  let is_present = (id : String) => match matcher {
    Some(m) => m.check_explicit(id)
    None => false
  }
  let required_groups_members = []
  let required_groups = []
  for req in [..unrolled_reqs, ..incls] {
    if self.cmd.find_group(req) is Some(_) {
      let group_members = self.cmd.unroll_args_in_group(req)
      if group_members.iter().any(is_present) {
        continue
      }
      insert_unique(required_groups, self.cmd.format_group(req))
      for m in group_members {
        insert_unique(required_groups_members, m)
      }
    }
  }
  let required_opts = []
  let required_positionals : Array[String?] = []
  for req in [..unrolled_reqs, ..incls] {
    guard self.cmd.find(req) is Some(arg) else { continue }
    if required_groups_members.contains(arg.id) {
      continue
    }
    if is_present(req) {
      continue
    }
    let stylized = arg.stylized(required=true)
    if arg.index is Some(index) {
      if !arg.last || incl_last {
        while required_positionals.length() < index + 1 {
          required_positionals.push(None)
        }
        required_positionals[index] = Some(stylized)
      }
    } else {
      insert_unique(required_opts, stylized)
    }
  }
  let ret_val = []
  ret_val.append(required_opts)
  ret_val.append(required_groups)
  for pos in required_positionals {
    if pos is Some(pos) {
      ret_val.push(pos)
    }
  }
  ret_val
}

///|
/// `StyledStr::trim_end`.
fn trim_end(s : String) -> String {
  let mut end = s.length()
  while end > 0 && s[end - 1] is (' ' | '\t' | '\n' | '\r') {
    end -= 1
  }
  s.unsafe_substring(start=0, end~)
}

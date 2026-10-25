// Port of clap_builder 4.6.7 `parser/parser.rs`, `parser/validator.rs`,
// `parser/arg_matcher.rs` and `parser/matches/arg_matches.rs`, restricted to
// the settings the tree-sitter CLI uses (no flag subcommands, external
// subcommands, `last`, inferred names, value delimiters or terminators).

///|
/// `clap::parser::ValueSource`.
pub(all) enum ValueSource {
  DefaultValue
  EnvVariable
  CommandLine
} derive(Eq, Debug)

///|
fn ValueSource::is_explicit(self : ValueSource) -> Bool {
  !(self is DefaultValue)
}

///|
priv struct MatchedArg {
  mut source : ValueSource
  vals : Array[String]
}

///|
/// `clap::ArgMatches`.
pub struct ArgMatches {
  priv args : Map[String, MatchedArg]
  priv mut subcommand : (String, ArgMatches)?
}

///|
fn ArgMatches::new() -> ArgMatches {
  { args: {}, subcommand: None, }
}

///|
fn ArgMatches::check_explicit(self : ArgMatches, id : String) -> Bool {
  match self.args.get(id) {
    Some(m) => m.source.is_explicit()
    None => false
  }
}

///|
/// The name and matches of the subcommand that was used.
pub fn ArgMatches::subcommand(self : ArgMatches) -> (String, ArgMatches)? {
  self.subcommand
}

///|
/// Whether a `SetTrue` flag is set.
pub fn ArgMatches::get_flag(self : ArgMatches, id : String) -> Bool {
  match self.args.get(id) {
    Some(m) => m.vals.last() == Some("true")
    None => false
  }
}

///|
/// The value of an argument, if it has one (`get_one`).
pub fn ArgMatches::get_one(self : ArgMatches, id : String) -> String? {
  match self.args.get(id) {
    Some(m) => m.vals.get(0)
    None => None
  }
}

///|
/// All values of an argument, if it occurred (`get_many`).
pub fn ArgMatches::get_many(self : ArgMatches, id : String) -> Array[String]? {
  match self.args.get(id) {
    Some(m) => Some(m.vals)
    None => None
  }
}

///|
/// Whether the argument is present (explicitly or from a default).
pub fn ArgMatches::contains_id(self : ArgMatches, id : String) -> Bool {
  self.args.contains(id)
}

///|
pub fn ArgMatches::value_source(self : ArgMatches, id : String) -> ValueSource? {
  match self.args.get(id) {
    Some(m) => Some(m.source)
    None => None
  }
}

///|
priv enum Identifier {
  Short
  Long
  Index
}

///|
priv struct PendingArg {
  id : String
  ident : Identifier?
  raw_vals : Array[String]
}

///|
priv enum ParseState {
  ValuesDone
  Opt(String)
  Pos(String)
}

///|
priv enum ParseResult {
  FlagSubCommand(String)
  Opt(String)
  ValuesDone
  AttachedValueNotConsumed
  UnneededAttachedValue(rest~ : String, used~ : Array[String], arg~ : String)
  EqualsNotProvided(String)
  NoMatchingArg(String)
  NoArg
}

///|
priv struct Parser {
  cmd : Command
  matcher : ArgMatches
  mut pending : PendingArg?
}

///|
/// `Command::try_get_matches_from`: `args[0]` is the binary name. The command
/// is built first.
pub fn Command::try_get_matches_from(
  self : Command,
  args : Array[String],
) -> ArgMatches raise ClapError {
  self.build_self()
  self.build_bin_names_shallow()
  let p = Parser::{ cmd: self, matcher: ArgMatches::new(), pending: None, }
  p.get_matches_with(args, 1)
  p.matcher
}

///|
/// Build only this command's immediate bin names (subcommands are built
/// lazily as they are parsed, like `_build_subcommand`).
fn Command::build_bin_names_shallow(self : Command) -> Unit {
  if self.bin_names_built {
    return
  }
  self.build_bin_names()
}

///|
fn Parser::get_matches_with(
  self : Parser,
  args : Array[String],
  start : Int32,
) -> Unit raise ClapError {
  self.parse(args, start)
  self.resolve_pending()
  self.add_env()
  self.add_defaults()
  self.validate()
}

///|
fn is_escape(arg : String) -> Bool {
  arg == "--"
}

///|
/// `ParsedArg::to_long`.
fn to_long(arg : String) -> (String, String?)? {
  if arg.has_prefix("--") && arg.length() > 2 {
    let rest = arg.unsafe_substring(start=2, end=arg.length())
    match rest.find("=") {
      Some(i) =>
        Some(
          (
            rest.unsafe_substring(start=0, end=i),
            Some(rest.unsafe_substring(start=i + 1, end=rest.length())),
          ),
        )
      None => Some((rest, None))
    }
  } else {
    None
  }
}

///|
/// `ParsedArg::to_short`: the flag characters after `-`.
fn to_short(arg : String) -> Array[Char]? {
  if arg.has_prefix("-") && !arg.has_prefix("--") && arg.length() > 1 {
    Some(arg.unsafe_substring(start=1, end=arg.length()).iter().collect())
  } else {
    None
  }
}

///|
fn is_long(arg : String) -> Bool {
  arg.has_prefix("--") && arg.length() > 2
}

///|
fn is_short(arg : String) -> Bool {
  arg.has_prefix("-") && !arg.has_prefix("--") && arg.length() > 1
}

///|
fn Parser::find_long(self : Parser, long : String) -> Arg? {
  for a in self.cmd.args {
    if a.long == Some(long) || a.aliases.iter().any(al => al.0 == long) {
      return Some(a)
    }
  }
  None
}

///|
fn Parser::find_short(self : Parser, c : Char) -> Arg? {
  for a in self.cmd.args {
    if a.short == Some(c) || a.short_aliases.iter().any(al => al.0 == c) {
      return Some(a)
    }
  }
  None
}

///|
fn Parser::find_position(self : Parser, index : Int32) -> Arg? {
  for a in self.cmd.args {
    if a.is_positional() && a.index == Some(index) {
      return Some(a)
    }
  }
  None
}

///|
fn Parser::usage(self : Parser) -> String {
  Usage::new(self.cmd).create_usage_with_title([])
}

///|
fn Parser::parse(
  self : Parser,
  args : Array[String],
  start : Int32,
) -> Unit raise ClapError {
  let mut subcmd_name : String? = None
  let mut parse_state = ParseState::ValuesDone
  let mut pos_counter = 1
  let mut valid_arg_found = false
  let mut trailing_values = false
  let positional_count = self.cmd.get_positionals().length()
  let mut cursor = start
  while cursor < args.length() {
    let arg_os = args[cursor]
    cursor += 1
    if !trailing_values {
      if !(parse_state is (Opt(_) | Pos(_))) {
        if self.possible_subcommand(arg_os, valid_arg_found) is Some(sc_name) {
          subcmd_name = Some(sc_name)
          break
        }
      }
      if is_escape(arg_os) {
        trailing_values = true
        continue
      } else if to_long(arg_os) is Some((long_arg, long_value)) {
        match self.parse_long_arg(long_arg, long_value, pos_counter) {
          NoArg => ()
          ValuesDone => {
            valid_arg_found = true
            parse_state = ValuesDone
            continue
          }
          Opt(id) => {
            valid_arg_found = true
            parse_state = Opt(id)
            continue
          }
          FlagSubCommand(name) => {
            subcmd_name = Some(name)
            break
          }
          EqualsNotProvided(arg) => {
            self.resolve_pending() catch {
              _ => ()
            }
            raise error_no_equals(arg, self.usage())
          }
          NoMatchingArg(arg) => {
            self.resolve_pending() catch {
              _ => ()
            }
            raise self.did_you_mean_error(
              arg,
              args[cursor:].to_owned(),
              trailing_values,
            )
          }
          UnneededAttachedValue(rest~, used~, arg~) => {
            self.resolve_pending() catch {
              _ => ()
            }
            raise error_too_many_values(
              rest,
              arg,
              Usage::new(self.cmd).create_usage_with_title(used),
            )
          }
          AttachedValueNotConsumed => ()
        }
      } else if to_short(arg_os) is Some(short_arg) {
        match self.parse_short_arg(short_arg) {
          NoArg => ()
          ValuesDone => {
            valid_arg_found = true
            parse_state = ValuesDone
            continue
          }
          Opt(id) => {
            valid_arg_found = true
            parse_state = Opt(id)
            continue
          }
          FlagSubCommand(name) => {
            subcmd_name = Some(name)
            break
          }
          EqualsNotProvided(arg) => {
            self.resolve_pending() catch {
              _ => ()
            }
            raise error_no_equals(arg, self.usage())
          }
          NoMatchingArg(arg) => {
            self.resolve_pending() catch {
              _ => ()
            }
            let suggested_trailing_arg = !trailing_values &&
              !self.cmd.get_positionals().is_empty()
            raise error_unknown_argument(
              arg,
              None,
              suggested_trailing_arg,
              self.usage(),
            )
          }
          _ => ()
        }
      }
      if parse_state is Opt(id) {
        let arg = self.cmd.find(id).unwrap()
        let pending = self.pending_values(id, None)
        pending.push(arg_os)
        parse_state = if arg.num_vals.unwrap().accepts_more(pending.length()) {
          Opt(id)
        } else {
          ValuesDone
        }
        continue
      }
    }
    // Correct pos_counter: the second-to-last positional may be multiple.
    let is_second_to_last = pos_counter + 1 == positional_count
    let low_index_mults = is_second_to_last &&
      self.cmd
      .get_positionals()
      .iter()
      .any(a => a.is_multiple() && positional_count != a.index.unwrap_or(0))
    if low_index_mults {
      let skip_current = match args.get(cursor) {
        Some(n) =>
          match self.find_position(pos_counter) {
            Some(arg) =>
              self.is_new_arg(n, arg) ||
              self.possible_subcommand(n, valid_arg_found) is Some(_)
            None => true
          }
        None => true
      }
      if skip_current {
        pos_counter += 1
      }
    }
    match self.find_position(pos_counter) {
      Some(arg) => {
        match self.pending {
          Some(p) if p.id == arg.id && arg.is_multiple_values_set() => ()
          _ => self.resolve_pending()
        }
        let pending = self.pending_values(arg.id, Some(Index))
        pending.push(arg_os)
        if !arg.is_multiple() {
          pos_counter += 1
          parse_state = ValuesDone
        } else {
          parse_state = Pos(arg.id)
        }
        valid_arg_found = true
      }
      None => {
        self.resolve_pending() catch {
          _ => ()
        }
        raise self.match_arg_error(arg_os, valid_arg_found, trailing_values)
      }
    }
  }
  if subcmd_name is Some(name) {
    let sc = self.cmd.find_subcommand(name).unwrap()
    self.resolve_pending()
    sc.build_self()
    sc.build_bin_names_shallow()
    let p = Parser::{ cmd: sc, matcher: ArgMatches::new(), pending: None, }
    p.get_matches_with(args, cursor)
    self.matcher.subcommand = Some((sc.name, p.matcher))
  }
}

///|
fn Parser::match_arg_error(
  self : Parser,
  arg_os : String,
  valid_arg_found : Bool,
  trailing_values : Bool,
) -> ClapError {
  if trailing_values {
    if self.possible_subcommand(arg_os, valid_arg_found) is Some(_) {
      return error_unnecessary_double_dash(arg_os, self.usage())
    }
  }
  let has_positionals = !self.cmd.get_positionals().is_empty()
  let suggested_trailing_arg = !trailing_values &&
    has_positionals &&
    (is_long(arg_os) || is_short(arg_os))
  if self.cmd.has_subcommands() {
    let candidates = suggestions_did_you_mean(
      arg_os,
      self.cmd.all_subcommand_names(),
    )
    if !candidates.is_empty() {
      return error_invalid_subcommand(
        arg_os,
        candidates,
        self.cmd.get_bin_name_fallback(),
        suggested_trailing_arg,
        self.usage(),
      )
    }
    if !has_positionals {
      return error_unrecognized_subcommand(arg_os, self.usage())
    }
  }
  error_unknown_argument(arg_os, None, suggested_trailing_arg, self.usage())
}

///|
fn Parser::possible_subcommand(
  self : Parser,
  arg : String,
  _valid_arg_found : Bool,
) -> String? {
  match self.cmd.find_subcommand(arg) {
    Some(sc) => Some(sc.name)
    None => None
  }
}

///|
fn Parser::is_new_arg(self : Parser, next : String, current : Arg) -> Bool {
  ignore(self)
  if current.allow_hyphen_values {
    false
  } else {
    is_long(next) || is_short(next)
  }
}

///|
fn Parser::parse_long_arg(
  self : Parser,
  long_arg : String,
  long_value : String?,
  _pos_counter : Int32,
) -> ParseResult raise ClapError {
  match self.find_long(long_arg) {
    Some(arg) =>
      if arg.is_takes_value_set() {
        let has_eq = long_value is Some(_)
        self.parse_opt_value(Long, long_value, arg, has_eq)
      } else if long_value is Some(rest) {
        let required = self.cmd.required_graph()
        let used = []
        for id, m in self.matcher.args {
          if !m.source.is_explicit() {
            continue
          }
          match self.cmd.find(id) {
            Some(a) => if !(a.hide || required.contains(a.id)) { used.push(id) }
            None => used.push(id)
          }
        }
        used.push(arg.id)
        UnneededAttachedValue(rest~, used~, arg=arg.to_string())
      } else {
        self.react(Some(Long), CommandLine, arg, [])
      }
    None => NoMatchingArg(long_arg)
  }
}

///|
fn Parser::parse_short_arg(
  self : Parser,
  short_arg : Array[Char],
) -> ParseResult raise ClapError {
  let mut ret = ParseResult::NoArg
  let mut i = 0
  while i < short_arg.length() {
    let c = short_arg[i]
    i += 1
    match self.find_short(c) {
      Some(arg) => {
        if !arg.is_takes_value_set() {
          ret = self.react(Some(Short), CommandLine, arg, [])
          continue
        }
        let rest = String::from_array(short_arg[i:])
        let val = if rest.is_empty() { None } else { Some(rest) }
        let (val, has_eq) = match val {
          Some(v) if v.has_prefix("=") =>
            (Some(v.unsafe_substring(start=1, end=v.length())), true)
          v => (v, false)
        }
        match self.parse_opt_value(Short, val, arg, has_eq) {
          AttachedValueNotConsumed => continue
          x => return x
        }
      }
      None => return NoMatchingArg("-\{c}")
    }
  }
  ret
}

///|
fn Parser::parse_opt_value(
  self : Parser,
  ident : Identifier,
  attached_value : String?,
  arg : Arg,
  has_eq : Bool,
) -> ParseResult raise ClapError {
  if arg.require_equals && !has_eq {
    if arg.get_min_vals() == 0 {
      let _ = self.react(Some(ident), CommandLine, arg, [])
      if attached_value is Some(_) {
        AttachedValueNotConsumed
      } else {
        ValuesDone
      }
    } else {
      EqualsNotProvided(arg.to_string())
    }
  } else if attached_value is Some(v) {
    let _ = self.react(Some(ident), CommandLine, arg, [v])
    ValuesDone
  } else {
    self.resolve_pending()
    let _ = self.pending_values(arg.id, Some(ident))
    Opt(arg.id)
  }
}

///|
/// `ArgMatcher::pending_values_mut`.
fn Parser::pending_values(
  self : Parser,
  id : String,
  ident : Identifier?,
) -> Array[String] {
  match self.pending {
    Some(p) if p.id == id => p.raw_vals
    _ => {
      let p = PendingArg::{ id, ident, raw_vals: [], }
      self.pending = Some(p)
      p.raw_vals
    }
  }
}

///|
fn Parser::resolve_pending(self : Parser) -> Unit raise ClapError {
  guard self.pending is Some(pending) else { return }
  self.pending = None
  let arg = self.cmd.find(pending.id).unwrap()
  let _ = self.react(pending.ident, CommandLine, arg, pending.raw_vals)
}

///|
fn Parser::start_custom_arg(
  self : Parser,
  arg : Arg,
  source : ValueSource,
) -> Unit {
  match self.matcher.args.get(arg.id) {
    Some(m) => if m.source != source { m.source = source }
    None => self.matcher.args[arg.id] = { source, vals: [], }
  }
  if source.is_explicit() {
    for group in self.cmd.groups_for_arg(arg.id) {
      match self.matcher.args.get(group) {
        Some(m) => {
          m.source = source
          m.vals.push(arg.id)
        }
        None => self.matcher.args[group] = { source, vals: [arg.id], }
      }
    }
  }
}

///|
fn Parser::push_arg_values(
  self : Parser,
  arg : Arg,
  raw_vals : Array[String],
) -> Unit raise ClapError {
  for raw_val in raw_vals {
    let val = self.parse_value(arg, raw_val)
    self.matcher.args[arg.id].vals.push(val)
  }
}

///|
/// `ValueParser::parse_ref`.
fn Parser::parse_value(
  self : Parser,
  arg : Arg,
  value : String,
) -> String raise ClapError {
  ignore(self)
  let validation = (msg : String) => {
    error_value_validation(arg.to_string(), value, msg)
  }
  match arg.get_value_parser() {
    String | PathBuf => value
    Bool =>
      if value == "true" || value == "false" {
        value
      } else {
        raise error_invalid_value(value, ["true", "false"], arg.to_string())
      }
    U32 =>
      match parse_unsigned(value, 4294967295L) {
        Ok(_) => value
        Err(msg) => raise validation(msg)
      }
    U64 =>
      match parse_unsigned(value, -1L) {
        Ok(_) => value
        Err(msg) => raise validation(msg)
      }
    Usize =>
      match parse_unsigned(value, -1L) {
        Ok(_) => value
        Err(msg) => raise validation(msg)
      }
    Enum(values) =>
      if values.iter().any(p => p.matches(value, false)) {
        value
      } else {
        raise error_invalid_value(
          value,
          values.filter(p => !p.hide).map(p => p.name),
          arg.to_string(),
        )
      }
    Custom(validate) =>
      match validate(value) {
        None => value
        Some(msg) => raise validation(msg)
      }
  }
}

///|
/// Rust's integer `FromStr` errors (`max == -1` means `u64::MAX`), and clap's
/// `RangedI64ValueParser` range message for `u32`.
fn parse_unsigned(value : String, max : Int64) -> Result[UInt64, String] {
  if value.is_empty() {
    return Err("cannot parse integer from empty string")
  }
  let mut s = value
  if s.has_prefix("+") {
    s = s.unsafe_substring(start=1, end=s.length())
    if s.is_empty() {
      return Err("invalid digit found in string")
    }
  }
  if max != -1L && value.has_prefix("-") {
    // `u32` goes through `i64::from_str` and a range check.
    let digits = value.unsafe_substring(start=1, end=value.length())
    if digits.is_empty() || !digits.iter().all(c => c >= '0' && c <= '9') {
      return Err("invalid digit found in string")
    }
    return Err("\{value} is not in 0..=\{max}")
  }
  let mut n : UInt64 = 0
  let mut overflow = false
  for c in s {
    if c < '0' || c > '9' {
      return Err("invalid digit found in string")
    }
    let d = (c.to_int() - '0'.to_int()).to_uint64()
    if n > (18446744073709551615UL - d) / 10UL {
      overflow = true
    }
    n = n * 10UL + d
  }
  if max == -1L {
    if overflow {
      return Err("number too large to fit in target type")
    }
  } else if overflow || n > 9223372036854775807UL {
    return Err("number too large to fit in target type")
  } else if n > max.reinterpret_as_uint64() {
    return Err("\{value} is not in 0..=\{max}")
  }
  Ok(n)
}

///|
fn Parser::react(
  self : Parser,
  ident : Identifier?,
  source : ValueSource,
  arg : Arg,
  raw_vals : Array[String],
) -> ParseResult raise ClapError {
  self.resolve_pending()
  if source is CommandLine {
    self.verify_num_args(arg, raw_vals)
  }
  let raw_vals = if raw_vals.is_empty() && !arg.default_missing_vals.is_empty() {
    arg.default_missing_vals.copy()
  } else {
    raw_vals
  }
  match arg.get_action() {
    Set | SetTrue => {
      if self.matcher.args.contains(arg.id) {
        self.matcher.args.remove(arg.id)
        raise error_argument_conflict(
          arg.to_string(),
          [arg.to_string()],
          self.usage(),
        )
      }
      self.start_custom_arg(arg, source)
      self.push_arg_values(arg, raw_vals)
      ValuesDone
    }
    Append => {
      self.start_custom_arg(arg, source)
      self.push_arg_values(arg, raw_vals)
      ValuesDone
    }
    Count => {
      let existing = match self.matcher.args.get(arg.id) {
        Some(m) =>
          m.vals
          .get(0)
          .map(v => @string.parse_int(v) catch { _ => 0 })
          .unwrap_or(0)
        None => 0
      }
      self.matcher.args.remove(arg.id)
      self.start_custom_arg(arg, source)
      self.push_arg_values(arg, ["\{existing + 1}"])
      ValuesDone
    }
    Help => {
      let use_long = !(ident is Some(Short))
      raise ClapError(kind=DisplayHelp, message=self.cmd.render_help(use_long))
    }
    HelpShort =>
      raise ClapError(kind=DisplayHelp, message=self.cmd.render_help(false))
    HelpLong =>
      raise ClapError(kind=DisplayHelp, message=self.cmd.render_help(true))
    Version =>
      raise ClapError(kind=DisplayVersion, message=self.cmd.render_version())
  }
}

///|
fn Parser::verify_num_args(
  self : Parser,
  arg : Arg,
  raw_vals : Array[String],
) -> Unit raise ClapError {
  let actual = raw_vals.length()
  let expected = arg.num_vals.unwrap()
  if 0 < expected.min && actual == 0 {
    raise error_invalid_value(
      "",
      arg.get_possible_values().filter(p => !p.hide).map(p => p.name),
      arg.to_string(),
    )
  } else if expected.num_values() is Some(n) {
    if n != actual {
      raise error_wrong_number_of_values(
        arg.to_string(),
        n,
        actual,
        self.usage(),
      )
    }
  } else if actual < expected.min {
    raise error_too_few_values(
      arg.to_string(),
      expected.min,
      actual,
      self.usage(),
    )
  } else if expected.max < actual {
    raise error_too_many_values(
      raw_vals[raw_vals.length() - 1],
      arg.to_string(),
      self.usage(),
    )
  }
}

///|
fn Parser::add_env(self : Parser) -> Unit raise ClapError {
  for arg in self.cmd.args {
    if self.matcher.args.contains(arg.id) {
      continue
    }
    if arg.env is Some((_, Some(val))) {
      let _ = self.react(None, EnvVariable, arg, [val])
    }
  }
}

///|
fn Parser::add_defaults(self : Parser) -> Unit raise ClapError {
  for arg in self.cmd.args {
    if !arg.default_vals.is_empty() && !self.matcher.args.contains(arg.id) {
      let _ = self.react(None, DefaultValue, arg, arg.default_vals.copy())
    }
  }
}

///|
fn Parser::did_you_mean_error(
  self : Parser,
  arg : String,
  remaining_args : Array[String],
  trailing_values : Bool,
) -> ClapError {
  let longs = []
  for a in self.cmd.args {
    if a.long is Some(l) {
      longs.push(l)
    }
    for al in a.aliases {
      longs.push(al.0)
    }
  }
  let did_you_mean : (String, String?)? = match
    suggestions_did_you_mean(arg, longs).pop() {
    Some(candidate) => Some((candidate, None))
    None => {
      let mut best : (Int32, (String, String?))? = None
      for sc in self.cmd.subcommands {
        sc.build_self()
        let sc_longs = []
        for a in sc.args {
          if a.long is Some(l) {
            sc_longs.push(l)
          }
        }
        guard suggestions_did_you_mean(arg, sc_longs).pop() is Some(candidate) else {
          continue
        }
        guard remaining_args.search(sc.name) is Some(score) else { continue }
        match best {
          Some((s, _)) if s <= score => ()
          _ => best = Some((score, (candidate, Some(sc.name))))
        }
      }
      best.map(b => b.1)
    }
  }
  if did_you_mean is Some((name, _)) {
    if self.find_long(name) is Some(a) {
      self.start_custom_arg(a, CommandLine)
    }
  }
  let did_you_mean = did_you_mean.map(d => ("--" + d.0, d.1))
  let required = self.cmd.required_graph()
  let used = []
  for id, m in self.matcher.args {
    if m.source.is_explicit() &&
      (match self.cmd.find(id) {
        Some(a) => !a.hide
        None => false
      }) {
      used.push(id)
    }
  }
  let suggested_trailing_arg = did_you_mean is None &&
    !trailing_values &&
    !self.cmd.get_positionals().is_empty()
  error_unknown_argument(
    "--" + arg,
    did_you_mean,
    suggested_trailing_arg,
    Usage::new(self.cmd).with_required(required).create_usage_with_title(used),
  )
}

// Validation (`parser/validator.rs`).

///|
fn Parser::explicit_ids(self : Parser) -> Array[String] {
  let ids = []
  for id, m in self.matcher.args {
    if m.source.is_explicit() {
      ids.push(id)
    }
  }
  ids
}

///|
fn Parser::validate(self : Parser) -> Unit raise ClapError {
  let has_subcmd = self.matcher.subcommand is Some(_)
  if !has_subcmd && self.cmd.arg_required_else_help {
    if self.explicit_ids().is_empty() {
      raise ClapError(
        kind=DisplayHelpOnMissingArgumentOrSubcommand,
        message=self.cmd.render_help(false),
      )
    }
  }
  let required = self.cmd.required_graph()
  if !has_subcmd && self.cmd.subcommand_required {
    let bn = self.cmd.get_bin_name_fallback()
    raise error_missing_subcommand(
      bn,
      self.cmd.all_subcommand_names(),
      Usage::new(self.cmd).with_required(required).create_usage_with_title([]),
    )
  }
  let conflicts = self.potential_conflicts()
  self.validate_conflicts(conflicts, required)
  self.validate_required(conflicts, required)
}

///|
fn Parser::gather_direct_conflicts(self : Parser, id : String) -> Array[String] {
  match self.cmd.find(id) {
    Some(arg) => {
      let conf = arg.conflicts.copy()
      for group_id in self.cmd.groups_for_arg(arg.id) {
        let group = self.cmd.find_group(group_id).unwrap()
        conf.append(group.conflicts)
        if !group.multiple {
          for member in group.args {
            if member != arg.id {
              conf.push(member)
            }
          }
        }
      }
      conf
    }
    None =>
      match self.cmd.find_group(id) {
        Some(g) => g.conflicts.copy()
        None => []
      }
  }
}

///|
fn Parser::potential_conflicts(self : Parser) -> Array[(String, Array[String])] {
  self.explicit_ids().map(id => (id, self.gather_direct_conflicts(id)))
}

///|
fn Parser::gather_conflicts(
  self : Parser,
  potential : Array[(String, Array[String])],
  arg_id : String,
) -> Array[String] {
  let conflicts = []
  let arg_id_conflicts = match potential.search_by(p => p.0 == arg_id) {
    Some(i) => potential[i].1
    None => self.gather_direct_conflicts(arg_id)
  }
  for entry in potential {
    let (other, other_conflicts) = entry
    if arg_id == other {
      continue
    }
    if arg_id_conflicts.contains(other) {
      conflicts.push(other)
    }
    if other_conflicts.contains(arg_id) {
      conflicts.push(other)
    }
  }
  conflicts
}

///|
fn Parser::validate_conflicts(
  self : Parser,
  potential : Array[(String, Array[String])],
  required : Array[String],
) -> Unit raise ClapError {
  for arg_id in self.explicit_ids() {
    if self.cmd.find(arg_id) is None {
      continue
    }
    let conflict_ids = self.gather_conflicts(potential, arg_id)
    if conflict_ids.is_empty() {
      continue
    }
    let unrolled = []
    for c in conflict_ids {
      if self.cmd.find_group(c) is Some(_) {
        for m in self.cmd.unroll_args_in_group(c) {
          insert_unique(unrolled, m)
        }
      } else {
        insert_unique(unrolled, c)
      }
    }
    let conflicts = unrolled.map(c => self.cmd.find(c).unwrap().to_string())
    let former_arg = self.cmd.find(arg_id).unwrap()
    // `build_conflict_err_usage`.
    let used_filtered = self
      .explicit_ids()
      .filter(n => {
        (match self.cmd.find(n) {
          Some(a) => !a.hide
          None => false
        }) &&
        !unrolled.contains(n)
      })
    let req = []
    for key in used_filtered {
      match self.cmd.find(key) {
        Some(a) =>
          for r in a.requires {
            if !used_filtered.contains(r) && !unrolled.contains(r) {
              req.push(r)
            }
          }
        None => ()
      }
    }
    req.append(used_filtered)
    let usage = Usage::new(self.cmd)
      .with_required(required)
      .create_usage_with_title(req)
    raise error_argument_conflict(former_arg.to_string(), conflicts, usage)
  }
}

///|
fn Parser::validate_required(
  self : Parser,
  potential : Array[(String, Array[String])],
  required : Array[String],
) -> Unit raise ClapError {
  // `gather_requires`.
  let required = required.copy()
  for name in self.explicit_ids() {
    if self.cmd.find(name) is Some(arg) {
      for req in self.cmd.unroll_arg_requires(arg.id) {
        insert_unique(required, req)
      }
    } else if self.cmd.find_group(name) is Some(g) {
      for r in g.requires {
        insert_unique(required, r)
      }
    }
  }
  let missing_required = []
  let mut highest_index = 0
  for arg_or_group in required {
    if self.matcher.check_explicit(arg_or_group) {
      continue
    }
    if self.cmd.find(arg_or_group) is Some(arg) {
      let missing_ok = !self.gather_conflicts(potential, arg.id).is_empty() ||
        self.cmd
        .groups_for_arg(arg.id)
        .iter()
        .any(g => !self.gather_conflicts(potential, g).is_empty())
      if !missing_ok {
        missing_required.push(arg.id)
        if !arg.last {
          highest_index = highest_index.max(arg.index.unwrap_or(0))
        }
      }
    } else if self.cmd.find_group(arg_or_group) is Some(group) {
      if !self.cmd
        .unroll_args_in_group(group.id)
        .iter()
        .any(a => self.matcher.check_explicit(a)) {
        missing_required.push(group.id)
      }
    }
  }
  for pos in self.cmd.get_positionals() {
    if self.matcher.check_explicit(pos.id) {
      continue
    }
    if pos.index.unwrap_or(0) < highest_index {
      missing_required.push(pos.id)
    }
  }
  if !missing_required.is_empty() {
    let usg = Usage::new(self.cmd).with_required(required)
    let req_args = usg.get_required_usage_from(
      missing_required,
      Some(self.matcher),
      true,
    )
    let used = self
      .explicit_ids()
      .filter(n => {
        match self.cmd.find(n) {
          Some(a) => !a.hide
          None => false
        }
      })
    used.append(missing_required)
    raise error_missing_required_argument(
      req_args,
      usg.create_usage_with_title(used),
    )
  }
}

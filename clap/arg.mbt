// Port of the parts of clap_builder 4.6.7 `builder/arg.rs`,
// `builder/action.rs`, `builder/range.rs`, `builder/possible_value.rs` and
// `builder/value_hint.rs` that the tree-sitter CLI uses. Styles are not
// modelled: output is always rendered as clap renders it without colors.

///|
/// `clap::ArgAction`.
pub(all) enum ArgAction {
  Set
  Append
  SetTrue
  Count
  Help
  HelpShort
  HelpLong
  Version
} derive(Eq, Debug)

///|
fn ArgAction::default_num_args(self : ArgAction) -> ValueRange {
  match self {
    Set | Append => ValueRange::single()
    _ => ValueRange::empty()
  }
}

///|
/// `clap::builder::ValueRange`; `max == value_range_unbounded` means no
/// upper bound.
pub(all) struct ValueRange {
  min : Int32
  max : Int32
} derive(Eq, Debug)

///|
pub let value_range_unbounded : Int32 = 2147483647

///|
pub fn ValueRange::new(min : Int32, max : Int32) -> ValueRange {
  { min, max, }
}

///|
pub fn ValueRange::empty() -> ValueRange {
  { min: 0, max: 0, }
}

///|
pub fn ValueRange::single() -> ValueRange {
  { min: 1, max: 1, }
}

///|
/// `n..`
pub fn ValueRange::at_least(n : Int32) -> ValueRange {
  { min: n, max: value_range_unbounded, }
}

///|
pub fn ValueRange::min_values(self : ValueRange) -> Int32 {
  self.min
}

///|
pub fn ValueRange::max_values(self : ValueRange) -> Int32 {
  self.max
}

///|
pub fn ValueRange::takes_values(self : ValueRange) -> Bool {
  self.max != 0
}

///|
pub fn ValueRange::is_unbounded(self : ValueRange) -> Bool {
  self.max == value_range_unbounded
}

///|
pub fn ValueRange::is_fixed(self : ValueRange) -> Bool {
  self.min == self.max
}

///|
pub fn ValueRange::is_multiple(self : ValueRange) -> Bool {
  self.min != self.max || self.min != 1
}

///|
pub fn ValueRange::num_values(self : ValueRange) -> Int32? {
  if self.min == self.max {
    Some(self.min)
  } else {
    None
  }
}

///|
pub fn ValueRange::accepts_more(self : ValueRange, current : Int32) -> Bool {
  current < self.max
}

///|
/// `Display for ValueRange` (used by clap_complete's nushell generator).
pub fn ValueRange::to_string(self : ValueRange) -> String {
  if self.is_unbounded() {
    "\{self.min}.."
  } else {
    "\{self.min}..=\{self.max}"
  }
}

///|
/// `clap::builder::PossibleValue`.
pub(all) struct PossibleValue {
  name : String
  help : String?
  aliases : Array[String]
  hide : Bool
} derive(Debug)

///|
pub fn PossibleValue::new(name : String, help? : String) -> PossibleValue {
  { name, help, aliases: [], hide: false, }
}

///|
pub fn PossibleValue::get_name(self : PossibleValue) -> String {
  self.name
}

///|
pub fn PossibleValue::get_help(self : PossibleValue) -> String? {
  self.help
}

///|
pub fn PossibleValue::is_hide_set(self : PossibleValue) -> Bool {
  self.hide
}

///|
pub fn PossibleValue::should_show_help(self : PossibleValue) -> Bool {
  !self.hide && self.help is Some(_)
}

///|
/// `PossibleValue::get_visible_quoted_name`: the name, `Debug`-quoted if it is
/// empty or contains whitespace (`Escape::to_cow`).
pub fn PossibleValue::get_visible_quoted_name(self : PossibleValue) -> String? {
  if self.hide {
    None
  } else {
    Some(escape(self.name))
  }
}

///|
pub fn PossibleValue::get_name_and_aliases(
  self : PossibleValue,
) -> Array[String] {
  [self.name, ..self.aliases]
}

///|
pub fn PossibleValue::matches(
  self : PossibleValue,
  value : String,
  ignore_case : Bool,
) -> Bool {
  self
  .get_name_and_aliases()
  .iter()
  .any(name => {
    if ignore_case {
      name.to_lower() == value.to_lower()
    } else {
      name == value
    }
  })
}

///|
/// `clap::ValueHint`.
pub(all) enum ValueHint {
  Unknown
  Other
  AnyPath
  FilePath
  DirPath
  ExecutablePath
  CommandName
  CommandString
  CommandWithArguments
  Username
  Hostname
  Url
  EmailAddress
} derive(Eq, Debug)

///|
/// The value parsers used by the tree-sitter CLI (`value_parser!` of the
/// field types). `Custom` validators return an error message for an invalid
/// value, as the `FromStr` implementation would display it.
pub(all) enum ValueParser {
  String
  PathBuf
  Bool
  U8
  U32
  U64
  Usize
  Enum(Array[PossibleValue])
  Custom((String) -> String?)
}

///|
fn ValueParser::possible_values(self : ValueParser) -> Array[PossibleValue] {
  match self {
    Bool => [PossibleValue::new("true"), PossibleValue::new("false")]
    Enum(values) => values
    _ => []
  }
}

///|
/// `clap::Arg`.
pub struct Arg {
  id : String
  priv mut short : Char?
  priv mut long : String?
  priv mut help : String?
  priv mut long_help : String?
  priv mut action : ArgAction?
  priv mut num_vals : ValueRange?
  priv mut val_names : Array[String]
  priv mut value_parser : ValueParser?
  priv mut value_hint : ValueHint?
  priv mut index : Int32?
  priv mut required : Bool
  priv mut hide : Bool
  priv mut last : Bool
  priv mut global : Bool
  priv mut exclusive : Bool
  priv mut require_equals : Bool
  priv mut allow_hyphen_values : Bool
  priv mut hide_possible_values : Bool
  priv mut hide_default_value : Bool
  priv mut next_line_help : Bool
  priv mut default_vals : Array[String]
  priv mut default_missing_vals : Array[String]
  priv mut env : (String, String?)?
  priv mut conflicts : Array[String]
  priv mut requires : Array[String]
  priv mut groups : Array[String]
  priv mut short_aliases : Array[(Char, Bool)]
  priv mut aliases : Array[(String, Bool)]
  priv mut disp_ord : Int32?
  priv mut help_heading : String?
  priv mut value_terminator : String?
  priv mut value_delimiter : Char?
}

///|
pub fn Arg::new(id : String) -> Arg {
  {
    id,
    short: None,
    long: None,
    help: None,
    long_help: None,
    action: None,
    num_vals: None,
    val_names: [],
    value_parser: None,
    value_hint: None,
    index: None,
    required: false,
    hide: false,
    last: false,
    global: false,
    exclusive: false,
    require_equals: false,
    allow_hyphen_values: false,
    hide_possible_values: false,
    hide_default_value: false,
    next_line_help: false,
    default_vals: [],
    default_missing_vals: [],
    env: None,
    conflicts: [],
    requires: [],
    groups: [],
    short_aliases: [],
    aliases: [],
    disp_ord: None,
    help_heading: None,
    value_terminator: None,
    value_delimiter: None,
  }
}

///|
/// `Clone for Arg` (used to propagate global arguments to subcommands).
fn Arg::clone(self : Arg) -> Arg {
  {
    id: self.id,
    short: self.short,
    long: self.long,
    help: self.help,
    long_help: self.long_help,
    action: self.action,
    num_vals: self.num_vals,
    val_names: self.val_names.copy(),
    value_parser: self.value_parser,
    value_hint: self.value_hint,
    index: self.index,
    required: self.required,
    hide: self.hide,
    last: self.last,
    global: self.global,
    exclusive: self.exclusive,
    require_equals: self.require_equals,
    allow_hyphen_values: self.allow_hyphen_values,
    hide_possible_values: self.hide_possible_values,
    hide_default_value: self.hide_default_value,
    next_line_help: self.next_line_help,
    default_vals: self.default_vals.copy(),
    default_missing_vals: self.default_missing_vals.copy(),
    env: self.env,
    conflicts: self.conflicts.copy(),
    requires: self.requires.copy(),
    groups: self.groups.copy(),
    short_aliases: self.short_aliases.copy(),
    aliases: self.aliases.copy(),
    disp_ord: self.disp_ord,
    help_heading: self.help_heading,
    value_terminator: self.value_terminator,
    value_delimiter: self.value_delimiter,
  }
}

///|
pub fn Arg::short(self : Arg, c : Char) -> Arg {
  self.short = Some(c)
  self
}

///|
pub fn Arg::long(self : Arg, l : String) -> Arg {
  self.long = Some(l)
  self
}

///|
pub fn Arg::help(self : Arg, h : String) -> Arg {
  self.help = Some(h)
  self
}

///|
pub fn Arg::long_help(self : Arg, h : String) -> Arg {
  self.long_help = Some(h)
  self
}

///|
pub fn Arg::action(self : Arg, a : ArgAction) -> Arg {
  self.action = Some(a)
  self
}

///|
pub fn Arg::num_args(self : Arg, r : ValueRange) -> Arg {
  self.num_vals = Some(r)
  self
}

///|
pub fn Arg::value_name(self : Arg, n : String) -> Arg {
  self.val_names = [n]
  self
}

///|
pub fn Arg::value_parser(self : Arg, p : ValueParser) -> Arg {
  self.value_parser = Some(p)
  self
}

///|
pub fn Arg::value_hint(self : Arg, h : ValueHint) -> Arg {
  self.value_hint = Some(h)
  self
}

///|
pub fn Arg::index(self : Arg, i : Int32) -> Arg {
  self.index = Some(i)
  self
}

///|
pub fn Arg::required(self : Arg, r : Bool) -> Arg {
  self.required = r
  self
}

///|
pub fn Arg::hide(self : Arg, h : Bool) -> Arg {
  self.hide = h
  self
}

///|
pub fn Arg::last(self : Arg, l : Bool) -> Arg {
  self.last = l
  self
}

///|
pub fn Arg::global(self : Arg, g : Bool) -> Arg {
  self.global = g
  self
}

///|
pub fn Arg::default_value(self : Arg, v : String) -> Arg {
  self.default_vals = [v]
  self
}

///|
pub fn Arg::env(self : Arg, name : String, value : String?) -> Arg {
  self.env = Some((name, value))
  self
}

///|
pub fn Arg::conflicts_with(self : Arg, id : String) -> Arg {
  self.conflicts.push(id)
  self
}

///|
pub fn Arg::requires(self : Arg, id : String) -> Arg {
  self.requires.push(id)
  self
}

///|
pub fn Arg::group(self : Arg, id : String) -> Arg {
  self.groups.push(id)
  self
}

///|
pub fn Arg::alias(self : Arg, name : String) -> Arg {
  self.aliases.push((name, false))
  self
}

///|
pub fn Arg::visible_alias(self : Arg, name : String) -> Arg {
  self.aliases.push((name, true))
  self
}

///|
pub fn Arg::short_alias(self : Arg, c : Char) -> Arg {
  self.short_aliases.push((c, false))
  self
}

///|
pub fn Arg::visible_short_alias(self : Arg, c : Char) -> Arg {
  self.short_aliases.push((c, true))
  self
}

///|
pub fn Arg::help_heading(self : Arg, h : String) -> Arg {
  self.help_heading = Some(h)
  self
}

///|
pub fn Arg::display_order(self : Arg, o : Int32) -> Arg {
  self.disp_ord = Some(o)
  self
}

// Getters (`Arg::get_*`/`Arg::is_*` of clap).

///|
pub fn Arg::get_id(self : Arg) -> String {
  self.id
}

///|
pub fn Arg::get_short(self : Arg) -> Char? {
  self.short
}

///|
pub fn Arg::get_long(self : Arg) -> String? {
  self.long
}

///|
pub fn Arg::get_help(self : Arg) -> String? {
  self.help
}

///|
pub fn Arg::get_long_help(self : Arg) -> String? {
  self.long_help
}

///|
pub fn Arg::get_action(self : Arg) -> ArgAction {
  self.action.unwrap_or(Set)
}

///|
pub fn Arg::get_num_args(self : Arg) -> ValueRange? {
  self.num_vals
}

///|
pub fn Arg::get_min_vals(self : Arg) -> Int32 {
  self.num_vals.unwrap_or(ValueRange::single()).min
}

///|
pub fn Arg::get_value_names(self : Arg) -> Array[String]? {
  if self.val_names.is_empty() {
    None
  } else {
    Some(self.val_names)
  }
}

///|
pub fn Arg::get_value_parser(self : Arg) -> ValueParser {
  self.value_parser.unwrap_or(String)
}

///|
/// `Arg::get_value_hint`: an explicit hint, else `AnyPath` for `PathBuf`
/// values, else `Unknown`.
pub fn Arg::get_value_hint(self : Arg) -> ValueHint {
  match self.value_hint {
    Some(h) => h
    None =>
      if self.is_takes_value_set() && self.get_value_parser() is PathBuf {
        AnyPath
      } else {
        Unknown
      }
  }
}

///|
pub fn Arg::get_possible_values(self : Arg) -> Array[PossibleValue] {
  if !self.is_takes_value_set() {
    []
  } else {
    self.get_value_parser().possible_values()
  }
}

///|
pub fn Arg::get_index(self : Arg) -> Int32? {
  self.index
}

///|
pub fn Arg::get_default_values(self : Arg) -> Array[String] {
  self.default_vals
}

///|
pub fn Arg::get_env(self : Arg) -> (String, String?)? {
  self.env
}

///|
pub fn Arg::get_display_order(self : Arg) -> Int32 {
  self.disp_ord.unwrap_or(999)
}

///|
pub fn Arg::get_help_heading(self : Arg) -> String? {
  self.help_heading
}

///|
pub fn Arg::get_value_terminator(self : Arg) -> String? {
  self.value_terminator
}

///|
pub fn Arg::get_value_delimiter(self : Arg) -> Char? {
  self.value_delimiter
}

///|
pub fn Arg::get_conflicts(self : Arg) -> Array[String] {
  self.conflicts
}

///|
pub fn Arg::get_requires(self : Arg) -> Array[String] {
  self.requires
}

///|
pub fn Arg::get_groups(self : Arg) -> Array[String] {
  self.groups
}

///|
pub fn Arg::get_visible_aliases(self : Arg) -> Array[String]? {
  let v = self.aliases.filter(a => a.1).map(a => a.0)
  if v.is_empty() {
    None
  } else {
    Some(v)
  }
}

///|
pub fn Arg::get_all_aliases(self : Arg) -> Array[String]? {
  if self.aliases.is_empty() {
    None
  } else {
    Some(self.aliases.map(a => a.0))
  }
}

///|
pub fn Arg::get_visible_short_aliases(self : Arg) -> Array[Char]? {
  let v = self.short_aliases.filter(a => a.1).map(a => a.0)
  if v.is_empty() {
    None
  } else {
    Some(v)
  }
}

///|
pub fn Arg::get_all_short_aliases(self : Arg) -> Array[Char]? {
  if self.short_aliases.is_empty() {
    None
  } else {
    Some(self.short_aliases.map(a => a.0))
  }
}

///|
/// `Arg::get_short_and_visible_aliases`.
pub fn Arg::get_short_and_visible_aliases(self : Arg) -> Array[Char]? {
  let shorts = []
  if self.short is Some(s) {
    shorts.push(s)
    for a in self.short_aliases {
      if a.1 {
        shorts.push(a.0)
      }
    }
    Some(shorts)
  } else {
    None
  }
}

///|
/// `Arg::get_long_and_visible_aliases`.
pub fn Arg::get_long_and_visible_aliases(self : Arg) -> Array[String]? {
  let longs = []
  if self.long is Some(l) {
    longs.push(l)
    for a in self.aliases {
      if a.1 {
        longs.push(a.0)
      }
    }
    Some(longs)
  } else {
    None
  }
}

///|
pub fn Arg::is_positional(self : Arg) -> Bool {
  self.long is None && self.short is None
}

///|
pub fn Arg::is_required_set(self : Arg) -> Bool {
  self.required
}

///|
pub fn Arg::is_hide_set(self : Arg) -> Bool {
  self.hide
}

///|
pub fn Arg::is_last_set(self : Arg) -> Bool {
  self.last
}

///|
pub fn Arg::is_global_set(self : Arg) -> Bool {
  self.global
}

///|
pub fn Arg::is_exclusive_set(self : Arg) -> Bool {
  self.exclusive
}

///|
pub fn Arg::is_require_equals_set(self : Arg) -> Bool {
  self.require_equals
}

///|
pub fn Arg::is_allow_hyphen_values_set(self : Arg) -> Bool {
  self.allow_hyphen_values
}

///|
pub fn Arg::is_hide_possible_values_set(self : Arg) -> Bool {
  self.hide_possible_values
}

///|
pub fn Arg::is_hide_default_value_set(self : Arg) -> Bool {
  self.hide_default_value
}

///|
pub fn Arg::is_next_line_help_set(self : Arg) -> Bool {
  self.next_line_help
}

///|
pub fn Arg::is_takes_value_set(self : Arg) -> Bool {
  self
  .get_num_args()
  .unwrap_or(self.get_action().default_num_args())
  .takes_values()
}

///|
/// `Arg::is_multiple`: either multiple values or occurrences.
pub fn Arg::is_multiple(self : Arg) -> Bool {
  self.get_num_args().unwrap_or(ValueRange::single()).is_multiple() ||
  self.get_action() is Append
}

///|
fn Arg::is_multiple_values_set(self : Arg) -> Bool {
  self.get_num_args().unwrap_or(ValueRange::single()).is_multiple()
}

///|
/// `Arg::_build`.
fn Arg::build(self : Arg) -> Unit {
  if self.action is None {
    if self.num_vals == Some(ValueRange::empty()) {
      self.action = Some(SetTrue)
    } else if self.is_positional() &&
      self.num_vals.unwrap_or(ValueRange::single()).is_unbounded() {
      self.action = Some(Append)
    } else {
      self.action = Some(Set)
    }
  }
  if self.action is Some(SetTrue) && self.default_vals.is_empty() {
    self.default_vals = ["false"]
  }
  if self.action is Some(SetTrue) && self.default_missing_vals.is_empty() {
    self.default_missing_vals = ["true"]
  }
  if self.action is Some(Count) && self.default_vals.is_empty() {
    self.default_vals = ["0"]
  }
  if self.value_parser is None {
    self.value_parser = Some(
      match self.action {
        Some(SetTrue) => Bool
        Some(Count) => U8
        _ => String
      },
    )
  }
  if self.num_vals is None {
    self.num_vals = Some(self.get_action().default_num_args())
  }
  // `clap_derive` names values after the field (`value_name` defaults to the
  // uppercased id).
  if self.val_names.is_empty() &&
    (self.is_takes_value_set() || self.is_positional()) {
    self.val_names = [self.id.to_upper()]
  }
}

///|
/// `Arg::name_no_brackets`.
fn Arg::name_no_brackets(self : Arg) -> String {
  if self.val_names.length() > 1 {
    self.val_names.map(n => "<\{n}>").join(" ")
  } else if self.val_names.length() == 1 {
    self.val_names[0]
  } else {
    self.id
  }
}

///|
/// `Arg::stylized` without styles.
pub fn Arg::stylized(self : Arg, required? : Bool) -> String {
  let sb = StringBuilder()
  if self.long is Some(l) {
    sb.write_string("--\{l}")
  } else if self.short is Some(s) {
    sb.write_string("-")
    sb.write_char(s)
  }
  sb.write_string(self.stylize_arg_suffix(required?))
  sb.to_string()
}

///|
/// `Arg::stylize_arg_suffix` without styles.
pub fn Arg::stylize_arg_suffix(self : Arg, required? : Bool) -> String {
  let sb = StringBuilder()
  let mut need_closing_bracket = false
  if self.is_takes_value_set() && !self.is_positional() {
    let is_optional_val = self.get_min_vals() == 0
    let start = if self.require_equals {
      if is_optional_val {
        need_closing_bracket = true
        "[="
      } else {
        "="
      }
    } else if is_optional_val {
      need_closing_bracket = true
      " ["
    } else {
      " "
    }
    sb.write_string(start)
  }
  if self.is_takes_value_set() || self.is_positional() {
    let required = required.unwrap_or(self.required)
    sb.write_string(self.render_arg_val(required))
  } else if self.get_action() is Count {
    sb.write_string("...")
  }
  if need_closing_bracket {
    sb.write_string("]")
  }
  sb.to_string()
}

///|
/// `Arg::render_arg_val`.
fn Arg::render_arg_val(self : Arg, required : Bool) -> String {
  let rendered = StringBuilder()
  let num_vals = self.num_vals.unwrap_or(ValueRange::single())
  let mut val_names = if self.val_names.is_empty() {
    [self.id]
  } else {
    self.val_names.copy()
  }
  if val_names.length() == 1 {
    let min = if num_vals.min > 1 { num_vals.min } else { 1 }
    val_names = Array::make(min, val_names[0])
  }
  let min_vals = num_vals.min
  for n, val_name in val_names {
    let is_optional_val = min_vals == 0
    let is_past_min = min_vals <= n
    let is_optional = if self.is_positional() {
      !required || is_past_min
    } else {
      !is_optional_val && is_past_min
    }
    if n != 0 {
      rendered.write_char(' ')
    }
    if is_optional {
      rendered.write_string("[\{val_name}]")
    } else {
      rendered.write_string("<\{val_name}>")
    }
  }
  let mut extra_values = val_names.length() < num_vals.max
  if self.is_positional() && self.get_action() is Append {
    extra_values = true
  }
  if extra_values {
    rendered.write_string("...")
  }
  rendered.to_string()
}

///|
/// `Display for Arg`.
pub impl Show for Arg with fn output(self, logger) {
  logger.write_string(self.stylized())
}

///|
/// The `Display` text of an argument (`--long <VALUE>`).
pub fn Arg::to_string(self : Arg) -> String {
  self.stylized()
}

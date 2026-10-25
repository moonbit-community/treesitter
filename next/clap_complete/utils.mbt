// Port of clap_complete 4.6.11 `aot/generator/utils.rs`, plus small helpers
// standing in for Rust standard library behavior.

///|
/// `utils::all_subcommands`: `(name, bin_name)` of all subcommands, direct
/// ones first, then recursively.
fn all_subcommands(cmd : @clap.Command) -> Array[(String, String)] {
  let subcmds = subcommands(cmd)
  for sc in cmd.get_subcommands() {
    subcmds.push_iter(all_subcommands(sc).iter())
  }
  subcmds
}

///|
/// `utils::find_subcommand_with_path`.
fn find_subcommand_with_path(
  p : @clap.Command,
  path : Array[String],
) -> @clap.Command {
  let mut cmd = p
  for sc in path {
    cmd = cmd.find_subcommand(sc).unwrap()
  }
  cmd
}

///|
/// `utils::subcommands`: `(name, bin_name)` of the direct subcommands and
/// their visible aliases.
fn subcommands(p : @clap.Command) -> Array[(String, String)] {
  let subcmds = []
  for sc in p.get_subcommands() {
    let sc_bin_name = sc.get_bin_name().unwrap()
    subcmds.push((sc.get_name(), sc_bin_name))
    for alias in sc.get_visible_aliases() {
      subcmds.push((alias, sc_bin_name))
    }
  }
  subcmds
}

///|
/// `utils::shorts_and_visible_aliases` (visible aliases come first).
fn shorts_and_visible_aliases(p : @clap.Command) -> Array[Char] {
  let result = []
  for a in p.get_arguments() {
    if a.is_positional() {
      continue
    }
    match (a.get_visible_short_aliases(), a.get_short()) {
      (Some(aliases), Some(short)) => {
        result.push_iter(aliases.iter())
        result.push(short)
      }
      (None, Some(short)) => result.push(short)
      _ => ()
    }
  }
  result
}

///|
/// `utils::longs_and_visible_aliases` (visible aliases come first).
fn longs_and_visible_aliases(p : @clap.Command) -> Array[String] {
  let result = []
  for a in p.get_arguments() {
    if a.is_positional() {
      continue
    }
    match (a.get_visible_aliases(), a.get_long()) {
      (Some(aliases), Some(long)) => {
        result.push_iter(aliases.iter())
        result.push(long)
      }
      (None, Some(long)) => result.push(long)
      _ => ()
    }
  }
  result
}

///|
/// `utils::flags`: non-positional arguments that take no values.
fn flags(p : @clap.Command) -> Array[@clap.Arg] {
  p
  .get_arguments()
  .filter(a => !num_args(a).takes_values() && !a.is_positional())
}

///|
/// `arg.get_num_args().expect("built")`.
fn num_args(a : @clap.Arg) -> @clap.ValueRange {
  a.get_num_args().unwrap()
}

///|
/// `utils::possible_values`: `None` when the argument takes no values or
/// its value parser has no possible values.
fn possible_values(a : @clap.Arg) -> Array[@clap.PossibleValue]? {
  if !num_args(a).takes_values() {
    None
  } else {
    value_parser_possible_values(a.get_value_parser())
  }
}

///|
/// `ValueParser::possible_values`.
fn value_parser_possible_values(
  p : @clap.ValueParser,
) -> Array[@clap.PossibleValue]? {
  match p {
    Bool =>
      Some([@clap.PossibleValue::new("true"), @clap.PossibleValue::new("false")])
    Enum(values) => Some(values)
    _ => None
  }
}

///|
/// Rust's `str::cmp`: lexicographic by UTF-8 bytes (equivalently, by code
/// point). MoonBit's `String::compare` orders by length first.
fn str_cmp(a : String, b : String) -> Int32 {
  let ai = a.iter()
  let bi = b.iter()
  for ;; {
    match (ai.next(), bi.next()) {
      (None, None) => return 0
      (None, Some(_)) => return -1
      (Some(_), None) => return 1
      (Some(x), Some(y)) => if x != y { return x.to_int().compare(y.to_int()) }
    }
  }
}

///|
/// Rust's `Vec<String>::sort` followed by `dedup`.
fn sort_dedup(v : Array[String]) -> Array[String] {
  v.sort_by(str_cmp)
  let result = []
  for s in v {
    if result.last() is Some(last) && last == s {
      continue
    }
    result.push(s)
  }
  result
}

///|
/// The length of `s` in UTF-8 bytes (Rust's `str::len`).
fn utf8_len(s : StringView) -> Int32 {
  let mut n = 0
  for c in s {
    let code = c.to_int()
    n += if code < 0x80 {
      1
    } else if code < 0x800 {
      2
    } else if code < 0x10000 {
      3
    } else {
      4
    }
  }
  n
}

///|
/// `Option<&StyledStr>::unwrap_or_default().to_string()`.
fn or_empty(s : String?) -> String {
  s.unwrap_or("")
}

///|
/// A stable sort (Rust's `slice::sort_by`), as insertion sort.
fn[T] stable_sort_by(v : Array[T], cmp : (T, T) -> Int32) -> Unit {
  for i in 1..<v.length() {
    let x = v[i]
    let mut j = i
    while j > 0 && cmp(v[j - 1], x) > 0 {
      v[j] = v[j - 1]
      j -= 1
    }
    v[j] = x
  }
}

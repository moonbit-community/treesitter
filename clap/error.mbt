// Port of clap_builder 4.6.7 `error/mod.rs`, `error/kind.rs` and the
// `RichFormatter` of `error/format.rs`, rendered without styles.

///|
/// `clap::error::ErrorKind`.
pub(all) enum ErrorKind {
  InvalidValue
  UnknownArgument
  InvalidSubcommand
  NoEquals
  ValueValidation
  TooManyValues
  TooFewValues
  WrongNumberOfValues
  ArgumentConflict
  MissingRequiredArgument
  MissingSubcommand
  InvalidUtf8
  DisplayHelp
  DisplayHelpOnMissingArgumentOrSubcommand
  DisplayVersion
} derive(Eq, Debug)

///|
/// A parse outcome that ends the program: help or version output, or a usage
/// error. `message` is the complete text clap prints.
pub suberror ClapError {
  ClapError(kind~ : ErrorKind, message~ : String)
}

///|
pub fn ClapError::kind(self : ClapError) -> ErrorKind {
  match self {
    ClapError(kind~, ..) => kind
  }
}

///|
pub fn ClapError::message(self : ClapError) -> String {
  match self {
    ClapError(message~, ..) => message
  }
}

///|
/// `Error::use_stderr`.
pub fn ClapError::use_stderr(self : ClapError) -> Bool {
  !(self.kind() is (DisplayHelp | DisplayVersion))
}

///|
/// `Error::exit_code`.
pub fn ClapError::exit_code(self : ClapError) -> Int32 {
  if self.use_stderr() {
    2
  } else {
    0
  }
}

///|
pub impl Show for ClapError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
/// The context an error is formatted from (`ContextKind`/`ContextValue`).
priv struct Ctx {
  invalid_arg : String?
  invalid_args : Array[String]?
  prior_arg : PriorArg?
  invalid_value : String?
  valid_values : Array[String]?
  invalid_subcommand : String?
  valid_subcommands : Array[String]?
  suggested_subcommand : Array[String]?
  suggested_arg : String?
  suggested_value : String?
  suggested : Array[String]?
  usage : String?
  actual_num_values : Int32?
  min_values : Int32?
  expected_num_values : Int32?
  source : String?
}

///|
priv enum PriorArg {
  One(String)
  Many(Array[String])
  Other
}

///|
fn Ctx::default() -> Ctx {
  {
    invalid_arg: None,
    invalid_args: None,
    prior_arg: None,
    invalid_value: None,
    valid_values: None,
    invalid_subcommand: None,
    valid_subcommands: None,
    suggested_subcommand: None,
    suggested_arg: None,
    suggested_value: None,
    suggested: None,
    usage: None,
    actual_num_values: None,
    min_values: None,
    expected_num_values: None,
    source: None,
  }
}

///|
/// `RichFormatter::format_error`; `with_help` is false for errors built
/// without a command (`value_validation`), which get no "try --help" line
/// until the command is attached, as clap does.
fn format_error(kind : ErrorKind, ctx : Ctx, help_flag : String?) -> String {
  let styled = StringBuilder()
  styled.write_string("error: ")
  if !write_dynamic_context(kind, ctx, styled) {
    styled.write_string(kind_as_str(kind))
  }
  let mut suggested = false
  if ctx.suggested_subcommand is Some(valid) {
    styled.write_string("\n")
    if !suggested {
      styled.write_string("\n")
      suggested = true
    }
    did_you_mean(styled, "subcommand", valid)
  }
  if ctx.suggested_arg is Some(valid) {
    styled.write_string("\n")
    if !suggested {
      styled.write_string("\n")
      suggested = true
    }
    did_you_mean(styled, "argument", [valid])
  }
  if ctx.suggested_value is Some(valid) {
    styled.write_string("\n")
    if !suggested {
      styled.write_string("\n")
      suggested = true
    }
    did_you_mean(styled, "value", [valid])
  }
  if ctx.suggested is Some(suggestions) {
    if !suggested {
      styled.write_string("\n")
    }
    for suggestion in suggestions {
      styled.write_string("\n\{tab}tip: \{suggestion}")
    }
  }
  if ctx.usage is Some(usage) {
    styled.write_string("\n\n")
    styled.write_string(usage)
  }
  match help_flag {
    Some(help) =>
      styled.write_string("\n\nFor more information, try '\{help}'.\n")
    None => styled.write_string("\n")
  }
  styled.to_string()
}

///|
fn kind_as_str(kind : ErrorKind) -> String {
  match kind {
    InvalidValue => "one of the values isn't valid for an argument"
    UnknownArgument => "unexpected argument found"
    InvalidSubcommand => "unrecognized subcommand"
    NoEquals => "equal is needed when assigning values to one of the arguments"
    ValueValidation => "invalid value for one of the arguments"
    TooManyValues => "unexpected value for an argument found"
    TooFewValues => "more values required for an argument"
    WrongNumberOfValues => "too many or too few values for an argument"
    ArgumentConflict =>
      "an argument cannot be used with one or more of the other specified arguments"
    MissingRequiredArgument =>
      "one or more required arguments were not provided"
    MissingSubcommand => "a subcommand is required but one was not provided"
    InvalidUtf8 => "invalid UTF-8 was detected in one or more arguments"
    _ => ""
  }
}

///|
fn write_dynamic_context(
  kind : ErrorKind,
  ctx : Ctx,
  styled : StringBuilder,
) -> Bool {
  match kind {
    ArgumentConflict => {
      let mut prior_arg = ctx.prior_arg
      if ctx.invalid_arg is Some(invalid_arg) {
        if prior_arg is Some(One(p)) && p == invalid_arg {
          prior_arg = None
          styled.write_string(
            "the argument '\{invalid_arg}' cannot be used multiple times",
          )
        } else {
          styled.write_string(
            "the argument '\{invalid_arg}' cannot be used with",
          )
        }
      } else if ctx.invalid_subcommand is Some(sub) {
        styled.write_string("the subcommand '\{sub}' cannot be used with")
      } else {
        styled.write_string(kind_as_str(kind))
      }
      match prior_arg {
        Some(Many(values)) => {
          styled.write_string(":")
          for v in values {
            styled.write_string("\n\{tab}\{v}")
          }
        }
        Some(One(value)) => styled.write_string(" '\{value}'")
        Some(Other) =>
          styled.write_string(" one or more of the other specified arguments")
        None => ()
      }
      true
    }
    NoEquals =>
      match ctx.invalid_arg {
        Some(a) => {
          styled.write_string(
            "equal sign is needed when assigning values to '\{a}'",
          )
          true
        }
        None => false
      }
    InvalidValue =>
      match (ctx.invalid_arg, ctx.invalid_value) {
        (Some(invalid_arg), Some(invalid_value)) => {
          if invalid_value.is_empty() {
            styled.write_string(
              "a value is required for '\{invalid_arg}' but none was supplied",
            )
          } else {
            styled.write_string(
              "invalid value '\{invalid_value}' for '\{invalid_arg}'",
            )
          }
          write_values_list("possible values", styled, ctx.valid_values)
          true
        }
        _ => false
      }
    InvalidSubcommand =>
      match ctx.invalid_subcommand {
        Some(sub) => {
          styled.write_string("unrecognized subcommand '\{sub}'")
          true
        }
        None => false
      }
    MissingRequiredArgument =>
      match ctx.invalid_args {
        Some(args) => {
          styled.write_string(
            "the following required arguments were not provided:",
          )
          for v in args {
            styled.write_string("\n\{tab}\{v}")
          }
          true
        }
        None => false
      }
    MissingSubcommand =>
      match ctx.invalid_subcommand {
        Some(sub) => {
          styled.write_string(
            "'\{sub}' requires a subcommand but one was not provided",
          )
          write_values_list("subcommands", styled, ctx.valid_subcommands)
          true
        }
        None => false
      }
    TooManyValues =>
      match (ctx.invalid_arg, ctx.invalid_value) {
        (Some(a), Some(v)) => {
          styled.write_string(
            "unexpected value '\{v}' for '\{a}' found; no more were expected",
          )
          true
        }
        _ => false
      }
    TooFewValues =>
      match (ctx.invalid_arg, ctx.actual_num_values, ctx.min_values) {
        (Some(a), Some(actual), Some(min)) => {
          let were_provided = singular_or_plural(actual)
          styled.write_string(
            "\{min} values required by '\{a}'; only \{actual}\{were_provided}",
          )
          true
        }
        _ => false
      }
    ValueValidation =>
      match (ctx.invalid_arg, ctx.invalid_value) {
        (Some(a), Some(v)) => {
          styled.write_string("invalid value '\{v}' for '\{a}'")
          if ctx.source is Some(source) {
            styled.write_string(": \{source}")
          }
          true
        }
        _ => false
      }
    WrongNumberOfValues =>
      match (ctx.invalid_arg, ctx.actual_num_values, ctx.expected_num_values) {
        (Some(a), Some(actual), Some(expected)) => {
          let were_provided = singular_or_plural(actual)
          styled.write_string(
            "\{expected} values required for '\{a}' but \{actual}\{were_provided}",
          )
          true
        }
        _ => false
      }
    UnknownArgument =>
      match ctx.invalid_arg {
        Some(a) => {
          styled.write_string("unexpected argument '\{a}' found")
          true
        }
        None => false
      }
    _ => false
  }
}

///|
fn write_values_list(
  list_name : String,
  styled : StringBuilder,
  possible_values : Array[String]?,
) -> Unit {
  if possible_values is Some(values) && !values.is_empty() {
    styled.write_string("\n\{tab}[\{list_name}: ")
    for idx, val in values {
      if idx > 0 {
        styled.write_string(", ")
      }
      styled.write_string(escape(val))
    }
    styled.write_string("]")
  }
}

///|
fn singular_or_plural(n : Int32) -> String {
  if n > 1 {
    " were provided"
  } else {
    " was provided"
  }
}

///|
fn did_you_mean(
  styled : StringBuilder,
  context : String,
  possibles : Array[String],
) -> Unit {
  styled.write_string("\{tab}tip:")
  if possibles.length() == 1 {
    styled.write_string(" a similar \{context} exists: ")
  } else {
    styled.write_string(" some similar \{context}s exist: ")
  }
  for i, possible in possibles {
    if i != 0 {
      styled.write_string(", ")
    }
    styled.write_string("'\{possible}'")
  }
}

///|
fn make_error(kind : ErrorKind, ctx : Ctx) -> ClapError {
  ClapError(kind~, message=format_error(kind, ctx, Some("--help")))
}

///|
fn error_argument_conflict(
  arg : String,
  others : Array[String],
  usage : String,
) -> ClapError {
  let prior = match others.length() {
    0 => PriorArg::Other
    1 => One(others[0])
    _ => Many(others)
  }
  make_error(ArgumentConflict, {
    ..Ctx::default(),
    invalid_arg: Some(arg),
    prior_arg: Some(prior),
    usage: Some(usage),
  })
}

///|
fn error_invalid_value(
  bad_val : String,
  good_vals : Array[String],
  arg : String,
) -> ClapError {
  let suggestion = suggestions_did_you_mean(bad_val, good_vals).pop()
  make_error(InvalidValue, {
    ..Ctx::default(),
    invalid_arg: Some(arg),
    invalid_value: Some(bad_val),
    valid_values: Some(good_vals),
    suggested_value: suggestion,
  })
}

///|
fn error_invalid_subcommand(
  subcmd : String,
  did_you_mean : Array[String],
  name : String,
  suggested_trailing_arg : Bool,
  usage : String,
) -> ClapError {
  let suggestions = []
  if suggested_trailing_arg {
    suggestions.push(
      "to pass '\{subcmd}' as a value, use '\{name} -- \{subcmd}'",
    )
  }
  make_error(InvalidSubcommand, {
    ..Ctx::default(),
    invalid_subcommand: Some(subcmd),
    suggested_subcommand: Some(did_you_mean),
    suggested: Some(suggestions),
    usage: Some(usage),
  })
}

///|
fn error_unrecognized_subcommand(subcmd : String, usage : String) -> ClapError {
  make_error(InvalidSubcommand, {
    ..Ctx::default(),
    invalid_subcommand: Some(subcmd),
    usage: Some(usage),
  })
}

///|
fn error_missing_required_argument(
  required : Array[String],
  usage : String,
) -> ClapError {
  make_error(MissingRequiredArgument, {
    ..Ctx::default(),
    invalid_args: Some(required),
    usage: Some(usage),
  })
}

///|
fn error_missing_subcommand(
  parent : String,
  available : Array[String],
  usage : String,
) -> ClapError {
  make_error(MissingSubcommand, {
    ..Ctx::default(),
    invalid_subcommand: Some(parent),
    valid_subcommands: Some(available),
    usage: Some(usage),
  })
}

///|
fn error_too_many_values(
  val : String,
  arg : String,
  usage : String,
) -> ClapError {
  make_error(TooManyValues, {
    ..Ctx::default(),
    invalid_arg: Some(arg),
    invalid_value: Some(val),
    usage: Some(usage),
  })
}

///|
fn error_too_few_values(
  arg : String,
  min_vals : Int32,
  curr_vals : Int32,
  usage : String,
) -> ClapError {
  make_error(TooFewValues, {
    ..Ctx::default(),
    invalid_arg: Some(arg),
    min_values: Some(min_vals),
    actual_num_values: Some(curr_vals),
    usage: Some(usage),
  })
}

///|
fn error_wrong_number_of_values(
  arg : String,
  num_vals : Int32,
  curr_vals : Int32,
  usage : String,
) -> ClapError {
  make_error(WrongNumberOfValues, {
    ..Ctx::default(),
    invalid_arg: Some(arg),
    expected_num_values: Some(num_vals),
    actual_num_values: Some(curr_vals),
    usage: Some(usage),
  })
}

///|
fn error_value_validation(
  arg : String,
  val : String,
  source : String,
) -> ClapError {
  make_error(ValueValidation, {
    ..Ctx::default(),
    invalid_arg: Some(arg),
    invalid_value: Some(val),
    source: Some(source),
  })
}

///|
fn error_invalid_utf8(usage : String) -> ClapError {
  make_error(InvalidUtf8, { ..Ctx::default(), usage: Some(usage), })
}

///|
fn error_no_equals(arg : String, usage : String) -> ClapError {
  make_error(NoEquals, {
    ..Ctx::default(),
    invalid_arg: Some(arg),
    usage: Some(usage),
  })
}

///|
fn error_unknown_argument(
  arg : String,
  did_you_mean : (String, String?)?,
  suggested_trailing_arg : Bool,
  usage : String,
) -> ClapError {
  let suggestions = []
  if suggested_trailing_arg {
    suggestions.push("to pass '\{arg}' as a value, use '-- \{arg}'")
  }
  let mut suggested_arg = None
  match did_you_mean {
    Some((flag, Some(sub))) => suggestions.push("'\{sub} \{flag}' exists")
    Some((flag, None)) => suggested_arg = Some(flag)
    None => ()
  }
  make_error(UnknownArgument, {
    ..Ctx::default(),
    invalid_arg: Some(arg),
    usage: Some(usage),
    suggested_arg,
    suggested: if suggestions.is_empty() {
      None
    } else {
      Some(suggestions)
    },
  })
}

///|
fn error_unnecessary_double_dash(arg : String, usage : String) -> ClapError {
  make_error(UnknownArgument, {
    ..Ctx::default(),
    invalid_arg: Some(arg),
    suggested: Some([
      "subcommand '\{arg}' exists; to use it, remove the '--' before it",
    ]),
    usage: Some(usage),
  })
}

///|
/// `parser::features::suggestions::did_you_mean`.
fn suggestions_did_you_mean(
  v : String,
  possible_values : Array[String],
) -> Array[String] {
  let candidates : Array[(Double, String)] = []
  for pv in possible_values {
    let confidence = jaro(v, pv)
    if confidence > 0.7 {
      // `binary_search_by` with a comparator that never returns `Equal`.
      let mut lo = 0
      let mut hi = candidates.length()
      while lo < hi {
        let mid = (lo + hi) / 2
        if candidates[mid].0 > confidence {
          hi = mid
        } else {
          lo = mid + 1
        }
      }
      candidates.insert(lo, (confidence, pv))
    }
  }
  candidates.map(c => c.1)
}

///|
/// `strsim::jaro`.
fn jaro(a : String, b : String) -> Double {
  let a_chars = a.iter().collect()
  let b_chars = b.iter().collect()
  let a_len = a_chars.length()
  let b_len = b_chars.length()
  if a_len == 0 && b_len == 0 {
    return 1.0
  } else if a_len == 0 || b_len == 0 {
    return 0.0
  }
  let mut search_range = (if a_len > b_len { a_len } else { b_len }) / 2
  search_range = if search_range > 1 { search_range - 1 } else { 0 }
  let flags_memory = Array::make(a_len + b_len, false)
  let mut matches = 0
  for i in 0..<a_len {
    let a_elem = a_chars[i]
    let min_bound = if i > search_range { i - search_range } else { 0 }
    let max_bound = if b_len - 1 < i + search_range {
      b_len - 1
    } else {
      i + search_range
    }
    if min_bound > max_bound {
      continue
    }
    for j in min_bound..<=max_bound {
      if a_elem == b_chars[j] && !flags_memory[a_len + j] {
        flags_memory[i] = true
        flags_memory[a_len + j] = true
        matches += 1
        break
      }
    }
  }
  let mut transpositions = 0
  if matches != 0 {
    let mut b_iter = 0
    for i in 0..<a_len {
      if flags_memory[i] {
        while b_iter < b_len {
          let j = b_iter
          b_iter += 1
          if flags_memory[a_len + j] {
            if a_chars[i] != b_chars[j] {
              transpositions += 1
            }
            break
          }
        }
      }
    }
  }
  transpositions = transpositions / 2
  if matches == 0 {
    0.0
  } else {
    let m = matches.to_double()
    (
      m / a_len.to_double() +
      m / b_len.to_double() +
      (matches - transpositions).to_double() / m
    ) /
    3.0
  }
}

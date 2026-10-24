// Port of tree-sitter crates/cli/src/logger.rs: the `log` facade backend
// (`error!`, `warn!`, `info!`, `debug!` all write to standard error).

///|
let debug_enabled : Ref[Bool] = Ref(false)

///|
pub fn enable_debug() -> Unit {
  debug_enabled.val = true
}

///|
/// `error!`.
pub fn log_error(message : String) -> Unit {
  print_err("\{paint_style(style_red, "Error:")} \{message}\n")
}

///|
/// `warn!`.
pub fn log_warn(message : String) -> Unit {
  print_err("\{paint_style(style_yellow, "Warning:")} \{message}\n")
}

///|
/// `info!`.
pub fn log_info(message : String) -> Unit {
  print_err("\{message}\n")
}

///|
/// `debug!`.
pub fn log_debug(message : String) -> Unit {
  if debug_enabled.val {
    print_err("\{message}\n")
  }
}

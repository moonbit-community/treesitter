// `anyhow::Error` as the CLI uses it: a message with a chain of causes,
// built with `Context::with_context` and printed by `main` with `{:?}`.

///|
/// An error and its causes, outermost first.
pub(all) suberror CliError {
  CliError(Array[String])
}

///|
pub impl Show for CliError with output(self, logger) {
  let CliError(chain) = self
  logger.write_string(chain.get(0).unwrap_or(""))
}

///|
/// `anyhow!(message)`.
pub fn anyhow(message : String) -> CliError {
  CliError([message])
}

///|
/// The display text of any error raised inside the CLI (`Show` dispatches to
/// the concrete error type; OS errors use the text of Rust's `io::Error`).
pub fn error_message(e : Error) -> String {
  match e {
    CliError(chain) => chain.get(0).unwrap_or("")
    @init.InitError(chain) => chain.get(0).unwrap_or("")
    @os_error.OSError(_) => @support.io_error_message(e)
    _ => e.to_string()
  }
}

///|
/// The cause chain of an error.
fn error_chain(e : Error) -> Array[String] {
  match e {
    CliError(chain) => chain
    @init.InitError(chain) => chain
    _ => [error_message(e)]
  }
}

///|
/// `Context::with_context`.
pub fn with_context(e : Error, context : String) -> CliError {
  CliError([context, ..error_chain(e)])
}

///|
/// `Debug for anyhow::Error`.
pub fn CliError::debug(self : CliError) -> String {
  let CliError(chain) = self
  let sb = StringBuilder()
  sb.write_string(chain.get(0).unwrap_or(""))
  if chain.length() > 1 {
    sb.write_string("\n\nCaused by:")
    let multiple = chain.length() > 2
    for n, error in chain[1:] {
      sb.write_char('\n')
      for i, line in error.split("\n").collect() {
        if i == 0 {
          if multiple {
            let num = n.to_string()
            sb.write_string(" ".repeat(5 - num.length()) + num + ": ")
          } else {
            sb.write_string("    ")
          }
        } else {
          sb.write_char('\n')
          sb.write_string(if multiple { "       " } else { "    " })
        }
        sb.write_view(line)
      }
    }
  }
  sb.to_string()
}

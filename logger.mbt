///|
/// Parser diagnostics distinguish lexical recognition from parser actions.
pub(all) enum LogType {
  Parse
  Lex
} derive(Eq, Debug)

///|
pub extend LogType with Eq::{equal, not_equal}

///|
pub extend LogType with @debug.Debug::{to_repr}

///|
/// Set a synchronous diagnostic callback, or pass None to disable logging.
/// Messages describe implementation decisions and are not a stable data format.
/// The callback must not reenter this parser. Logging remains active across
/// cancellation/resumption and reset, until replaced or disabled explicitly.
pub fn Parser::set_logger(
  self : Parser,
  logger : ((LogType, String) -> Unit)?,
) -> Unit {
  self.logger = logger
}

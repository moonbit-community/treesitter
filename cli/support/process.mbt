// Waiting for a child process with Rust's `ExitStatus::code()` semantics.
// (moonbitlang/async's `wait_pid` reports a process killed by a signal as
// exit status 0.)

///|
extern "C" fn ts_cli_wait_exit_code(pid : Int32) -> Int32 = "ts_cli_wait_exit_code"

///|
extern "C" fn ts_cli_wait_error() -> Int32 = "ts_cli_wait_error"

///|
/// `Child::wait()?.code()` for a process spawned with
/// `@process.spawn_orphan`: its exit code, or `None` when a signal ended it.
pub fn wait_exit_code(pid : Int) -> Int? raise {
  match ts_cli_wait_exit_code(pid) {
    -2 => raise @os_error.OSError(ts_cli_wait_error(), context="waitpid")
    -1 => None
    code => Some(code)
  }
}

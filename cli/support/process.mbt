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
pub fn wait_exit_code(pid : Int32) -> Int32? raise {
  match ts_cli_wait_exit_code(pid) {
    -2 => raise @os_error.OSError(ts_cli_wait_error(), context="waitpid")
    -1 => None
    code => Some(code)
  }
}

///|
extern "C" fn ts_cli_set_blocking(fd : Int32) -> Int32 = "ts_cli_set_blocking"

///|
/// Make the file descriptor `fd` blocking: the child's end of a pipe created
/// with `@pipe.pipe()` (both of whose ends are non-blocking), as the ends
/// that Rust's `Stdio::piped()` gives a child are. (Some programs take
/// `EAGAIN` on a non-blocking standard input for its end, or fail with it.)
pub fn set_blocking(fd : Int32) -> Unit raise {
  let errno = ts_cli_set_blocking(fd)
  if errno != 0 {
    raise @os_error.OSError(errno, context="fcntl")
  }
}

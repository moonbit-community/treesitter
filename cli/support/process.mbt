// Waiting for a child process with Rust's `ExitStatus::code()` semantics.
// (moonbitlang/async's `wait_pid` reports a process killed by a signal as
// exit status 0.)

///|
extern "C" fn ts_cli_wait_exit_code(pid : Int32) -> Int32 = "ts_cli_wait_exit_code"

///|
extern "C" fn ts_cli_wait_error() -> Int32 = "ts_cli_wait_error"

///|
extern "C" fn ts_cli_wait_signal() -> Int32 = "ts_cli_wait_signal"

///|
/// The signal that ended the process whose `wait_exit_code` was `None` last.
pub fn last_wait_signal() -> Int32 {
  ts_cli_wait_signal()
}

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

///|
#cfg(not(platform="windows"))
extern "C" fn ts_cli_os_args() -> FixedArray[Bytes] = "moonbit_rt_get_cli_args"

///|
/// Whether each argument of the process (`std::env::args_os()`, including
/// the program name) is not valid UTF-8. `@env.args()` decodes such an
/// argument lossily.
#cfg(not(platform="windows"))
pub fn os_args_invalid_utf8() -> Array[Bool] {
  [
    for arg in ts_cli_os_args() => utf8_error(arg) is Some(_)
  ]
}

///|
/// Whether each argument of the process is not valid UTF-8 (Windows
/// arguments are UTF-16 and decoded as such).
#cfg(platform="windows")
pub fn os_args_invalid_utf8() -> Array[Bool] {
  [
    for _ in @env.args() => false
  ]
}

///|
/// `Command::output()`: run `program` with its standard input `/dev/null`
/// (`output`'s default `Stdio::null()`) and its standard output and error
/// collected through blocking pipe ends (standard error goes to `/dev/null`
/// instead when `null_stderr`). Returns the exit code (`None` when a signal
/// ended the process), standard output and standard error. Fails when the
/// process cannot be started.
pub async fn command_output(
  program : String,
  args : Array[String],
  cwd? : StringView,
  null_stderr~ : Bool = false,
) -> (Int32?, Bytes, Bytes) {
  let (pid, out_read, err_read) = spawn_with_output_pipes(
    program,
    args,
    cwd?,
    null_stderr~,
  )
  defer out_read.close()
  defer err_read.close()
  let stdout = Ref(b"")
  let stderr = Ref(b"")
  // Read both pipes to their ends, then wait, as `wait_with_output` does
  // (also when reading fails, so that the child is reaped).
  let read = try
    @async.with_task_group(group => {
      group.spawn_bg(() => stdout.val = out_read.read_all().binary())
      stderr.val = err_read.read_all().binary()
    })
  catch {
    e => Err(e)
  } noraise {
    _ => Ok(())
  }
  let code = wait_exit_code(pid)
  if read is Err(e) {
    raise e
  }
  (code, stdout.val, stderr.val)
}

///|
/// `Command::status()`: run `program` with the standard streams of this
/// process and wait for it. Returns its exit code (`None` when a signal
/// ended it); fails when it cannot be started.
pub async fn command_status(program : String, args : Array[String]) -> Int32? {
  let pid = @process.spawn_orphan(program, args)
  wait_exit_code(pid)
}

///|
/// Start `program` for `command_output`: its pid and the read ends of its
/// standard output and error pipes. Every end is closed when a step fails.
async fn spawn_with_output_pipes(
  program : String,
  args : Array[String],
  cwd? : StringView,
  null_stderr~ : Bool,
) -> (Int32, @pipe.PipeRead, @pipe.PipeRead) {
  let (out_read, out_write) = @pipe.pipe()
  errdefer out_read.close()
  defer out_write.close()
  let (err_read, err_write) = @pipe.pipe()
  errdefer err_read.close()
  defer err_write.close()
  set_blocking(out_write.fd())
  set_blocking(err_write.fd())
  let stdin = @process.redirect_from_file("/dev/null")
  let pid = if null_stderr {
    @process.spawn_orphan(
      program,
      args,
      stdin~,
      stdout=out_write,
      stderr=@process.redirect_to_file("/dev/null"),
      cwd?,
    )
  } else {
    @process.spawn_orphan(
      program,
      args,
      stdin~,
      stdout=out_write,
      stderr=err_write,
      cwd?,
    )
  }
  (pid, out_read, err_read)
}

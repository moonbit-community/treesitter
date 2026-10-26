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
#borrow(argv, env, cwd)
extern "C" fn ts_cli_spawn(
  argv : FixedArray[Bytes],
  env : FixedArray[Bytes],
  cwd : Bytes,
  stdin : Int32,
  stdout : Int32,
  stderr : Int32,
) -> Int32 = "ts_cli_spawn"

///|
/// A standard stream of a child process (`std::process::Stdio`).
pub(all) enum Stdio {
  /// The stream of this process.
  Inherit
  /// `/dev/null`.
  Null
  /// The file descriptor of an open file or pipe end of this process.
  Fd(Int32)
}

///|
fn Stdio::to_fd(self : Stdio) -> Int32 {
  match self {
    Inherit => -1
    Null => -2
    Fd(fd) => fd
  }
}

///|
/// `Command::spawn()`: start `program` (looked up in `PATH` unless it
/// contains a `/`) with `args`, the environment of this process plus
/// `extra_env`, the working directory `cwd` and the given standard streams.
/// The child gets an empty signal mask and the default `SIGPIPE` action, as
/// Rust's children do. (moonbitlang/async cannot give a child `/dev/null`:
/// its `redirect_from_file("/dev/null")` fails registering the character
/// device with the event loop.) Returns the pid.
pub fn spawn(
  program : String,
  args : Array[String],
  cwd? : String,
  extra_env~ : Array[(String, String)] = [],
  stdin~ : Stdio = Inherit,
  stdout~ : Stdio = Inherit,
  stderr~ : Stdio = Inherit,
) -> Int32 raise {
  let argv : FixedArray[Bytes] = FixedArray::make(args.length() + 1, b"")
  argv[0] = c_string(program)
  for i, arg in args {
    argv[i + 1] = c_string(arg)
  }
  let env : FixedArray[Bytes] = FixedArray::make(extra_env.length(), b"")
  for i, entry in extra_env {
    env[i] = c_string("\{entry.0}=\{entry.1}")
  }
  let cwd = match cwd {
    Some(dir) => c_string(dir)
    None => b""
  }
  let pid = ts_cli_spawn(
    argv,
    env,
    cwd,
    stdin.to_fd(),
    stdout.to_fd(),
    stderr.to_fd(),
  )
  if pid < 0 {
    raise @os_error.OSError(-pid, context="spawn")
  }
  pid
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
  cwd? : String,
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
pub fn command_status(program : String, args : Array[String]) -> Int32? raise {
  let pid = spawn(program, args)
  wait_exit_code(pid)
}

///|
/// Start `program` for `command_output`: its pid and the read ends of its
/// standard output and error pipes. Every end is closed when a step fails.
fn spawn_with_output_pipes(
  program : String,
  args : Array[String],
  cwd? : String,
  null_stderr~ : Bool,
) -> (Int32, @pipe.PipeRead, @pipe.PipeRead) raise {
  let (out_read, out_write) = @pipe.pipe()
  errdefer out_read.close()
  defer out_write.close()
  let (err_read, err_write) = @pipe.pipe()
  errdefer err_read.close()
  defer err_write.close()
  set_blocking(out_write.fd())
  set_blocking(err_write.fd())
  let pid = spawn(
    program,
    args,
    cwd?,
    stdin=Null,
    stdout=Fd(out_write.fd()),
    stderr=if null_stderr { Null } else { Fd(err_write.fd()) },
  )
  (pid, out_read, err_read)
}

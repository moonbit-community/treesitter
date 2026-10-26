///|
async test "command_output: null stdin, collected output, signals" {
  let (code, stdout, stderr) = @support.command_output("sh", [
    "-c", "test -c /dev/stdin && echo null-stdin; echo err >&2; exit 3",
  ])
  debug_inspect(
    (code, @support.utf8_lossy(stdout), @support.utf8_lossy(stderr)),
    content=(
      #|(Some(3), "null-stdin\n", "err\n")
    ),
  )
  let (code, _, _) = @support.command_output("sh", ["-c", "kill -TERM $$"])
  debug_inspect(
    code,
    content=(
      #|None
    ),
  )
  let (code, _, stderr) = @support.command_output(
    "sh",
    ["-c", "echo err >&2"],
    null_stderr=true,
  )
  debug_inspect(
    (code, stderr),
    content=(
      #|(Some(0), <Bytes: []>)
    ),
  )
  let failed = try {
    ignore(@support.command_output("/nonexistent/program", []))
    false
  } catch {
    _ => true
  }
  inspect(failed, content="true")
  debug_inspect(
    @support.command_status("sh", ["-c", "exit 4"]),
    content=(
      #|Some(4)
    ),
  )
  debug_inspect(
    @support.command_status("sh", ["-c", "kill -KILL $$"]),
    content=(
      #|None
    ),
  )
  inspect(@support.last_wait_signal(), content="9")
  let (_, stdout, _) = @support.command_output("sh", ["-c", "pwd"], cwd="/")
  inspect(@support.utf8_lossy(stdout), content="/\n")
}

///|
test "spawn: extra environment and standard streams" {
  let pid = @support.spawn(
    "sh",
    ["-c", "test \"$TS_SPAWN_TEST\" = 1 && test -c /dev/stdin"],
    extra_env=[("TS_SPAWN_TEST", "1")],
    stdin=Null,
    stdout=Null,
  )
  debug_inspect(@support.wait_exit_code(pid), content="Some(0)")
}

///|
test "io errors" {
  let broken_pipe = @os_error.OSError(32, context="write")
  inspect(
    @support.io_error_message(broken_pipe),
    content="Broken pipe (os error 32)",
  )
  inspect(
    @support.io_error_debug(broken_pipe),
    content=(
      #|Os { code: 32, kind: BrokenPipe, message: "Broken pipe" }
    ),
  )
  inspect(@support.is_broken_pipe(broken_pipe), content="true")
  let custom = @support.Custom(kind="NotFound", error="No \"valid\"\nbrowsers")
  inspect(@support.io_error_message(custom), content="No \"valid\"\nbrowsers")
  inspect(
    @support.io_error_debug(custom),
    content=(
      #|Custom { kind: NotFound, error: "No \"valid\"\nbrowsers" }
    ),
  )
  inspect(@support.is_broken_pipe(custom), content="false")
}

///|
test "fs::read of special files" {
  inspect(@support.read_file("/dev/null").length(), content="0")
  inspect(@support.read_to_string("/dev/null"), content="")
  try @support.read_file("/") catch {
    e =>
      inspect(
        @support.io_error_message(e),
        content="Is a directory (os error 21)",
      )
  } noraise {
    _ => fail("expected to fail")
  }
  try @support.read_file("/nonexistent/x") catch {
    e =>
      inspect(
        @support.io_error_message(e),
        content="No such file or directory (os error 2)",
      )
  } noraise {
    _ => fail("expected to fail")
  }
}

///|
test "home directory" {
  inspect(@support.home_dir() is Some(_), content="true")
}

// Port of the `LogSession` part of tree-sitter crates/cli/src/util.rs
// (`print_tree_graph`, `log_graphs`, `LogSession` and its `Drop`). It lives
// here rather than in `cli` because the fuzzing and corpus-test harness
// (`cli_test`, upstream's `fuzz` module) uses it too.

///|
let html_header : String = "\n<!DOCTYPE html>\n\n<style>\nsvg { width: 100%; }\n</style>\n\n"

///|
/// `LogSession`: a running `dot -Tsvg` whose standard input receives dot
/// graphs and whose output is appended to the HTML file at `path`. Call
/// `close` (upstream's `Drop`) on every path out of the session's scope.
pub struct LogSession {
  path : String
  priv mut dot_process : Int32?
  priv mut dot_process_stdin : @pipe.PipeWrite?
  open_log : Bool
}

///|
pub async fn print_tree_graph(
  tree : @treesitter.Tree,
  path : String,
  open_log : Bool,
) -> Unit {
  let session = LogSession::new(path, open_log)
  defer session.close()
  let graph = StringBuilder()
  tree.print_dot_graph(graph)
  session.write_graph(graph.to_string())
}

///|
pub async fn log_graphs(
  parser : @treesitter.Parser,
  path : String,
  open_log : Bool,
) -> LogSession {
  let session = LogSession::new(path, open_log)
  parser.print_dot_graphs(s => session.write_graph(s))
  session
}

///|
/// The `dot` command could not be started: the CLI adds the context
/// "Failed to run the `dot` command. Check that graphviz is installed.".
pub(all) suberror DotSpawnError {
  DotSpawnError(Error)
}

///|
async fn LogSession::new(path : String, open_log : Bool) -> LogSession {
  @fs.write_file(
    path,
    html_header,
    create_mode=CreateOrTruncate,
    permission=0o666,
  )
  // `Stdio::piped()`: the child's end is blocking, as Rust's pipes are. (A
  // non-blocking standard input makes `dot` take `EAGAIN` for the end of its
  // input when it reads before the first graph is written.) The parent's
  // end stays non-blocking; `write_graph` waits until it is writable.
  // (`@process.write_to_process` creates the same pipe, but does not expose
  // the parent's file descriptor, which the synchronous dot-graph callback
  // needs.)
  let (dot_stdin_read, dot_stdin) = @pipe.pipe()
  let dot_process = try {
    set_blocking(dot_stdin_read.fd())
    @process.spawn_orphan(
      "dot",
      ["-Tsvg"],
      stdin=dot_stdin_read,
      stdout=@process.redirect_to_file(
        path,
        append=true,
        create_mode=OpenExisting,
      ),
    )
  } catch {
    e => {
      dot_stdin_read.close()
      dot_stdin.close()
      raise DotSpawnError(e)
    }
  }
  dot_stdin_read.close()
  {
    path,
    dot_process: Some(dot_process),
    dot_process_stdin: Some(dot_stdin),
    open_log,
  }
}

///|
/// Write graph text to the `dot` process (ignoring errors, as the C library
/// does).
fn LogSession::write_graph(self : LogSession, graph : String) -> Unit {
  if self.dot_process_stdin is Some(stdin) {
    write_fd_blocking(stdin.fd(), utf8(graph))
  }
}

///|
/// `Drop for LogSession`: close the input of `dot`, wait for it and open
/// the log in a browser if requested. Does nothing when the session was
/// closed already.
pub async fn LogSession::close(self : LogSession) -> Unit {
  guard self.dot_process_stdin is Some(stdin) else { return }
  self.dot_process_stdin = None
  stdin.close()
  guard self.dot_process is Some(pid) else { return }
  self.dot_process = None
  // A blocking waitpid: moonbitlang/async's `wait_pid` fails with EAGAIN on
  // Linux for this child.
  let status = wait_exit_code(pid) catch {
    e =>
      rust_panic(
        "called `Result::unwrap()` on an `Err` value: \{io_error_debug(e)}",
        "crates/cli/src/util.rs:118:74",
      )
  }
  if status == Some(0) {
    if self.open_log {
      let len = file_len(self.path) catch {
        e =>
          rust_panic(
            "called `Result::unwrap()` on an `Err` value: \{io_error_debug(e)}",
            "crates/cli/src/util.rs:120:58",
          )
      }
      if len > utf8_len(html_header).to_int64() {
        webbrowser_open(self.path) catch {
          e =>
            rust_panic(
              "called `Result::unwrap()` on an `Err` value: \{io_error_debug(e)}",
              "crates/cli/src/util.rs:121:64",
            )
        }
      }
    }
  } else {
    // The output of `dot` goes to the log file and its error output is
    // inherited, so neither is captured.
    log_error("Dot failed:  ")
  }
}

///|
/// `fs::metadata(path).len()`.
async fn file_len(path : String) -> Int64 {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  file.size()
}

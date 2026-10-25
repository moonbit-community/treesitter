// Port of tree-sitter crates/cli/src/util.rs.
//
// `cancel_on_signal` is not ported (Ctrl-C cancellation is not available).

///|
let html_header : String = "\n<!DOCTYPE html>\n\n<style>\nsvg { width: 100%; }\n</style>\n\n"

///|
pub async fn lang_not_found_for_path(
  path : String,
  loader_config : @loader.LoaderConfig,
) -> String {
  let dirs = loader_config.parser_directories
    .mapi((i, d) => "  \{i + 1}. \{d}")
    .join("  \n")
  let location = match
    (@config.Config::find_config_file() catch { _ => None }) {
    Some(config_path) => "located at \{config_path}"
    None => "which you need to create by running `tree-sitter init-config`"
  }
  "No language found for path `\{path}`\n\nIf a language should be associated with this file extension, please ensure the path to `\{path}` is inside one of the following directories as specified by your 'config.json':\n\n\{dirs}\n\nIf the directory that contains the relevant grammar for `\{path}` is not listed above, please add the directory to the list of directories in your config file, \{location}\n"
}

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
async fn LogSession::new(path : String, open_log : Bool) -> LogSession {
  @fs.write_file(
    path,
    html_header,
    create_mode=CreateOrTruncate,
    permission=0o666,
  )
  let (dot_stdin_read, dot_stdin) = @pipe.pipe()
  let dot_process = @process.spawn_orphan(
    "dot",
    ["-Tsvg"],
    stdin=dot_stdin_read,
    stdout=@process.redirect_to_file(
      path,
      append=true,
      create_mode=OpenExisting,
    ),
  ) catch {
    e => {
      dot_stdin_read.close()
      dot_stdin.close()
      raise with_context(
        e, "Failed to run the `dot` command. Check that graphviz is installed.",
      )
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
    @support.write_fd_blocking(stdin.fd(), @support.utf8(graph))
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
  let status = @support.wait_exit_code(pid) catch {
    e =>
      @support.rust_panic(
        "called `Result::unwrap()` on an `Err` value: \{@support.io_error_debug(e)}",
        "crates/cli/src/util.rs:118:74",
      )
  }
  if status == Some(0) {
    if self.open_log {
      let len = file_len(self.path) catch {
        e =>
          @support.rust_panic(
            "called `Result::unwrap()` on an `Err` value: \{@support.io_error_debug(e)}",
            "crates/cli/src/util.rs:120:58",
          )
      }
      if len > @support.utf8_len(html_header).to_int64() {
        @support.webbrowser_open(self.path) catch {
          e =>
            @support.rust_panic(
              "called `Result::unwrap()` on an `Err` value: \{@support.io_error_debug(e)}",
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

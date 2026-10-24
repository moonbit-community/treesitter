// Port of tree-sitter crates/cli/src/util.rs.

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
/// `LogSession`: dot graphs written to `path` as SVG through graphviz's
/// `dot`. Upstream streams the graphs into a running `dot` process; here
/// they are collected and piped to `dot` when the session ends.
pub struct LogSession {
  path : String
  graphs : StringBuilder
  open_log : Bool
}

///|
async fn LogSession::new(path : String, open_log : Bool) -> LogSession {
  @fs.write_file(path, html_header, create_mode=CreateOrTruncate)
  { path, graphs: StringBuilder(), open_log }
}

///|
/// `Drop for LogSession`.
pub async fn LogSession::close(self : LogSession) -> Unit {
  let temp = @support.path_join(@support.temp_dir(), ".tree-sitter-dot-input")
  @fs.write_file(temp, self.graphs.to_string(), create_mode=CreateOrTruncate)
  let (code, stdout, stderr) = @process.collect_output(
    "dot",
    ["-Tsvg"],
    stdin=@process.redirect_from_file(temp),
  ) catch {
    _ => {
      ignore(@fs.remove(temp) catch { _ => () })
      raise anyhow(
        "Failed to run the `dot` command. Check that graphviz is installed.",
      )
    }
  }
  ignore(@fs.remove(temp) catch { _ => () })
  if code == 0 {
    @fs.write_file(self.path, stdout.binary(), append=true)
    if self.open_log {
      let size = (@fs.read_file(self.path).binary()).length()
      if size > @support.utf8_len(html_header) {
        open_in_browser(self.path)
      }
    }
  } else {
    log_error(
      "Dot failed: \{@support.utf8_lossy(stdout.binary())} \{@support.utf8_lossy(stderr.binary())}",
    )
  }
}

///|
/// `webbrowser::open`.
pub async fn open_in_browser(path : String) -> Unit {
  let opener = if @support.current_os == "macos" { "open" } else { "xdg-open" }
  ignore(@process.run(opener, [path]) catch { _ => 0 })
}

///|
pub async fn print_tree_graph(
  tree : @api.Tree,
  path : String,
  open_log : Bool,
) -> Unit {
  let session = LogSession::new(path, open_log)
  tree.print_dot_graph(session.graphs)
  session.close()
}

///|
pub async fn log_graphs(
  parser : @api.Parser,
  path : String,
  open_log : Bool,
) -> LogSession {
  let session = LogSession::new(path, open_log)
  parser.print_dot_graphs(s => session.graphs.write_string(s))
  session
}

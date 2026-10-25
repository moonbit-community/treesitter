// Port of tree-sitter crates/cli/src/util.rs.
//
// `cancel_on_signal` is not ported (Ctrl-C cancellation is not available).

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
/// `LogSession` (cli/support/log_session.mbt, shared with the fuzzing
/// harness).
pub using @support {type LogSession}

///|
/// `print_tree_graph`.
pub async fn print_tree_graph(
  tree : @treesitter.Tree,
  path : String,
  open_log : Bool,
) -> Unit {
  @support.print_tree_graph(tree, path, open_log) catch {
    e => raise dot_context(e)
  }
}

///|
/// `log_graphs`.
pub async fn log_graphs(
  parser : @treesitter.Parser,
  path : String,
  open_log : Bool,
) -> LogSession {
  @support.log_graphs(parser, path, open_log) catch {
    e => raise dot_context(e)
  }
}

///|
/// The context `LogSession::new` adds to a failure to start `dot`.
fn dot_context(e : Error) -> Error {
  match e {
    @support.DotSpawnError(e) =>
      with_context(
        e, "Failed to run the `dot` command. Check that graphviz is installed.",
      )
    e => e
  }
}

///|
/// The `tree-sitter` executable (native only).
///
/// clap names the program after the file name of `argv[0]`. MoonBit names
/// this executable after its package (`treesitter.exe` when built,
/// `treesitter` when installed), where cargo builds upstream's as
/// `tree-sitter`; under those default names the program presents itself as
/// `tree-sitter`, and under any other name (a renamed copy, a link or
/// `exec -a`) as that name, like upstream.
async fn main {
  let args = @env.args()
  if args.get(0) is Some(argv0) && is_default_executable_name(argv0) {
    args[0] = "tree-sitter"
  }
  @cli.cli_main(args)
}

///|
/// Whether the file name of `path` is the name moon gives this executable.
fn is_default_executable_name(path : String) -> Bool {
  let name = match path.rev_find("/") {
    Some(i) => path.view(start_offset=i + 1)
    None => path[:]
  }
  name is ("treesitter" | "treesitter.exe")
}

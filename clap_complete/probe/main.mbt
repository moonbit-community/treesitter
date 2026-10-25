// Prints the completion script for the shell named by the first argument
// (`bash`, `zsh`, `fish`, `elvish`, `power-shell` or `nushell`) for the
// tree-sitter command, for diffing against `tree-sitter complete --shell`.

///|
fn main {
  let args = @env.args()
  let shell : @clap_complete.Shell = match args.get(1) {
    Some("bash") => Bash
    Some("zsh") => Zsh
    Some("fish") => Fish
    Some("elvish") => Elvish
    Some("power-shell") => PowerShell
    Some("nushell") => Nushell
    _ => abort("usage: probe <bash|zsh|fish|elvish|power-shell|nushell>")
  }
  let script = @clap_complete.generate(
    shell,
    @commands.build_cli(),
    "tree-sitter",
  )
  // `println` adds the final newline back. (Every script ends with one.)
  guard script.strip_suffix("\n") is Some(body) else {
    abort("script without a final newline")
  }
  println(body)
}

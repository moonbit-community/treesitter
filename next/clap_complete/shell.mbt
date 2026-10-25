// Port of clap_complete 4.6.11 `aot/shells/shell.rs` and
// `aot/generator/mod.rs`, extended with clap_complete_nushell 4.6.2's
// `Nushell` generator.

///|
/// The shells a completion script can be generated for
/// (`clap_complete::Shell` plus `clap_complete_nushell::Nushell`).
pub(all) enum Shell {
  Bash
  Elvish
  Fish
  PowerShell
  Zsh
  Nushell
} derive(Eq, Debug)

///|
/// `Generator::file_name`: the conventional file name of the completion
/// script for the binary `name`.
pub fn Shell::file_name(self : Shell, name : String) -> String {
  match self {
    Bash => "\{name}.bash"
    Elvish => "\{name}.elv"
    Fish => "\{name}.fish"
    PowerShell => "_\{name}.ps1"
    Zsh => "_\{name}"
    Nushell => "\{name}.nu"
  }
}

///|
/// `clap_complete::generate`: sets the bin name of `cmd`, builds it (with
/// clap's expanded help tree) and returns the completion script for
/// `shell`.
pub fn generate(
  shell : Shell,
  cmd : @clap.Command,
  bin_name : String,
) -> String {
  cmd.set_bin_name(bin_name)
  cmd.build_with_help_tree()
  let buf = StringBuilder()
  match shell {
    Bash => generate_bash(cmd, buf)
    Elvish => generate_elvish(cmd, buf)
    Fish => generate_fish(cmd, buf)
    PowerShell => generate_powershell(cmd, buf)
    Zsh => generate_zsh(cmd, buf)
    Nushell => generate_nushell(cmd, buf)
  }
  buf.to_string()
}

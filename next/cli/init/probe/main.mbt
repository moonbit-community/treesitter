// Differential probe for next/cli/init: runs `tree-sitter init` and
// `tree-sitter version` in a directory, for comparison with the upstream
// binary.
//
//   probe init <dir> [--update]
//   probe version <dir> [<version>] [--bump patch|minor|major]

///|
async fn main {
  let args = @env.args()
  let rest = args[1:].to_owned()
  let result = try {
    match rest {
      ["init", dir, .. flags] => @init.run_init(dir, flags.contains("--update"))
      ["version", dir, .. flags] => {
        let mut version = None
        let mut bump = None
        let mut i = 0
        while i < flags.length() {
          if flags[i] == "--bump" && i + 1 < flags.length() {
            bump = Some(
              match flags[i + 1] {
                "minor" => @init.BumpLevel::Minor
                "major" => Major
                _ => Patch
              },
            )
            i += 2
          } else {
            version = Some(@loader.SemverVersion::parse(flags[i]))
            i += 1
          }
        }
        @init.Version::new(version, dir, bump).run()
      }
      _ => @support.print_err("usage: probe init|version <dir> ...\n")
    }
  } catch {
    e => Some(e)
  } noraise {
    _ => None
  }
  if result is Some(e) {
    @support.log_error("\{e}")
    @support.flush()
    @support.exit(1)
  }
}

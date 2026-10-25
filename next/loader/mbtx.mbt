// MoonBit-specific loading: grammars written as `.mbtx` MoonBit programs and
// external scanners written in MoonBit.
//
// A `grammar.mbtx` is an ordinary MoonBit program (an import block followed
// by a `main`) that prints the grammar JSON on standard output; it runs with
// `moon run` in a temporary workspace that depends on this module.
//
// MoonBit has no dynamic loading, so MoonBit external scanners are compiled
// into a "driver": a copy of the CLI whose scanner registry contains them.
// Each `scanner.mbtx` defines `pub fn scanner() -> @runtime.ExternalScanner`
// (an `ExternalScannerFactory`). The driver is built in the cache directory,
// keyed by the set of scanner files, and re-run with the original arguments.

///|
/// The MoonBit scanners (language name to `scanner.mbtx` path) that were
/// needed in this process but are not registered; the CLI re-runs itself
/// through a driver with them (see `run_with_scanners`).
pub let required_mbtx_scanners : Map[String, String] = Map([])

///|
/// The environment variable that marks a process as a scanner driver.
pub let driver_env_var : String = "TREE_SITTER_MBT_DRIVER"

///|
async fn write_file(path : String, content : String) -> Unit {
  // Leave unchanged files alone so that cached driver builds stay valid.
  if @fs.exists(path) &&
    (@fs.read_file(path).text() catch { _ => "" }) == content {
    return
  }
  @fs.write_file(path, content, create_mode=CreateOrTruncate)
}

///|
fn parent_directory(path : String) -> String? {
  match @support.parent(path) {
    Some("") => None
    p => p
  }
}

///|
fn module_name(source : String) -> String? {
  for line in source.split("\n") {
    let line = line.trim()
    if line.has_prefix("name") {
      let rest = line[4:].trim()
      if rest.has_prefix("=") {
        let value = @json.parse(rest[1:].trim()) catch { _ => Json::null() }
        if value is String(name) {
          return Some(name)
        }
      }
    }
  }
  None
}

///|
/// Find a checkout of this module at or above `path`, so that scripts build
/// against it instead of the registry version.
async fn find_checkout(path : String) -> String? {
  if path.is_empty() || !@fs.exists(path) {
    return None
  }
  let mut directory = @fs.realpath(path)
  if @fs.kind(directory) != Directory {
    directory = parent_directory(directory).unwrap_or(directory)
  }
  for ;; {
    let manifest = @support.path_join(directory, "moon.mod")
    if @fs.exists(manifest) &&
      module_name(@fs.read_file(manifest).text()) ==
      Some("moonbit-community/treesitter") {
      return Some(directory)
    }
    guard parent_directory(directory) is Some(parent) && parent != directory else {
      return None
    }
    directory = parent
  }
}

///|
/// The checkout of this module to build scripts against: `$TREESITTER_MBT_ROOT`,
/// the current directory or the executable's directory, or none (registry).
pub async fn module_checkout(current_dir : String) -> String? {
  let hints = []
  if @env.get_env_var("TREESITTER_MBT_ROOT") is Some(root) {
    hints.push(root)
  }
  hints.push(current_dir)
  if @env.args().get(0) is Some(exe) && exe.contains("/") {
    hints.push(exe)
  }
  for hint in hints {
    if find_checkout(hint) is Some(root) {
      return Some(root)
    }
  }
  None
}

///|
async fn prepare_workspace(dir : String, checkout : String?) -> Unit {
  let members = ["script"]
  if checkout is Some(root) {
    members.push(root)
  }
  write_file(
    @support.path_join(dir, "moon.work"),
    "members = \{Json::array(members.map(Json::string)).stringify()}\n",
  )
}

///|
/// Run a `grammar.mbtx` program and return the grammar JSON it prints.
pub async fn run_grammar_script(path : String, current_dir : String) -> String {
  let source = @fs.read_file(path).text() catch {
    e => raise IO(@support.io_error_with_path(e, Some(path)))
  }
  let (imports, body) = @mbtx.prepare(source) catch {
    e => raise Script("\{path}: \{script_error_message(e)}")
  }
  let temp = @fs.tmpdir(prefix="treesitter-mbtx-")
  defer (@fs.rmdir(temp, recursive=true) catch { _ => () })
  @fs.mkdir(@support.path_join(temp, "script"))
  prepare_workspace(temp, module_checkout(current_dir))
  write_file(
    @support.path_join(temp, "script/moon.mod"),
    "name = \"treesitter/local_grammar\"\nimport { \"moonbit-community/treesitter@0.1.0\" }\n",
  )
  write_file(
    @support.path_join(temp, "script/moon.pkg"),
    "\{imports}\noptions(\"is-main\": true)\n",
  )
  write_file(@support.path_join(temp, "script/main.mbt"), body)
  let (code, stdout, stderr) = @process.collect_output(
    "moon",
    ["run", "--target", "native", "."],
    cwd=@support.path_join(temp, "script"),
  )
  if code != 0 {
    raise Script(
      "`moon run` of \{path} exited with status \{code}\n\{stderr.text()}",
    )
  }
  stdout.text()
}

///|
/// FNV-1a over a string, for cache keys.
fn fnv1a(s : String) -> String {
  let mut h : UInt64 = 0xcbf29ce484222325UL
  for b in @support.utf8(s) {
    h = (h ^ b.to_uint64()) * 0x100000001b3UL
  }
  h.to_string(radix=16)
}

///|
/// Build (or reuse) a driver binary with the given MoonBit scanners
/// (language name, `scanner.mbtx` path) and return its path.
pub async fn build_scanner_driver(
  scanners : Array[(String, String)],
  current_dir : String,
) -> String {
  let scanners = scanners.copy()
  scanners.sort_by((a, b) => a.0.compare(b.0))
  let key = fnv1a(scanners.map(s => "\{s.0}=\{s.1}").join("\n"))
  guard @support.cache_dir() is Some(cache) else { raise HomeDir }
  let dir = @support.path_join(cache, "tree-sitter/moonbit-drivers/\{key}")
  let script = @support.path_join(dir, "script")
  @support.create_dir_all(@support.path_join(script, "driver"))
  let checkout = module_checkout(current_dir)
  prepare_workspace(dir, checkout)
  let deps = StringBuilder()
  deps.write_string("\"moonbit-community/treesitter@0.1.0\", \"moonbitlang/async@0.20.2\"")
  write_file(
    @support.path_join(script, "moon.mod"),
    "name = \"treesitter/local_scanners\"\nimport { \{deps.to_string()} }\n",
  )
  let driver_imports = StringBuilder()
  let cases = StringBuilder()
  for i, entry in scanners {
    let (name, path) = entry
    let source = @fs.read_file(path).text() catch {
      e => raise IO(@support.io_error_with_path(e, Some(path)))
    }
    let (imports, body) = @mbtx.prepare(source) catch {
      e => raise Script("\{path}: \{script_error_message(e)}")
    }
    let pkg = @support.path_join(script, "scanner\{i}")
    @support.create_dir_all(pkg)
    write_file(
      @support.path_join(pkg, "moon.pkg"),
      "\{imports}\nsupported_targets = \"+native\"\n",
    )
    write_file(@support.path_join(pkg, "scanner.mbt"), body)
    driver_imports.write_string(
      "\"treesitter/local_scanners/scanner\{i}\" @scanner\{i}, ",
    )
    cases.write_string(
      "    \{Json::string(name).stringify()} => Some(@scanner\{i}.scanner)\n",
    )
  }
  write_file(
    @support.path_join(script, "driver/moon.pkg"),
    "import { \{driver_imports.to_string()}\"moonbit-community/treesitter/next/cli\", \"moonbit-community/treesitter/next/runtime\", \"moonbitlang/async\", \"moonbitlang/core/env\" }\noptions(\"is-main\": true)\nsupported_targets = \"+native\"\n",
  )
  write_file(
    @support.path_join(script, "driver/main.mbt"),
    "fn scanners(name : String) -> @runtime.ExternalScannerFactory? {\n  match name {\n\{cases.to_string()}    _ => None\n  }\n}\n\nasync fn main {\n  @cli.cli_main(@env.args(), scanners~)\n}\n",
  )
  let (code, _, stderr) = @process.collect_output(
    "moon",
    [
      "build", "--target", "native", "--release", "--target-dir", @support.path_join(
        dir, "build",
      ), "driver",
    ],
    cwd=script,
  )
  if code != 0 {
    raise Script(
      "Compiling the MoonBit scanners failed (exit \{code}):\n\{stderr.text()}",
    )
  }
  let candidates = [
    "build/native/release/build/treesitter/local_scanners/driver/driver.exe", "build/native/release/build/driver/driver.exe",
  ]
  for c in candidates {
    let p = @support.path_join(dir, c)
    if @fs.exists(p) {
      return p
    }
  }
  raise Script("The compiled scanner driver was not found in \{dir}/build")
}

///|
/// Re-run the command line through a driver with the given scanners, with
/// the same arguments, working directory and standard streams. Returns the
/// driver's exit status.
pub async fn run_with_scanners(
  scanners : Array[(String, String)],
  args : Array[String],
  current_dir : String,
) -> Int {
  let driver = build_scanner_driver(scanners, current_dir)
  @support.flush()
  @process.run(
    driver,
    args[1:].to_owned(),
    extra_env=Map::from_array([(driver_env_var, "1")]),
    cwd=current_dir,
    stdin=@stdio.stdin,
    stdout=@stdio.stdout,
    stderr=@stdio.stderr,
  )
}

///|
fn script_error_message(e : Error) -> String {
  match e {
    @mbtx.InvalidScript(message) => message
    _ => e.to_string()
  }
}

///|
pub suberror LoadError {
  LoadFailure(String)
}

///|
/// Run a local unpublished grammar script in an isolated MoonBit workspace.
/// The script is executed as ordinary MoonBit code, with no grammar evaluator.
/// `module_root` must be this library's checkout. No source file is modified.
pub async fn run_grammar(
  path : String,
  module_root : String,
) -> @grammar.Grammar {
  let source = @fs.read_file(path).text()
  let (imports, body) = @mbtx.prepare(source)
  let root = @fs.realpath(module_root)
  let temp = @fs.tmpdir(prefix="treesitter-mbtx-")
  defer @fs.rmdir(temp, recursive=true)
  @fs.mkdir("\{temp}/script")
  write_file(
    "\{temp}/moon.work",
    "members = [\"script\", \{Json(root).stringify()}]\n",
  )
  write_file(
    "\{temp}/script/moon.mod",
    "name = \"treesitter/local_grammar\"\nimport { \"bobzhang/treesitter@0.1.0\" }\n",
  )
  write_file(
    "\{temp}/script/moon.pkg",
    "\{imports}\noptions(\"is-main\": true)\n",
  )
  write_file("\{temp}/script/main.mbt", body)
  let (code, stdout, stderr) = @process.collect_output(
    "moon",
    ["run", "--target", "native", "."],
    cwd="\{temp}/script",
  )
  if code != 0 {
    raise LoadFailure("grammar script failed (exit \{code}):\n\{stderr.text()}")
  }
  @grammar.Grammar::parse(stdout.text())
}

///|
pub async fn load_grammar(
  path : String,
  module_root : String,
) -> @grammar.Grammar {
  if path.has_suffix(".mbtx") {
    run_grammar(path, module_root)
  } else {
    @grammar.Grammar::parse(@fs.read_file(path).text())
  }
}

///|
pub async fn load_language(path : String) -> @language.Language {
  @language.Language::parse(@fs.read_file(path).text())
}

///|
async fn write_file(path : String, content : String) -> Unit {
  @fs.write_file(path, content, create_mode=CreateOrTruncate)
}

///|
/// Compile a MoonBit scanner registry with the CLI and run a command. The mbtx
/// file defines `pub fn scanner(language : String) -> @ts.ExternalScanner?`; it can
/// return different scanners for the root language and injected languages.
pub async fn run_scanner(
  path : String,
  module_root : String,
  args : Array[String],
  current_dir~ : String,
) -> Int32 {
  let (imports, body) = @mbtx.prepare(@fs.read_file(path).text())
  let root = @fs.realpath(module_root)
  let temp = @fs.tmpdir(prefix="treesitter-scanner-")
  defer @fs.rmdir(temp, recursive=true)
  @fs.mkdir("\{temp}/script")
  @fs.mkdir("\{temp}/script/driver")
  write_file(
    "\{temp}/moon.work",
    "members = [\"script\", \{Json(root).stringify()}]\n",
  )
  write_file(
    "\{temp}/script/moon.mod",
    "name = \"treesitter/local_scanner\"\nimport { \"bobzhang/treesitter@0.1.0\", \"moonbitlang/async@0.20.2\" }\n",
  )
  write_file(
    "\{temp}/script/moon.pkg",
    "\{imports}\nsupported_targets = \"+native\"\n",
  )
  write_file(
    "\{temp}/script/driver/moon.pkg",
    "import { \"treesitter/local_scanner\" @registry, \"bobzhang/treesitter/cli\", \"moonbitlang/async\" }\noptions(\"is-main\": true)\nsupported_targets = \"+native\"\n",
  )
  write_file("\{temp}/script/scanner.mbt", body)
  write_file(
    "\{temp}/script/driver/main.mbt",
    "async fn main {\n  @cli.run(\{Json(args).stringify()}, scanners=@registry.scanner, module_root=\{Json(root).stringify()}, current_dir=\{Json(current_dir).stringify()})\n}\n",
  )
  let (code, _, stderr) = @process.collect_output(
    "moon",
    ["build", "--target", "native", "--target-dir", "\{temp}/build", "driver"],
    cwd="\{temp}/script",
  )
  if code != 0 {
    raise LoadFailure(
      "scanner compilation failed (exit \{code}):\n\{stderr.text()}",
    )
  }
  // Workspace builds qualify paths with the module name. Execute the compiled
  // driver in the caller's directory so every argument keeps its original
  // meaning, including non-path arguments and paths supplied by future flags.
  @process.run(
    "\{temp}/build/native/debug/build/treesitter/local_scanner/driver/driver.exe",
    [],
    cwd=current_dir,
    stdout=@stdio.stdout,
    stderr=@stdio.stderr,
  )
}

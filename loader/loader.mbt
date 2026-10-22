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

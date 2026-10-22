///|
async test "init creates mbtx grammar files and rejects overwrites" {
  let directory = @fs.tmpdir(prefix="treesitter-init-test-")
  defer @fs.rmdir(directory, recursive=true)
  @cli.run(["treesitter", "init", "sample", directory])
  let script = @fs.read_file("\{directory}/grammar.mbtx").text()
  assert_true(script.contains("Grammar::new(\"sample\""))
  assert_true(
    @fs.read_file("\{directory}/test/corpus/words.txt")
    .text()
    .contains("(document (word) (word))"),
  )
  let config = @config.Config::parse(
    @fs.read_file("\{directory}/tree-sitter.json").text(),
  )
  assert_eq(config.grammars[0].name, "sample")
  try @cli.run(["treesitter", "init", "sample", directory]) catch {
    _ => ()
  } noraise {
    _ => fail("overwrote existing project")
  }
  assert_eq(@fs.read_file("\{directory}/grammar.mbtx").text(), script)
}

///|
async test "init validates names before creating files" {
  let directory = @fs.tmpdir(prefix="treesitter-init-invalid-")
  defer @fs.rmdir(directory, recursive=true)
  for name in ["", "../escape", "bad-name", "1name", "BadName"] {
    try @cli.run(["treesitter", "init", name, directory]) catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid grammar name")
    }
  }
  assert_eq(@fs.readdir(directory).length(), 0)
}

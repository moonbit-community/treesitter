///|
async test "corpus CLI prepares every file before writing updates" {
  let directory = @fs.tmpdir(prefix="treesitter-update-")
  defer @fs.rmdir(directory, recursive=true)
  let language = @generate.generate(
    @grammar.Grammar::new("updates", [
      ("document", Repeat1(Symbol("word"))),
      ("word", @grammar.pattern("[a-z]+")),
    ]),
  )
  let table = "\{directory}/language.json"
  @fs.write_file(table, Json(language).stringify(), create_mode=CreateNew)
  let corpus = "\{directory}/corpus"
  @fs.mkdir(corpus)
  let first = "\{corpus}/a.txt"
  let second = "\{corpus}/b.txt"
  let before = "===\nFirst\n===\na\n---\n(document)\n"
  @fs.write_file(first, before, create_mode=CreateNew)
  @fs.write_file(
    second,
    "===\nSecond\n===\n@\n---\n(document)\n",
    create_mode=CreateNew,
  )
  try @cli.run(["treesitter", "test", table, corpus, "--update"]) catch {
    _ => ()
  } noraise {
    _ => fail("updated a corpus with an unexpected parse error")
  }
  assert_eq(@fs.read_file(first).text(), before)
  @fs.write_file(
    second,
    "===\nSecond\n===\nb\n---\n(document)\n",
    create_mode=CreateOrTruncate,
  )
  @cli.run(["treesitter", "test", table, corpus, "--update"])
  assert_true(@fs.read_file(first).text().contains("(word)"))
  @cli.run(["treesitter", "test", table, corpus])
  let updated = @fs.read_file(first).text()
  @cli.run(["treesitter", "test", table, corpus, "--update"])
  @cli.run(["treesitter", "test", "-u", table, corpus])
  assert_eq(@fs.read_file(first).text(), updated)
}

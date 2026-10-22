///|
async test "checkout discovery distinguishes grammar modules and nested runtime paths" {
  let temp = @fs.tmpdir(prefix="treesitter-workspace-test-")
  defer @fs.rmdir(temp, recursive=true)
  @fs.mkdir("\{temp}/runtime/grammars/other", recursive=true)
  write_file(
    "\{temp}/runtime/grammars/other/moon.mod",
    "name = \"example/grammar\"\n",
  )
  write_file("\{temp}/runtime/grammars/other/grammar.mbtx", "// fixture\n")
  assert_eq(find_checkout("\{temp}/missing"), None)
  assert_eq(find_checkout("\{temp}/runtime/grammars/other"), None)
  write_file("\{temp}/runtime/moon.mod", "name = \"bobzhang/treesitter\"\n")
  let expected = Some(@fs.realpath("\{temp}/runtime"))
  assert_eq(find_checkout("\{temp}/runtime/grammars/other"), expected)
  assert_eq(
    find_checkout("\{temp}/runtime/grammars/other/grammar.mbtx"),
    expected,
  )
  assert_eq(prepare_workspace(temp, temp, executable=""), None)
  assert_eq(
    @fs.read_file("\{temp}/moon.work").text(),
    "members = [\"script\"]\n",
  )
}

///|
test "checkout manifest and parent paths" {
  assert_eq(
    module_name("// name = \"bobzhang/treesitter\"\nname=\"example/grammar\"\n"),
    Some("example/grammar"),
  )
  assert_eq(module_name("namespace = \"bobzhang/treesitter\"\n"), None)
  assert_eq(parent_directory("/tmp/grammar"), Some("/tmp"))
  assert_eq(parent_directory("/tmp"), Some("/"))
  assert_eq(parent_directory("/"), None)
  assert_eq(parent_directory("C:\\grammar\\src"), Some("C:\\grammar"))
  assert_eq(parent_directory("C:\\grammar"), Some("C:\\"))
  assert_eq(parent_directory("C:\\"), None)
}

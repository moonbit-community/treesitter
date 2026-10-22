///|
async test "discovery loads package metadata tables and query files" {
  let temp = @fs.tmpdir(prefix="treesitter-discover-test-")
  defer @fs.rmdir(temp, recursive=true)
  @fs.mkdir("\{temp}/tree-sitter-example/queries", recursive=true)
  @fs.write_file(
    "\{temp}/tree-sitter-example/tree-sitter.json",
    "{\"grammars\":[{\"name\":\"example\",\"scope\":\"source.example\",\"file-types\":[\"example\"],\"highlights\":\"queries/highlights.scm\"}]}",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{temp}/tree-sitter-example/queries/highlights.scm",
    "(root) @root",
    create_mode=CreateOrTruncate,
  )
  @fs.mkdir("\{temp}/tree-sitter-example/src")
  @fs.write_file(
    "\{temp}/tree-sitter-example/src/grammar.json",
    "{\"name\":\"example\",\"rules\":{\"root\":{\"type\":\"STRING\",\"value\":\"a\"}}}",
    create_mode=CreateOrTruncate,
  )
  let locations = @loader.discover([temp, temp])
  assert_eq(locations.length(), 1)
  assert_eq(locations[0].grammar.name, "example")
  assert_eq(locations[0].queries("highlights"), "(root) @root")
  assert_eq(locations[0].queries("locals"), "")
  assert_eq(locations[0].language(temp).name, "example")
  @fs.write_file(
    "\{temp}/config.json",
    Json::object({ "parser-directories": Json([temp]) }).stringify(),
    create_mode=CreateOrTruncate,
  )
  assert_eq(@loader.parser_directories(path="\{temp}/config.json"), [temp])
}

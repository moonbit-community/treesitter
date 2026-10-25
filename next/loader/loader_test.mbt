///|
fn semver(text : String) -> String {
  @loader.SemverVersion::parse(text).to_string() catch {
    e => "error: \{e}"
  }
}

///|
test "semver" {
  inspect(semver("1.2.3"), content="1.2.3")
  inspect(semver("1.2.3-alpha.1+build"), content="1.2.3-alpha.1+build")
  inspect(
    semver("1.x"),
    content="error: unexpected character 'x' while parsing minor version number",
  )
  inspect(
    semver("01.2.3"),
    content="error: invalid leading zero in major version number",
  )
  inspect(
    semver("1.2"),
    content="error: unexpected end of input while parsing minor version number",
  )
}

///|
test "tree-sitter.json" {
  let config = @loader.TreeSitterJSON::parse(
    (
      #|{
      #|  "grammars": [
      #|    { "name": "json", "scope": "source.json", "file-types": ["json"], "highlights": ["queries/a.scm", "queries/b.scm"] }
      #|  ],
      #|  "metadata": { "version": "0.1.0", "license": "MIT" },
      #|  "bindings": { "rust": false }
      #|}
    ),
  )
  inspect(
    @support.to_string_pretty(config.to_json()),
    content=(
      #|{
      #|  "$schema": null,
      #|  "grammars": [
      #|    {
      #|      "name": "json",
      #|      "scope": "source.json",
      #|      "file-types": [
      #|        "json"
      #|      ],
      #|      "highlights": [
      #|        "queries/a.scm",
      #|        "queries/b.scm"
      #|      ]
      #|    }
      #|  ],
      #|  "metadata": {
      #|    "version": "0.1.0",
      #|    "license": "MIT"
      #|  },
      #|  "bindings": {
      #|    "c": true,
      #|    "go": true,
      #|    "java": false,
      #|    "node": true,
      #|    "python": true,
      #|    "rust": false,
      #|    "swift": true,
      #|    "zig": false
      #|  }
      #|}
    ),
  )
  let missing = try @loader.TreeSitterJSON::parse("{\"grammars\": []}") catch {
    e => e.to_string()
  } noraise {
    _ => "ok"
  }
  inspect(missing, content="missing field `metadata`")
}

///|
test "rust debug strings" {
  inspect(@loader.rust_debug_str("a\"b\\\n"), content="\"a\\\"b\\\\\\n\"")
  inspect(@loader.rust_debug_strs(["x", "y"]), content="[\"x\", \"y\"]")
}

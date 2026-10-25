// Expected messages from `serde_json::from_str::<TreeSitterJSON>` and
// `serde_json::from_value::<Config>` of the pinned upstream loader.

///|
fn tree_sitter_json(text : String) -> String {
  try @loader.TreeSitterJSON::parse(text) catch {
    e => e.to_string()
  } noraise {
    config =>
      config.grammars
      .map(g => "\{g.name}:\{g.scope}:\{to_repr(g.highlights)}")
      .join(",")
  }
}

///|
test "tree-sitter.json typed deserialization" {
  let meta = "\"metadata\": {\"version\": \"1.0.0\"}"
  inspect(
    tree_sitter_json(
      "{\"grammars\": [{\"name\": \"x\", \"scope\": \"a\", \"highlights\": [\"h\"]}], \{meta}}",
    ),
    content="x:a:Multiple([\"h\"])",
  )
  inspect(
    tree_sitter_json(
      "{\"grammars\": [{\"name\": \"x\", \"scope\": \"a\", \"scope\": \"b\"}], \{meta}}",
    ),
    content="duplicate field `scope` at line 1 column 49",
  )
  // Fields are validated in the order they appear.
  inspect(
    tree_sitter_json(
      "{\"grammars\": [{\"name\": 1, \"file-types\": 2, \"scope\": 3}], \{meta}}",
    ),
    content="invalid type: integer `1`, expected a string at line 1 column 24",
  )
  inspect(
    tree_sitter_json(
      "{\"grammars\": [{\"name\": \"x\", \"scope\": \"a\", \"tags\": {}}, 5], \{meta}}",
    ),
    content="data did not match any variant of untagged enum PathsJSON at line 1 column 53",
  )
  inspect(
    tree_sitter_json("{\"grammars\": [], \"metadata\": {\"version\": \"1.x\"}}"),
    content="unexpected character 'x' while parsing minor version number at line 1 column 46",
  )
}

///|
test "config.json parser directories" {
  let dirs = (text : String) => {
    let value = try! @support.from_str(text)
    @loader.LoaderConfig::from_json(value).parser_directories.join(",") catch {
      e => e.to_string()
    }
  }
  inspect(dirs("{\"parser-directories\": [\"/a\", \"/b\"]}"), content="/a,/b")
  inspect(dirs("{}"), content="")
  inspect(dirs("[]"), content="")
  inspect(
    dirs("{\"parser-directories\": 1.0}"),
    content="invalid type: floating point `1.0`, expected a sequence",
  )
  inspect(
    dirs("{\"parser-directories\": [\"a\", 12]}"),
    content="invalid type: integer `12`, expected path string",
  )
  inspect(
    dirs("1"),
    content="invalid type: integer `1`, expected struct Config",
  )
}

///|
test "read_grammar_version's TreeSitterJson (@generate.tree_sitter_json_version)" {
  let version = (text : String) => {
    @generate.tree_sitter_json_version(text) catch {
      e => e.to_string()
    }
  }
  inspect(version("{\"metadata\": {\"version\": \"0.1.0\"}}"), content="0.1.0")
  inspect(version("{}"), content="missing field `metadata` at line 1 column 2")
  inspect(
    version("{\"metadata\": {}}"),
    content="missing field `version` at line 1 column 15",
  )
  inspect(
    version("{\"metadata\": {\"version\": 1}}"),
    content="invalid type: integer `1`, expected a string at line 1 column 26",
  )
}

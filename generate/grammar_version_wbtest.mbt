// Expected texts: the pinned `tree-sitter generate` (after its
// ``Failed to parse `tree-sitter.json` -- `` prefix).

///|
fn version_result(contents : String) -> String {
  try tree_sitter_json_version(contents) catch {
    e => e.to_string()
  } noraise {
    _ => "OK"
  }
}

///|
test "tree_sitter_json_version follows serde" {
  inspect(
    version_result(
      (
        #|{"metadata":["1.2.3"]}
      ),
    ),
    content=(
      #|OK
    ),
  )
  inspect(
    version_result(
      (
        #|{"metadata":{"version":1}}
      ),
    ),
    content=(
      #|invalid type: integer `1`, expected a string at line 1 column 24
    ),
  )
  inspect(
    version_result(
      (
        #|{"metadata":{"version":"1.0.0","version":"2.0.0"}}
      ),
    ),
    content=(
      #|duplicate field `version` at line 1 column 40
    ),
  )
  inspect(
    version_result(
      (
        #|{"metadata":{}}
      ),
    ),
    content=(
      #|missing field `version` at line 1 column 14
    ),
  )
  inspect(
    version_result(
      (
        #|{}
      ),
    ),
    content=(
      #|missing field `metadata` at line 1 column 2
    ),
  )
  inspect(
    version_result(
      (
        #|[]
      ),
    ),
    content=(
      #|invalid length 0, expected struct TreeSitterJson with 1 element at line 1 column 2
    ),
  )
  inspect(
    version_result(
      (
        #|[[]]
      ),
    ),
    content=(
      #|invalid length 0, expected struct Metadata with 1 element at line 1 column 3
    ),
  )
  inspect(
    version_result(
      (
        #|{"metadata":{"version":"1.0.0"},"metadata":{}}
      ),
    ),
    content=(
      #|duplicate field `metadata` at line 1 column 42
    ),
  )
  inspect(
    version_result(
      (
        #|{"grammars":["\uD800",[[[[1]]]]],"metadata":{"version":"1.2.3","x":null}}
      ),
    ),
    content=(
      #|OK
    ),
  )
  inspect(
    version_result(
      (
        #|{"metadata":["1.2.3",4]}
      ),
    ),
    content=(
      #|trailing characters at line 1 column 22
    ),
  )
  inspect(
    version_result(
      (
        #|{
      ),
    ),
    content=(
      #|EOF while parsing an object at line 1 column 1
    ),
  )
  inspect(
    version_result(
      (
        #|{"metadata":{"version":"1.0.0"}} x
      ),
    ),
    content=(
      #|trailing characters at line 1 column 34
    ),
  )
  inspect(
    version_result(
      (
        #|{"metadata":null}
      ),
    ),
    content=(
      #|invalid type: null, expected struct Metadata at line 1 column 16
    ),
  )
  inspect(
    version_result(
      (
        #|5
      ),
    ),
    content=(
      #|invalid type: integer `5`, expected struct TreeSitterJson at line 1 column 1
    ),
  )
  inspect(version_result("{\"metadata\":[\"1.2.3\"]}"), content="OK")
  inspect(
    tree_sitter_json_version("{\"metadata\":[\"1.2.3\"]}"),
    content="1.2.3",
  )
}

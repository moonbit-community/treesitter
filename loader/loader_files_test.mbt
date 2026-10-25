///|
async fn write_bytes(path : String, bytes : Bytes) -> Unit {
  @fs.write_file(path, bytes, create_mode=CreateOrTruncate)
}

///|
async fn grammar_json_name_result(path : String) -> String {
  @loader.Loader::grammar_json_name(path) catch {
    e => "error: \{e}"
  }
}

///|
async test "grammar_json_name reads only the first three lines strictly" {
  let dir = @fs.tmpdir(prefix="ts-loader-test")
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  let path = dir + "/grammar.json"
  // Invalid UTF-8 after the third line is never read.
  write_bytes(path, b"{\r\n  \"name\": \"x\",\r\n  \"word\": 1,\n\xff\xfe\n")
  inspect(grammar_json_name_result(path), content="x")
  // Invalid UTF-8 in the first three lines is a GrammarJSON error.
  write_bytes(path, b"{\n  \"\xff\": 1,\n  \"name\": \"x\"\n}\n")
  inspect(
    grammar_json_name_result(path),
    content="error: Failed to parse the language name from grammar.json at \{path}",
  )
  // The name must be in the first three lines.
  write_bytes(path, b"{\n\n\n  \"name\": \"x\"\n}\n")
  inspect(
    grammar_json_name_result(path),
    content="error: Failed to parse the language name from grammar.json at \{path}",
  )
  // A missing file is an IO error.
  let missing = dir + "/missing.json"
  inspect(
    grammar_json_name_result(missing),
    content="error: No such file or directory (os error 2) (\{missing})",
  )
}

///|
async fn first_line_result(loader : @loader.Loader, path : String) -> String {
  match
    (loader.language_configuration_for_first_line_regex(path) catch {
      e => return "error: \{e}"
    }) {
    Some((_, configuration)) => "Some(\{configuration.language_name})"
    None => "None"
  }
}

///|
async test "first-line detection reads the first line strictly" {
  let dir = @fs.tmpdir(prefix="ts-loader-test")
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  let grammar = dir + "/tree-sitter-x"
  @fs.mkdir(grammar)
  @fs.mkdir(grammar + "/src")
  write_bytes(
    grammar + "/tree-sitter.json",
    b"{\"grammars\": [{\"name\": \"x\", \"scope\": \"source.x\", \"first-line-regex\": \"^#!/x\"}], \"metadata\": {\"version\": \"0.1.0\"}}",
  )
  let loader = @loader.Loader::with_parser_lib_path(dir + "/lib")
  ignore(loader.find_language_configurations_at_path(grammar, false))
  let file = dir + "/script"
  // The language is only loaded when the pattern matches; an invalid
  // grammar directory makes that an error, which shows the match.
  write_bytes(file, b"#!/y\n\xff\n")
  inspect(first_line_result(loader, file), content="None")
  write_bytes(file, b"#!/x\xff\n")
  inspect(
    first_line_result(loader, file),
    content="error: stream did not contain valid UTF-8 (\{file})",
  )
  write_bytes(file, b"")
  inspect(first_line_result(loader, file), content="None")
  let missing = dir + "/missing"
  inspect(
    first_line_result(loader, missing),
    content="error: No such file or directory (os error 2) (\{missing})",
  )
}

///|
async test "grammar paths are compared as Rust paths" {
  let dir = @fs.tmpdir(prefix="ts-loader-test")
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  let root = dir + "/tree-sitter-g"
  @fs.mkdir(root)
  write_bytes(
    root + "/tree-sitter.json",
    b"{\"grammars\": [{\"name\": \"b\", \"scope\": \"source.b\", \"path\": \"g\"}, {\"name\": \"aa\", \"scope\": \"source.aa\", \"path\": \"g/.\"}, {\"name\": \"c\", \"scope\": \"source.c\", \"path\": \"./g//\"}, {\"name\": \"d\", \"scope\": \"source.d\", \"path\": \"../tree-sitter-g/g\"}], \"metadata\": {\"version\": \"0.1.0\"}}",
  )
  let loader = @loader.Loader::with_parser_lib_path(dir + "/lib")
  ignore(loader.find_language_configurations_at_path(root, false))
  let paths = loader
    .get_all_language_configurations()
    .map(c => "\{c.0.language_name}: \{c.1.replace(old=dir, new="")}")
  // `g`, `g/.` and `./g//` joined to the root have the same components;
  // `..` is not resolved.
  debug_inspect(
    paths,
    content=(
      #|[
      #|  "b: /tree-sitter-g/g",
      #|  "aa: /tree-sitter-g/g",
      #|  "c: /tree-sitter-g/g",
      #|  "d: /tree-sitter-g/../tree-sitter-g/g",
      #|]
    ),
  )
}

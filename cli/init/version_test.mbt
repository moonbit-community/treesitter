///|
async test "Version::run bumps every versioned file" {
  let dir = @fs.tmpdir(prefix="ts-version-test")
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  let files = [
    (
      "tree-sitter.json", "{\n  \"grammars\": [{\"name\": \"foo\", \"scope\": \"source.foo\"}],\n  \"metadata\": {\n    \"version\": \"0.4.2\"\n  }\n}",
    ),
    (
      "package.json", "{\r\n  \"name\": \"x\",\r\n  \"version\": \"0.4.2\",\r\n}\r\n",
    ),
    ("Cargo.toml", "[package]\nversion = \"0.4.2\"\n"),
    ("Makefile", "VERSION := 0.4.2\nLANGUAGE_NAME := foo\n"),
    (
      "CMakeLists.txt", "project(tree-sitter-foo\n        VERSION \"0.4.2\"\n        LANGUAGES C)\n",
    ),
    ("pyproject.toml", "[project]\nversion = \"0.4.2\"\n"),
    ("build.zig.zon", ".{\n    .version = \"0.4.2\",\n}"),
  ]
  for file in files {
    @fs.write_file(dir + "/" + file.0, file.1, create_mode=CreateOrTruncate)
  }
  @init.Version::new(None, dir, Some(Minor)).run()
  let out = StringBuilder()
  for file in files {
    out.write_string("== \{file.0}\n")
    out.write_string(@fs.read_file(dir + "/" + file.0).text())
  }
  inspect(
    out.to_string(),
    content=(
      #|== tree-sitter.json
      #|{
      #|  "grammars": [{"name": "foo", "scope": "source.foo"}],
      #|  "metadata": {
      #|    "version": "0.5.0"
      #|  }
      #|}
      #|== package.json
      #|{
      #|  "name": "x",
      #|  "version": "0.5.0",
      #|}
      #|== Cargo.toml
      #|[package]
      #|version = "0.5.0"
      #|== Makefile
      #|VERSION := 0.5.0
      #|LANGUAGE_NAME := foo
      #|== CMakeLists.txt
      #|project(tree-sitter-foo
      #|        VERSION "0.5.0"
      #|        LANGUAGES C)
      #|== pyproject.toml
      #|[project]
      #|version = "0.5.0"
      #|== build.zig.zon
      #|.{
      #|    .version = "0.5.0",
      #|}
      #|
    ),
  )
  @init.Version::new(Some(@loader.SemverVersion::new(1, 0, 0)), dir, None).run()
  inspect(
    @fs.read_file(dir + "/Cargo.toml").text(),
    content=(
      #|[package]
      #|version = "1.0.0"
      #|
    ),
  )
}

///|
async test "Version errors" {
  let dir = @fs.tmpdir(prefix="ts-version-test")
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  try @init.Version::new(None, dir, Some(Patch)).run() catch {
    e => inspect(e, content="No such file or directory (os error 2)")
  } noraise {
    _ => fail("expected an error")
  }
  let error : Error = @init.VersionError::Update([
    Io("Permission denied (os error 13)", "/x/Cargo.toml"),
    Command("npm install", "boom\n"),
  ])
  inspect(
    error,
    content=(
      #|Failed to update one or more files:
      #|
      #|Failed to update /x/Cargo.toml:
      #|Permission denied (os error 13)
      #|
      #|Failed to run `npm install`:
      #|boom
      #|
      #|
      #|
    ),
  )
}

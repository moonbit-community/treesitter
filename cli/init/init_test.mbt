///|
/// The files under `dir`, relative and sorted.
async fn list_files(dir : String) -> Array[String] {
  let files = []
  async fn walk(rel : String) -> Unit {
    let path = if rel.is_empty() { dir } else { dir + "/" + rel }
    for name in @fs.readdir(path, include_hidden=true, sort=true) {
      let child = if rel.is_empty() { name } else { rel + "/" + name }
      if @fs.kind(dir + "/" + child) is Directory {
        walk(child)
      } else {
        files.push(child)
      }
    }
  }

  walk("")
  // Byte-wise order, as `ls`/`find | sort` (`String::compare` orders by
  // length first).
  files.sort_by((a, b) => {
    let n = if a.length() < b.length() { a.length() } else { b.length() }
    for i in 0..<n {
      if a[i] != b[i] {
        return a[i].compare(b[i])
      }
    }
    a.length().compare(b.length())
  })
  files
}

///|
async fn read(path : String) -> String {
  @fs.read_file(path).text()
}

///|
async test "generate_grammar_files from an existing tree-sitter.json" {
  let dir = @fs.tmpdir(prefix="ts-init-test")
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  @fs.write_file(
    dir + "/tree-sitter.json",
    (
      #|{
      #|  "grammars": [{"name": "foo", "scope": "source.foo"}],
      #|  "metadata": {"version": "1.2.3", "authors": [{"name": "Ann"}]},
      #|  "bindings": {"go": false, "python": false, "swift": false, "node": false}
      #|}
    ),
    create_mode=CreateOrTruncate,
  )
  @init.generate_grammar_files(dir, "foo", false, None)
  inspect(
    list_files(dir).join("\n"),
    content=(
      #|.editorconfig
      #|.gitattributes
      #|.gitignore
      #|CMakeLists.txt
      #|Cargo.toml
      #|Makefile
      #|bindings/c/tree-sitter-foo.pc.in
      #|bindings/c/tree_sitter/tree-sitter-foo.h
      #|bindings/rust/build.rs
      #|bindings/rust/lib.rs
      #|grammar.js
      #|package.json
      #|tree-sitter.json
    ),
  )
  inspect(
    read(dir + "/grammar.js"),
    content=(
      #|/**
      #| * @file Foo grammar for tree-sitter
      #| * @author Ann
      #| * @license MIT
      #| */
      #|
      #|/// <reference types="tree-sitter-cli/dsl" />
      #|// @ts-check
      #|
      #|export default grammar({
      #|  name: "foo",
      #|
      #|  rules: {
      #|    // TODO: add the actual grammar rules
      #|    source_file: $ => "hello"
      #|  }
      #|});
      #|
    ),
  )
  let cargo = read(dir + "/Cargo.toml")
  inspect(
    cargo.split("\n").take(12).collect().map(l => l.to_owned()).join("\n"),
    content=(
      #|[package]
      #|authors = [ "Ann" ]
      #|autoexamples = false
      #|categories = [ "parser-implementations", "parsing", "text-editors" ]
      #|description = "Foo grammar for tree-sitter"
      #|edition = "2024"
      #|keywords = [ "incremental", "parsing", "tree-sitter", "foo" ]
      #|license = "MIT"
      #|name = "tree-sitter-foo"
      #|readme = "README.md"
      #|repository = "https://github.com/tree-sitter/tree-sitter-foo"
      #|version = "1.2.3"
    ),
  )
}

///|
async test "generate_grammar_files writes tree-sitter.json from JsonConfigOpts" {
  let dir = @fs.tmpdir(prefix="ts-init-test")
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  let opts = @init.JsonConfigOpts::default()
  opts.name = "my_lang"
  opts.camelcase = "MyLang"
  opts.title = "My Lang"
  opts.description = "My grammar"
  opts.funding = Some("")
  opts.scope = "source.my_lang"
  opts.file_types = ["ml"]
  opts.license = "MIT"
  opts.author = "Bob"
  opts.email = Some("bob@example.com")
  opts.bindings = match @loader.Bindings::with_enabled_languages(["c"]) {
    Ok(b) => b
    Err(_) => fail("unexpected")
  }
  inspect(
    @support.to_string_pretty(opts.to_json()),
    content=(
      #|{
      #|  "name": "my_lang",
      #|  "camelcase": "MyLang",
      #|  "title": "My Lang",
      #|  "description": "My grammar",
      #|  "funding": "",
      #|  "scope": "source.my_lang",
      #|  "file_types": [
      #|    "ml"
      #|  ],
      #|  "version": "0.1.0",
      #|  "license": "MIT",
      #|  "author": "Bob",
      #|  "email": "bob@example.com",
      #|  "namespace": null,
      #|  "bindings": {
      #|    "c": true,
      #|    "go": false,
      #|    "java": false,
      #|    "node": false,
      #|    "python": false,
      #|    "rust": false,
      #|    "swift": false,
      #|    "zig": false
      #|  }
      #|}
    ),
  )
  @init.generate_grammar_files(dir, "my_lang", false, Some(opts))
  inspect(
    read(dir + "/tree-sitter.json"),
    content=(
      #|{
      #|  "$schema": "https://tree-sitter.github.io/tree-sitter/assets/schemas/config.schema.json",
      #|  "grammars": [
      #|    {
      #|      "name": "my_lang",
      #|      "camelcase": "MyLang",
      #|      "title": "My Lang",
      #|      "scope": "source.my_lang",
      #|      "file-types": [
      #|        "ml"
      #|      ],
      #|      "injection-regex": "^my_lang$",
      #|      "class-name": "TreeSitterMyLang"
      #|    }
      #|  ],
      #|  "metadata": {
      #|    "version": "0.1.0",
      #|    "license": "MIT",
      #|    "description": "My grammar",
      #|    "authors": [
      #|      {
      #|        "name": "Bob",
      #|        "email": "bob@example.com"
      #|      }
      #|    ],
      #|    "links": {
      #|      "repository": "https://github.com/tree-sitter/tree-sitter-my_lang",
      #|      "funding": ""
      #|    }
      #|  },
      #|  "bindings": {
      #|    "c": true,
      #|    "go": false,
      #|    "java": false,
      #|    "node": false,
      #|    "python": false,
      #|    "rust": false,
      #|    "swift": false,
      #|    "zig": false
      #|  }
      #|}
    ),
  )
  inspect(
    list_files(dir).join("\n"),
    content=(
      #|.editorconfig
      #|.gitattributes
      #|.gitignore
      #|CMakeLists.txt
      #|Makefile
      #|bindings/c/tree-sitter-my-lang.pc.in
      #|bindings/c/tree_sitter/tree-sitter-my-lang.h
      #|grammar.js
      #|package.json
      #|tree-sitter.json
    ),
  )
}

///|
async test "generate_grammar_files error" {
  let dir = @fs.tmpdir(prefix="ts-init-test")
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  @fs.write_file(dir + "/tree-sitter.json", "{}", create_mode=CreateOrTruncate)
  try @init.generate_grammar_files(dir, "foo", false, None) catch {
    e => inspect(e, content="missing field `grammars`")
  } noraise {
    _ => fail("expected an error")
  }
}

///|
async test "get_root_path" {
  let dir = @fs.tmpdir(prefix="ts-init-root")
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  @fs.mkdir(dir + "/a")
  @fs.mkdir(dir + "/a/b")
  @fs.mkdir(dir + "/a/b/c")
  @fs.write_file(
    dir + "/a/tree-sitter.json",
    "{\"grammars\": [], \"metadata\": {\"version\": \"1.0.0\"}}",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    dir + "/a/package.json",
    "{\"tree-sitter\": []}",
    create_mode=CreateOrTruncate,
  )
  // A `package.json` without a `tree-sitter` key is skipped.
  @fs.write_file(
    dir + "/a/b/package.json",
    "{\"name\": \"x\"}",
    create_mode=CreateOrTruncate,
  )
  let rel = (p : String) => p.replace(old=dir, new="DIR")
  inspect(
    rel(@init.get_root_path(dir + "/a/b/c/tree-sitter.json")),
    content="DIR/a",
  )
  inspect(rel(@init.get_root_path(dir + "/a/b/c/package.json")), content="DIR/a")
  inspect(rel(@init.get_root_path(dir + "/a/tree-sitter.json")), content="DIR/a")
  // An invalid file stops the search.
  @fs.write_file(
    dir + "/a/b/tree-sitter.json",
    "{}",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(dir + "/a/b/c/package.json", "1", create_mode=CreateOrTruncate)
  async fn error_chain(name : String) -> String {
    try @init.get_root_path(dir + "/a/b/c/" + name) catch {
      @init.InitError(chain) => chain.join(" / ")
      e => "unexpected error \{e}"
    } noraise {
      _ => "no error"
    }
  }
  inspect(
    error_chain("tree-sitter.json"),
    content="Failed to parse tree-sitter.json / missing field `grammars`",
  )
  inspect(
    error_chain("package.json"),
    content="Failed to parse package.json / invalid type: integer `1`, expected a map",
  )
  // No file up to the root.
  try @init.get_root_path("x/y/none.json") catch {
    e =>
      inspect(
        e,
        content="Failed to locate a none.json file, please ensure you have one, and if you don't then consult the docs",
      )
  } noraise {
    _ => fail("expected an error")
  }
}
